#!/bin/bash
# List all Claude Code development containers
set -euo pipefail

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

List all Claude Code development containers.

Options:
  --all             Show all LXD containers, not just claude-dev
  --running         Show only running containers
  --stopped         Show only stopped containers
  --json            Output in JSON format
  -h, --help        Show this help message
EOF
    exit "${1:-0}"
}

# Defaults
FILTER=""
FORMAT="table"
ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all) ALL=true; shift ;;
        --running) FILTER="status=Running"; shift ;;
        --stopped) FILTER="status=Stopped"; shift ;;
        --json) FORMAT="json"; shift ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1"; usage 1 ;;
        *) shift ;;
    esac
done

echo "Claude Code Development Containers"
echo "==================================="
echo

if [ "$ALL" = true ]; then
    if [ -n "$FILTER" ]; then
        lxc list "$FILTER" --format "$FORMAT" -c n,s,4,m,t
    else
        lxc list --format "$FORMAT" -c n,s,4,m,t
    fi
else
    # Filter to containers with claude-dev profile
    if [ "$FORMAT" = "json" ]; then
        lxc list --format json | jq '[.[] | select(.profiles | contains(["claude-dev"]))]'
    else
        # Get containers with claude-dev profile
        echo "NAME                 STATE    IPv4               MEMORY    TYPE"
        echo "----                 -----    ----               ------    ----"

        lxc list --format csv -c n,s,4,m,t | while IFS=',' read -r name state ipv4 memory type; do
            # Check if container has claude-dev profile
            if lxc info "$name" 2>/dev/null | grep -q "claude-dev"; then
                # Apply filter if set
                if [ -n "$FILTER" ]; then
                    case "$FILTER" in
                        "status=Running")
                            [ "$state" = "RUNNING" ] && printf "%-20s %-8s %-18s %-9s %s\n" "$name" "$state" "${ipv4:-'-'}" "${memory:-'-'}" "${type:-'CONTAINER'}"
                            ;;
                        "status=Stopped")
                            [ "$state" = "STOPPED" ] && printf "%-20s %-8s %-18s %-9s %s\n" "$name" "$state" "${ipv4:-'-'}" "${memory:-'-'}" "${type:-'CONTAINER'}"
                            ;;
                    esac
                else
                    printf "%-20s %-8s %-18s %-9s %s\n" "$name" "$state" "${ipv4:-'-'}" "${memory:-'-'}" "${type:-'CONTAINER'}"
                fi
            fi
        done
    fi
fi

echo
echo "Commands:"
echo "  Create:   ./scripts/create-env.sh <name> --stack <stack>"
echo "  Enter:    ./scripts/enter.sh <name>"
echo "  Snapshot: ./scripts/snapshot.sh <name> <snapshot-name>"
echo "  Destroy:  ./scripts/destroy.sh <name>"
