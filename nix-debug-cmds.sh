# shellcheck shell=bash

# if this isn't a bash/stdenv-based derivation, we're useless
if [[ "$(basename "${SHELL:-$0}")" != *bash ]] || [[ "${stdenv:-}" != *stdenv-linux ]]; then
    __drv_env="$(basename "${SHELL:-$0}")+$(basename "${stdenv:-unknown}")"
    echo -e "\e[1;33mWARN: derivation builder '$__drv_env' is not a supported stdenv,\e[0m"
    echo -e   "\e[33m      nix-debug will not be able to detect build phases.\e[0m"
    unset __drv_env
    return
fi

# todo: check that `genericBuild` isn't overridden/short-circuited
# before starting a normal phase-based build, `genericBuild` checks the `buildCommandPath` and `buildCommand`
# variables to make sure it actually should run phases. if these variables are set, then we should honor
# that and display a warning about the builder not being supported/not being phased-based

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

__delete_src_on_start() {
    # todo: look at how unpackPhase sets the $sourceRoot variable (or look $src to get the name maybe?)
    #       (but fallback to "source/" in case it doesn't work)
    local __src_folder="./source" # no trailing slashes to avoid symlink shenanigans
    if [[ -d "$__src_folder" ]]; then
        echo -e "There seems to already be a \e[1m$__src_folder/\e[22m folder in the working directory."
        echo -ne '\e[1mDo you want to \e[31mdelete\e[39m it? [y/N] \e[22m'
        if __ask_yn; then
            echo -e "\e[31mDeleting \e[1m$__src_folder/\e[0m"
            chmod u+w -R -- "$__src_folder" # set directory to be writable, so we can delete it (cf #6)
            rm -rf -- "$__src_folder"
        else
            echo -e "\e[32mKeeping folder\e[39m -> \e[1;33munpack phase may fail!\e[0m"
        fi
    fi
}

__delete_src_on_exit() {
    # todo: cf __delete_src_on_start comment
    local __src_folder="./source"
    if [[ -d "$__original_pwd/$__src_folder" ]]; then
        echo -ne "\e[1mDelete unpacked \e[31m$__src_folder/\e[39m folder? [y/N] \e[22m"
        if __ask_yn; then
            echo -e "\e[31mDeleting \e[1m$(realpath "$__original_pwd/$__src_folder")/\e[0m"
            chmod u+w -R -- "$__original_pwd/$__src_folder" # set directory to be writable, so we can delete it (cf #6)
            # shellcheck disable=SC2115 # __original_pwd is never empty, so the expr will never be '/'
            rm -rf -- "$__original_pwd/$__src_folder"
        else
            echo -e "\e[32mKeeping folder\e[39m"
        fi
    fi
}

# shellcheck disable=SC2016 # we want expansion at prompt-eval time, not variable assignment time
# shellcheck disable=SC2329 # yes, some of these are unused; i don't care
__setup_prompt() {
    # check
    # ppppp
    # (i mean, it's the name of the phase in purple/pink, what else do you want to me to say?)
    local _ph_seg='\[\e[3;35m\]${nextPhase/Phase/}\[\e[0m\]'

    # hello(source/tests)
    # ggggggGGGGGGGGGGGGg
    local _pname_and_dir='\[\e[32m\]${pname:-${name:-unknown}}(\[\e[1m\]$(__relative_pwd)\[\e[22m\])\[\e[0m\]'

    # hello(source/tests) $ 
    # ggggggGGGGGGGGGGGGg w
    short() {
        printf '%s \\$ ' "$_pname_and_dir"
    }

    # hello(source/tests) check> 
    # ggggggGGGGGGGGGGGGg pppppw
    withPhase() {
        printf '%s %s> ' "$_pname_and_dir" "$_ph_seg"
    }

    # PS1="$(short)"
    PS1="$(withPhase)"

    unset -f short
    unset -f withPhase

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

__setup_phases
__setup_utils
__setup_prompt

__delete_src_on_start
trap __delete_src_on_exit EXIT

echo
echo -e "\e[1m${#phases_arr[@]}\e[22m" phases to run: "${phases_arr[@]}"
__set_next_phase 0
echo
echo -e 'Use \e[1mrun-next-phase\e[22m to step through each phase'
echo -e 'Use \e[1mrun-until <phase>\e[22m to run every phase *before* the given phase'

r() {
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
alias u='run-until'
alias n='run-next-phase'

unset -f __setup_phases
unset -f __setup_utils
unset -f __setup_prompt
unset -f __delete_src_on_start
