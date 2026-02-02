# Codebase Structure

**Analysis Date:** 2026-02-02

## Directory Layout

```
lxd-dev/
├── cdev                    # Main CLI entry point (1467 lines, Bash)
├── README.md               # Project documentation
├── .cache/                 # Generated files (cloud-init merge output)
├── cloud-init/             # Cloud-init templates for first-boot provisioning
│   ├── base.yaml           # User creation, packages, SSH, workspace setup
│   └── claude-code.yaml    # Claude Code specific cloud-init additions
├── completions/            # Shell tab-completion scripts
│   └── cdev.bash           # Bash completion for cdev commands
├── configs/                # Declarative package configs for image builds
│   ├── base.yaml           # Packages installed in ALL images
│   └── stacks/             # Stack-specific package configs
│       ├── go.yaml
│       ├── nodejs.yaml
│       ├── python.yaml
│       └── rust.yaml
├── profiles/               # LXD profile definitions
│   ├── claude-dev.yaml     # Base profile (resources, mounts, env vars)
│   └── stacks/             # Stack-specific profiles (cloud-init user-data)
│       ├── go.yaml
│       ├── nodejs.yaml
│       ├── python.yaml
│       └── rust.yaml
├── scripts/                # Complex operation scripts delegated from cdev
│   ├── build-image.sh      # Build custom LXD images from configs (13K)
│   ├── create-env.sh       # Standalone container creation (5K)
│   ├── destroy.sh          # Container removal with confirmation (2.6K)
│   ├── enter.sh            # Interactive shell entry (2.6K)
│   ├── gh-worktree-env.sh  # GitHub clone + worktree creation (4.8K)
│   ├── list.sh             # Container listing (2.8K)
│   ├── setup.sh            # One-time LXD initialization (3.7K)
│   ├── snapshot.sh         # Snapshot management (3.9K)
│   ├── vscode-connect.sh   # VS Code Remote-SSH setup (3K)
│   ├── worktree-env.sh     # Local repo worktree + container (13K)
│   ├── worktree-status.sh  # Multi-worktree status/exec (5.2K)
│   └── lib/                # Shared libraries
│       └── yaml-parser.sh  # Custom YAML parser for config files (3.4K)
├── templates/              # Files pushed into containers
│   └── bashrc-cdev.sh      # Shell config (prompt, aliases, options)
└── .planning/              # Planning/analysis documents
    └── codebase/
```

## Directory Purposes

**`cloud-init/`:**
- Purpose: Cloud-init YAML templates used when launching containers from vanilla `ubuntu-base` image
- Contains: User creation (`developer`), package lists, SSH config, workspace setup
- Key files: `base.yaml` (core provisioning), `claude-code.yaml` (Claude-specific additions)

**`configs/`:**
- Purpose: Declarative package definitions consumed by `scripts/build-image.sh`
- Contains: YAML files with `apt`, `pip_global`, `npm_global`, `post_apt_commands`, `developer_commands` keys
- Key files: `base.yaml` (all images), `stacks/<stack>.yaml` (per-stack)

**`profiles/`:**
- Purpose: LXD profile YAML files applied to containers at launch
- Contains: Resource limits, device definitions (disk, SSH mount), environment variables, cloud-init user-data
- Key files: `claude-dev.yaml` (always applied), `stacks/<stack>.yaml` (applied for vanilla image launches)

**`scripts/`:**
- Purpose: Complex operations that `cdev` delegates to via `exec`
- Contains: Bash scripts, each self-contained with argument parsing and help
- Key files: `build-image.sh` and `worktree-env.sh` are the most complex (~13K each)

**`scripts/lib/`:**
- Purpose: Shared utility functions sourced by other scripts
- Contains: `yaml-parser.sh` with `parse_yaml_array`, `parse_yaml_commands`, `parse_yaml_value` functions

**`templates/`:**
- Purpose: Files pushed into containers (via `lxc file push`)
- Contains: Shell configuration appended to container `~/.bashrc`

**`.cache/`:**
- Purpose: Generated/temporary files
- Contains: `cloud-init-merged.yaml` (merged base + claude-code cloud-init)
- Generated: Yes (by `cdev setup`)
- Committed: Unclear (no `.gitignore` detected)

## Key File Locations

**Entry Points:**
- `cdev`: Main CLI, all user commands enter here

**Configuration:**
- `configs/base.yaml`: Base packages for all image builds
- `configs/stacks/*.yaml`: Stack-specific packages
- `profiles/claude-dev.yaml`: Base LXD profile (resources, mounts)
- `profiles/stacks/*.yaml`: Stack LXD profiles (cloud-init)
- `cloud-init/base.yaml`: First-boot provisioning template

**Core Logic:**
- `scripts/build-image.sh`: Image building pipeline
- `scripts/worktree-env.sh`: Worktree + container lifecycle
- `scripts/gh-worktree-env.sh`: GitHub integration layer
- `scripts/lib/yaml-parser.sh`: Config file parsing

**Shell Integration:**
- `completions/cdev.bash`: Tab completion definitions
- `templates/bashrc-cdev.sh`: In-container shell config

## Naming Conventions

**Files:**
- Bash scripts: `kebab-case.sh` (e.g., `build-image.sh`, `worktree-env.sh`)
- YAML configs: `kebab-case.yaml` (e.g., `claude-dev.yaml`)
- Main CLI: no extension (`cdev`)
- Templates: `kebab-case.sh` (e.g., `bashrc-cdev.sh`)

**Directories:**
- All lowercase, hyphen-separated where needed (e.g., `cloud-init`)
- Stack subdirs named `stacks/`

**Functions in Bash:**
- `cmd_*` for command implementations in `cdev`
- `show_*_help` for help functions in `cdev`
- `parse_yaml_*` / `yaml_has_*` for library functions

**Config YAML keys:**
- `snake_case` (e.g., `apt`, `pip_global`, `npm_global`, `post_apt_commands`, `developer_commands`)

## Where to Add New Code

**New CLI Command:**
- Add `show_<cmd>_help()` function in `cdev`
- Add `cmd_<cmd>()` function in `cdev`
- Add case to `main()` dispatcher in `cdev`
- If complex, create `scripts/<cmd-name>.sh` and delegate via `exec`
- Add completion in `completions/cdev.bash`

**New Development Stack:**
- Add `configs/stacks/<stack>.yaml` (package definitions)
- Add `profiles/stacks/<stack>.yaml` (LXD profile with cloud-init)
- Add stack name to validation in `cdev` `cmd_create()` case statement
- Add to `cdev setup` loop in `cmd_setup()`

**New Shared Utility:**
- Add to `scripts/lib/` directory
- Source with `source "$SCRIPT_DIR/lib/<name>.sh"` from consuming scripts

**New Template/Config Pushed to Containers:**
- Add file to `templates/`
- Add push logic in relevant script or `cdev refresh`

## Special Directories

**`.cache/`:**
- Purpose: Merged cloud-init output and temporary build artifacts
- Generated: Yes
- Committed: Should not be (generated content)

**`completions/`:**
- Purpose: Shell completion scripts installed during `cdev setup`
- Generated: No (manually maintained)
- Committed: Yes

---

*Structure analysis: 2026-02-02*
