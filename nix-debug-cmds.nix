# separate package so that it can be easily
# overridden for the main nix-debug derivation
{
  coreutils,
  writeShellApplication,
}:

writeShellApplication {
  name = "__nix-debug-cmds";
  runtimeInputs = [ coreutils ]; # realpath + grep
  text = builtins.readFile ./nix-debug-cmds.sh;
}