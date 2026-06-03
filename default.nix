let pins = import ./npins {}; in
{
  pkgs ? import pins.nixpkgs {},
  nix-debug-cmds ? pkgs.callPackage ./nix-debug-cmds.nix {}
}:
pkgs.callPackage ./package.nix { inherit nix-debug-cmds; }