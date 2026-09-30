"""Read-only startup guard for an already admitted SPIRE 1.15.2 member.

This never initializes or repairs SPIRE state. A root-private receipt identifies
one previously verified admission; normal A/B key and CA rotation remain allowed.
"""
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import resource
import socket
import stat
import subprocess
import sys
import time
from urllib.parse import urlsplit

from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization

SCHEMA = "kaiba.admitted-spire-member/v1alpha1"
CACHE_FIELDS = {"svid", "bundle", "reattestable", "bootstrap_use", "bootstrap_start_time", "connection_attempts"}
SCOPE = {"host", "trust_domain", "server_address", "server_port", "state_directory", "not_after"}
CONFIG_FIELDS = SCOPE | {"receipt_file", "join_token_file", "timedatectl"}
RECEIPT_FIELDS = SCOPE | {"schema", "node_id_sha256"}
UTC = dt.timezone.utc
STARTUP_VALIDITY_MARGIN_SECONDS = 120


def need(value, reason):
    if not value:
        raise ValueError(reason)


def closed_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            need(key not in result, "duplicate-json-field")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs)


def timestamp(value):
    need(isinstance(value, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z", value), "invalid-deadline")
    return dt.datetime.fromisoformat(value[:-1] + "+00:00")


def public(key):
    return key.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)


def certificates(values, maximum):
    need(isinstance(values, list) and 0 < len(values) <= maximum, "invalid-certificate-list")
    result = []
    for value in values:
        need(isinstance(value, str) and len(value) <= 32768, "invalid-certificate-encoding")
        raw = base64.b64decode(value, validate=True)
        certs = x509.load_pem_x509_certificates(raw)
        need(len(certs) == 1, "ambiguous-certificate-encoding")
        result.append(certs[0])
    return result


def current(cert, now):
    return cert.not_valid_before_utc <= now < cert.not_valid_after_utc


def validate(receipt, cache, keys, config, now):
    need(isinstance(config, dict) and set(config) == CONFIG_FIELDS, "config-shape")
    need(isinstance(receipt, dict) and set(receipt) == RECEIPT_FIELDS and receipt["schema"] == SCHEMA, "receipt-shape")
    need(all(receipt[key] == config[key] for key in SCOPE), "receipt-scope-changed")
    need(type(receipt["server_port"]) is int and 1 <= receipt["server_port"] <= 65535, "invalid-server-port")
    need(isinstance(receipt["node_id_sha256"], str) and re.fullmatch("[a-f0-9]{64}", receipt["node_id_sha256"]), "invalid-node-binding")
    need(now < timestamp(receipt["not_after"]), "admission-window-expired")
    need(isinstance(cache, dict) and set(cache) == CACHE_FIELDS, "cache-shape")
    need(type(cache["reattestable"]) is bool and cache["reattestable"] is False, "unexpected-reattestable-node")
    need(all(type(cache[key]) is int and cache[key] >= 0 for key in ("bootstrap_use", "connection_attempts")) and isinstance(cache["bootstrap_start_time"], str), "invalid-bootstrap-state")
    chain = certificates(cache["svid"], 6)
    roots = certificates(cache["bundle"], 16)
    leaf = chain[0]
    need(current(leaf, now) and leaf.not_valid_after_utc > now + dt.timedelta(seconds=STARTUP_VALIDITY_MARGIN_SECONDS), "node-certificate-expired-or-not-yet-valid")
    uris = leaf.extensions.get_extension_for_class(x509.SubjectAlternativeName).value.get_values_for_type(x509.UniformResourceIdentifier)
    need(len(uris) == 1, "ambiguous-node-identity")
    uri = uris[0]
    parsed = urlsplit(uri)
    need(parsed.scheme == "spiffe" and parsed.netloc == config["trust_domain"] and not parsed.query and not parsed.fragment and parsed.path.startswith("/spire/agent/join_token/") and len(parsed.path.split("/")) == 5 and bool(parsed.path.split("/")[-1]), "wrong-node-trust-domain-or-path")
    need(hashlib.sha256(uri.encode("utf-8")).hexdigest() == receipt["node_id_sha256"], "admitted-node-changed")
    need(not leaf.extensions.get_extension_for_class(x509.BasicConstraints).value.ca, "node-certificate-is-ca")
    need(isinstance(keys, dict) and set(keys) == {"keys"} and isinstance(keys["keys"], dict) and 0 < len(keys["keys"]) <= 2 and set(keys["keys"]) <= {"agent-svid-A", "agent-svid-B"}, "key-slots-shape")
    public_keys = set()
    for value in keys["keys"].values():
        need(isinstance(value, str) and len(value) <= 32768, "invalid-key-encoding")
        key = serialization.load_der_private_key(base64.b64decode(value, validate=True), password=None)
        public_keys.add(public(key.public_key()))
    need(public(leaf.public_key()) in public_keys, "node-key-missing-or-mismatched")
    for child, issuer in zip(chain, chain[1:]):
        need(current(issuer, now) and issuer.extensions.get_extension_for_class(x509.BasicConstraints).value.ca, "invalid-intermediate")
        child.verify_directly_issued_by(issuer)
    trusted = False
    for root in roots:
        if not current(root, now) or not root.extensions.get_extension_for_class(x509.BasicConstraints).value.ca:
            continue
        try:
            chain[-1].verify_directly_issued_by(root)
            trusted = True
            break
        except (ValueError, TypeError, InvalidSignature):
            continue
    need(trusted, "node-not-issued-by-current-cached-authority")
    return {"status": "passed", "admitted_identity_preserved": True, "read_only": True}


def directory(path, uid, mode):
    # Reject symlinks in every ancestor, including the shared traversal parents.
    path = Path(path)
    need(path.is_absolute() and ".." not in path.parts, "unsafe-state-path")
    for parent in reversed((path, *path.parents[:-1])):
        metadata = parent.lstat()
        need(stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode), "unsafe-directory")
        if parent != path:
            need(metadata.st_uid == 0 and not stat.S_IMODE(metadata.st_mode) & 0o022, "unsafe-parent-directory")
    metadata = path.lstat()
    need(metadata.st_uid == uid and stat.S_IMODE(metadata.st_mode) == mode, "unsafe-directory-owner-or-mode")


def private_read(path, uid):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        metadata = os.fstat(fd)
        need(stat.S_ISREG(metadata.st_mode) and metadata.st_uid == uid and stat.S_IMODE(metadata.st_mode) == 0o600 and metadata.st_nlink == 1 and 0 < metadata.st_size <= 1048576, "unsafe-state-file")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            raw = stream.read(1048577)
        need(len(raw) <= 1048576 and len(raw) == metadata.st_size, "state-file-changed")
        return raw
    finally:
        os.close(fd)


def inspect(config):
    need(isinstance(config, dict) and set(config) == CONFIG_FIELDS, "config-shape")
    need(socket.gethostname() == config["host"], "wrong-host")
    need(not os.path.lexists(config["join_token_file"]), "unexpected-admission-grant")
    account = pwd.getpwnam("spire-agent")
    state = Path(config["state_directory"])
    directory(state, account.pw_uid, 0o700)
    # Its parent is daemon-owned, validated above rather than treated as root.
    keys_dir = state / "keys"
    metadata = keys_dir.lstat()
    need(stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode) and metadata.st_uid == account.pw_uid and stat.S_IMODE(metadata.st_mode) == 0o700, "unsafe-keys-directory")
    receipt_path = Path(config["receipt_file"])
    directory(receipt_path.parent, 0, 0o700)
    receipt = closed_json(private_read(receipt_path, 0))
    cache_raw = private_read(state / "agent-data.json", account.pw_uid)
    keys_raw = private_read(keys_dir / "keys.json", account.pw_uid)
    result = validate(receipt, closed_json(cache_raw), closed_json(keys_raw), config, dt.datetime.now(UTC))
    need(private_read(state / "agent-data.json", account.pw_uid) == cache_raw and private_read(keys_dir / "keys.json", account.pw_uid) == keys_raw, "state-changed-during-validation")
    return result


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    need(os.geteuid() == 0 and len(sys.argv) == 2, "root-and-config-required")
    config = closed_json(Path(sys.argv[1]).read_bytes())
    need(set(config) == CONFIG_FIELDS, "config-shape")
    end = time.monotonic() + 60
    while True:
        status = subprocess.run([config["timedatectl"], "show", "--property=NTPSynchronized", "--value"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5)
        if status.returncode == 0 and status.stdout.strip() == b"yes":
            break
        need(time.monotonic() < end, "online-synchronized-clock-required")
        time.sleep(1)
    # Consistent snapshots allow a read-only check while the existing agent is
    # being observed. ExecStartPre itself runs after the old service has stopped.
    for attempt in range(4):
        try:
            inspect(config)
            return
        except (OSError, ValueError):
            if attempt == 3:
                raise
            time.sleep(.1)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        code = str(error) if isinstance(error, ValueError) and re.fullmatch("[a-z0-9-]+", str(error)) else "admitted-state-invalid"
        print("member identity startup refused: " + code, file=sys.stderr)
        raise SystemExit(1)
