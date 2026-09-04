#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Claude Code Hook: PreToolUse - Check Compound Bash Commands
# =============================================================================
# Reads a Bash tool call on stdin and decides:
#   allow  (skip prompt)  every (sub-)command is allowed and none denied
#   deny   (exit 2)       any (sub-)command matches a deny rule
#   else   (exit 0)       fall through to Claude Code's native prompt/rules
#
# Compound commands (pipes, chains, subshells, substitutions, bash -c, ...) are
# split via shfmt's AST and each segment is checked independently.
#
# Rules come from .claude/settings.json (user + project) Bash(...) specifiers:
#   allow  literal start-anchored prefix. Bash(ls *) matches `ls`/`ls -la`, not
#          `lsof`; embedded `*` is literal (conservative - native may still
#          auto-approve mid-wildcard allows).
#   deny   literal prefix OR native-style glob, so trailing/mid-command flags
#          are caught: `*` matches any run of chars (incl. spaces) anywhere,
#          trailing ` *` (or `:*`) means "space-or-end-of-string". Mirrors
#          Claude Code's matcher - Bash(find * -delete*) blocks `find . -delete`,
#          Bash(sed -i*) blocks every in-place sed. A strict superset of literal.
#
# Deny is matched even though Bash(find *) would make this hook return `allow`:
# native deny-first precedence would still block it, but matching here keeps the
# hook self-consistent rather than relying on the native override.
#
# Dependencies: bash 4.3+, shfmt, jq
# =============================================================================
set -uo pipefail

# Re-exec with modern bash if running old bash (namerefs require 4.3+)
if [[ "${BASH_VERSINFO[0]}" -lt 4 || ( "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -lt 3 ) ]]; then
  for try_bash in /opt/homebrew/bin/bash /usr/local/bin/bash /home/linuxbrew/.linuxbrew/bin/bash; do
    if [[ -x "$try_bash" ]]; then
      exec "$try_bash" "$0" "$@"
    fi
  done
  exit 0
fi

DEBUG=false
readonly ALLOW_JSON='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'

debug() { if $DEBUG; then printf '[check-compound] %s\n' "$*" >&2; fi; }
approve() { printf '%s\n' "$ALLOW_JSON"; exit 0; }
deny() {
  jq -n --arg msg "$1" '{
    hookSpecificOutput: {hookEventName:"PreToolUse", permissionDecision:"deny"},
    systemMessage: $msg
  }' >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Permission loading (single pass over all settings files)
# ---------------------------------------------------------------------------

find_git_root() {
  local toplevel git_dir git_common_dir
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || return
  git_dir=$(git rev-parse --git-dir 2>/dev/null)
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  if [[ "$git_dir" != "$git_common_dir" ]]; then
    dirname "$git_common_dir"
  else
    printf '%s\n' "$toplevel"
  fi
}

# Populates the caller's allowed_prefixes, denied_prefixes, and denied_globs arrays.
load_prefixes() {
  local git_root
  git_root=$(find_git_root 2>/dev/null || true)

  local files=(
    "$HOME/.claude/settings.json"
    "$HOME/.claude/settings.local.json"
  )
  if [[ -n "$git_root" ]]; then
    files+=("$git_root/.claude/settings.json" "$git_root/.claude/settings.local.json")
  else
    files+=(".claude/settings.json" ".claude/settings.local.json")
  fi

  local line
  while IFS= read -r line; do
    case "$line" in
      allow:*)    allowed_prefixes+=("${line#allow:}") ;;
      denyglob:*) denied_globs+=("${line#denyglob:}") ;;
      deny:*)     denied_prefixes+=("${line#deny:}") ;;
    esac
  done < <(
    for file in "${files[@]}"; do
      [[ -f "$file" ]] || continue
      debug "Reading prefixes from: $file"
      jq -r '
        def extract_prefix: sub("^Bash\\("; "") | sub("( \\*|\\*|:\\*)\\)$"; "") | sub("\\)$"; "");
        def extract_glob:   sub("^Bash\\("; "") | sub("\\)$"; "");
        (.permissions.allow[]? // empty | select(startswith("Bash(")) | "allow:" + extract_prefix),
        (.permissions.deny[]?  // empty | select(startswith("Bash(")) | "deny:"  + extract_prefix),
        (.permissions.deny[]?  // empty | select(startswith("Bash(")) | "denyglob:" + extract_glob)
      ' "$file" 2>/dev/null || true
    done | sort -u
  )
}

# ---------------------------------------------------------------------------
# Command detection and parsing (shfmt AST -> individual commands via jq)
# ---------------------------------------------------------------------------

# Returns 0 if the command needs compound parsing (contains shell metacharacters
# that could hide sub-commands: pipes, chains, semicolons, command substitution,
# process substitution, backticks).
needs_compound_parse() {
  # shellcheck disable=SC2016  # $( is a literal pattern, not an expansion
  [[ "$1" == *['|&;`']* || "$1" == *'$('* || "$1" == *'<('* || "$1" == *'>('* ]]
}

# read returns 1 on EOF before delimiter; || true prevents exit under pipefail
read -r -d '' SHFMT_AST_FILTER << 'JQEOF' || true
def get_part_value:
  if (type == "object" | not) then ""
  elif .Type == "Lit" then .Value // ""
  elif .Type == "DblQuoted" then
    "\"" + ([.Parts[]? | get_part_value] | join("")) + "\""
  elif .Type == "SglQuoted" then
    "'" + (.Value // "") + "'"
  elif .Type == "ParamExp" then
    "$" + (.Param.Value // "")
  elif .Type == "CmdSubst" then "$(..)"
  else ""
  end;

def find_cmd_substs:
  if type == "object" then
    if .Type == "CmdSubst" or .Type == "ProcSubst" then .
    elif .Type == "DblQuoted" then .Parts[]? | find_cmd_substs
    elif .Type == "ParamExp" then
      (.Exp?.Word | find_cmd_substs),
      (.Repl?.Orig | find_cmd_substs),
      (.Repl?.With | find_cmd_substs)
    elif .Parts then .Parts[]? | find_cmd_substs
    else empty
    end
  elif type == "array" then .[] | find_cmd_substs
  else empty
  end;

def get_arg_value:
  [.Parts[]? | get_part_value] | join("");

def get_command_string:
  if .Type == "CallExpr" and .Args then
    [.Args[] | get_arg_value] | map(select(length > 0)) | join(" ")
  else empty
  end;

def extract_commands:
  if type == "object" then
    if .Type == "CallExpr" then
      get_command_string,
      (.Args[]? | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Assigns[]?.Value | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Assigns[]?.Array?.Elems[]?.Value | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Redirs[]?.Word | find_cmd_substs | .Stmts[]? | extract_commands)
    elif .Type == "BinaryCmd" then
      (.X | extract_commands), (.Y | extract_commands)
    elif .Type == "Subshell" or .Type == "Block" then
      (.Stmts[]? | extract_commands)
    elif .Type == "CmdSubst" then
      (.Stmts[]? | extract_commands)
    elif .Type == "IfClause" then
      (.Cond[]? | extract_commands),
      (.Then[]? | extract_commands),
      (.Else | extract_commands)
    elif .Type == "WhileClause" or .Type == "UntilClause" then
      (.Cond[]? | extract_commands), (.Do[]? | extract_commands)
    elif .Type == "ForClause" then
      (.Loop.Items[]? | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Do[]? | extract_commands)
    elif .Type == "CaseClause" then
      (.Items[]?.Stmts[]? | extract_commands)
    elif .Type == "DeclClause" then
      (.Args[]?.Value | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Args[]?.Array?.Elems[]?.Value | find_cmd_substs | .Stmts[]? | extract_commands)
    elif .Cmd then
      (.Cmd | extract_commands),
      (.Redirs[]?.Word | find_cmd_substs | .Stmts[]? | extract_commands)
    elif .Stmts then
      (.Stmts[] | extract_commands)
    else
      (.[] | extract_commands)
    end
  elif type == "array" then
    (.[] | extract_commands)
  else empty
  end;

extract_commands | select(length > 0)
JQEOF
readonly SHFMT_AST_FILTER

# Parse compound command into individual commands (NUL-delimited)
parse_compound() {
  local cmd="$1"

  # Normalize [[ \! $x =~ ]] patterns that shfmt can't parse
  if [[ "$cmd" == *"=~"* ]]; then
    cmd=$(sed -E 's/\[\[[[:space:]]*\\?![[:space:]]+(.+)[[:space:]]+=~/! [[ \1 =~/g' <<< "$cmd")
  fi

  local ast
  if ! ast=$(shfmt -ln bash -tojson <<< "$cmd" 2>/dev/null); then
    debug "shfmt parse failed"
    return 1
  fi

  local raw_commands
  raw_commands=$(jq -r "$SHFMT_AST_FILTER" <<< "$ast" 2>/dev/null) || return 1

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Recursively expand bash -c / sh -c
    if [[ "$line" =~ ^(env[[:space:]]+)?(/[^[:space:]]*/)?((ba)?sh)[[:space:]]+-c[[:space:]]*[\'\"](.*)[\'\"]$ ]]; then
      debug "Recursing into shell -c: ${BASH_REMATCH[5]}"
      if ! parse_compound "${BASH_REMATCH[5]}"; then
        # Inner parse failed - emit wrapper as-is so it gets checked
        # against allow/deny lists (and likely falls through)
        printf '%s\0' "$line"
      fi
    else
      printf '%s\0' "$line"
    fi
  done <<< "$raw_commands"
}

# ---------------------------------------------------------------------------
# Permission matching
# ---------------------------------------------------------------------------

# Strip leading env var assignments (VAR=val cmd ...) and populate
# the caller's candidates array via nameref.
strip_env_vars() {
  local full_command="$1"
  local -n out_ref=$2
  local stripped="$full_command"

  while [[ "$stripped" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*) ]]; do
    stripped="${BASH_REMATCH[1]}"
  done

  out_ref=("$full_command")
  [[ "$stripped" != "$full_command" ]] && out_ref+=("$stripped")
}

# Check if a command matches any prefix in the given list.
matches_prefix_list() {
  local full_command="$1"
  local -n list_ref=$2
  local label="${3:-}"

  [[ ${#list_ref[@]} -eq 0 ]] && return 1

  local -a candidates=()
  strip_env_vars "$full_command" candidates

  for cmd in "${candidates[@]}"; do
    for prefix in "${list_ref[@]}"; do
      if [[ "$cmd" == "$prefix" ]] || [[ "$cmd" == "$prefix "* ]] || [[ "$cmd" == "$prefix/"* ]]; then
        debug "MATCH ($label): '$cmd' -> '$prefix'"
        return 0
      fi
    done
  done
  return 1
}

# Match one command against one glob pattern, per the native deny semantics
# described in the file header.
glob_match_one() {
  local cmd="$1" pat="$2"

  # `:*` is an equivalent trailing wildcard; normalize it to ` *`.
  [[ "$pat" == *':*' ]] && pat="${pat%:\*} *"

  # Direct glob match (pat is UNQUOTED so * is an active glob metachar).
  # shellcheck disable=SC2053
  [[ "$cmd" == $pat ]] && return 0

  # Trailing ` *` also matches the prefix at end-of-string (word boundary).
  if [[ "$pat" == *' *' ]]; then
    local base="${pat% \*}"
    # shellcheck disable=SC2053
    [[ "$cmd" == $base ]] && return 0
  fi
  return 1
}

# Check if a command matches any glob pattern in the given list. Unlike
# matches_prefix_list (literal, start-anchored), this honors mid-command
# wildcards so deny rules like `find * -delete*` are enforced.
matches_glob_list() {
  local full_command="$1"
  local -n glist_ref=$2
  local label="${3:-}"

  [[ ${#glist_ref[@]} -eq 0 ]] && return 1

  local -a candidates=()
  strip_env_vars "$full_command" candidates

  for cmd in "${candidates[@]}"; do
    for pat in "${glist_ref[@]}"; do
      if glob_match_one "$cmd" "$pat"; then
        debug "MATCH ($label glob): '$cmd' ~ '$pat'"
        return 0
      fi
    done
  done
  return 1
}

# Check a single command against the deny lists (literal prefix OR native-style
# glob). Returns 0 if denied.
is_denied() {
  local cmd="$1"
  matches_prefix_list "$cmd" denied_prefixes "deny" && return 0
  matches_glob_list "$cmd" denied_globs "deny" && return 0
  return 1
}

# Check a single command against deny then allow lists.
# Returns: 0=allowed, 1=not allowed (denied or unknown)
is_allowed() {
  local cmd="$1"
  if is_denied "$cmd"; then
    return 1
  fi
  matches_prefix_list "$cmd" allowed_prefixes "allow"
}

# Check all commands in the given array. Returns 0 only if every one is allowed.
all_allowed() {
  local -n cmds_ref=$1

  for cmd in "${cmds_ref[@]}"; do
    [[ -z "$cmd" ]] && continue
    if ! is_allowed "$cmd"; then
      debug "Not all commands approved"
      return 1
    fi
  done
  return 0
}

# Check if any command in the given array matches the deny list.
any_denied() {
  local -n cmds_ref=$1
  [[ ${#denied_prefixes[@]} -eq 0 && ${#denied_globs[@]} -eq 0 ]] && return 1

  for cmd in "${cmds_ref[@]}"; do
    [[ -z "$cmd" ]] && continue
    if is_denied "$cmd"; then
      debug "Denied segment found: $cmd"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local permissions_json="" deny_json="" mode="hook"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --debug) DEBUG=true; shift ;;
      --permissions) permissions_json="$2"; shift 2 ;;
      --deny) deny_json="$2"; shift 2 ;;
      parse) mode="parse"; shift ;;
      *) shift ;;
    esac
  done

  # Guard: dependencies
  for dep in jq shfmt; do
    if ! command -v "$dep" &>/dev/null; then
      debug "Missing $dep, falling through"
      exit 0
    fi
  done

  # Parse mode: extract commands from stdin (plain text), one per line
  if [[ "$mode" == "parse" ]]; then
    local cmd
    cmd=$(cat)
    [[ -z "$cmd" ]] && exit 0
    if ! needs_compound_parse "$cmd"; then
      printf '%s\n' "$cmd"
    else
      local -a cmds=()
      mapfile -d '' cmds < <(parse_compound "$cmd")
      for c in "${cmds[@]}"; do
        [[ -n "$c" ]] && printf '%s\n' "$c"
      done
    fi
    exit 0
  fi

  # Guard: read hook input
  local input command
  input=$(cat)
  command=$(jq -r '.tool_input.command // empty' <<< "$input")
  [[ -z "$command" ]] && exit 0

  debug "Command: $command"

  # Load permissions (from settings files, or from --permissions/--deny for testing)
  local -a allowed_prefixes=() denied_prefixes=() denied_globs=()
  if [[ -n "$permissions_json" ]]; then
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] && allowed_prefixes+=("$line")
    done < <(jq -r '.[] | sub("^Bash\\("; "") | sub("( \\*|\\*|:\\*)\\)$"; "") | sub("\\)$"; "")' <<< "$permissions_json" 2>/dev/null)
    if [[ -n "$deny_json" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && denied_prefixes+=("$line")
      done < <(jq -r '.[] | sub("^Bash\\("; "") | sub("( \\*|\\*|:\\*)\\)$"; "") | sub("\\)$"; "")' <<< "$deny_json" 2>/dev/null)
      while IFS= read -r line; do
        [[ -n "$line" ]] && denied_globs+=("$line")
      done < <(jq -r '.[] | sub("^Bash\\("; "") | sub("\\)$"; "")' <<< "$deny_json" 2>/dev/null)
    fi
  else
    load_prefixes
  fi
  debug "Loaded ${#allowed_prefixes[@]} allow, ${#denied_prefixes[@]} deny prefixes, ${#denied_globs[@]} deny globs"
  [[ ${#allowed_prefixes[@]} -eq 0 ]] && exit 0

  # Simple command - check directly without shfmt parsing
  if ! needs_compound_parse "$command"; then
    debug "Simple command"
    is_denied "$command" && deny "Command matches a denied rule"
    is_allowed "$command" && approve
    exit 0
  fi

  # Compound command - parse into segments and check each
  debug "Compound command"
  local -a extracted_commands=()
  mapfile -d '' extracted_commands < <(parse_compound "$command")

  # Parse failure or empty result - fall through to prompt (don't auto-approve
  # unparseable commands that may contain dangerous sub-commands)
  [[ ${#extracted_commands[@]} -eq 0 || -z "${extracted_commands[0]}" ]] && exit 0

  all_allowed extracted_commands && approve

  # Not all approved: actively deny if any segment is in the deny list,
  # otherwise fall through to Claude Code's native permission prompt.
  any_denied extracted_commands && deny "Compound command contains a denied sub-command"
  exit 0
}

main "$@"
