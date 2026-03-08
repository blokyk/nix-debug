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
    for arg in "$@"; do
      if [[ "$arg" = "-p" ]] || [[ "$arg" = "--packages" ]]; then
        exec nix-shell "$@"
      fi
    done

    nix-shell "$@" \
      --command \
      '
      __nix_debug_cmds() { local -; . ${lib.getExe nix-debug-cmds}; }
      __nix_debug_cmds
      return $?
      '
  '';
}
