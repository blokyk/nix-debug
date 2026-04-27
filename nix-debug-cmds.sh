# shellcheck shell=bash

# if this isn't a bash/stdenv-based derivation, we're useless
# (we do this outside of main because we might not be able to parse the rest of this file otherwise)
if [[ "$(basename "${SHELL:-$0}")" != *bash ]] || [[ "${stdenv:-}" != *stdenv-linux ]]; then
    __drv_env="$(basename "${SHELL:-$0}")+$(basename "${stdenv:-unknown}")"
    echo -e "\e[1;33mWARN: derivation builder '$__drv_env' is not a supported stdenv,\e[0m"
    echo -e   "\e[33m      nix-debug will not be able to detect build phases.\e[0m"
    unset __drv_env
    return
fi

__main() {
    __setup_utils
    __setup_prompt

    if [[ "${buildCommand:-}${buildCommandPath:-}" != "" ]]; then
        echo -e "\e[1;33mWARN: derivation doesn't use phases but instead use buildCommand (this is the case for runCommand, writeText, and other similar builders.)\e[0m"
        echo -e "\e[1;33m      nix-debug will not be of much help here, good luck.\e[0m"
        # remove phases from the prompt
        # todo: this is hacky, we can probably rewrite __setup_prompt to better support this
        #        (especially cause we already have `__ps1_short`, which doesn't include phases)
        phases_arr=()
        return 0
    fi

    __setup_phases

    trap __delete_src_on_exit EXIT

    echo
    echo -e "\e[1m${#phases_arr[@]}\e[22m" phases to run: "${phases_arr[@]}"
    __set_next_phase 0
    echo
    echo -e 'Use \e[1mrun <phase>\e[22m to run a specific phase (alias: \e[1mr\e[22m)'
    echo -e 'Use \e[1mrun-next-phase\e[22m to step through each phase (alias: \e[1mn\e[22m)'
    echo -e 'Use \e[1mrun-until <phase>\e[22m to run every phase *before* the given phase (alias: \e[1mu\e[22m)'

    alias r='run'
    alias u='run-until'
    alias n='run-next-phase'
}

__cleanup_start() {
    unset -f __setup_phases || true
    unset -f __setup_utils || true
    unset -f __setup_prompt || true
    unset -f __delete_src_on_start || true
}

__setup_phases() {
    # sets up the 'phases' variable globally, either using the `definePhases` function if it
    # exists (recent nixpkgs/stdenv), or by looking at the code of `genericBuild` (older stdenv)
    if declare -F "definePhases" >/dev/null; then
        definePhases
    else
        eval "$(typeset -f genericBuild | grep "phases=")"
    fi

    # ...but it's just a string, so we need to turn it into a proper bash array
    read -ra phases_arr < <(echo "${phases:?}")
}

__setup_utils() {
    __original_pwd="$PWD"

    __ask_yn() {
        local res
        read -r res
        case "$res" in
            [yY][eE][sS]|[yY])
                true
            ;;
            *)
                false
            ;;
        esac
    }

    __find_matching_phase() {
        # iterate through all phases to find the phase that <phase> is targeting
        local candidates=( )
        local p
        for p in "${phases_arr[@]}"; do
            if [[ "$p" = $1* ]]; then
                candidates+=("$p")
            fi
        done

        # if there's no candidate, error out
        if [[ "${#candidates[@]}" = 0 ]]; then
            echo -e "\e[31mERR: Pattern \e[1m$1\e[22m didn't match any phase" >&2
            return 1
        fi

        # if there's more than one candidate phases, error out
        if [[ "${#candidates[@]}" != 1 ]]; then
            echo -e "\e[31mERR: Pattern \e[1m$1\e[22m is ambiguous; it matches:\e[0m" >&2
            for p in "${candidates[@]}"; do
                echo -e "  - \e[1;31m$p\e[0m" >&2
            done
            return 1
        fi

        # if all went well, there is exactly one item in `candidates`, it's our target phase
        printf "%s" "${candidates[0]}"
        return 0
    }

    __shortenPhase() { printf '%s' "${1/Phase/}"; }

    __set_next_phase() {
        __nextPhaseIdx=${1:?}
        nextPhase="${phases_arr[$__nextPhaseIdx]:=}"
        if [[ "$nextPhase" = "" ]]; then
            echo -e "No more phases to run"
        else
            echo -e "Next phase: \e[1m${nextPhase/Phase/}\e[22m"
        fi
    }
}

__delete_src_on_exit() {
    # if $src isn't defined, define it based on $srcs (or set it empty if $srcs is undefined)
    src="${src:-${srcs[0]:-}}"

    # if there's more than one source, we don't really know how to cleanup right now ¯\_(ツ)_/¯
    if [[ "${srcs[*]:-}" != "${srcs:-}" ]] && [[ "${#srcs[@]:-0}" -gt 1 ]]; then
        echo -e "\e[2;33mWARN: Didn't cleanup unpack because there was more than one source\e[0m"
        return 0
    fi

    # if none of $src, $srcs, or $sourceRoot is defined, we have no way to know what to cleanup
    if [[ "${src:-}" = "" ]] && [[ "${sourceRoot:-}" = "" ]]; then
        echo -e "\e[2;33mWARN: Didn't cleanup because unpack phase seems custom (\$src, \$srcs and \$sourceRoot are all unset)\e[0m"
        return 0
    fi

    local srcName
    # in most cases, $sourceRoot will just be the name of the unpacked folder.
    # but when it is manually set, it's almost always a subfolder of the unpacked
    # dir, given as a relative path.
    # therefore, to get the root unpacked name, get the first segment (not including
    # a leading './', if there is any)
    srcName="${sourceRoot:-.}"
    srcName="$(echo "${srcName#./}" | cut -d/ -f1)"

    # however, in some cases sourceRoot is '.' or './.', in which case we can instead
    # try to guess the unpacked name based on the name of the $src derivation.
    if [[ "$srcName" = "." ]]; then
        srcName="$(stripHash "$src")"
        # remove archive extension, if any
        srcName="${srcName%.tar.gz}"
        srcName="${srcName%.zip}"
    fi

    # this should never happen, but better be safe than delete the user's project (ask me how i know)
    if [[ "$srcName" = "" ]]; then
        return 0
    fi

    local to_rm
    to_rm="$(realpath --no-symlinks "$__original_pwd/$srcName")"
    if [[ -d "$to_rm" ]]; then
        echo -ne "\e[1mDelete unpacked source folder \e[31m./$srcName/\e[39m? [y/N] \e[22m"
        if __ask_yn; then
            echo -e "\e[31mDeleting \e[1m$to_rm/\e[0m"
            # try to delete directory normally, and if it doesn't work, make it writable and try again (cf #6)

            # shellcheck disable=SC2115 # __original_pwd is never empty, so the expr will never be '/'
            rm -rf -- "$to_rm" 2>/dev/null ||
                (chmod u+w -R -- "$to_rm" && rm -rf -- "$to_rm")
        else
            # todo: when we don't delete the source folder, add a little file that tracks the curr phase
            #       and then (on next startup) as the user if they want to pick back up from there
            #       (if we do that we'd have to delete the state file on startup, to not interfere with the build)
            echo -e "\e[32mKeeping folder\e[39m -> \e[1;33mnext unpack may fail!\e[0m"
        fi
    fi
}

# shellcheck disable=SC2016 # we want expansion at prompt-eval time, not variable assignment time
# shellcheck disable=SC2329 # yes, some of these are unused; i don't care
__setup_prompt() {
    # check
    # ppppp
    # (i mean, it's the name of the phase in purple/pink, what else do you want to me to say?)
    __ps1_ph_seg='\[\e[3;35m\]${nextPhase/Phase/}\[\e[0m\]'

    # hello(source/tests)
    # ggggggGGGGGGGGGGGGg
    __ps1_pname_and_dir='\[\e[32m\]${pname:-${name:-unknown}}(\[\e[1m\]$(__relative_pwd)\[\e[22m\])\[\e[0m\]'

    # hello(source/tests) $ 
    # ggggggGGGGGGGGGGGGg w
    __ps1_short() {
        printf '%s \\$ ' "$__ps1_pname_and_dir"
    }

    # hello(source/tests) check> 
    # ggggggGGGGGGGGGGGGg pppppw
    __ps1_withPhase() {
        printf '%s %s> ' "$__ps1_pname_and_dir" "$__ps1_ph_seg"
    }

    PROMPT_COMMAND="__nix_debug_ps1"
    __nix_debug_ps1() {
        if [[ $? == 0 ]]; then
            PS1="$(__ps1_withPhase)"
        else
            PS1="$(__ps1_withPhase)"
            # replace the green from the prompt with red
            PS1="${PS1/32/31}"
            export PS1
        fi
    }

    __relative_pwd() {
        # if the working directory is a subfolder of the original pwd,
        if [[ "$PWD" = "$__original_pwd"* ]]; then
            # only display the relative path (based on the working dir of the original shell)
            realpath --no-symlinks --relative-to="$__original_pwd" -- "$PWD"
        else
            # otherwise, just use the absolute path
            echo "$PWD"
        fi
    }
}

run-next-phase() {
    if [[ "$nextPhase" = "" ]]; then
        echo -e "\e[2;33mNo more phases to run\e[0m"
        return 1
    fi

    echo -e "Running phase: \e[1m${nextPhase/Phase/}\e[22m"

    # only advance if the phase completed successfully
    if runPhase "$nextPhase"; then
        __set_next_phase $((__nextPhaseIdx+1))
        return 0
    else
        # otherwise, print a warning and keep the current phase
        local err_code=$?
        echo -e "\e[31mPhase \e[1m${nextPhase/Phase/}\e[22m didn't run successfully (exit code: $err_code)\e[0m" >&2
        return 1
    fi
}

run-until() {
    if [[ "$1" = "" ]]; then
        echo 'Run every phase *before* the given phase (but not the phase itself)'
        echo 'Usage: run-until <phase>'
        echo 'Note:'
        echo '  <phase> should be a prefix of the target phase name. In other words, the'
        echo "  arguments 'b', 'build', and 'buildPhase' will all match the phase 'buildPhase'"
        return 1
    fi

    local target
    if ! target="$(__find_matching_phase "$1")"; then
        return $?
    fi

    __is_target_phase() { [[ ${nextPhase:-} =~ $target* ]]; }

    until __is_target_phase; do
      if ! run-next-phase; then
        echo -e "\e[31mCouldn't run until target phase '${target/Phase/}', stopped.\e[0m" >&2
        unset -f __is_target_phase
        return 1
      fi
    done

    echo -e "Reached target phase \e[1m${target/Phase/}\e[22m, use \e[1mrun-next-phase\e[22m to continue"
    unset -f __is_target_phase
}

run() {
    if [[ "$1" = "" ]]; then
        echo "Alias for 'runPhase' except that <phase> can be a prefix"
        echo "Usage: r <phase>"
        echo "Note: "
        echo "  Since <phase> can be a prefix, 'r b', 'r build' and 'r buildPhase'"
        echo "  are all equivalent to 'runPhase buildPhase'."
        return 1
    fi

    local phase
    if phase="$(__find_matching_phase "$1")"; then
        runPhase "$phase"
    fi
}

__main
__cleanup_start
