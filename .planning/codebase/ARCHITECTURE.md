# Architecture

**Analysis Date:** 2026-02-02

## Pattern Overview

**Overall:** CLI dispatcher with script delegation

**Key Characteristics:**
- Single monolithic Bash entry point (`cdev`) that parses commands and delegates to either inline implementations or external scripts
- Configuration-driven image building via YAML config files parsed by a custom YAML parser
- LXD as the container runtime, managed entirely through `lxc` CLI commands
- Cloud-init for first-boot container provisioning; custom image builds for pre-baked environments

## Layers

**CLI Entry Point (`cdev`):**
- Purpose: Command routing, argument parsing, help display, and simple command implementations
- Location: `cdev` (project root)
- Contains: `main()` dispatcher, `cmd_*` functions for each command, `show_*_help` functions
- Depends on: LXD (`lxc` CLI), scripts in `scripts/`
- Used by: End users directly

**Delegate Scripts (`scripts/`):**
- Purpose: Complex operations that require significant logic beyond simple `lxc` wrappers
- Location: `scripts/`
- Contains: `build-image.sh`, `worktree-env.sh`, `gh-worktree-env.sh`, `create-env.sh`, `destroy.sh`, `enter.sh`, `list.sh`, `setup.sh`, `snapshot.sh`, `vscode-connect.sh`, `worktree-status.sh`
- Depends on: `scripts/lib/yaml-parser.sh`, LXD, git, gh CLI
- Used by: `cdev` via `exec` calls

**Shared Library (`scripts/lib/`):**
- Purpose: Reusable parsing utilities
- Location: `scripts/lib/yaml-parser.sh`
- Contains: Custom YAML parser (arrays, scalars, multiline commands)
- Depends on: `awk`
- Used by: `scripts/build-image.sh`

**Configuration Layer (`configs/`):**
- Purpose: Declarative package and setup definitions for image builds
- Location: `configs/base.yaml`, `configs/stacks/*.yaml`
- Contains: apt packages, pip/npm globals, post-install commands per stack
- Used by: `scripts/build-image.sh` via `scripts/lib/yaml-parser.sh`

**LXD Profiles (`profiles/`):**
- Purpose: LXD profile definitions applied to containers for resource limits, device mounts, and environment
- Location: `profiles/claude-dev.yaml`, `profiles/stacks/*.yaml`
- Contains: Resource limits, disk mounts (SSH keys, root), security settings, cloud-init user-data
- Used by: `cdev setup` (pushed to LXD), `cdev create` (applied to containers)

**Cloud-Init Templates (`cloud-init/`):**
- Purpose: First-boot provisioning for vanilla Ubuntu containers (when not using pre-built images)
- Location: `cloud-init/base.yaml`, `cloud-init/claude-code.yaml`
- Contains: User creation, package install, SSH setup, shell config
- Used by: `cdev setup` (merged into `.cache/cloud-init-merged.yaml`)

**Shell Templates (`templates/`):**
- Purpose: Bashrc configuration pushed into containers
- Location: `templates/bashrc-cdev.sh`
- Contains: Colored prompt, git aliases, shell options, workspace auto-cd
- Used by: `cdev refresh`, container setup process

## Data Flow

**Container Creation (standalone):**

1. User runs `cdev create my-project --stack python`
2. `cdev` `cmd_create()` parses args, auto-detects image (prefers `cdev-python` over `ubuntu-base`)
3. Calls `lxc launch <image> <name> --profile default --profile claude-dev [--profile <stack>]`
4. LXD applies profiles (resource limits, SSH mount, cloud-init if vanilla image)
5. Container boots; cloud-init runs if using `ubuntu-base`

**Image Build Flow:**

1. User runs `cdev build python`
2. `cdev` delegates to `scripts/build-image.sh python`
3. Script sources `scripts/lib/yaml-parser.sh`
4. Parses `configs/base.yaml` + `configs/stacks/python.yaml`
5. Launches temporary container, installs apt/pip/npm packages, runs commands
6. Publishes container as LXD image with alias `cdev-python`

**Worktree Flow (local repo):**

1. User runs `cdev worktree ~/code/myapp feature/auth`
2. `cdev` `cmd_worktree()` detects local path, delegates to `scripts/worktree-env.sh`
3. Script creates git worktree at `<repo>/../worktrees/<branch>`
4. Launches container with worktree bind-mounted at `/home/developer/workspace/<repo>`
5. Container has isolated branch view; git history shared with main repo

**Worktree Flow (GitHub repo):**

1. User runs `cdev worktree owner/repo feature/auth`
2. `cdev` detects `owner/repo` format, delegates to `scripts/gh-worktree-env.sh`
3. Script uses `gh` CLI to clone repo (if needed) to `~/Projects/<repo>`
4. Then delegates to `scripts/worktree-env.sh` for worktree + container creation

**State Management:**
- No application state files; all state lives in LXD (containers, images, profiles)
- Git worktrees live on host filesystem
- `.cache/` holds merged cloud-init (regenerated on setup)

## Key Abstractions

**Stacks:**
- Purpose: Named development environment presets (nodejs, python, rust, go)
- Examples: `configs/stacks/python.yaml`, `profiles/stacks/python.yaml`
- Pattern: Each stack has a config file (packages) and a profile file (cloud-init). A stack name maps to both.

**Profiles:**
- Purpose: LXD profiles that configure container behavior
- Examples: `profiles/claude-dev.yaml` (base), `profiles/stacks/go.yaml` (stack-specific)
- Pattern: Base profile `claude-dev` is always applied. Stack profile adds cloud-init for first-boot installs when using vanilla images.

**Images:**
- Purpose: Pre-built LXD images with all packages pre-installed (faster than cloud-init)
- Pattern: Named `cdev-<stack>`. If image exists, `cdev create` uses it automatically; otherwise falls back to `ubuntu-base` + cloud-init.

## Entry Points

**`cdev` (main CLI):**
- Location: `cdev`
- Triggers: User invocation from terminal
- Responsibilities: Parse global flags, route to `cmd_*` function, delegate complex ops to scripts

**`scripts/build-image.sh`:**
- Location: `scripts/build-image.sh`
- Triggers: `cdev build <stack>`
- Responsibilities: Parse configs, launch temp container, install packages, publish image

**`scripts/worktree-env.sh`:**
- Location: `scripts/worktree-env.sh`
- Triggers: `cdev worktree <local-path> <branch>`
- Responsibilities: Create git worktree, launch container with bind mount

**`scripts/gh-worktree-env.sh`:**
- Location: `scripts/gh-worktree-env.sh`
- Triggers: `cdev worktree <owner/repo> <branch>`
- Responsibilities: Clone GitHub repo via `gh`, then delegate to `worktree-env.sh`

## Error Handling

**Strategy:** `set -euo pipefail` in all scripts; explicit validation with user-facing error messages

**Patterns:**
- Pre-flight checks: verify LXD installed, container exists, image available
- Colored error messages via `${RED}Error: ...${RESET}`
- Exit code 1 on all errors
- No retry logic; user re-runs on failure

## Cross-Cutting Concerns

**Logging:** Colored terminal output only (no log files). Color disabled when not a TTY.
**Validation:** Inline in each `cmd_*` function. Stack names validated against hardcoded list `nodejs|python|rust|go`.
**Authentication:** SSH keys bind-mounted read-only from host. GitHub auth via `gh` CLI. Claude Code auth via interactive `--with-auth` flag during image build.

---

*Architecture analysis: 2026-02-02*
