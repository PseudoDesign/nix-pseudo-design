"""Synthetic only: preserve admitted state before SPIRE's key-generating path."""
import base64
import copy
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import stat
import types
import unittest
from unittest import mock
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

SOURCE = Path(os.environ.get('KAIBA_MEMBER_GUARD', str(Path(__file__).resolve().parents[1] / 'hosts/mako/member-identity-guard.py')))
SPEC = importlib.util.spec_from_file_location('member_guard', SOURCE)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)
NOW = dt.datetime(2026, 9, 30, 7, 0, tzinfo=dt.timezone.utc)
DOMAIN = 'pilot.kaiba.pseudo.design'
URI = 'spiffe://' + DOMAIN + '/spire/agent/join_token/synthetic-not-a-grant'

def utc(value):
    return value.isoformat().replace('+00:00', 'Z')

def b64(value):
    return base64.b64encode(value).decode()

def pem(cert):
    return b64(cert.public_bytes(serialization.Encoding.PEM))

def der(key):
    return b64(key.private_bytes(serialization.Encoding.DER,
        serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))

def name(value):
    return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, value)])

def root(key, label='synthetic-root', before=None, after=None):
    return (x509.CertificateBuilder().subject_name(name(label)).issuer_name(name(label))
        .public_key(key.public_key()).serial_number(x509.random_serial_number())
        .not_valid_before(before or NOW-dt.timedelta(hours=1))
        .not_valid_after(after or NOW+dt.timedelta(days=1))
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False,
            key_encipherment=False, data_encipherment=False, key_agreement=False,
            key_cert_sign=True, crl_sign=True, encipher_only=False, decipher_only=False), critical=True)
        .sign(key, hashes.SHA256()))

def leaf(key, ca, ca_key, uri=URI, before=None, after=None):
    return (x509.CertificateBuilder().subject_name(name('synthetic-member'))
        .issuer_name(ca.subject).public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(before or NOW-dt.timedelta(minutes=2))
        .not_valid_after(after or NOW+dt.timedelta(minutes=58))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(x509.SubjectAlternativeName([x509.UniformResourceIdentifier(uri)]), critical=False)
        .sign(ca_key, hashes.SHA256()))

class MemberGuardTests(unittest.TestCase):
    def setUp(self):
        self.ca_key=ec.generate_private_key(ec.SECP256R1())
        self.ca=root(self.ca_key)
        self.key=ec.generate_private_key(ec.SECP256R1())
        self.leaf=leaf(self.key,self.ca,self.ca_key)
        self.config={'host':'mako','trust_domain':DOMAIN,'server_address':'192.168.8.214',
            'server_port':8081,'state_directory':'/var/lib/kaiba/identity/local',
            'receipt_file':'/var/lib/kaiba/identity/member-bootstrap/admitted.json',
            'join_token_file':'/run/kaiba-member-admission/join-token',
            'timedatectl':'/run/current-system/sw/bin/timedatectl',
            'not_after':'2026-10-03T02:06:35Z'}
        self.receipt={'schema':'kaiba.admitted-spire-member/v1alpha1',
            **{k:self.config[k] for k in ('host','trust_domain','server_address','server_port','state_directory','not_after')},
            'node_id_sha256':hashlib.sha256(URI.encode()).hexdigest()}
        self.cache={'svid':[pem(self.leaf)],'bundle':[pem(self.ca)],
            'reattestable':False,'bootstrap_use':3,'bootstrap_start_time':utc(NOW),
            'connection_attempts':0}
        self.keys={'keys':{'agent-svid-A':der(self.key)}}
    def check(self):
        return guard.validate(self.receipt,self.cache,self.keys,self.config,NOW)
    def test_valid_admitted_member(self):
        self.check()
    def test_rotated_leaf_and_alternate_key_slot_accepted(self):
        next_key=ec.generate_private_key(ec.SECP256R1())
        self.keys['keys']['agent-svid-B']=der(next_key)
        self.cache['svid']=[pem(leaf(next_key,self.ca,self.ca_key))]
        self.check()
    def test_expired_unused_root_and_new_root_accepted(self):
        old_key=ec.generate_private_key(ec.SECP256R1())
        old=root(old_key,'old-root',NOW-dt.timedelta(days=2),NOW-dt.timedelta(days=1))
        self.cache['bundle'].insert(0,pem(old))
        self.check()
    def test_expired_and_near_expired_node_rejected(self):
        for delta in (-60,0,1,119,120):
            with self.subTest(delta=delta):
                self.cache['svid']=[pem(leaf(self.key,self.ca,self.ca_key,after=NOW+dt.timedelta(seconds=delta)))]
                with self.assertRaises(ValueError):self.check()
    def test_leaf_outside_startup_safety_margin_accepted(self):
        self.cache['svid']=[pem(leaf(self.key,self.ca,self.ca_key,after=NOW+dt.timedelta(seconds=121)))]
        self.check()
    def test_future_leaf_rejected(self):
        self.cache['svid']=[pem(leaf(self.key,self.ca,self.ca_key,before=NOW+dt.timedelta(seconds=1)))]
        with self.assertRaises(ValueError):self.check()
    def test_other_node_same_authority_rejected(self):
        self.cache['svid']=[pem(leaf(self.key,self.ca,self.ca_key,uri=URI+'other'))]
        with self.assertRaises(ValueError):self.check()
    def test_missing_and_mismatched_disk_key_rejected(self):
        self.keys={'keys':{}}
        with self.assertRaises(ValueError):self.check()
        self.keys={'keys':{'agent-svid-A':der(ec.generate_private_key(ec.SECP256R1()))}}
        with self.assertRaises(ValueError):self.check()
    def test_wrong_signer_rejected(self):
        other=ec.generate_private_key(ec.SECP256R1())
        self.cache['bundle']=[pem(root(other))]
        with self.assertRaises(ValueError):self.check()
    def test_expired_issuer_rejected(self):
        expired=root(self.ca_key,before=NOW-dt.timedelta(days=2),after=NOW-dt.timedelta(seconds=1))
        self.cache['bundle']=[pem(expired)]
        self.cache['svid']=[pem(leaf(self.key,expired,self.ca_key))]
        with self.assertRaises(ValueError):self.check()
    def test_receipt_identity_deadline_and_destination_bound(self):
        for field,value in [('host','ace'),('server_address','192.168.8.249'),
            ('server_port',18444),('state_directory','/tmp/other'),
            ('trust_domain','other.example'),('node_id_sha256','0'*64),
            ('not_after','2026-09-30T06:59:59Z')]:
            with self.subTest(field=field):
                original=self.receipt[field];self.receipt[field]=value
                with self.assertRaises(ValueError):self.check()
                self.receipt[field]=original
    def test_closed_shape_and_key_slots(self):
        for obj in (self.receipt,self.cache,self.keys):
            with self.subTest(kind=list(obj)[0]):
                obj['unexpected']='canary'
                with self.assertRaises(ValueError):self.check()
                del obj['unexpected']
        self.keys['keys']['other-key']=der(self.key)
        with self.assertRaises(ValueError):self.check()
    def test_missing_cache_never_qualifies(self):
        self.cache['svid']=[]
        with self.assertRaises(ValueError):self.check()
        self.cache['svid']=[pem(self.leaf)];self.cache['bundle']=[]
        with self.assertRaises(ValueError):self.check()
    def test_malformed_pem_and_pkcs8_rejected(self):
        self.cache['svid']=[b64(b'not a certificate')]
        with self.assertRaises(ValueError):self.check()
        self.cache['svid']=[pem(self.leaf)];self.keys['keys']['agent-svid-A']=b64(b'not a private key')
        with self.assertRaises(ValueError):self.check()

    def test_duplicate_json_fields_rejected(self):
        with self.assertRaisesRegex(ValueError,'duplicate-json-field'):
            guard.closed_json(b'{"keys":{},"keys":{}}')

    def test_private_file_rejects_mode_symlink_hardlink_and_wrong_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);p=base/'cache';p.write_bytes(b'synthetic');p.chmod(0o600)
            self.assertEqual(guard.private_read(p,os.getuid()),b'synthetic')
            with self.assertRaises(ValueError):guard.private_read(p,os.getuid()+1)
            p.chmod(0o644)
            with self.assertRaises(ValueError):guard.private_read(p,os.getuid())
            p.chmod(0o600);link=base/'linked';link.symlink_to(p)
            with self.assertRaises(OSError):guard.private_read(link,os.getuid())
            hard=base/'hard';os.link(p,hard)
            with self.assertRaises(ValueError):guard.private_read(p,os.getuid())

    def test_inspect_failure_preserves_actual_files_and_never_invokes_commands(self):
        # Only synthetic temporary files. Root/daemon ownership is mapped to the
        # current test UID; production ownership remains enforced by the helper.
        class Clock(dt.datetime):
            @classmethod
            def now(cls,tz=None):return NOW
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);state=base/'local';keysdir=state/'keys';receipt_dir=base/'bootstrap'
            state.mkdir(mode=0o700);keysdir.mkdir(mode=0o700);receipt_dir.mkdir(mode=0o700)
            config=copy.deepcopy(self.config);config['state_directory']=str(state)
            config['receipt_file']=str(receipt_dir/'admitted.json');config['join_token_file']=str(base/'absent-token')
            receipt=copy.deepcopy(self.receipt);receipt['state_directory']=str(state)
            cachepath=state/'agent-data.json';keypath=keysdir/'keys.json';receiptpath=Path(config['receipt_file'])
            def save(path,value):
                path.write_text(json.dumps(value));path.chmod(0o600)
            save(cachepath,self.cache);save(keypath,self.keys);save(receiptpath,receipt)
            expired=copy.deepcopy(self.cache)
            expired['svid']=[pem(leaf(self.key,self.ca,self.ca_key,after=NOW-dt.timedelta(seconds=1)))]
            original_read=guard.private_read
            def read(path,uid):
                self.assertIn(uid,(0,os.getuid()))
                return original_read(path,os.getuid())
            def checked_directory(path,uid,mode):
                metadata=Path(path).lstat()
                self.assertIn(uid,(0,os.getuid()))
                guard.need(stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode)
                    and metadata.st_uid==os.getuid() and stat.S_IMODE(metadata.st_mode)==mode,'test-directory')
            def snapshot():return {str(p):p.read_bytes() for p in (cachepath,keypath,receiptpath)}
            with mock.patch.object(guard.socket,'gethostname',return_value='mako'), \
                 mock.patch.object(guard.pwd,'getpwnam',return_value=types.SimpleNamespace(pw_uid=os.getuid())), \
                 mock.patch.object(guard,'directory',side_effect=checked_directory), \
                 mock.patch.object(guard,'private_read',side_effect=read), \
                 mock.patch.object(guard.dt,'datetime',Clock), \
                 mock.patch.object(guard.subprocess,'run',side_effect=AssertionError('no commands during inspect')):
                before=snapshot();self.assertEqual(guard.inspect(config)['status'],'passed');self.assertEqual(before,snapshot())
                save(cachepath,expired);before=snapshot()
                with self.assertRaises(ValueError):guard.inspect(config)
                self.assertEqual(before,snapshot())
                save(cachepath,self.cache);keypath.unlink();before=snapshot() if keypath.exists() else {str(p):p.read_bytes() for p in (cachepath,receiptpath)}
                with self.assertRaises(OSError):guard.inspect(config)
                self.assertFalse(keypath.exists());self.assertEqual(before,{str(p):p.read_bytes() for p in (cachepath,receiptpath)})
                save(keypath,self.keys);Path(config['join_token_file']).write_bytes(b'synthetic-not-a-grant')
                before=snapshot()
                with self.assertRaisesRegex(ValueError,'unexpected-admission-grant'):guard.inspect(config)
                self.assertEqual(before,snapshot())

if __name__=='__main__':unittest.main()
