{ home-manager, ... }: 
{
  imports = [
    home-manager.nixosModules.default
  ];
  
  users.users.adam = {
    isNormalUser = true;
    description = "Test account for Adam Schafer";
    # Sudo access
    extraGroups = [
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJMjtOqSWLDq79t/9XljmBrfBVm8deQJdOQmTV7c45Ni adam@malak"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIojZ/xu4CVq5TbY51CMUlRiWnSdkS7ZN9xL10gNrFux black@plagueis"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIDVEuyPwmcEybp5d1/FEbCPOjCfuRZ2vp7tYGqe64mg adamschafer@starkiller"
    ];
  };

  # Home Manager integration
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.adam = import ../../home/adam.nix;
}