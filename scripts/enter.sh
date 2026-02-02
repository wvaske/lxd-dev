#!/bin/bash
# Enter a Claude Code development container
set -euo pipefail

usage() {
    cat << EOF
Usage: $(basename "$0") <name> [options]

Enter an existing Claude Code development container.

Arguments:
  name              Name of the container (required)

Options:
  --root            Enter as root instead of developer user
  --ssh             Use SSH instead of lxc exec
  --cmd COMMAND     Run a command instead of interactive shell
  -h, --help        Show this help message

Examples:
  $(basename "$0") my-project
  $(basename "$0") my-project --root
  $(basename "$0") my-project --cmd "git status"
  $(basename "$0") my-project --ssh
EOF
    exit "${1:-0}"
}

# Defaults
USER="developer"
USE_SSH=false
COMMAND=""

# Parse arguments
NAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --root) USER="root"; shift ;;
        --ssh) USE_SSH=true; shift ;;
        --cmd) COMMAND="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1"; usage 1 ;;
        *) NAME="$1"; shift ;;
    esac
done

if [ -z "$NAME" ]; then
    echo "Error: Container name is required"
    usage 1
fi

# Check if container exists
if ! lxc info "$NAME" &> /dev/null; then
    echo "Error: Container '$NAME' does not exist"
    echo
    echo "Available containers:"
    lxc list --format table -c n,s,4 | grep -E "claude-dev|NAME" || echo "  (none)"
    exit 1
fi

# Check if container is running
STATE=$(lxc list "$NAME" --format csv -c s)
if [ "$STATE" != "RUNNING" ]; then
    echo "Container '$NAME' is not running. Starting..."
    lxc start "$NAME"
    sleep 2
fi

if [ "$USE_SSH" = true ]; then
    # Get container IP
    IP=$(lxc list "$NAME" --format csv -c 4 | cut -d' ' -f1)
    if [ -z "$IP" ] || [ "$IP" = "-" ]; then
        echo "Error: Could not get container IP address"
        echo "Container may still be starting. Try again in a few seconds."
        exit 1
    fi

    if [ -n "$COMMAND" ]; then
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$USER@$IP" "$COMMAND"
    else
        echo "Connecting via SSH to $USER@$IP..."
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$USER@$IP"
    fi
else
    if [ -n "$COMMAND" ]; then
        lxc exec "$NAME" --user 1000 --group 1000 --cwd /home/developer -- \
            bash -c "$COMMAND"
    else
        # Interactive shell
        if [ "$USER" = "root" ]; then
            lxc exec "$NAME" -- bash
        else
            lxc exec "$NAME" --user 1000 --group 1000 --cwd /home/developer -- \
                bash -l
        fi
    fi
fi
