{
  description = "sh0rtround system";

  nixConfig = {
    pure-eval = false;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/4bd9165a9165";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-neo4j.url = "github:NixOS/nixpkgs/nixos-22.11";
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-neo4j, ... }:
  let
    cfg = import ./config.nix;

    mkHost = { hostname, profile, system ? "x86_64-linux", user, wallpaperDir }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit nixpkgs-neo4j;
          flake        = self;
          hostname     = hostname;
          homeUser     = user;
          powerProfile     = cfg.powerProfile;
          gpu              = cfg.gpu;
          cpuVendor        = cfg.cpuVendor;
          nvidiaBusId      = cfg.nvidiaBusId;
          amdBusId         = cfg.amdBusId;
          intelBusId       = cfg.intelBusId;
          inputSensitivity = cfg.inputSensitivity;
        };
        modules = [
          ./base.nix
          profile
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs       = true;
            home-manager.useUserPackages     = true;
            home-manager.backupFileExtension = "bak";
            home-manager.extraSpecialArgs    = { inherit wallpaperDir; homeUser = user; inputSensitivity = cfg.inputSensitivity; };
            home-manager.users.${user}       = import ./user.nix;
          }
        ];
      };

  in {
    nixosConfigurations = {
      pentest = mkHost {
        inherit (cfg) hostname user;
        wallpaperDir = "/home/${cfg.user}/hacknix/wallpapers";
        profile = ./profiles/pentest.nix;
      };

      gaming = mkHost {
        inherit (cfg) hostname user;
        wallpaperDir = "/home/${cfg.user}/hacknix/wallpapers";
        profile = ./profiles/gaming.nix;
      };
    };
  };
}
