# The "adam" user is a root development account.  Ideally, we'll design the need for this out of the system.
{...}: 
{
  users.users.adam = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJMjtOqSWLDq79t/9XljmBrfBVm8deQJdOQmTV7c45Ni adam" # content of authorized_keys file
    ];
  };
}