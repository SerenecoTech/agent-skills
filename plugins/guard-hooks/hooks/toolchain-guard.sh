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

# =============================================================================
# Section 6: commands whose stdout IS a credential
# =============================================================================

# These commands do not touch the filesystem and break nothing. What they do is
# print a live secret, and an agent's stdout becomes conversation transcript,
# which is summarised into session memory and can be indexed by project memory
# stores. A token in a transcript has to be treated as rotated, not deleted.
#
# Written after a real incident: `git credential fill` was used to inspect which
# fields a credential helper receives. The stub helper under test returned
# nothing, so git fell through to the configured osxkeychain helper and printed a
# real OAuth token with org-admin and SSH-key-write scopes into the transcript.
# The command looked like introspection. It was exfiltration.

# Command boundaries. `$(` and a backtick have to open a command as much as a
# space or a pipe does, and `)` has to close one: without them
# `TOKEN=$(gh auth token)` reads as no command at all and walks straight through.
# `/` belongs here too — `/opt/homebrew/bin/gh` is the same binary as `gh`.
CRED_PRE='(^|[[:space:];|&(`/])'
CRED_POST='([[:space:];|&)`]|$)'

# Quotes around a word change nothing about what runs, so `gh auth "token"` has
# to match as `gh auth token` does.
CRED_Q='["'"'"']*'

# The matching copy of the command. Two normalisations, both matching-only:
#
#   1. A leading backslash suppresses an alias and nothing else — `\gh` is `gh`.
#   2. A quoted run containing whitespace is prose, not a command: it belongs to
#      whatever command owns the quotes. Without this, `git commit -m "block git
#      credential fill"` is denied — the commit message for this section cannot
#      be typed. Quotes attached to `=` are left alone, because that is an option
#      value (`-c credential.helper="!f() { …; }; f"`) and its content decides.
#
# A newline stands in as CRED_NL while (2) runs, because sed works a line at a
# time and a commit body is prose that spans lines.
#
# The cost of (2) is that `bash -c "gh auth token"` is out of reach. Nothing a
# regex does can both read inside quotes and not read inside prose.
# \001-\004 are this section's own sentinels for a newline and for separators
# masked inside quotes. They carry meaning only inside the matching copy, so a
# command that contains them for real is stripped of them first — otherwise the
# caller writes its own sentinels and chooses how the line is split.
#
# Order matters. The quote-state scan runs first, on the original quotes: the
# prose strip and the unquoting below both remove quote characters, and either
# one leaves an odd count behind that would desync the scan.
CRED_NL=$'\001'
cred_cmd=$(printf '%s' "$command" \
    | tr -d '\001\002\003\004' \
    | sed -E 's/\\([A-Za-z])/\1/g' \
    | tr '\n' "$CRED_NL" \
    | awk '
{
    q = ""; out = ""
    for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "\\" && i < length($0)) {
            out = out c substr($0, i + 1, 1)
            i++
            continue
        }
        if (q == "") {
            if (c == "\"" || c == "\047") q = c
            out = out c
        } else if (c == q) {
            q = ""; out = out c
        } else if (c == ";") { out = out "\002" }
        else if (c == "|")   { out = out "\003" }
        else if (c == "&")   { out = out "\004" }
        else                 { out = out c }
    }
    print out
}' \
    | sed -E "s/^\"[^\"]*[[:space:]${CRED_NL}][^\"]*\"//" \
    | sed -E "s/([^>[:space:]${CRED_NL}])([[:space:]${CRED_NL}]+)\"[^\"]*[[:space:]${CRED_NL}][^\"]*\"/\\1\\2/g" \
    | sed -E "s/^'[^']*[[:space:]${CRED_NL}][^']*'//" \
    | sed -E "s/([^>[:space:]${CRED_NL}])([[:space:]${CRED_NL}]+)'[^']*[[:space:]${CRED_NL}][^']*'/\\1\\2/g" \
    | sed -E "s/(^|[[:space:]${CRED_NL}])\"([^\"'[:space:]${CRED_NL}]*)\"/\\1\\2/g" \
    | sed -E "s/(^|[[:space:]${CRED_NL}])'([^\"'[:space:]${CRED_NL}]*)'/\\1\\2/g" \
    | sed -E "s/(^|[[:space:]${CRED_NL}])\"([^\"'[:space:]${CRED_NL}]*)\"/\\1\\2/g" \
    | sed -E "s/(^|[[:space:]${CRED_NL}])'([^\"'[:space:]${CRED_NL}]*)'/\\1\\2/g" \
    | tr "$CRED_NL" '\n')

# The body of a command substitution is a command in its own right, wherever it
# is written. Inside quotes it survives the prose strip above — `echo "$(gh auth
# token)"` prints the token exactly as the bare command does — so the bodies are
# appended as lines of their own and matched as separate segments.
# Both a shortest and a longest read of `$(…)`: a body may contain its own
# parens — `$(echo ')' ; gh auth token)` — and the shortest read stops at the
# first one, dropping the command that follows.
cred_subs=$(printf '%s' "$command" | grep -oE '\$\([^)]*\)|\$\(.*\)|`[^`]*`|`.*`' \
    | sed -E 's/^\$\(//; s/^`//; s/\)$//; s/`$//' || true)
if [ -n "$cred_subs" ]; then
    cred_cmd="$cred_cmd
$cred_subs"
fi

# A run of `git` global options ahead of the subcommand. An option value can be
# quoted and can contain spaces — `-c credential.helper="!f() { …; }; f"` is one
# option — and a run that cannot express that stops matching the subcommand
# entirely, which reads as "no credential command here" and allows it.
CRED_OPTVAL="[^[:space:]]*(\"[^\"]*\"|'[^']*')?[^[:space:]]*"
CRED_OPTS="([[:space:]]+-[^[:space:]]+([[:space:]]+${CRED_OPTVAL})?)*"

# --- what a redirect actually protects -------------------------------------
# A redirect belongs to one stream of one command. `echo x > f; gh auth token`
# redirects echo; `gh auth token 2>/dev/null` redirects stderr while stdout
# still prints. So the check has to run against the segments holding the match,
# and only a redirect of *stdout* counts.

# The command line split into segments. `&` separates commands as much as `;`
# does, so a lone one splits too — but not `&&`, `&>`, `>&` or `2>&1`. A group's
# closing `; }` is punctuation rather than a separator, so `{ cmd; } > f` stays
# whole and keeps its redirect.
cred_segments() {
    printf '%s\n' "$cred_cmd" \
        | sed -E 's/;[[:space:]]*\}/ }/g' \
        | sed -E 's/\|\||&&/\n/g' \
        | sed -E 's/;/\n/g' \
        | sed -E 's/([^>])\|/\1\n/g' \
        | sed -E 's/([^>&])&([^&>])/\1\n\2/g'
}

# True when this segment sends its own stdout somewhere the transcript cannot
# see. `/dev/stdout`, `/dev/stderr`, a tty and `/dev/fd/N` are all still the
# transcript; `>&1` and `1>&2` name no file at all.
cred_stdout_is_redirected() {
    local seg="$1" target
    # A redirect inside a command substitution belongs to the inner command.
    seg=$(printf '%s' "$seg" | sed -E 's/\$\([^)]*\)//g; s/`[^`]*`//g')
    # Drop redirects of any descriptor other than 1 — 0, 2-9, and 10 upward.
    seg=$(printf '%s' "$seg" | sed -E 's/(^|[[:space:]])([02-9][0-9]*|1[0-9]+)>>?[[:space:]]*[^[:space:]]*//g')
    # `>|` is the noclobber override, and still a plain stdout redirect.
    target=$(printf '%s' "$seg" | grep -oE '(&|1)?>>?\|?[[:space:]]*[^[:space:]<>&|;]+' \
        | tail -1 | sed -E 's/^[^>]*>>?\|?[[:space:]]*//' || true)
    # The shell strips quotes from a redirect target and collapses `/./`, so
    # `> "/dev/stdout"` and `> /dev/./stdout` are both the transcript.
    target=$(printf '%s' "$target" | tr -d "\"'" | sed -E 's#/\./#/#g' || true)
    [ -n "$target" ] || return 1
    case "$target" in
        /dev/stdout|/dev/stderr|/dev/console|/dev/tty*|/dev/fd/*) return 1 ;;
    esac
    return 0
}

# --- git credential fill ---------------------------------------------------
# `fill` asks every configured helper in turn and prints the assembled
# credential. Passing `-c credential.helper=` first resets the helper list to
# empty, so only a helper named explicitly on that command line can answer -
# which is what makes an inspection of helper behaviour safe.
# The reset protects the command it is written on, not every command sharing the
# line: `git -c credential.helper= credential fill; git credential fill` runs an
# unprotected fill second. So each segment that runs `fill` is judged alone.
cred_fill_re="${CRED_PRE}git${CRED_OPTS}[[:space:]]+${CRED_Q}credential${CRED_Q}[[:space:]]+${CRED_Q}fill${CRED_Q}${CRED_POST}"

while IFS= read -r cred_seg; do
    [ -n "$cred_seg" ] || continue

    # `-c` needs a boundary of its own: without one, `#-c credential.helper=` in
    # a trailing comment reads as a reset that never executes.
    if ! echo "$cred_seg" | grep -qE -- "(^|[[:space:]])-c[[:space:]]+${CRED_Q}credential\.helper=${CRED_Q}([[:space:]]|\$)"; then
        deny "'git credential fill' prints a real credential to stdout, and stdout becomes transcript. It consults every configured helper, so on a machine with osxkeychain (or any store) configured it emits a live token even when the helper you are testing returns nothing.

To inspect what a helper receives, reset the helper list first so only yours can answer:
  git -c credential.helper= -c credential.helper=/path/to/your-helper credential fill

If you need to know whether a credential EXISTS, check the store's own state instead of filling. If you genuinely need the value on disk, redirect it to a 0600 file and never to stdout."
    fi

    # An empty `credential.helper` only clears the list. Anything else on this
    # command that puts a helper back defeats it, and `-c credential.helper=` is
    # not the only spelling: a URL-scoped helper, `--config-env`, and an
    # included config file all re-arm the list, verified against git 2.55 with a
    # stub helper that answered in every one of those forms.
    if echo "$cred_seg" | grep -qE -- '(--config-env|include\.path=|credential\.[^[:space:]=]+\.helper=)'; then
        deny "This resets the credential helper list and then puts a helper back on it by another route, so 'fill' still prints a live credential to stdout — and stdout becomes transcript.

A URL-scoped helper (credential.https://host.helper=…), --config-env, and -c include.path= are all applied after the reset. Only the plain 'credential.helper=' form is a reset, and only a helper you wrote may follow it:
  git -c credential.helper= -c credential.helper=/path/to/your-helper credential fill"
    fi

    # The reset only helps if what gets re-added is a helper you wrote. A bare
    # name (osxkeychain, manager, store, cache) IS the real store, and a `!…`
    # value is an arbitrary shell snippet that can call it. Naming one by path
    # is the same store by a longer name: they ship as git-credential-* binaries
    # under git's exec-path, so the path form has to be checked, not trusted.
    cred_stores='(osxkeychain|manager|manager-core|libsecret|wincred|gnome-keyring|store|cache|netrc|gcloud|helper-selector)'
    cred_readded=""
    while IFS= read -r cred_val; do
        [ -n "$cred_val" ] || continue
        case "$cred_val" in
            /*|./*|../*|~*) ;;                      # named by path — check which
            *) cred_readded="$cred_val"; break ;;   # a bare name or a !snippet
        esac
        cred_base="${cred_val##*/}"
        cred_base="${cred_base#git-credential-}"
        if printf '%s' "$cred_base" | grep -qE "^${cred_stores}\$"; then
            cred_readded="$cred_val"
            break
        fi
    done < <(printf '%s' "$cred_seg" \
        | grep -oE -- "-c[[:space:]]+${CRED_Q}credential\.helper=[^[:space:]]*" \
        | sed -E 's/.*credential\.helper=//' | tr -d "\"'" || true)

    if [ -n "$cred_readded" ]; then
        # Restore any separators masked inside quotes, for the message only.
        cred_readded=$(printf '%s' "$cred_readded" | tr '\002\003\004' ';|&' || true)
        deny "This resets the credential helper list and then names '$cred_readded', which puts a real store back on it — so 'fill' still prints a live credential to stdout, and stdout becomes transcript.

The reset is only protective when the helper re-added afterwards is one you wrote, named by path:
  git -c credential.helper= -c credential.helper=/path/to/your-helper credential fill

A bare helper name is the system store. So is a path ending in git-credential-osxkeychain (or -store, -cache, -manager, …) — the stores ship as executables under git's exec-path, so naming one by path is the same store spelled longer. A '!…' value is a shell snippet, which can call any of them."
    fi
done < <(cred_segments | grep -E "$cred_fill_re" || true)

# --- direct helper invocation ----------------------------------------------
# `git credential-osxkeychain get` (and any other credential-* helper) asks the
# store directly and prints the result. There is no helper list to reset here,
# so there is no safe form of this command for an agent to run.
if echo "$cred_cmd" | grep -qE "(^|[[:space:];|&(\`/])git-credential-[a-z0-9-]+${CRED_Q}[[:space:]]+${CRED_Q}get${CRED_Q}${CRED_POST}" ||
    echo "$cred_cmd" | grep -qE "${CRED_PRE}git[[:space:]]+${CRED_Q}credential-[a-z0-9-]+${CRED_Q}[[:space:]]+${CRED_Q}get${CRED_Q}${CRED_POST}"; then
    deny "Invoking a git credential helper's 'get' prints the stored secret to stdout, and stdout becomes transcript. There is no helper list to reset for a direct invocation, so there is no safe form of this command.

To confirm a credential exists without reading it, check the store's own listing (e.g. Keychain Access, or the helper's own status output). To use a credential, let git call the helper itself rather than reading the value out first."
fi

# --- CLI token printers ----------------------------------------------------
# `gh auth token` and `--show-token` exist to print the token. Sending its
# stdout to a file is a legitimate use and never reaches the transcript, so that
# form is allowed. A bare invocation, a pipe, a stderr-only redirect, or a
# redirect belonging to a different command in the line are all not.
gh_token_re="${CRED_PRE}gh${CRED_Q}[[:space:]]+${CRED_Q}auth${CRED_Q}[[:space:]]+${CRED_Q}token${CRED_Q}${CRED_POST}"
# `-t` is the documented short spelling of `--show-token`, and short flags
# cluster in any order — pflag decomposes left to right, so `-ta` and `-at` are
# the same two flags — hence `t` anywhere in the cluster. A long option never
# matches: `--hostname` cannot, because the class after the single `-` excludes
# another `-`. The terminator is CRED_POST, not whitespace: an operator can
# follow the flag directly, as in `TOK=$(gh auth status --show-token)`.
gh_showtoken_re="${CRED_PRE}gh${CRED_Q}[[:space:]]+${CRED_Q}auth${CRED_Q}[[:space:]]+${CRED_Q}status${CRED_Q}[^;|&]*[[:space:]](--show-token|-[a-zA-Z]*t[a-zA-Z]*)${CRED_POST}"

cred_hit=""
if echo "$cred_cmd" | grep -qE "$gh_token_re"; then
    cred_hit="$gh_token_re"
elif echo "$cred_cmd" | grep -qE "$gh_showtoken_re"; then
    cred_hit="$gh_showtoken_re"
fi

# Every segment that runs the command has to be covered. A redirect on the first
# occurrence says nothing about a second one later on the same line.
cred_every_hit_is_redirected() {
    local pattern="$1" seg matched=0
    while IFS= read -r seg; do
        [ -n "$seg" ] || continue
        matched=1
        cred_stdout_is_redirected "$seg" || return 1
    done < <(cred_segments | grep -E "$pattern" || true)
    [ "$matched" -eq 1 ] || return 1
    return 0
}

if [ -n "$cred_hit" ]; then
    if ! cred_every_hit_is_redirected "$cred_hit"; then
        deny "This command prints a live GitHub token to stdout, and stdout becomes transcript. Session memory summarises transcripts, so a token printed here has to be treated as compromised and rotated.

If you need the token on disk, send its own stdout to a file and lock it down:
  gh auth token > ~/.config/somewhere/token && chmod 0600 ~/.config/somewhere/token

Note what does NOT count: '2>/dev/null' redirects stderr while stdout still prints, a redirect on another command in the line protects only that command, and '/dev/stdout', '/dev/tty' and '/dev/fd/N' are the transcript.

If you need to know whether authentication is working, 'gh auth status' without --show-token reports the account and scopes and prints no secret."
    fi
fi

# All checks passed — allow
exit 0
