#!/bin/bash
# =============================================================================
# Simple YAML Parser for cdev configs
# =============================================================================
# Parses our specific YAML format (arrays and multiline commands)
# Usage: source this file, then call parse_yaml_* functions

# Parse a simple array from YAML (items starting with "  - ")
# Usage: parse_yaml_array "filename" "key"
# Returns array items, one per line
parse_yaml_array() {
    local file="$1"
    local key="$2"

    awk -v key="$key:" '
        $0 ~ "^" key { found=1; next }
        found && /^[a-zA-Z_]+:/ { found=0 }
        found && /^  - / {
            gsub(/^  - /, "")
            gsub(/"/, "")
            print
        }
    ' "$file"
}

# Parse multiline commands from YAML (commands with | syntax)
# Usage: parse_yaml_commands "filename" "key"
# Returns commands separated by NULL character for safe processing
parse_yaml_commands() {
    local file="$1"
    local key="$2"

    awk -v key="$key:" '
        BEGIN { in_section=0; in_command=0; cmd="" }

        # Start of our section
        $0 ~ "^" key { in_section=1; next }

        # End of section (new top-level key)
        in_section && /^[a-zA-Z_]+:/ { in_section=0 }

        # Inside our section
        in_section {
            # Single-line command: "  - command here"
            if (/^  - [^|]/ && !/^  - \|/) {
                gsub(/^  - /, "")
                gsub(/"/, "")
                print
                print "\0"
                next
            }

            # Start of multiline command: "  - |"
            if (/^  - \|/) {
                in_command=1
                cmd=""
                next
            }

            # Inside multiline command (indented with 4+ spaces)
            if (in_command) {
                if (/^    /) {
                    gsub(/^    /, "")
                    cmd = cmd (cmd ? "\n" : "") $0
                } else if (/^  - / || /^[a-zA-Z]/) {
                    # End of multiline command
                    if (cmd) { print cmd; print "\0" }
                    in_command=0
                    cmd=""

                    # Process new single-line command if present
                    if (/^  - [^|]/) {
                        gsub(/^  - /, "")
                        gsub(/"/, "")
                        print
                        print "\0"
                    }
                    if (/^  - \|/) {
                        in_command=1
                    }
                }
            }
        }

        END {
            if (cmd) { print cmd; print "\0" }
        }
    ' "$file"
}

# Parse a simple scalar value
# Usage: parse_yaml_value "filename" "key"
parse_yaml_value() {
    local file="$1"
    local key="$2"

    awk -v key="$key:" '
        $0 ~ "^" key {
            gsub(key " *", "")
            gsub(/"/, "")
            gsub(/^ +| +$/, "")
            print
            exit
        }
    ' "$file"
}

# Check if a key exists and has items
# Usage: yaml_has_items "filename" "key"
yaml_has_items() {
    local file="$1"
    local key="$2"

    local items=$(parse_yaml_array "$file" "$key")
    [[ -n "$items" ]]
}

# Check if a key exists and has commands
# Usage: yaml_has_commands "filename" "key"
yaml_has_commands() {
    local file="$1"
    local key="$2"

    local cmds=$(parse_yaml_commands "$file" "$key")
    [[ -n "$cmds" ]]
}
