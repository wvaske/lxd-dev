#!/bin/bash
# =============================================================================
# Build a custom base image from config files
# =============================================================================
# Reads package definitions from configs/base.yaml and configs/stacks/<stack>.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source YAML parser
source "$SCRIPT_DIR/lib/yaml-parser.sh"

# Colors
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' RESET=''
fi

usage() {
    cat << EOF
${BOLD}cdev build${RESET} - Build a custom base image from config files

${BOLD}USAGE${RESET}
    $(basename "$0") <stack> [options]

${BOLD}ARGUMENTS${RESET}
    stack           Development stack: nodejs, python, rust, go

${BOLD}OPTIONS${RESET}
    --alias NAME    Image alias (default: cdev-<stack>)
    --with-auth     Launch interactive shell to authenticate Claude Code and gh
    --no-cleanup    Keep build container after image creation
    --dry-run       Show what would be installed without building
    -h, --help      Show this help message

${BOLD}DESCRIPTION${RESET}
    Builds a custom LXD image using config files:
      configs/base.yaml              - Packages for all images
      configs/stacks/<stack>.yaml    - Stack-specific packages

    Edit these YAML files to customize what gets installed.

${BOLD}CONFIG FORMAT${RESET}
    apt:                    # System packages
      - package1
      - package2

    pip_global:             # Python packages (pip install)
      - black
      - pytest

    npm_global:             # NPM packages (npm install -g)
      - typescript

    post_apt_commands:      # Shell commands (as root)
      - "single line command"
      - |
        multiline
        command here

    developer_commands:     # Commands run as developer user
      - "command here"

${BOLD}EXAMPLES${RESET}
    # Build Python image
    $(basename "$0") python

    # Preview what would be installed
    $(basename "$0") python --dry-run

    # Build with authentication
    $(basename "$0") python --with-auth

${BOLD}CUSTOMIZATION${RESET}
    Edit configs/base.yaml to change packages in ALL images.
    Edit configs/stacks/<stack>.yaml to change stack-specific packages.
EOF
    exit "${1:-0}"
}

# Defaults
STACK=""
ALIAS=""
WITH_AUTH=false
CLEANUP=true
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage 0 ;;
        --alias) ALIAS="$2"; shift 2 ;;
        --with-auth) WITH_AUTH=true; shift ;;
        --no-cleanup) CLEANUP=false; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -*) echo "${RED}Unknown option: $1${RESET}"; usage 1 ;;
        *) STACK="$1"; shift ;;
    esac
done

if [[ -z "$STACK" ]]; then
    echo "${RED}Error: Stack is required${RESET}"
    usage 1
fi

# Config file paths
BASE_CONFIG="$PROJECT_DIR/configs/base.yaml"
STACK_CONFIG="$PROJECT_DIR/configs/stacks/${STACK}.yaml"

# Validate stack config exists
if [[ ! -f "$STACK_CONFIG" ]]; then
    echo "${RED}Error: Unknown stack '$STACK'${RESET}"
    echo "Available stacks:"
    for f in "$PROJECT_DIR/configs/stacks"/*.yaml; do
        [[ -f "$f" ]] && echo "  - $(basename "$f" .yaml)"
    done
    exit 1
fi

# Set default alias
[[ -z "$ALIAS" ]] && ALIAS="cdev-${STACK}"

# =============================================================================
# Collect packages from configs
# =============================================================================

echo "${BOLD}Reading configuration...${RESET}"
echo "  Base config:  $BASE_CONFIG"
echo "  Stack config: $STACK_CONFIG"
echo

# Collect apt packages
APT_PACKAGES=()
while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && APT_PACKAGES+=("$pkg")
done < <(parse_yaml_array "$BASE_CONFIG" "apt")
while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && APT_PACKAGES+=("$pkg")
done < <(parse_yaml_array "$STACK_CONFIG" "apt")

# Collect pip packages
PIP_PACKAGES=()
while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && PIP_PACKAGES+=("$pkg")
done < <(parse_yaml_array "$STACK_CONFIG" "pip_global")

# Collect npm packages
NPM_PACKAGES=()
while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && NPM_PACKAGES+=("$pkg")
done < <(parse_yaml_array "$BASE_CONFIG" "npm_global")
while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && NPM_PACKAGES+=("$pkg")
done < <(parse_yaml_array "$STACK_CONFIG" "npm_global")

# =============================================================================
# Dry run - show what would be installed
# =============================================================================

if [[ "$DRY_RUN" == true ]]; then
    echo "${BOLD}=== Dry Run: Image contents for ${STACK} ===${RESET}"
    echo

    echo "${BLUE}APT Packages:${RESET}"
    for pkg in "${APT_PACKAGES[@]}"; do
        echo "  - $pkg"
    done
    echo

    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        echo "${BLUE}PIP Packages (global):${RESET}"
        for pkg in "${PIP_PACKAGES[@]}"; do
            echo "  - $pkg"
        done
        echo
    fi

    if [[ ${#NPM_PACKAGES[@]} -gt 0 ]]; then
        echo "${BLUE}NPM Packages (global):${RESET}"
        for pkg in "${NPM_PACKAGES[@]}"; do
            echo "  - $pkg"
        done
        echo
    fi

    echo "${BLUE}Post-apt commands (base):${RESET}"
    if yaml_has_commands "$BASE_CONFIG" "post_apt_commands"; then
        echo "  (commands defined - see $BASE_CONFIG)"
    else
        echo "  (none)"
    fi

    echo "${BLUE}Post-apt commands (stack):${RESET}"
    if yaml_has_commands "$STACK_CONFIG" "post_apt_commands"; then
        echo "  (commands defined - see $STACK_CONFIG)"
    else
        echo "  (none)"
    fi

    echo "${BLUE}Developer commands:${RESET}"
    if yaml_has_commands "$STACK_CONFIG" "developer_commands"; then
        echo "  (commands defined - see $STACK_CONFIG)"
    else
        echo "  (none)"
    fi

    echo
    echo "Run without --dry-run to build the image."
    exit 0
fi

# =============================================================================
# Build the image
# =============================================================================

BUILD_CONTAINER="cdev-build-${STACK}-$$"

echo "${BOLD}Building image: ${ALIAS}${RESET}"
echo "  Stack: $STACK"
echo "  Auth:  $WITH_AUTH"
echo

# Check if image already exists
if lxc image info "$ALIAS" &>/dev/null; then
    echo "${YELLOW}Image '$ALIAS' already exists.${RESET}"
    read -p "Replace it? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    echo "Will replace existing image after build."
    DELETE_OLD=true
else
    DELETE_OLD=false
fi

cleanup() {
    if [[ "$CLEANUP" == true ]] && lxc info "$BUILD_CONTAINER" &>/dev/null; then
        echo "Cleaning up build container..."
        lxc delete "$BUILD_CONTAINER" --force 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Step 1: Create build container
echo "${BLUE}[1/6]${RESET} Creating build container..."
lxc launch ubuntu:24.04 "$BUILD_CONTAINER" \
    --profile default \
    --profile claude-dev

echo "       Waiting for container to start..."
sleep 5
lxc exec "$BUILD_CONTAINER" -- cloud-init status --wait 2>/dev/null || sleep 10

# Step 2: Install apt packages
echo "${BLUE}[2/6]${RESET} Installing apt packages (${#APT_PACKAGES[@]} packages)..."
lxc exec "$BUILD_CONTAINER" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ${APT_PACKAGES[*]}
"

# Step 3: Run post-apt commands from base config
echo "${BLUE}[3/6]${RESET} Running setup commands..."

# Run base post_apt_commands
while IFS= read -r -d $'\0' cmd; do
    [[ -z "$cmd" ]] && continue
    echo "       Running base setup command..."
    lxc exec "$BUILD_CONTAINER" -- bash -c "$cmd"
done < <(parse_yaml_commands "$BASE_CONFIG" "post_apt_commands")

# Run stack post_apt_commands
while IFS= read -r -d $'\0' cmd; do
    [[ -z "$cmd" ]] && continue
    echo "       Running stack setup command..."
    lxc exec "$BUILD_CONTAINER" -- bash -c "$cmd"
done < <(parse_yaml_commands "$STACK_CONFIG" "post_apt_commands")

# Step 4: Install language-specific packages
echo "${BLUE}[4/6]${RESET} Installing language packages..."

# Install npm packages if any
if [[ ${#NPM_PACKAGES[@]} -gt 0 ]]; then
    echo "       Installing ${#NPM_PACKAGES[@]} npm packages..."
    # Ensure Node.js is available
    lxc exec "$BUILD_CONTAINER" -- bash -c '
        if ! command -v npm &>/dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
            apt-get install -y nodejs
        fi
    '
    lxc exec "$BUILD_CONTAINER" -- npm install -g "${NPM_PACKAGES[@]}"
fi

# Install pip packages if any
if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
    echo "       Installing ${#PIP_PACKAGES[@]} pip packages..."
    lxc exec "$BUILD_CONTAINER" -- pip3 install --break-system-packages "${PIP_PACKAGES[@]}"
fi

# Step 5: Configure developer user
echo "${BLUE}[5/6]${RESET} Configuring developer user..."
lxc exec "$BUILD_CONTAINER" -- bash -c '
    # Create developer user if not exists
    if ! id developer &>/dev/null; then
        useradd -m -s /bin/bash -G sudo developer
        echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer
        chmod 440 /etc/sudoers.d/developer
    fi

    # Set up directories
    mkdir -p /home/developer/.ssh
    mkdir -p /home/developer/.config
    mkdir -p /home/developer/.claude
    mkdir -p /home/developer/workspace
    chmod 700 /home/developer/.ssh

    # Fix ownership
    chown -R developer:developer /home/developer

    # Configure git defaults
    su - developer -c "git config --global init.defaultBranch main"
    su - developer -c "git config --global pull.rebase false"
'

# Ensure .profile exists
lxc exec "$BUILD_CONTAINER" -- bash -c '
    if [[ ! -f /home/developer/.profile ]]; then
        cp /etc/skel/.profile /home/developer/.profile
        chown developer:developer /home/developer/.profile
    fi
'

# Push bashrc template
lxc file push "$PROJECT_DIR/templates/bashrc-cdev.sh" "$BUILD_CONTAINER/tmp/bashrc-cdev.sh"
lxc exec "$BUILD_CONTAINER" -- bash -c '
    cat /tmp/bashrc-cdev.sh >> /home/developer/.bashrc
    rm /tmp/bashrc-cdev.sh
    chown developer:developer /home/developer/.bashrc
'

# Run developer commands from stack config
while IFS= read -r -d $'\0' cmd; do
    [[ -z "$cmd" ]] && continue
    echo "       Running developer setup command..."
    lxc exec "$BUILD_CONTAINER" -- su - developer -c "$cmd"
done < <(parse_yaml_commands "$STACK_CONFIG" "developer_commands")

# Step 5.5: Authentication
if [[ "$WITH_AUTH" == true ]]; then
    echo "${BLUE}[5.5/6]${RESET} Authenticating Claude Code and GitHub CLI..."
    echo
    echo "${YELLOW}An interactive shell will open. Please authenticate both tools:${RESET}"
    echo
    echo "  ${BOLD}1. Authenticate Claude Code:${RESET}"
    echo "     claude"
    echo "     (Follow the prompts to log in)"
    echo
    echo "  ${BOLD}2. Authenticate GitHub CLI:${RESET}"
    echo "     gh auth login"
    echo "     (Choose: GitHub.com -> HTTPS -> Login with a web browser)"
    echo
    echo "  ${BOLD}3. When done, type 'exit' to continue the build${RESET}"
    echo
    read -p "Press Enter to open the shell..."

    lxc exec "$BUILD_CONTAINER" -- su - developer

    echo
    echo "Verifying authentication..."

    if lxc exec "$BUILD_CONTAINER" -- su - developer -c "test -f ~/.claude/.credentials.json || test -f ~/.config/claude-code/credentials.json" 2>/dev/null; then
        echo "${GREEN}✓ Claude Code authenticated${RESET}"
    else
        echo "${YELLOW}⚠ Claude Code authentication not detected${RESET}"
    fi

    if lxc exec "$BUILD_CONTAINER" -- su - developer -c "gh auth status" &>/dev/null; then
        echo "${GREEN}✓ GitHub CLI authenticated${RESET}"
    else
        echo "${YELLOW}⚠ GitHub CLI authentication not detected${RESET}"
    fi
fi

# Step 6: Create image
echo "${BLUE}[6/6]${RESET} Creating image..."

lxc stop "$BUILD_CONTAINER"

if [[ "$DELETE_OLD" == true ]]; then
    echo "       Removing old image..."
    lxc image delete "$ALIAS" 2>/dev/null || true
fi

echo "       Publishing image (this may take a moment)..."
lxc publish "$BUILD_CONTAINER" --alias "$ALIAS" \
    description="Claude Code dev environment ($STACK stack)"

echo
echo "${GREEN}${BOLD}Image created successfully!${RESET}"
echo
echo "Image: $ALIAS"
echo "Stack: $STACK"
lxc image info "$ALIAS" | grep -E "^(Size|Description):"
echo
echo "${BOLD}Usage:${RESET}"
echo "  cdev create my-project --image $ALIAS"
echo
echo "${BOLD}Customization:${RESET}"
echo "  Edit configs/base.yaml for packages in all images"
echo "  Edit configs/stacks/${STACK}.yaml for ${STACK}-specific packages"
