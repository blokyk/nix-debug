A wrapper around nix-shell to provide one or two niceties when debugging derivations

todo: package this up in a nice module so i can have all that functionality be declarative
for example:
   let
     check-usage = ...; # check that we're not creating a `nix-shell -p` kind of shell
                        # note: it'd be okay if this was an option directly, so that we
                        # have a wrapper that checks if one of the args is '-p', before
                        # any derivation might be downloaded/built (since '--command'
                        # otherwise only takes effect once the shell has started)
     phase-helpers = writeShellApplication { ... };
     ...
   in
     # or maybe, `mkDebugShell` ? like it creates a derivation wrapping nix-shell?
     programs.nix-debug = {
       initHooks = [ check-usage phase-helpers setup-prompt list-aliases ];
       runPhaseHooks = [ ... ]; # on runPhase
       exitHooks = [ ... ];

       propagateCorrectExitCodesYouGoddamnLittleFruit = true;

       preUnpackHooks = [ delete-src ];
       postBuildHook = [ ... ];

       aliases = {
         "r" = "run-next-phase";
         "u" = "run-until";
         "n" = "run-next-phase";
       };

       env = { ... };
     }