# Bash completion for cdev - Claude Code Development Environments
# Source this file or place in /etc/bash_completion.d/

_cdev_get_containers() {
    lxc list --format csv -c n 2>/dev/null
}

_cdev_get_running_containers() {
    lxc list --format csv -c n,s 2>/dev/null | grep ",RUNNING" | cut -d',' -f1
}

_cdev_get_snapshots() {
    local container="$1"
    lxc info "$container" 2>/dev/null | awk '/^Snapshots:/,/^[^ ]/' | grep -E '^\s+\w' | awk '{print $1}'
}

_cdev_get_stacks() {
    echo "nodejs python rust go"
}

_cdev_get_repos() {
    # Find git repositories in common locations
    local dirs=()
    for base in "$HOME/Projects" "$HOME/code" "$HOME/src" "$HOME/repos" "$HOME/dev"; do
        if [[ -d "$base" ]]; then
            for dir in "$base"/*/.git; do
                [[ -d "$dir" ]] && dirs+=("${dir%/.git}")
            done
        fi
    done
    printf '%s\n' "${dirs[@]}"
}

_cdev_get_images() {
    lxc image list --format csv -c l 2>/dev/null | grep -E "^(cdev-|ubuntu-base)" || echo "ubuntu-base"
}

_cdev_completions() {
    local cur prev words cword
    _init_completion || return

    local commands="setup build create worktree enter list images status snapshot vscode port mount unmount mounts resources refresh destroy exec help"
    local global_opts="-h --help -v --version"

    # Get the command (first non-option argument after 'cdev')
    local cmd=""
    local cmd_index=0
    for ((i=1; i < cword; i++)); do
        if [[ "${words[i]}" != -* ]]; then
            cmd="${words[i]}"
            cmd_index=$i
            break
        fi
    done

    # Complete commands if no command yet
    if [[ -z "$cmd" ]]; then
        COMPREPLY=($(compgen -W "$commands $global_opts" -- "$cur"))
        return
    fi

    # Command-specific completions
    case "$cmd" in
        setup)
            COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
            ;;

        build)
            case "$prev" in
                --alias)
                    # No completion for alias name
                    ;;
                build)
                    # Stack name
                    COMPREPLY=($(compgen -W "$(_cdev_get_stacks)" -- "$cur"))
                    ;;
                *)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--alias --with-auth --no-cleanup -h --help" -- "$cur"))
                    else
                        COMPREPLY=($(compgen -W "$(_cdev_get_stacks)" -- "$cur"))
                    fi
                    ;;
            esac
            ;;

        images)
            COMPREPLY=($(compgen -W "--all -h --help" -- "$cur"))
            ;;

        create)
            case "$prev" in
                --stack)
                    COMPREPLY=($(compgen -W "$(_cdev_get_stacks)" -- "$cur"))
                    ;;
                --image)
                    COMPREPLY=($(compgen -W "$(_cdev_get_images)" -- "$cur"))
                    ;;
                --cpu|--memory|--disk)
                    # No completion for values
                    ;;
                *)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--stack --image --cpu --memory --disk -h --help" -- "$cur"))
                    fi
                    ;;
            esac
            ;;

        worktree)
            case "$prev" in
                --stack)
                    COMPREPLY=($(compgen -W "$(_cdev_get_stacks)" -- "$cur"))
                    ;;
                --image)
                    COMPREPLY=($(compgen -W "$(_cdev_get_images)" -- "$cur"))
                    ;;
                --base|--name|--cpu|--memory|--clone-dir)
                    # No completion for these values
                    ;;
                worktree)
                    # First arg after worktree - complete repos
                    if [[ "$cur" == /* || "$cur" == ~* || "$cur" == .* ]]; then
                        # Path completion
                        _filedir -d
                    else
                        # Could be GitHub repo (user/repo) or local path
                        _filedir -d
                    fi
                    ;;
                *)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--stack --image --cpu --memory --base --name --clone-dir --list --destroy -h --help" -- "$cur"))
                    else
                        # Complete directories for repo path
                        _filedir -d
                    fi
                    ;;
            esac
            ;;

        enter)
            case "$prev" in
                --cmd)
                    # No completion for command string
                    ;;
                enter)
                    # Container name
                    COMPREPLY=($(compgen -W "$(_cdev_get_containers)" -- "$cur"))
                    ;;
                *)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--root --ssh --cmd -h --help" -- "$cur"))
                    else
                        COMPREPLY=($(compgen -W "$(_cdev_get_containers)" -- "$cur"))
                    fi
                    ;;
            esac
            ;;

        list|ls)
            COMPREPLY=($(compgen -W "--all -h --help" -- "$cur"))
            ;;

        status)
            case "$prev" in
                --exec)
                    # No completion for command string
                    ;;
                status)
                    # Repo path
                    _filedir -d
                    ;;
                *)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--exec --start-all --stop-all -h --help" -- "$cur"))
                    else
                        _filedir -d
                    fi
                    ;;
            esac
            ;;

        snapshot|snap)
            # Get position in command
            local container="" action=""
            local pos=0
            for ((i=cmd_index+1; i < cword; i++)); do
                if [[ "${words[i]}" != -* ]]; then
                    ((pos++))
                    if [[ $pos -eq 1 ]]; then
                        container="${words[i]}"
                    elif [[ $pos -eq 2 ]]; then
                        action="${words[i]}"
                    fi
                fi
            done

            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
            elif [[ $pos -eq 0 ]]; then
                # Container name
                COMPREPLY=($(compgen -W "$(_cdev_get_containers)" -- "$cur"))
            elif [[ $pos -eq 1 ]]; then
                # Action
                COMPREPLY=($(compgen -W "save restore list delete" -- "$cur"))
            elif [[ $pos -eq 2 && "$action" != "list" ]]; then
                # Snapshot name for restore/delete
                if [[ "$action" == "restore" || "$action" == "delete" ]]; then
                    COMPREPLY=($(compgen -W "$(_cdev_get_snapshots "$container")" -- "$cur"))
                fi
            fi
            ;;

        vscode)
            case "$prev" in
                --folder)
                    _filedir -d
                    ;;
                vscode)
                    COMPREPLY=($(compgen -W "$(_cdev_get_running_containers)" -- "$cur"))
                    ;;
                *)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--folder --setup-only -h --help" -- "$cur"))
                    else
                        COMPREPLY=($(compgen -W "$(_cdev_get_running_containers)" -- "$cur"))
                    fi
                    ;;
            esac
            ;;

        port)
            # Get position in command
            local container="" action=""
            local pos=0
            for ((i=cmd_index+1; i < cword; i++)); do
                if [[ "${words[i]}" != -* ]]; then
                    ((pos++))
                    if [[ $pos -eq 1 ]]; then
                        container="${words[i]}"
                    elif [[ $pos -eq 2 ]]; then
                        action="${words[i]}"
                    fi
                fi
            done

            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--host --protocol -h --help" -- "$cur"))
            elif [[ "$prev" == "--protocol" ]]; then
                COMPREPLY=($(compgen -W "tcp udp" -- "$cur"))
            elif [[ "$prev" == "--host" ]]; then
                COMPREPLY=($(compgen -W "0.0.0.0 127.0.0.1" -- "$cur"))
            elif [[ $pos -eq 0 ]]; then
                COMPREPLY=($(compgen -W "$(_cdev_get_containers)" -- "$cur"))
            elif [[ $pos -eq 1 ]]; then
                COMPREPLY=($(compgen -W "add list remove" -- "$cur"))
            fi
            ;;

        mount)
            # Get position in command
            local pos=0
            for ((i=cmd_index+1; i < cword; i++)); do
                if [[ "${words[i]}" != -* ]]; then
                    ((pos++))
                fi
            done

            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--readonly -h --help" -- "$cur"))
            elif [[ $pos -eq 0 ]]; then
                # Container name
                COMPREPLY=($(compgen -W "$(_cdev_get_running_containers)" -- "$cur"))
            elif [[ $pos -eq 1 ]]; then
                # Host path
                _filedir -d
            elif [[ $pos -eq 2 ]]; then
                # Container path - no completion, user types absolute path
                :
            fi
            ;;

        unmount)
            # Get position in command
            local pos=0
            for ((i=cmd_index+1; i < cword; i++)); do
                if [[ "${words[i]}" != -* ]]; then
                    ((pos++))
                fi
            done

            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
            elif [[ $pos -eq 0 ]]; then
                # Container name
                COMPREPLY=($(compgen -W "$(_cdev_get_containers)" -- "$cur"))
            fi
            # Position 1 would be mount name/path - no good completion available
            ;;

        mounts)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "$(_cdev_get_containers)" -- "$cur"))
            fi
            ;;

        resources)
            # Get position in command
            local pos=0
            for ((i=cmd_index+1; i < cword; i++)); do
                if [[ "${words[i]}" != -* ]]; then
                    ((pos++))
                fi
            done

            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--cpu --memory -h --help" -- "$cur"))
            elif [[ "$prev" == "--cpu" ]]; then
                COMPREPLY=($(compgen -W "1 2 4 8 16" -- "$cur"))
            elif [[ "$prev" == "--memory" ]]; then
                COMPREPLY=($(compgen -W "2GB 4GB 8GB 16GB 32GB 64GB" -- "$cur"))
            elif [[ $pos -eq 0 ]]; then
                # Container name
                COMPREPLY=($(compgen -W "$(_cdev_get_containers)" -- "$cur"))
            fi
            ;;

        refresh)
            case "$prev" in
                refresh)
                    COMPREPLY=($(compgen -W "--all $(_cdev_get_running_containers)" -- "$cur"))
                    ;;
                *)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--all --bashrc --gitconfig -h --help" -- "$cur"))
                    else
                        COMPREPLY=($(compgen -W "$(_cdev_get_running_containers)" -- "$cur"))
                    fi
                    ;;
            esac
            ;;

        destroy|rm)
            case "$prev" in
                destroy|rm)
                    COMPREPLY=($(compgen -W "$(_cdev_get_containers)" -- "$cur"))
                    ;;
                *)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--force -h --help" -- "$cur"))
                    else
                        COMPREPLY=($(compgen -W "$(_cdev_get_containers)" -- "$cur"))
                    fi
                    ;;
            esac
            ;;

        exec)
            # Get position in command
            local pos=0
            for ((i=cmd_index+1; i < cword; i++)); do
                if [[ "${words[i]}" != -* ]]; then
                    ((pos++))
                fi
            done

            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--root -h --help" -- "$cur"))
            elif [[ $pos -eq 0 ]]; then
                # Container name
                COMPREPLY=($(compgen -W "$(_cdev_get_running_containers)" -- "$cur"))
            fi
            # After container name, let bash do normal command completion
            ;;

        help)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            ;;
    esac
}

complete -F _cdev_completions cdev
