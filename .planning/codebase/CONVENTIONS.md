# Coding Conventions

**Analysis Date:** 2026-02-02

## Language

**Primary:** Bash (all scripts use `#!/bin/bash`)

**Strict Mode:** Every script starts with `set -euo pipefail` immediately after the shebang and header comment.

## Naming Patterns

**Files:**
- Hyphenated lowercase for scripts: `create-env.sh`, `worktree-env.sh`, `build-image.sh`
- Library files in `scripts/lib/`: `yaml-parser.sh`
- Main CLI entry point has no extension: `cdev`

**Functions:**
- Underscore-prefixed for completion helpers: `_cdev_get_containers()`, `_cdev_get_stacks()`
- `cmd_` prefix for CLI subcommand handlers in `cdev`: `cmd_create()`, `cmd_enter()`, `cmd_worktree()`
- `show_` prefix for help functions: `show_create_help()`, `show_main_help()`
- Lowercase with underscores for library functions: `parse_yaml_array()`, `yaml_has_items()`

**Variables:**
- UPPER_SNAKE_CASE for all variables: `SCRIPT_DIR`, `CONTAINER_NAME`, `BASE_BRANCH`, `WORKTREE_PATH`
- No distinction between constants and mutable variables (all uppercase)
- Color variables are short uppercase names: `RED`, `GREEN`, `YELLOW`, `BLUE`, `BOLD`, `DIM`, `RESET`

**Containers/Resources:**
- Hyphenated lowercase: `cdev-build-python-$$`, `cdev-python`
- Repo-branch pattern for worktree containers: `${REPO_NAME}-${BRANCH_SANITIZED}`

## Code Style

**Formatting:**
- No formatter or linter configured (no shellcheck config, no shfmt config)
- 4-space indentation throughout
- Section headers use `# ====` comment blocks in larger files (`cdev`, `build-image.sh`)
- Inline comments on same line for short explanations

**Quoting:**
- Double-quote all variable expansions: `"$NAME"`, `"$STACK"`
- Use `$()` for command substitution, never backticks

## Script Structure Pattern

Every script follows this structure:

```bash
#!/bin/bash
# One-line description comment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    cat << EOF
...
EOF
    exit "${1:-0}"
}

# Defaults
VAR1="default"
VAR2="default"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --option) VAR="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1"; usage 1 ;;
        *) POSITIONAL="$1"; shift ;;
    esac
done

# Validation
if [ -z "$REQUIRED_VAR" ]; then
    echo "Error: ..."
    usage 1
fi

# Implementation steps with numbered progress
echo "[1/N] Doing first thing..."
echo "[2/N] Doing second thing..."
```

## Argument Parsing

**Pattern:** Use `while [[ $# -gt 0 ]]; do case $1 in ... esac done` in every script.

**Conventions:**
- Long options with `--` prefix: `--stack`, `--memory`, `--force`
- Short `-h` always maps to `--help`
- Unknown options print error and show usage: `echo "Unknown option: $1"; usage 1`
- Positional args collected via `*) NAME="$1"; shift ;;`
- Two-value options use `shift 2`: `--stack) STACK="$2"; shift 2 ;;`

## Error Handling

**Strategy:** Rely on `set -euo pipefail` for automatic exit on errors.

**Patterns:**
- Validate prerequisites early with clear error messages:
  ```bash
  if ! command -v lxc &> /dev/null; then
      echo "Error: LXD is not installed."
      exit 1
  fi
  ```
- Check resource existence before operations:
  ```bash
  if ! lxc info "$NAME" &> /dev/null; then
      echo "Error: Container '$NAME' not found"
      exit 1
  fi
  ```
- Suppress expected failures with `2>/dev/null || true`
- Use `trap cleanup EXIT` for resource cleanup in `build-image.sh`
- Error messages start with `"Error: "` prefix
- Always suggest next steps after errors: `echo "Run 'cdev setup' to download ubuntu-base"`

## Color Output

**Pattern:** Define color variables at top of file, conditionally disabled for non-TTY:

```bash
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' RESET=''
fi
```

**Usage conventions:**
- `RED` for errors: `echo "${RED}Error: ...${RESET}"`
- `GREEN` for success: `echo "${GREEN}Container created!${RESET}"`
- `YELLOW` for warnings: `echo "${YELLOW}Image already exists${RESET}"`
- `BLUE` for progress steps: `echo "${BLUE}[1/5]${RESET} Creating..."`
- `BOLD` for section headers: `echo "${BOLD}=== Title ===${RESET}"`

**Note:** Color definitions are duplicated in `cdev` and `scripts/build-image.sh`. Other scripts in `scripts/` do not use colors.

## Logging / User Feedback

**No logging framework.** All output goes to stdout/stderr via `echo`.

**Progress pattern:** Numbered steps `[N/M]` for multi-step operations:
```bash
echo "[1/4] Launching container..."
echo "[2/4] Applying cloud-init configuration..."
```

**Completion pattern:** Summary block at end of operations:
```bash
echo "=== Environment Ready: $NAME ==="
echo
echo "Commands:"
echo "  Enter container:    cdev enter $NAME"
```

## Import / Sourcing

**Pattern:** Use `source` for library files:
```bash
source "$SCRIPT_DIR/lib/yaml-parser.sh"
```

Only `build-image.sh` sources an external library. Other scripts are self-contained.

## Delegation

**Pattern:** Main CLI (`cdev`) delegates to `scripts/*.sh` via `exec`:
```bash
exec "$SCRIPT_DIR/scripts/build-image.sh" "$@"
exec "$SCRIPT_DIR/scripts/worktree-env.sh" "${args[@]}"
```

Some commands (setup, create, enter, list, snapshot, port, refresh) are implemented directly in `cdev`. Others (build, worktree, vscode, destroy) delegate to scripts.

## Help Text

**In `cdev`:** Rich formatted help with colors, using heredoc `cat << EOF`. Each subcommand has a dedicated `show_<cmd>_help()` function with USAGE, ARGUMENTS, OPTIONS, DESCRIPTION, EXAMPLES sections.

**In `scripts/*.sh`:** Simpler `usage()` functions without colors, same heredoc pattern.

## Comments

**When to comment:**
- File-level: one-line description after shebang
- Section separators: `# === Section Name ===` comment blocks
- Inline: explain non-obvious logic (e.g., why a mount is needed)
- No JSDoc/TSDoc equivalent; no structured documentation comments

---

*Convention analysis: 2026-02-02*
