# `nix-debug`

*A slightly nicer `nix-shell` debugging experience.*

[![An asciinema showcasing a `nix-debug` session (further description on asciinema)](https://asciinema.org/a/766619.svg)](https://asciinema.org/a/766619)

This is a very small wrapper around `nix-shell` that makes the `stdenv`-based
derivation debugging experience ever so slightly nicer, by:

- adding convenient functions like `run-next-phase` and `run-until <phase>`
- using short, convenient aliases for some commands (`r` for `runPhase`,
  `u` for `run-until`, and `n` for `run-next-phase`)
- avoiding the unending cycle of `rm -rf source/ && nix-shell ...`
- having a shorter, informative prompt:
  ![An example of `nix-debug`'s prompt, showing the package name, relative
  working directory, and current phase](prompt.png)

You should be able to use this exactly like `nix-shell` ([except for the fact
that it'll be misleading for `-p`](https://github.com/blokyk/nix-debug/issues/2));
if not please open an issue!

For known issues, see issue tracker, particularly the
[known issues list](https://github.com/blokyk/nix-debug/issues/1).

## Usage & niceties

`nix-debug` currently provides the following commands and niceties. Note that
these are only valid in an `stdenv`-based builder; if that is not the case (for
example with a bare `derivation`), it will stop early and leave you with the
basic `nix-shell` you would have gotten otherwise.

### `run-next-phase`, `n`

*`run-next-phase`* \
*`n`*

Runs the next phase, as described by `stdenv`'s `definePhases`. The next phase
is also indicated by the prompt and stored in the `$nextPhase` shell variable.

For example, after opening the shell, running `run-next-phase` will generally
start the `unpack` phase; running it again afterwards will trigger the `patch`
phase, etc.

### `run-until`, `u`

*`run-until <phase>`* \
*`u <phase>`*

Runs every phase up to *but excluding* the given `<phase>`, starting with the
current phase.

For example, in a classic `stdenv`, if you have just finished the `configure`
phase, running `run-until install` will run the `build` and `check` phase,
letting you inspect your surroundings before running `run-next-phase` or
`runPhase installPhase` (or even exit, if you want).

Note that the `<phase>` argument can be the *prefix* of a phase instead of the
full phase name; if there are multiple matching phases it will throw an error
and will have to be more specific. Thus, `run-until b`, `run-until build` and
`run-until buildPhase` will all run the `buildPhase` phase.

### `run`, `r`

*`run <phase>`* \
*`r <phase>`*

A simple alias/wrapper for `runPhase` that allows `<phase>` to be a prefix
instead of a full phase name. See the note on [`run-until`](#run-until-u) for
more information.

### Automatically deleting the unpacked source

When starting, if the shell detects a `source/` folder (such as those left
by the `unpack` phase), it will ask you if you want to delete it before starting
the session, since otherwise the `unpack` phase generally fails. To be safe, the
default action is to keep the folder.

Similarly, before exiting, the shell will detect whether or not there is a
`source/` folder, and ask you if you want to delete it, since it's nice to be
tidy :) Just like earlier, the default action is to keep the folder.

### An informative prompt

I mean, look at the difference.

*`nix-shell`'s original prompt:*

![the basic `nix-shell` prompt, where the only information is the fact that
it's a `nix-shell` and the long, absolute working directory](nix-shell-prompt.png)

*`nix-debug`'s new prompt:*

![the `nix-debug` prompt, showing the package name, relative working directory,
and current phase, in much fewer characters](nix-debug-prompt.png)

1. I barely ever go outside the original working directory in a debugging
  `nix-shell`, so relative directories are much more useful to me.
2. One of the most crucial pieces of information when fixing a derivation is
   which phase I'm currently running, and with a classic `nix-shell` there's
   basically no way to know that, you just have to guess.
3. Since I get easily distracted, I often end up opening a few terminals with
   different derivations, so instantly knowing what derivation this is relives
   some mental weight.

If you don't agree with those choices, you're very welcome to modify the
`__setup_prompt` function (and even submit a PR if you want). I'm biased towards
the shortest possible prompt (since I'm often working on limited screen space),
but I'll gladly add a new prompt option if someone submits one.

## License

This program is licensed under the GPLv3 or any later versions; the full text of
the GPLv3 can be found in [./LICENSE](./LICENSE).
