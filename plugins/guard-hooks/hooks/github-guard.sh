#!/usr/bin/env bash
# =============================================================================
# Claude Code Hook: GitHub workflow guard
# =============================================================================
# Blocks GitHub operations that bypass a safety check, rather than blocking
# the operations wholesale. A merge whose checks are green goes through
# untouched; a merge whose checks never ran does not.
#
# Rules:
#   R1  Merging a PR while a check is failing, cancelled, or still running.
#       -> deny
#   R2  Merging a PR when no check ran at all. An empty rollup is what a
#       GitHub Actions incident looks like from the client side: the merge
#       button is green because nothing reported, not because anything
#       passed. -> deny
#   R4  Deleting a branch carrying commits the current user did not author.
#       -> deny
#   R5  Deleting a branch whose name has no feature/ or hotfix/ prefix.
#       -> ask
#
# (R3, "deny when review threads are unresolved", was considered and
# dropped: passing checks is the safety signal, and unresolved-thread state
# is noise in any repo where people converse in review.)
#
# Two hook events, because the deny rules and the ask rule cannot share one:
#   PreToolUse        fires for every Bash call and supports allow/deny, so
#                     it carries R1, R2 and R4. A deny here is unappealable,
#                     which is the point.
#   PermissionRequest fires only when a call would otherwise prompt, and is
#                     the only event with an "ask" decision, so it carries
#                     R5. `git branch -D` is not commonly allow-listed, so
#                     it reaches this event and the prompt gains a reason.
#
# Unverifiable state is treated as unsafe. If `gh` is missing, logged out,
# rate-limited, erroring, or the PR cannot be identified from the command
# text, the merge is denied rather than waved through — a flaky network is
# otherwise a bypass. An unreadable *branch* name degrades to ask, not deny,
# because the branch rules are policy rather than a safety interlock.
#
# The hook stays silent where the rules provably do not apply: outside a git
# repository, or in a repository with no GitHub remote. That is a determinate
# "not in scope", not an unknown, so it falls through rather than failing
# closed.
#
# Optional configuration (all unset by default):
#   GUARD_BRANCH_PREFIXES   space-separated prefixes exempt from R5
#                           (default: "feature/ hotfix/")
#   GUARD_GITHUB_DISABLE    set to any non-empty value to disable this hook
#
# Input:  JSON via stdin with .hook_event_name and .tool_input.command
# Output: PreToolUse        -> hookSpecificOutput.permissionDecision = deny
#         PermissionRequest -> hookSpecificOutput.decision = ask
#         Silence (exit 0, no output) in every other case.
# =============================================================================

set -uo pipefail

[ -n "${GUARD_GITHUB_DISABLE:-}" ] && exit 0

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
event=$(echo "$input" | jq -r '.hook_event_name // "PreToolUse"' 2>/dev/null || echo "PreToolUse")

[ -z "$command" ] && exit 0

# -----------------------------------------------------------------------------
# Cheap scope gate. This hook is fifth in the Bash PreToolUse chain and makes
# network calls, so anything that is not a merge or a branch deletion must
# leave before any of that starts.
# -----------------------------------------------------------------------------
if ! printf '%s' "$command" | LC_ALL=C grep -qE \
    'gh[[:space:]]+pr[[:space:]]+merge|pulls/[0-9]+/merge|git[[:space:]]+branch[[:space:]]|git[[:space:]]+push[[:space:]]|git/refs/heads/'; then
    exit 0
fi

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
deny() {
    # Only PreToolUse can deny. On PermissionRequest the PreToolUse pass has
    # already denied the same command, so staying silent here is correct.
    [ "$event" = "PreToolUse" ] || exit 0
    jq -n --arg r "github-guard: $1" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
}

ask() {
    # Only PermissionRequest has an "ask" decision. On PreToolUse we cannot
    # express it, so the command falls through to the normal permission flow.
    [ "$event" = "PermissionRequest" ] || exit 0
    jq -n --arg r "github-guard: $1" \
        '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:"ask"},systemMessage:$r}'
    exit 0
}

# -----------------------------------------------------------------------------
# Split a command on top-level &&, ||, ;, | — respecting single/double quotes.
# Same approach as rm-guard.sh; the target of a merge or a deletion has to be
# read out of one specific segment, not out of the whole line.
# -----------------------------------------------------------------------------
split_segments() {
    awk '
    {
        in_sq=0; in_dq=0; out="";
        n=length($0);
        for (i=1; i<=n; i++) {
            ch=substr($0,i,1);
            nx=(i<n)?substr($0,i+1,1):"";
            if (in_sq) { out=out ch; if (ch=="\047") in_sq=0; continue; }
            if (in_dq) { out=out ch; if (ch=="\"") in_dq=0; continue; }
            if (ch=="\047") { in_sq=1; out=out ch; continue; }
            if (ch=="\"")   { in_dq=1; out=out ch; continue; }
            if ((ch=="&" && nx=="&") || (ch=="|" && nx=="|")) {
                print out; out=""; i++; continue;
            }
            if (ch==";" || ch=="|" || ch=="&") { print out; out=""; continue; }
            out=out ch;
        }
        if (length(out)>0) print out;
    }'
}

trim() {
    printf '%s' "$1" | sed -E 's/^[[:space:]]*\(?[[:space:]]*//; s/[[:space:]]*\)?[[:space:]]*$//'
}

# A segment holding a substitution or an expansion cannot be read statically:
# the PR number or branch name is whatever the shell computes at run time.
has_dynamic_value() {
    printf '%s' "$1" | LC_ALL=C grep -qE '`|\$\(|<\(|\$[A-Za-z_{]'
}

# The command word of a segment, skipping leading VAR=value assignments and an
# `env` wrapper along with its own assignments. Everything downstream keys off
# this rather than off a bare pattern match, because `echo "next: gh pr merge
# 42"` mentions a merge without performing one, and denying that is a false
# positive an agent hits while writing a commit message or a README.
command_word() {
    printf '%s' "$1" | awk '
    {
        for (i=1; i<=NF; i++) {
            t=$i
            if (t ~ /^[A-Za-z_][A-Za-z_0-9]*=/) continue
            if (t == "env") continue
            if (t ~ /^-/ && t != "-") continue
            n=split(t, parts, "/")
            print parts[n]
            exit
        }
    }'
}

# -----------------------------------------------------------------------------
# Repository resolution
# -----------------------------------------------------------------------------
# Parses OWNER/REPO out of an origin URL in either transport form.
parse_nwo_from_url() {
    local url="$1"
    url="${url%.git}"
    case "$url" in
        *github.com[:/]*) : ;;
        *) return 1 ;;
    esac
    local tail="${url##*github.com}"
    tail="${tail#:}"
    tail="${tail#/}"
    # Reject anything that is not exactly owner/repo.
    printf '%s' "$tail" | LC_ALL=C grep -qE '^[^/]+/[^/]+$' || return 1
    printf '%s' "$tail"
}

# Reads -R/--repo out of a gh invocation, else falls back to origin.
resolve_nwo() {
    local segment="$1" nwo=""

    nwo=$(printf '%s' "$segment" | LC_ALL=C sed -nE \
        's/.*(^|[[:space:]])(-R|--repo)[[:space:]]+([^[:space:]]+).*/\3/p' | head -1)
    if [ -n "$nwo" ]; then
        nwo="${nwo%.git}"
        if printf '%s' "$nwo" | LC_ALL=C grep -qE '^[^/]+/[^/]+$'; then
            printf '%s' "$nwo"
            return 0
        fi
        # A -R we cannot parse is worse than none: it points somewhere we did
        # not check.
        return 1
    fi

    local url
    url=$(git remote get-url origin 2>/dev/null) || return 2
    parse_nwo_from_url "$url" || return 2
}

# -----------------------------------------------------------------------------
# R1 / R2 — merge check state
# -----------------------------------------------------------------------------
CHECK_QUERY='
query($owner:String!,$repo:String!,$num:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$num){
      commits(last:1){nodes{commit{statusCheckRollup{
        contexts(first:100){totalCount nodes{
          __typename
          ... on CheckRun   { name status conclusion }
          ... on StatusContext { context state }
        }}
      }}}}
    }
  }
}'

# Turns the target token of `gh pr merge <target>` into a PR number.
# Accepts a bare number, a PR URL, a branch name, or nothing (current branch).
resolve_pr_number() {
    local target="$1" nwo="$2" out

    if printf '%s' "$target" | LC_ALL=C grep -qE '^[0-9]+$'; then
        printf '%s' "$target"
        return 0
    fi

    if printf '%s' "$target" | LC_ALL=C grep -qE '^https?://[^[:space:]]+/pull/[0-9]+'; then
        printf '%s' "$target" | LC_ALL=C sed -E 's#.*/pull/([0-9]+).*#\1#'
        return 0
    fi

    command -v gh >/dev/null 2>&1 || return 1
    if [ -n "$nwo" ]; then
        out=$(gh pr view ${target:+"$target"} -R "$nwo" --json number --jq '.number' 2>/dev/null) || return 1
    else
        out=$(gh pr view ${target:+"$target"} --json number --jq '.number' 2>/dev/null) || return 1
    fi
    printf '%s' "$out" | LC_ALL=C grep -qE '^[0-9]+$' || return 1
    printf '%s' "$out"
}

# Emits a deny unless every check on the PR head has completed successfully.
enforce_merge_checks() {
    local segment="$1"
    local nwo rc num payload total failing

    nwo=$(resolve_nwo "$segment")
    rc=$?
    if [ "$rc" -eq 2 ]; then
        # No GitHub remote and no -R: out of scope rather than unknown.
        return 0
    fi
    [ "$rc" -eq 0 ] || deny "cannot determine which repository this merge targets; refusing to merge on unverified check state"

    if has_dynamic_value "$segment"; then
        deny "the merge target is computed at run time, so its check state cannot be verified before the merge happens"
    fi

    local target
    target=$(printf '%s' "$segment" | awk '
        {
            seen=0
            for (i=1; i<=NF; i++) {
                if (!seen) { if ($i == "merge") seen=1; continue }
                if ($i ~ /^-/) { if ($i == "-R" || $i == "--repo") i++; continue }
                print $i; exit
            }
        }')

    num=$(resolve_pr_number "$target" "$nwo") \
        || deny "cannot identify the pull request for this merge (gh unavailable, not authenticated, or no PR for that target); refusing to merge on unverified check state"

    command -v gh >/dev/null 2>&1 \
        || deny "gh is not installed, so PR #$num's check state cannot be verified"

    payload=$(gh api graphql \
        -f query="$CHECK_QUERY" \
        -F owner="${nwo%%/*}" -F repo="${nwo##*/}" -F num="$num" 2>/dev/null) \
        || deny "GitHub could not be reached for PR #$num's check state (network, auth, or rate limit); refusing to merge unverified"

    local rollup
    rollup=$(printf '%s' "$payload" | jq -c \
        '.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup // null' 2>/dev/null) \
        || deny "GitHub returned an unreadable response for PR #$num's check state; refusing to merge unverified"

    # R2 — nothing reported at all.
    if [ -z "$rollup" ] || [ "$rollup" = "null" ]; then
        deny "PR #$num has no check runs at all. Nothing passed — nothing reported, which is what a GitHub Actions incident looks like from here. Confirm workflows are running before merging."
    fi

    total=$(printf '%s' "$rollup" | jq -r '.contexts.totalCount // 0' 2>/dev/null || echo 0)
    if [ "$total" = "0" ]; then
        deny "PR #$num has no check runs at all. Nothing passed — nothing reported, which is what a GitHub Actions incident looks like from here. Confirm workflows are running before merging."
    fi

    # R1 — anything not finished, or finished badly.
    failing=$(printf '%s' "$rollup" | jq -r '
        [ .contexts.nodes[]
          | if .__typename == "CheckRun" then
              if .status != "COMPLETED" then "\(.name) (\(.status|ascii_downcase))"
              elif (.conclusion // "") | IN("SUCCESS","SKIPPED","NEUTRAL") | not then
                   "\(.name) (\(.conclusion // "no conclusion"|ascii_downcase))"
              else empty end
            else
              if (.state // "") == "SUCCESS" then empty
              else "\(.context) (\(.state // "unknown"|ascii_downcase))" end
            end
        ] | join(", ")' 2>/dev/null) \
        || deny "PR #$num's check results could not be parsed; refusing to merge unverified"

    if [ -n "$failing" ]; then
        deny "PR #$num is not clear to merge — $failing. Fix or wait for these before merging."
    fi

    return 0
}

# -----------------------------------------------------------------------------
# R4 / R5 — branch deletion
# -----------------------------------------------------------------------------
default_base() {
    local ref
    ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) && {
        printf '%s' "${ref#refs/remotes/}"
        return 0
    }
    local candidate
    for candidate in origin/main origin/master main master; do
        if git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# Resolves a branch name to whichever ref actually exists locally.
branch_ref() {
    local branch="$1" candidate
    for candidate in "$branch" "origin/$branch"; do
        if git rev-parse --verify --quiet "refs/heads/${candidate}" >/dev/null 2>&1 \
            || git rev-parse --verify --quiet "refs/remotes/${candidate}" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

enforce_branch_rules() {
    local branch="$1" segment="$2"

    if has_dynamic_value "$segment"; then
        # Policy rules, not a safety interlock: an unreadable name is worth a
        # prompt, not a block.
        ask "a branch is being deleted under a name computed at run time, so neither its authorship nor its prefix could be checked. Confirm the target."
    fi

    local ref
    ref=$(branch_ref "$branch") || return 0   # nothing to delete; git will say so

    local base
    base=$(default_base) || base=""

    # Already merged into the base: no work can be lost, so neither rule
    # applies. Without this, every post-merge cleanup trips the prefix rule.
    if [ -n "$base" ] && git merge-base --is-ancestor "$ref" "$base" >/dev/null 2>&1; then
        return 0
    fi

    # R4 — commits on this branch that the current user did not author.
    local authors me_email me_login
    if [ -n "$base" ]; then
        authors=$(git log --format='%ae%n%al' "$ref" --not "$base" 2>/dev/null)
    else
        authors=$(git log --format='%ae%n%al' "$ref" 2>/dev/null)
    fi

    if [ -n "$authors" ]; then
        # Lower-cased through tr rather than ${var,,}: stock macOS still ships
        # bash 3.2, and a guard that errors out there fails open.
        lower() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'; }

        me_email=$(lower "$(git config user.email 2>/dev/null || echo "")")
        me_login=$(lower "$(gh api user --jq '.login' 2>/dev/null || echo "")")

        local mine=0 line lc
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            lc=$(lower "$line")
            if [ -n "$me_email" ] && [ "$lc" = "$me_email" ]; then mine=1; break; fi
            if [ -n "$me_login" ] && [ "$lc" = "$me_login" ]; then mine=1; break; fi
        done <<< "$authors"

        if [ "$mine" -eq 0 ]; then
            local others
            others=$(printf '%s\n' "$authors" | LC_ALL=C grep -E '@' | sort -u | head -3 | paste -sd', ' -)
            deny "'$branch' holds unmerged commits you did not author (${others:-author unknown}). Deleting it would discard someone else's work."
        fi
    fi

    # R5 — prefix policy.
    local prefixes="${GUARD_BRANCH_PREFIXES:-feature/ hotfix/}"
    local prefix
    for prefix in $prefixes; do
        case "$branch" in "$prefix"*) return 0 ;; esac
    done

    ask "'$branch' is unmerged and has none of the expected prefixes (${prefixes// /, }). Confirm this is a branch you meant to delete."
}

# -----------------------------------------------------------------------------
# Per-segment classification
# -----------------------------------------------------------------------------
# `git branch` deleting a local branch. Remote-tracking pruning (-r) is not a
# deletion of anyone's work, so it is left alone.
branches_from_git_branch() {
    printf '%s' "$1" | awk '
    {
        del=0; remotes=0
        for (i=1; i<=NF; i++) {
            t=$i
            if (t ~ /^--/) {
                if (t == "--delete") del=1
                else if (t == "--remotes") remotes=1
                continue
            }
            if (t ~ /^-[^-]/) {
                if (t ~ /[dD]/) del=1
                if (t ~ /r/) remotes=1
                continue
            }
        }
        if (!del || remotes) exit
        seen=0
        for (i=1; i<=NF; i++) {
            t=$i
            if (!seen) { if (t == "branch") seen=1; continue }
            if (t ~ /^-/) continue
            print t
        }
    }'
}

# `git push <remote> --delete <branch>` and the colon refspec `git push
# <remote> :<branch>`, which deletes just as thoroughly with no flag to spot.
branches_from_git_push() {
    printf '%s' "$1" | awk '
    {
        del=0
        for (i=1; i<=NF; i++) if ($i == "--delete" || $i == "-d") del=1

        # Colon refspecs are a deletion on their own terms, flag or not.
        for (i=1; i<=NF; i++) if ($i ~ /^:./) print substr($i,2)

        if (!del) exit

        seen=0; skipped_remote=0
        for (i=1; i<=NF; i++) {
            t=$i
            if (!seen) { if (t == "push") seen=1; continue }
            if (t ~ /^-/) continue
            if (!skipped_remote) { skipped_remote=1; continue }   # the remote name
            print t
        }
    }'
}

# `gh api -X DELETE repos/O/R/git/refs/heads/BRANCH`
branch_from_gh_api_delete() {
    local segment="$1"
    printf '%s' "$segment" | LC_ALL=C grep -qE '(-X|--method)[[:space:]]+DELETE' || return 1
    printf '%s' "$segment" | LC_ALL=C sed -nE 's#.*git/refs/heads/([^[:space:]"'"'"']+).*#\1#p' | head -1
}

# -----------------------------------------------------------------------------
# Walk the command
# -----------------------------------------------------------------------------
# Every rule below needs a repository to reason about. Outside one, none of
# them apply.
git rev-parse --git-dir >/dev/null 2>&1 || {
    # A gh call carrying an explicit -R still applies; anything else does not.
    printf '%s' "$command" | LC_ALL=C grep -qE '(^|[[:space:]])(-R|--repo)[[:space:]]' || exit 0
}

# The branch rules are about branches on GitHub. A repository whose origin is
# elsewhere is a determinate "out of scope" rather than an unknown, so it falls
# through rather than failing closed. (The merge path decides this for itself,
# since a `-R owner/repo` names a GitHub repository whether or not the working
# directory has one.)
in_github_repo=0
if origin_url=$(git remote get-url origin 2>/dev/null); then
    parse_nwo_from_url "$origin_url" >/dev/null 2>&1 && in_github_repo=1
fi

while IFS= read -r raw_segment; do
    segment=$(trim "$raw_segment")
    [ -z "$segment" ] && continue

    # Only a segment that actually runs gh or git can merge or delete anything.
    cmd_word=$(command_word "$segment")
    case "$cmd_word" in
        gh|git) : ;;
        *) continue ;;
    esac

    # The subcommand is the first non-flag word after the command word, so
    # `git log --grep="branch -D x"` reads as `log` and never reaches the
    # deletion parsers.
    subcommand=$(printf '%s' "$segment" | awk -v cw="$cmd_word" '
    {
        seen=0
        for (i=1; i<=NF; i++) {
            t=$i
            if (!seen) {
                n=split(t, parts, "/")
                if (parts[n] == cw) seen=1
                continue
            }
            if (t ~ /^-/) continue
            print t; exit
        }
    }')

    # --- merges -------------------------------------------------------------
    if [ "$cmd_word" = "gh" ] && [ "$subcommand" = "pr" ] \
        && printf '%s' "$segment" | LC_ALL=C grep -qE 'pr[[:space:]]+merge([[:space:]]|$)'; then
        enforce_merge_checks "$segment"
        continue
    fi
    if [ "$cmd_word" = "gh" ] && [ "$subcommand" = "api" ] \
        && printf '%s' "$segment" | LC_ALL=C grep -qE 'pulls/[0-9]+/merge'; then
        enforce_merge_checks "$segment"
        continue
    fi

    # --- branch deletions ---------------------------------------------------
    branches=""
    case "$cmd_word:$subcommand" in
        git:branch) branches=$(branches_from_git_branch "$segment") ;;
        git:push)   branches=$(branches_from_git_push "$segment") ;;
        gh:api)     branches=$(branch_from_gh_api_delete "$segment") || branches="" ;;
    esac

    [ -z "$branches" ] && continue
    [ "$in_github_repo" -eq 1 ] || continue

    while IFS= read -r branch; do
        [ -z "$branch" ] && continue
        enforce_branch_rules "$branch" "$segment"
    done <<< "$branches"
done < <(printf '%s' "$command" | split_segments)

exit 0
