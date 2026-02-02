#!/bin/bash
# Connect VS Code to a Claude Code development container
set -euo pipefail

usage() {
    cat << EOF
Usage: $(basename "$0") <name> [options]

Configure and open VS Code connected to an LXD container.

Arguments:
  name              Name of the container (required)

Options:
  --folder PATH     Open specific folder in container (default: /home/developer/workspace)
  --setup-only      Only configure SSH, don't open VS Code
  -h, --help        Show this help message

Prerequisites:
  - VS Code with "Remote - SSH" extension installed
  - Container must be running

Examples:
  $(basename "$0") my-project
  $(basename "$0") my-project --folder /home/developer/workspace/myrepo
EOF
    exit "${1:-0}"
}

# Defaults
FOLDER="/home/developer/workspace"
SETUP_ONLY=false

# Parse arguments
NAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --folder) FOLDER="$2"; shift 2 ;;
        --setup-only) SETUP_ONLY=true; shift ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1"; usage 1 ;;
        *) NAME="$1"; shift ;;
    esac
done

if [ -z "$NAME" ]; then
    echo "Error: Container name is required"
    usage 1
fi

# Check if container exists and is running
if ! lxc info "$NAME" &> /dev/null; then
    echo "Error: Container '$NAME' does not exist"
    exit 1
fi

STATE=$(lxc list "$NAME" --format csv -c s)
if [ "$STATE" != "RUNNING" ]; then
    echo "Starting container '$NAME'..."
    lxc start "$NAME"
    sleep 3
fi

# Get container IP
IP=$(lxc list "$NAME" --format csv -c 4 | cut -d' ' -f1)
if [ -z "$IP" ] || [ "$IP" = "-" ]; then
    echo "Error: Could not get container IP. Container may still be starting."
    echo "Try again in a few seconds."
    exit 1
fi

# Configure SSH for this container
SSH_CONFIG="$HOME/.ssh/config"
HOST_ALIAS="lxd-$NAME"

# Check if host already configured
if grep -q "^Host $HOST_ALIAS$" "$SSH_CONFIG" 2>/dev/null; then
    # Update existing entry
    echo "Updating SSH config for $HOST_ALIAS..."
    # Remove old entry (between "Host lxd-name" and next "Host" or EOF)
    sed -i "/^Host $HOST_ALIAS$/,/^Host /{/^Host $HOST_ALIAS$/d;/^Host /!d}" "$SSH_CONFIG"
fi

# Add new entry
echo "Adding SSH config for $HOST_ALIAS ($IP)..."
cat >> "$SSH_CONFIG" << EOF

Host $HOST_ALIAS
    HostName $IP
    User developer
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF

echo "SSH config updated: $HOST_ALIAS -> $IP"

if [ "$SETUP_ONLY" = true ]; then
    echo
    echo "SSH configured. Connect with:"
    echo "  ssh $HOST_ALIAS"
    echo
    echo "Or open in VS Code:"
    echo "  code --remote ssh-remote+$HOST_ALIAS $FOLDER"
    exit 0
fi

# Check if VS Code is installed
if ! command -v code &> /dev/null; then
    echo "Warning: VS Code CLI not found."
    echo "Open VS Code manually and connect to: $HOST_ALIAS"
    echo "Folder: $FOLDER"
    exit 0
fi

echo "Opening VS Code connected to $NAME..."
code --remote "ssh-remote+$HOST_ALIAS" "$FOLDER"

echo
echo "VS Code should now be connecting to the container."
echo "If prompted, select 'Linux' as the remote platform."
