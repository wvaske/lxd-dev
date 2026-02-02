# Codebase Concerns

**Analysis Date:** 2026-02-02

## Security Considerations

**SSH StrictHostKeyChecking Disabled:**
- Risk: Man-in-the-middle attacks when connecting to containers via SSH
- Files: `cdev` (lines 919-921), `scripts/vscode-connect.sh` (lines 91-93)
- Current mitigation: Containers are local LXD instances (low risk in practice)
- Recommendations: Use `StrictHostKeyChecking accept-new` instead of `no` to accept on first connect but warn on changes

**API Key Injected via Shell Expansion:**
- Risk: API key visible in process list, cloud-init logs, and `.bashrc` in plaintext
- Files: `scripts/create-env.sh` (lines 95-101), `cloud-init/claude-code.yaml` (lines 51-54)
- Current mitigation: None
- Recommendations: Use LXD environment config (`lxc config set <container> environment.ANTHROPIC_API_KEY=...`) or a secrets file with restricted permissions instead of appending to `.bashrc`

**SSH Config Manipulation Without Backup:**
- Risk: Corrupted `~/.ssh/config` if sed replacement fails mid-write
- Files: `scripts/vscode-connect.sh` (line 81)
- Current mitigation: None
- Recommendations: Write to temp file and atomically move, or use `Include` directive with a separate cdev-managed config file

**NOPASSWD Sudo for Developer User:**
- Risk: Any code running in the container has full root access
- Files: `scripts/build-image.sh` (line 316), `scripts/create-env.sh` (line 129), `scripts/worktree-env.sh` (line 327), `cloud-init/base.yaml` (line 12)
- Current mitigation: Containers are unprivileged (`security.privileged: "false"` in `profiles/claude-dev.yaml`)
- Recommendations: Acceptable for dev containers; document as intentional design decision

**Port Forwarding Defaults to 0.0.0.0:**
- Risk: Forwarded ports accessible from any network interface, exposing container services to the local network
- Files: `cdev` (line 1089)
- Current mitigation: None
- Recommendations: Default to `127.0.0.1` instead of `0.0.0.0`

## Tech Debt

**Duplicated Container Setup Logic:**
- Issue: User creation, SSH key copying, .profile/.bashrc setup, and git safe.directory configuration are duplicated across multiple scripts
- Files: `scripts/create-env.sh` (lines 125-149), `scripts/worktree-env.sh` (lines 323-371), `scripts/build-image.sh` (lines 312-356)
- Impact: Changes to setup logic must be applied in 3+ places; easy to miss one
- Fix approach: Extract a shared `lib/container-setup.sh` with common setup functions

**Duplicated Color Variable Definitions:**
- Issue: Terminal color escape codes defined identically in `cdev` and `scripts/build-image.sh`
- Files: `cdev` (lines 14-24), `scripts/build-image.sh` (lines 15-24)
- Impact: Minor; cosmetic inconsistency risk
- Fix approach: Source from a shared `lib/colors.sh`

**Dead Code in cmd_list:**
- Issue: The `--all` flag is parsed but both branches execute identical `lxc list` commands
- Files: `cdev` (lines 953-958)
- Impact: `--all` flag does nothing; misleading to users
- Fix approach: Implement filtering for dev-only containers (e.g., filter by profile)

**Legacy Script Files Not Used by cdev CLI:**
- Issue: `scripts/create-env.sh`, `scripts/setup.sh`, `scripts/enter.sh`, `scripts/list.sh`, `scripts/snapshot.sh` appear to be original standalone scripts superseded by the `cdev` CLI wrapper but still present
- Files: `scripts/create-env.sh`, `scripts/setup.sh`, `scripts/enter.sh`, `scripts/list.sh`, `scripts/snapshot.sh`
- Impact: Confusion about which entry point to use; the `cdev` CLI reimplements some of this logic internally while delegating to others
- Fix approach: Audit which scripts are still called by `cdev` (build-image.sh, worktree-env.sh, gh-worktree-env.sh, worktree-status.sh, vscode-connect.sh, destroy.sh are used) and remove or clearly mark the unused ones

## Performance Bottlenecks

**Hardcoded Sleep Timers:**
- Problem: Multiple `sleep 2`, `sleep 3`, `sleep 5`, `sleep 10` calls to wait for container readiness
- Files: `cdev` (line 909), `scripts/worktree-env.sh` (line 320), `scripts/vscode-connect.sh` (line 61), `scripts/build-image.sh` (lines 260-261)
- Cause: No polling mechanism for container readiness
- Improvement path: Poll `lxc exec <name> -- true` in a loop with timeout instead of fixed sleeps; use `cloud-init status --wait` consistently

**Container List Queries Are Expensive:**
- Problem: `lxc list` with CSV format is called repeatedly for state checks, IP lookups
- Files: `cdev` (lines 905, 913, 1277, 1410), `scripts/worktree-env.sh` (lines 139-145)
- Cause: No caching of container state within a single command invocation
- Improvement path: For operations that check multiple containers, query once and parse

## Fragile Areas

**YAML Parser:**
- Files: `scripts/lib/yaml-parser.sh`
- Why fragile: Custom awk-based YAML parser handles only a specific subset of YAML. Indentation-sensitive; will break on comments within arrays, quoted strings containing colons, or nested structures
- Safe modification: Only modify YAML configs that match the exact format: top-level keys with `  - ` prefixed array items and `  - |` multiline blocks
- Test coverage: No tests

**SSH Config Sed Surgery:**
- Files: `scripts/vscode-connect.sh` (line 81)
- Why fragile: The sed command to remove existing SSH config entries uses a range pattern that may misbehave if the config has unexpected formatting or if the host alias appears in comments
- Safe modification: Test with edge cases; consider using a separate include file
- Test coverage: No tests

**Cloud-Init YAML Merging:**
- Files: `cdev` (lines 642-644)
- Why fragile: Simple `cat` concatenation of two cloud-init YAML files assumes they can be merged this way. Multiple `runcmd:`, `packages:`, and `write_files:` sections in concatenated YAML may not merge correctly depending on cloud-init version
- Safe modification: Use cloud-init's native `#include` or merge mechanisms
- Test coverage: No tests

## Scaling Limits

**Container Naming Collisions:**
- Current capacity: Works for a few containers per repo
- Limit: Branch names that sanitize to the same string (e.g., `feature/foo-bar` and `feature/foo_bar`) will collide
- Scaling path: Add a short hash suffix to container names

**Worktree Listing Iterates All Containers:**
- Current capacity: Fine for <20 containers
- Limit: O(N*M) where N=worktrees, M=containers; each iteration calls `lxc config device get`
- Scaling path: Store container-to-worktree mapping in metadata (e.g., LXD config keys) instead of scanning
- Files: `scripts/worktree-env.sh` (lines 136-146)

## Missing Critical Features

**No Input Validation for Resource Limits:**
- Problem: `--cpu`, `--memory`, `--disk` values are passed directly to LXD without validation
- Blocks: Invalid values cause cryptic LXD errors
- Files: `cdev` (lines 787-790), `scripts/worktree-env.sh` (lines 288-299)

**No Container Name Validation:**
- Problem: Container names are not validated against LXD naming rules before attempting creation
- Blocks: Names with invalid characters cause errors after partial operations may have occurred
- Files: `cdev` (line 740 checks for empty but not format)

**No Disk Size Limit for Worktree Containers:**
- Problem: `cmd_create` in `cdev` accepts `--disk` but neither `worktree-env.sh` nor `cdev cmd_worktree` expose or apply disk limits
- Files: `cdev` (lines 797-871), `scripts/worktree-env.sh`

## Test Coverage Gaps

**No Tests Exist:**
- What's not tested: The entire codebase has zero automated tests
- Files: All files
- Risk: Any change can break existing functionality with no safety net. The YAML parser, container name sanitization, argument parsing, and SSH config manipulation are all untested
- Priority: High - at minimum, unit tests for `scripts/lib/yaml-parser.sh` and integration smoke tests for the main `cdev` commands

## Dependencies at Risk

**Custom YAML Parser Instead of Standard Tool:**
- Risk: Fragile, handles only subset of YAML, no error reporting for malformed input
- Impact: Build config changes may silently fail to parse
- Migration plan: Use `yq` (Go-based YAML processor) which is available via snap/apt
- Files: `scripts/lib/yaml-parser.sh`

---

*Concerns audit: 2026-02-02*
