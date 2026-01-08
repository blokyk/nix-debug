{
  lib,
  callPackage,
  nix-debug-cmds ? callPackage ./nix-debug-cmds.nix {},
  writeShellApplication,
}:
writeShellApplication {
  name = "nix-debug";
  excludeShellChecks = [ "SC2016" ]; # we *want* to have a raw string with an expression inside
  text = ''
    nix-shell "''${@}" \
      --command \
      '
      __nix_debug_cmds() { local -; . ${lib.getExe nix-debug-cmds}; }
      __nix_debug_cmds
      return $?
      '
  '';
}
