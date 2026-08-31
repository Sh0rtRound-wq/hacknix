{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
lutris
heroic
mangohud
gamemode
protonup-qt
prismlauncher
wowup-cf
guitarix
qpwgraph
bolt-launcher
];

# edit

  programs.steam.enable = true;

  programs.gamemode.enable = true;

  environment.sessionVariables = {
    GAME_DEBUGGER = "gamemoderun";
    PROTON_ENABLE_NVAPI = "1";
  };
}
