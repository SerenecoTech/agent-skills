#!/usr/bin/env bash
# =============================================================================
# Claude Code Hook: PreToolUse - Toolchain Guard
# =============================================================================
# Prevents use of mismatched package managers / toolchains based on project
# lock files, package.json#packageManager, and active virtual environments.
#
# JS/TS rules (lock-file priority: bun > pnpm > yarn):
#   bun.lock / bun.lockb present  → block npm, npx, yarn, pnpm
#   pnpm-lock.yaml present        → block npm, npx, yarn
#   yarn.lock present             → block npm (install/add/remove/ci only)
#   package.json#packageManager   → enforces declared manager
#
# Python rules:
#   VIRTUAL_ENV active + explicit global /usr/…/pip path → block
#   VIRTUAL_ENV active + python3 -m pip                  → block
#   VIRTUAL_ENV active + explicit global tool path        → block
#   uv.lock present                                       → block bare pip/pip3
#
# Input:  JSON via stdin with tool_input.command
# Output: hookSpecificOutput with permissionDecision deny, or exit 0 to allow
# =============================================================================

set -euo pipefail

# Fail open: advisory guard — errors should not block legitimate commands
trap 'exit 0' ERR

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

[ -z "$command" ] && exit 0

# =============================================================================
# Project root detection
# Walk up from CWD until we find a recognised lock file / manifest, or hit /
# =============================================================================
find_project_root() {
    # Use pwd -P to resolve symlinks (e.g. /var → /private/var on macOS)
    local dir
    dir=$(pwd -P)
    local depth=0
    while [ "$dir" != "/" ] && [ $depth -lt 6 ]; do
        if [ -f "$dir/bun.lock" ]       || [ -f "$dir/bun.lockb" ]     || \
           [ -f "$dir/pnpm-lock.yaml" ] || [ -f "$dir/yarn.lock" ]     || \
           [ -f "$dir/package.json" ]   || [ -f "$dir/pyproject.toml" ] || \
           [ -f "$dir/uv.lock" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
        depth=$((depth + 1))
    done
    pwd -P
}

PROJECT_ROOT=$(find_project_root)

has_file() { [ -f "$PROJECT_ROOT/$1" ]; }

# =============================================================================
# Helpers
# =============================================================================

deny() {
    local reason="$1"
    jq -n --arg r "$reason" \
        '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
    exit 0
}

# Extract the binary name from a command, skipping leading VAR=value pairs.
# Handles: "NODE_ENV=prod npm run build" → "npm"
#          "/usr/local/bin/pip install"  → "pip"
CMD_BINARY=$(echo "$command" | sed 's/^[[:space:]]*//' | \
    awk '{for(i=1;i<=NF;i++) if($i !~ /^[A-Z_][A-Z_0-9]*=/) { print $i; exit }}' | \
    xargs basename 2>/dev/null || echo "")

# =============================================================================
# Section 1: JS/TS Toolchain Rules
# =============================================================================

# --- Bun (highest priority) ---
if has_file "bun.lock" || has_file "bun.lockb"; then
    case "$CMD_BINARY" in
        npm)  deny "bun.lock present — use bun instead (bun install · bun add · bun run)" ;;
        npx)  deny "bun.lock present — use bunx instead of npx" ;;
        yarn) deny "bun.lock present — use bun instead of yarn" ;;
        pnpm) deny "bun.lock present — use bun instead of pnpm" ;;
    esac
fi

# --- pnpm ---
if has_file "pnpm-lock.yaml"; then
    case "$CMD_BINARY" in
        npm)  deny "pnpm-lock.yaml present — use pnpm instead of npm" ;;
        npx)  deny "pnpm-lock.yaml present — use 'pnpm dlx' instead of npx" ;;
        yarn) deny "pnpm-lock.yaml present — use pnpm instead of yarn" ;;
    esac
fi

# --- Yarn (only when no bun/pnpm lock present) ---
if has_file "yarn.lock" && ! has_file "bun.lock" && ! has_file "bun.lockb" && ! has_file "pnpm-lock.yaml"; then
    if [ "$CMD_BINARY" = "npm" ]; then
        # Block package-mutating commands; allow npm run / npm exec / npm test etc.
        if echo "$command" | grep -qE \
            '(^|[[:space:]])npm[[:space:]]+(install|i|add|remove|rm|uninstall|update|up|upgrade|ci)([[:space:]]|$)'; then
            deny "yarn.lock present — use yarn instead of npm for package management (yarn add · yarn install)"
        fi
    fi
fi

# --- package.json#packageManager (Corepack) ---
if has_file "package.json"; then
    declared_pm=$(jq -r '.packageManager // empty' "$PROJECT_ROOT/package.json" 2>/dev/null || echo "")
    if [ -n "$declared_pm" ]; then
        pm_name=$(echo "$declared_pm" | cut -d'@' -f1)
        case "$pm_name" in
            bun)
                case "$CMD_BINARY" in
                    npm|npx|yarn|pnpm)
                        deny "package.json declares packageManager=$declared_pm — use bun instead of $CMD_BINARY"
                        ;;
                esac
                ;;
            pnpm)
                case "$CMD_BINARY" in
                    npm|yarn)
                        deny "package.json declares packageManager=$declared_pm — use pnpm instead of $CMD_BINARY"
                        ;;
                esac
                ;;
            yarn)
                if [ "$CMD_BINARY" = "npm" ]; then
                    if echo "$command" | grep -qE \
                        '(^|[[:space:]])npm[[:space:]]+(install|i|add|remove|rm|uninstall|update|up|upgrade|ci)([[:space:]]|$)'; then
                        deny "package.json declares packageManager=$declared_pm — use yarn instead of npm"
                    fi
                fi
                ;;
        esac
    fi
fi

# =============================================================================
# Section 2: Python Toolchain Rules
# =============================================================================

VENV="${VIRTUAL_ENV:-}"

# --- Active virtualenv: block tools called via their global filesystem paths ---
if [ -n "$VENV" ]; then
    venv_name=$(basename "$VENV")

    # Explicit global pip paths bypass the venv activation
    if echo "$command" | grep -qE '(^|[[:space:]])/usr/(local/)?bin/pip[0-9]*[[:space:]]'; then
        deny "VIRTUAL_ENV '$venv_name' active — do not call /usr/…/pip directly; use 'pip' or 'python -m pip' within the venv"
    fi

    # python3 -m pip can silently use the system interpreter, not the venv's
    if echo "$command" | grep -qE '(^|[[:space:]])python3[[:space:]]+-m[[:space:]]+pip'; then
        deny "VIRTUAL_ENV '$venv_name' active — use 'pip' or 'python -m pip' (not python3) to stay within the venv"
    fi

    # Explicit global paths to common tools (ansible, poetry, etc.)
    if echo "$command" | grep -qE \
        '(^|[[:space:]])/usr/(local/)?bin/(ansible(-[a-z]+)?|poetry|pipx)[[:space:]]'; then
        tool=$(echo "$command" | grep -oE '/usr/(local/)?bin/[^ ]+' | head -1 | xargs basename)
        deny "VIRTUAL_ENV '$venv_name' active — calling global '$tool' may bypass the venv; use the venv-local binary instead"
    fi
fi

# --- uv project: pip/pip3 will install outside uv's managed environment ---
if has_file "uv.lock"; then
    case "$CMD_BINARY" in
        pip|pip3)
            deny "uv.lock present — use 'uv add' or 'uv sync' instead of $CMD_BINARY to keep the lockfile in sync"
            ;;
        python|python3)
            if echo "$command" | grep -qE \
                '(^|[[:space:]])python[0-9.]*[[:space:]]+-m[[:space:]]+pip'; then
                deny "uv.lock present — use 'uv add' instead of 'python -m pip' to keep the lockfile in sync"
            fi
            ;;
    esac
fi

# =============================================================================
# Section 3: Git invocation pattern
# =============================================================================

# Block `git -C /absolute/path <action>` only when the path resolves to the
# current project. This catches the common agent anti-pattern of using the
# project's own absolute path (which bypasses permission rules like
# `Bash(git status *)`) while allowing genuine cross-repo operations.
#
# Relative paths (-C . / -C ../sibling) are always allowed.
if [ "$CMD_BINARY" = "git" ]; then
    # Extract the argument after -C, but only if it's an absolute path
    c_path=$(echo "$command" | awk '{
        for (i=1; i<NF; i++) {
            if ($i == "-C" && substr($(i+1), 1, 1) == "/") {
                print $(i+1); exit
            }
        }
    }')

    if [ -n "$c_path" ]; then
        # Resolve symlinks so /var/… and /private/var/… compare equal on macOS.
        # Walk up to the nearest existing ancestor, resolve it, then reattach
        # any non-existent suffix (handles paths like /project/src that don't
        # exist yet but whose parent does).
        _resolve_path() {
            local p="${1%/}" suffix=""
            while [ -n "$p" ] && [ "$p" != "/" ] && [ ! -e "$p" ]; do
                suffix="/$(basename "$p")$suffix"
                p="$(dirname "$p")"
            done
            echo "$(realpath "$p" 2>/dev/null || echo "$p")$suffix"
        }
        norm_c=$(_resolve_path "$c_path")
        norm_root="${PROJECT_ROOT%/}"   # PROJECT_ROOT already from pwd -P

        # Block only if the target is the project root or a subdirectory of it
        if [ "$norm_c" = "$norm_root" ] || \
           [[ "$norm_c" == "$norm_root/"* ]]; then
            deny "Use bare 'git <action>' instead of 'git -C $c_path' — that path is the current project; bare git commands also match permission rules correctly"
        fi
        # Path points elsewhere (different repo) — fall through and allow
    fi
fi

# =============================================================================
# Section 4: Interpreter heredoc anti-pattern
# =============================================================================

# Block `python3 << 'EOF' ... EOF` and equivalent for node, perl, ruby, etc.
# These invocations cannot be meaningfully permission-scoped — the interpreter
# can do anything, so an "allow" rule is effectively unrestricted.
#
# Excluded: bash/sh heredocs (normal shell usage), short `-c`/`-e` one-liners
# (a different tradeoff — can be revisited separately).
if echo "$command" | grep -qE \
    "(^|[[:space:];|&/])(python[0-9.]*|ipython[0-9.]*|pypy[0-9.]*|py|nodejs|node|ts-node|tsx|deno|bun|perl[0-9.]*|ruby[0-9.]*|php[0-9.]*|tclsh|osascript)[[:space:]]+[^;|&]*<<-?[[:space:]]*['\"]?[A-Za-z_]"; then
    deny "Interpreter heredocs (e.g. 'python3 << EOF') can't be safely permission-scoped — the interpreter can touch anything. Use instead:
  • Read / Grep / Glob tools for file inspection
  • rg -Pzo '(?s)pattern' for multi-line regex extraction
  • awk '/start/,/end/' for block extraction
  • jq / yq / ast-grep for structured data (JSON / YAML / AST)
  • If a script is genuinely needed: write it to a file, run it, then delete"
fi

# =============================================================================
# Section 5: Interpreter one-liner filesystem-deletion anti-pattern
# =============================================================================

# Block `python3 -c "import os; os.remove(...)"` and equivalent across
# node/deno/bun/perl/ruby/php/osascript. These bypass shell-level safety
# (rm aliases, the Bash permission rule surface, the Bash deny list) by
# performing the deletion through the interpreter instead of `rm`.
#
# Detection: interpreter invoked with -c/-e/-E/-r AND the inline code
# contains a destructive filesystem call.
#
# If a delete is genuinely needed, use `rm` directly so permission rules
# and shell aliases apply — or use the Write tool path.

interp_inline_re="(^|[[:space:];|&/])(python[0-9.]*|ipython[0-9.]*|pypy[0-9.]*|py|nodejs|node|ts-node|tsx|deno|bun|perl[0-9.]*|ruby[0-9.]*|php[0-9.]*|tclsh|osascript)[[:space:]]+[^;|&]*-[ceErR]([[:space:]]|$)"

# Destructive call signatures across supported interpreters.
# Kept narrow on purpose: deletes only. Truncating writes (open(...,'w'))
# and ad-hoc fixture writes are intentionally NOT matched here.
destructive_calls_re="(os\.(remove|unlink|rmdir|removedirs)[[:space:]]*\(|shutil\.rmtree[[:space:]]*\(|\.(unlink|unlinkSync|rm|rmSync|rmdir|rmdirSync)[[:space:]]*\(|Deno\.remove(Sync)?[[:space:]]*\(|File\.(delete|unlink)|FileUtils\.rm[a-z_]*|Dir\.(rmdir|delete)|(^|[^A-Za-z_])unlink[[:space:]]*[\"'(]|(^|[^A-Za-z_])rmdir[[:space:]]*\(|os\.system[[:space:]]*\([^)]*[\"']rm[[:space:]]|subprocess\.[A-Za-z_]+[[:space:]]*\([^)]*[\"']rm[[:space:]]|subprocess\.[A-Za-z_]+[[:space:]]*\(\[[[:space:]]*[\"']rm[\"'])"

if echo "$command" | grep -qE "$interp_inline_re"; then
    if echo "$command" | grep -qE "$destructive_calls_re"; then
        deny "Interpreter one-liner performing a filesystem deletion is blocked — this bypasses shell aliases, the Bash permission surface, and the deny list. If you genuinely need to delete a file, run 'rm <path>' directly so the normal safety checks apply; if a richer script is needed, write it to a file and run that."
    fi
fi

# All checks passed — allow
exit 0
