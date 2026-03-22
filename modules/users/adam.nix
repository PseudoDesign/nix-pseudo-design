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
  # We don't have a password on this accunt, so sudo shouldn't ask for one.
  # This can have downstream effects, so be averse to including this configuration in production.
  security.sudo.wheelNeedsPassword = false; 
}