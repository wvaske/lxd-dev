# Testing Patterns

**Analysis Date:** 2026-02-02

## Test Framework

**Runner:** None

**There are no automated tests in this project.** No test framework, no test files, no test configuration, no CI pipeline.

## Test File Organization

**Location:** Not applicable - no test files exist.

**No test directories found:**
- No `tests/`, `test/`, `spec/`, or `__tests__/` directories
- No files matching `*.test.*`, `*.spec.*`, or `test_*` patterns
- No `bats` (Bash Automated Testing System) configuration
- No `shunit2` or `shellspec` configuration

## Run Commands

```bash
# No test commands available
# No Makefile targets for testing
# No CI configuration files (.github/workflows, .gitlab-ci.yml, etc.)
```

## Current Validation Approach

Testing is entirely manual. The scripts validate their own preconditions at runtime:

**Self-validation patterns used in scripts:**
- Check if LXD is installed: `command -v lxc &> /dev/null`
- Check if container exists: `lxc info "$NAME" &> /dev/null`
- Check if image exists: `lxc image info "$IMAGE" &>/dev/null`
- Validate stack names: `case $stack in nodejs|python|rust|go) ;; *) error ;; esac`
- Validate git repo: `[ -d "$REPO_PATH/.git" ]`

## Coverage

**Requirements:** None enforced. No coverage tooling.

## Test Types

**Unit Tests:** None

**Integration Tests:** None

**E2E Tests:** None. The tool manages LXD containers, making automated testing complex since it requires:
- LXD installed and initialized
- Network access for image downloads
- Sufficient system resources for containers

## Recommendations for Adding Tests

**Framework:** [bats-core](https://github.com/bats-core/bats-core) is the standard for Bash testing.

**What to test:**
- Argument parsing in each command (unit-testable without LXD)
- Branch name sanitization logic in `scripts/worktree-env.sh`
- YAML parser functions in `scripts/lib/yaml-parser.sh` (most testable component)
- Help text output for each command
- Error handling paths (missing arguments, invalid stacks)

**What requires integration testing (needs LXD):**
- Container creation, entry, destruction lifecycle
- Worktree mount verification
- Snapshot create/restore/delete
- Port forwarding

**Suggested test structure:**
```
tests/
├── unit/
│   ├── yaml-parser.bats      # Test parse_yaml_array, parse_yaml_commands
│   ├── arg-parsing.bats      # Test argument validation
│   └── name-sanitization.bats # Test branch/repo name sanitization
├── integration/
│   ├── create-destroy.bats   # Full container lifecycle
│   └── worktree.bats         # Worktree creation and mounting
└── fixtures/
    ├── sample.yaml            # Test YAML configs
    └── ...
```

## Linting

**shellcheck:** Not configured, but would be the standard linter for this project. No `.shellcheckrc` file exists.

**shfmt:** Not configured. No formatting enforcement.

---

*Testing analysis: 2026-02-02*
