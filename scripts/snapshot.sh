#!/bin/bash
# Manage snapshots for Claude Code development containers
set -euo pipefail

usage() {
    cat << EOF
Usage: $(basename "$0") <name> [snapshot-name] [options]

Create, list, or restore snapshots for a container.

Arguments:
  name              Name of the container (required)
  snapshot-name     Name for the snapshot (optional for --list)

Options:
  --list            List all snapshots for the container
  --restore NAME    Restore container to a specific snapshot
  --delete NAME     Delete a specific snapshot
  --info NAME       Show details about a specific snapshot
  -h, --help        Show this help message

Examples:
  $(basename "$0") my-project before-refactor    # Create snapshot
  $(basename "$0") my-project --list             # List snapshots
  $(basename "$0") my-project --restore fresh    # Restore to snapshot
  $(basename "$0") my-project --delete old-snap  # Delete snapshot
EOF
    exit "${1:-0}"
}

# Parse arguments
NAME=""
SNAPSHOT=""
ACTION="create"

while [[ $# -gt 0 ]]; do
    case $1 in
        --list) ACTION="list"; shift ;;
        --restore) ACTION="restore"; SNAPSHOT="$2"; shift 2 ;;
        --delete) ACTION="delete"; SNAPSHOT="$2"; shift 2 ;;
        --info) ACTION="info"; SNAPSHOT="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1"; usage 1 ;;
        *)
            if [ -z "$NAME" ]; then
                NAME="$1"
            else
                SNAPSHOT="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$NAME" ]; then
    echo "Error: Container name is required"
    usage 1
fi

# Check if container exists
if ! lxc info "$NAME" &> /dev/null; then
    echo "Error: Container '$NAME' does not exist"
    exit 1
fi

case "$ACTION" in
    create)
        if [ -z "$SNAPSHOT" ]; then
            # Generate timestamp-based name
            SNAPSHOT="snap-$(date +%Y%m%d-%H%M%S)"
        fi
        echo "Creating snapshot: $NAME/$SNAPSHOT"
        lxc snapshot "$NAME" "$SNAPSHOT"
        echo "Snapshot created successfully"
        echo
        echo "To restore: ./scripts/snapshot.sh $NAME --restore $SNAPSHOT"
        ;;

    list)
        echo "Snapshots for container '$NAME':"
        echo
        lxc info "$NAME" | grep -A 100 "^Snapshots:" | tail -n +2 | head -20
        if [ $? -ne 0 ]; then
            echo "  (no snapshots)"
        fi
        ;;

    restore)
        if [ -z "$SNAPSHOT" ]; then
            echo "Error: Snapshot name required for restore"
            exit 1
        fi
        echo "Restoring container '$NAME' to snapshot '$SNAPSHOT'..."
        echo "WARNING: This will discard all changes since the snapshot."
        read -p "Continue? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Stop container if running
            STATE=$(lxc list "$NAME" --format csv -c s)
            if [ "$STATE" = "RUNNING" ]; then
                echo "Stopping container..."
                lxc stop "$NAME"
            fi
            lxc restore "$NAME" "$SNAPSHOT"
            echo "Starting container..."
            lxc start "$NAME"
            echo "Restored to snapshot: $SNAPSHOT"
        else
            echo "Restore cancelled"
        fi
        ;;

    delete)
        if [ -z "$SNAPSHOT" ]; then
            echo "Error: Snapshot name required for delete"
            exit 1
        fi
        echo "Deleting snapshot: $NAME/$SNAPSHOT"
        read -p "Are you sure? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            lxc delete "$NAME/$SNAPSHOT"
            echo "Snapshot deleted"
        else
            echo "Delete cancelled"
        fi
        ;;

    info)
        if [ -z "$SNAPSHOT" ]; then
            echo "Error: Snapshot name required for info"
            exit 1
        fi
        echo "Snapshot: $NAME/$SNAPSHOT"
        lxc info "$NAME/$SNAPSHOT"
        ;;
esac
