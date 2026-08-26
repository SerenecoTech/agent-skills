#!/usr/bin/env bash
# =============================================================================
# Test suite for github-guard.sh
# =============================================================================
# Builds a fixture git repository with a GitHub origin and four branches whose
# authorship and merge state differ, plus a fake `gh` on PATH whose answers are
# selected per-test by GH_FIXTURE. Nothing here touches the network, and
# nothing here reads the developer's own git config, gh auth, or settings.
#
# Conventions:
#   expect_deny  -> PreToolUse should emit permissionDecision=deny
#   expect_ask   -> PermissionRequest should emit decision=ask
#   silent       -> the hook should exit 0 with no decision
#
# The two events are exercised separately because the guard splits its rules
# across them: deny lives on PreToolUse, ask lives on PermissionRequest.
# =============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"
HOOK="$HOOKS_DIR/github-guard.sh"

pass=0
fail=0

# -----------------------------------------------------------------------------
# Fixture: a fake gh
# -----------------------------------------------------------------------------
FIXTURE_ROOT=$(mktemp -d /tmp/ghguard-test.XXXXXX)
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

FIXTURE_BIN="$FIXTURE_ROOT/bin"
mkdir -p "$FIXTURE_BIN"

cat > "$FIXTURE_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
# Fake gh. GH_FIXTURE selects the scenario; anything unrecognised fails, so a
# code path reaching for an unstubbed gh call shows up as a test failure rather
# than as a silent pass.
mode="${GH_FIXTURE:-green}"

if [ "$1" = "api" ] && [ "$2" = "user" ]; then
    [ "$mode" = "ghuser-fail" ] && exit 1
    echo "testuser"
    exit 0
fi

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    [ "$mode" = "prview-fail" ] && exit 1
    echo "42"
    exit 0
fi

if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
    case "$mode" in
        graphql-fail) exit 1 ;;
        garbage)      echo "not json at all"; exit 0 ;;
        nochecks)
            echo '{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}}}}'
            exit 0 ;;
        emptychecks)
            echo '{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":0,"nodes":[]}}}}]}}}}}'
            exit 0 ;;
        failing)
            echo '{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":2,"nodes":[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"e2e","status":"COMPLETED","conclusion":"FAILURE"}]}}}}]}}}}}'
            exit 0 ;;
        running)
            echo '{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":2,"nodes":[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"e2e","status":"IN_PROGRESS","conclusion":null}]}}}}]}}}}}'
            exit 0 ;;
        legacy-failing)
            echo '{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":1,"nodes":[{"__typename":"StatusContext","context":"ci/jenkins","state":"FAILURE"}]}}}}]}}}}}'
            exit 0 ;;
        *)
            # green: everything completed, including a skipped and a neutral
            # check, neither of which is a failure.
            echo '{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":3,"nodes":[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SKIPPED"},{"__typename":"StatusContext","context":"ci/legacy","state":"SUCCESS"}]}}}}]}}}}}'
            exit 0 ;;
    esac
fi

exit 1
GHSTUB
chmod +x "$FIXTURE_BIN/gh"

# A PATH with no gh at all, for the "gh is not installed" fail-closed case.
# Symlinks rather than a bare /usr/bin, because jq and git usually are not there.
NOGH_BIN="$FIXTURE_ROOT/nogh"
mkdir -p "$NOGH_BIN"
# `bash` belongs in this list: env resolves the interpreter through the PATH it
# is handed, so omitting it makes the hook exit 127 without running and the
# test passes or fails for entirely the wrong reason.
for tool in bash jq git awk sed grep head sort paste tr cat env; do
    src=$(command -v "$tool" 2>/dev/null) && ln -sf "$src" "$NOGH_BIN/$tool"
done

# -----------------------------------------------------------------------------
# Fixture: a git repository with a GitHub origin
# -----------------------------------------------------------------------------
REPO="$FIXTURE_ROOT/widgets"
mkdir -p "$REPO"

build_repo() {
    local origin="$1"
    git -C "$REPO" init -q -b main
    git -C "$REPO" config user.email "me@example.com"
    git -C "$REPO" config user.name "Me"
    git -C "$REPO" config commit.gpgsign false
    git -C "$REPO" remote add origin "$origin"

    echo one > "$REPO/a.txt"
    git -C "$REPO" add a.txt
    git -C "$REPO" commit -q -m "base"

    # Unmerged, authored by the current user, correctly prefixed.
    git -C "$REPO" checkout -q -b feature/mine
    echo mine > "$REPO/mine.txt"
    git -C "$REPO" add mine.txt
    git -C "$REPO" commit -q -m "mine"

    # Unmerged, authored by the current user, no recognised prefix.
    git -C "$REPO" checkout -q main
    git -C "$REPO" checkout -q -b chore-mine
    echo chore > "$REPO/chore.txt"
    git -C "$REPO" add chore.txt
    git -C "$REPO" commit -q -m "chore"

    # Unmerged, authored by somebody else.
    git -C "$REPO" checkout -q main
    git -C "$REPO" checkout -q -b feature/theirs
    echo theirs > "$REPO/theirs.txt"
    git -C "$REPO" add theirs.txt
    git -C "$REPO" -c user.email="other@example.com" -c user.name="Other" \
        commit -q -m "theirs"

    # Merged into main: no work can be lost by deleting it.
    git -C "$REPO" checkout -q main
    git -C "$REPO" checkout -q -b chore-merged
    echo merged > "$REPO/merged.txt"
    git -C "$REPO" add merged.txt
    git -C "$REPO" commit -q -m "merged"
    git -C "$REPO" checkout -q main
    git -C "$REPO" merge -q --no-ff -m "merge" chore-merged

    git -C "$REPO" checkout -q main
}

build_repo "git@github.com:acme/widgets.git" >/dev/null 2>&1

# A second repository, hosted somewhere that is not GitHub.
GITLAB_REPO="$FIXTURE_ROOT/gitlab"
mkdir -p "$GITLAB_REPO"
(
    git -C "$GITLAB_REPO" init -q -b main
    git -C "$GITLAB_REPO" config user.email "me@example.com"
    git -C "$GITLAB_REPO" config user.name "Me"
    git -C "$GITLAB_REPO" config commit.gpgsign false
    git -C "$GITLAB_REPO" remote add origin "git@gitlab.com:acme/widgets.git"
    echo one > "$GITLAB_REPO/a.txt"
    git -C "$GITLAB_REPO" add a.txt
    git -C "$GITLAB_REPO" commit -q -m base
    git -C "$GITLAB_REPO" checkout -q -b chore-elsewhere
    echo two > "$GITLAB_REPO/b.txt"
    git -C "$GITLAB_REPO" add b.txt
    git -C "$GITLAB_REPO" commit -q -m two
    git -C "$GITLAB_REPO" checkout -q main
) >/dev/null 2>&1

# A directory that is not a git repository at all.
BARE_DIR="$FIXTURE_ROOT/notarepo"
mkdir -p "$BARE_DIR"

# -----------------------------------------------------------------------------
# Harness
# -----------------------------------------------------------------------------
# run_hook <event> <command> [cwd] [env assignments...]
run_hook() {
    local event="$1" cmd="$2" cwd="${3:-$REPO}"
    shift 3 2>/dev/null || shift $#
    local json_input
    json_input=$(jq -n --arg c "$cmd" --arg e "$event" \
        '{hook_event_name:$e, tool_input:{command:$c}}')
    # Every GUARD_* variable is cleared first, so the suite's results do not
    # depend on what the person running it happens to have exported.
    env -C "$cwd" \
        -u GUARD_GITHUB_DISABLE -u GUARD_BRANCH_PREFIXES -u GUARD_PROTECTED_BRANCHES \
        PATH="$FIXTURE_BIN:$PATH" "$@" bash "$HOOK" <<<"$json_input" 2>/dev/null || echo ""
}

decision_of() {
    echo "$1" | jq -r '
        .hookSpecificOutput.permissionDecision
        // .hookSpecificOutput.decision
        // "silent"' 2>/dev/null || echo "silent"
}

reason_of() {
    echo "$1" | jq -r '
        .hookSpecificOutput.permissionDecisionReason
        // .systemMessage // ""' 2>/dev/null || echo ""
}

# check <event> <expected> <description> <command> [cwd] [env...]
check() {
    local event="$1" expect="$2" description="$3" cmd="$4"
    shift 4
    local result got
    result=$(run_hook "$event" "$cmd" "$@")
    got=$(decision_of "$result")
    [ -z "$got" ] && got="silent"

    if [ "$got" = "$expect" ]; then
        echo -e "  ${GREEN}✓${NC} $description"
        pass=$((pass + 1))
    else
        echo -e "  ${RED}✗${NC} $description"
        echo -e "    expected $expect, got $got"
        echo -e "    command:  $cmd"
        [ -n "$result" ] && echo -e "    output:   $result"
        fail=$((fail + 1))
    fi
}

# Asserts the deny reason actually names what went wrong, so a correct
# decision reached for the wrong reason still fails.
check_reason() {
    local event="$1" needle="$2" description="$3" cmd="$4"
    shift 4
    local result reason
    result=$(run_hook "$event" "$cmd" "$@")
    reason=$(reason_of "$result")

    if printf '%s' "$reason" | grep -qF "$needle"; then
        echo -e "  ${GREEN}✓${NC} $description"
        pass=$((pass + 1))
    else
        echo -e "  ${RED}✗${NC} $description"
        echo -e "    reason did not mention: $needle"
        echo -e "    reason was: ${reason:-<none>}"
        fail=$((fail + 1))
    fi
}

# -----------------------------------------------------------------------------
echo ""
echo "R1 — merging with checks that have not passed"
# -----------------------------------------------------------------------------
check PreToolUse silent "green checks merge freely" \
    "gh pr merge 42 --squash" "$REPO" GH_FIXTURE=green
check PreToolUse deny "a failing check run blocks the merge" \
    "gh pr merge 42 --squash" "$REPO" GH_FIXTURE=failing
check_reason PreToolUse "e2e (failure)" "the reason names the failing check" \
    "gh pr merge 42 --squash" "$REPO" GH_FIXTURE=failing
check PreToolUse deny "a check still running blocks the merge" \
    "gh pr merge 42" "$REPO" GH_FIXTURE=running
check_reason PreToolUse "e2e (in_progress)" "the reason names the unfinished check" \
    "gh pr merge 42" "$REPO" GH_FIXTURE=running
check PreToolUse deny "a failing legacy status context blocks the merge" \
    "gh pr merge 42" "$REPO" GH_FIXTURE=legacy-failing
check PreToolUse silent "skipped and neutral conclusions are not failures" \
    "gh pr merge 42 --merge --delete-branch" "$REPO" GH_FIXTURE=green
check PreToolUse silent "a bare merge resolves the PR from the current branch" \
    "gh pr merge" "$REPO" GH_FIXTURE=green
check PreToolUse deny "a bare merge is still checked" \
    "gh pr merge --admin" "$REPO" GH_FIXTURE=failing
check PreToolUse deny "a PR URL target is resolved and checked" \
    "gh pr merge https://github.com/acme/widgets/pull/42 --squash" "$REPO" GH_FIXTURE=failing
check PreToolUse deny "the REST merge endpoint is guarded too" \
    "gh api -X PUT repos/acme/widgets/pulls/42/merge" "$REPO" GH_FIXTURE=failing
check PreToolUse silent "the REST merge endpoint passes when checks are green" \
    "gh api -X PUT repos/acme/widgets/pulls/42/merge" "$REPO" GH_FIXTURE=green
check PreToolUse deny "a merge inside a compound command is still checked" \
    "git status && gh pr merge 42 --squash" "$REPO" GH_FIXTURE=failing
check PreToolUse deny "an explicit -R is honoured" \
    "gh pr merge 42 -R other/repo" "$REPO" GH_FIXTURE=failing

# -----------------------------------------------------------------------------
echo ""
echo "R2 — merging when no workflow ran at all"
# -----------------------------------------------------------------------------
check PreToolUse deny "a null check rollup blocks the merge" \
    "gh pr merge 42 --squash" "$REPO" GH_FIXTURE=nochecks
check_reason PreToolUse "no check runs at all" "the reason explains the empty rollup" \
    "gh pr merge 42 --squash" "$REPO" GH_FIXTURE=nochecks
check PreToolUse deny "zero check contexts blocks the merge" \
    "gh pr merge 42 --squash" "$REPO" GH_FIXTURE=emptychecks

# -----------------------------------------------------------------------------
echo ""
echo "Fail-closed — unverifiable check state"
# -----------------------------------------------------------------------------
check PreToolUse deny "an unreachable GitHub API blocks the merge" \
    "gh pr merge 42 --squash" "$REPO" GH_FIXTURE=graphql-fail
check PreToolUse deny "an unreadable API response blocks the merge" \
    "gh pr merge 42 --squash" "$REPO" GH_FIXTURE=garbage
check PreToolUse deny "an unresolvable PR target blocks the merge" \
    "gh pr merge some-branch --squash" "$REPO" GH_FIXTURE=prview-fail
check PreToolUse deny "a PR number computed at run time blocks the merge" \
    'gh pr merge $PR --squash' "$REPO" GH_FIXTURE=green
check PreToolUse deny "a PR number from a subshell blocks the merge" \
    'gh pr merge $(gh pr list -q .[0].number) --squash' "$REPO" GH_FIXTURE=green
check PreToolUse deny "an unparseable -R blocks the merge" \
    "gh pr merge 42 -R not-a-repo" "$REPO" GH_FIXTURE=green

# gh missing entirely: PATH is replaced rather than prefixed.
result=$(jq -n --arg c "gh pr merge 42 --squash" \
    '{hook_event_name:"PreToolUse", tool_input:{command:$c}}' \
    | env -C "$REPO" PATH="$NOGH_BIN" bash "$HOOK" 2>/dev/null || echo "")
if [ "$(decision_of "$result")" = "deny" ]; then
    echo -e "  ${GREEN}✓${NC} a missing gh blocks the merge"
    pass=$((pass + 1))
else
    echo -e "  ${RED}✗${NC} a missing gh blocks the merge"
    echo -e "    expected deny, got $(decision_of "$result")"
    fail=$((fail + 1))
fi

# -----------------------------------------------------------------------------
echo ""
echo "R3 — deleting a protected branch"
# -----------------------------------------------------------------------------
# The case this rule exists for: a default branch is trivially an ancestor of
# itself, so the merged-branch exemption waved `git branch -D main` straight
# through until R3 was placed ahead of it.
check PreToolUse deny "git branch -D main" \
    "git branch -D main" "$REPO" GH_FIXTURE=green
check_reason PreToolUse "protected branch" "the reason says why" \
    "git branch -D main" "$REPO" GH_FIXTURE=green
check PreToolUse deny "master is protected even where it is not the default" \
    "git branch -D master" "$REPO" GH_FIXTURE=green
check PreToolUse deny "develop is protected" \
    "git branch -D develop" "$REPO" GH_FIXTURE=green
check PreToolUse deny "production is protected" \
    "git branch -D production" "$REPO" GH_FIXTURE=green
check PreToolUse deny "deleting main on the remote" \
    "git push origin --delete main" "$REPO" GH_FIXTURE=green
check PreToolUse deny "deleting main by colon refspec" \
    "git push origin :main" "$REPO" GH_FIXTURE=green
check PreToolUse deny "deleting main through the REST ref endpoint" \
    "gh api -X DELETE repos/acme/widgets/git/refs/heads/main" "$REPO" GH_FIXTURE=green
check PreToolUse silent "a branch merely starting with a protected name is fine" \
    "git branch -D chore-merged" "$REPO" GH_FIXTURE=green
check PreToolUse deny "GUARD_PROTECTED_BRANCHES can name another branch" \
    "git branch -D chore-merged" "$REPO" GH_FIXTURE=green GUARD_PROTECTED_BRANCHES="chore-merged"
check PreToolUse deny "the default branch stays protected whatever the override says" \
    "git branch -D main" "$REPO" GH_FIXTURE=green GUARD_PROTECTED_BRANCHES="trunk"

# -----------------------------------------------------------------------------
echo ""
echo "R4 — deleting a branch carrying someone else's commits"
# -----------------------------------------------------------------------------
check PreToolUse deny "git branch -D on another author's branch" \
    "git branch -D feature/theirs" "$REPO" GH_FIXTURE=green
check_reason PreToolUse "other@example.com" "the reason names the other author" \
    "git branch -D feature/theirs" "$REPO" GH_FIXTURE=green
check PreToolUse deny "git branch -d on another author's branch" \
    "git branch -d feature/theirs" "$REPO" GH_FIXTURE=green
check PreToolUse deny "git branch --delete on another author's branch" \
    "git branch --delete feature/theirs" "$REPO" GH_FIXTURE=green
check PreToolUse deny "git push --delete on another author's branch" \
    "git push origin --delete feature/theirs" "$REPO" GH_FIXTURE=green
check PreToolUse deny "a colon refspec deletes just as thoroughly" \
    "git push origin :feature/theirs" "$REPO" GH_FIXTURE=green
check PreToolUse deny "gh api DELETE on a ref" \
    "gh api -X DELETE repos/acme/widgets/git/refs/heads/feature/theirs" "$REPO" GH_FIXTURE=green
check PreToolUse deny "gh api --method DELETE on a ref" \
    "gh api --method DELETE repos/acme/widgets/git/refs/heads/feature/theirs" "$REPO" GH_FIXTURE=green
check PreToolUse silent "your own unmerged branch is yours to delete" \
    "git branch -D feature/mine" "$REPO" GH_FIXTURE=green
check PreToolUse silent "a merged branch is exempt whoever wrote it" \
    "git branch -D chore-merged" "$REPO" GH_FIXTURE=green
check PreToolUse deny "the guard falls back to the git login when gh is logged out" \
    "git branch -D feature/theirs" "$REPO" GH_FIXTURE=ghuser-fail

# -----------------------------------------------------------------------------
echo ""
echo "R5 — deleting a branch with no recognised prefix"
# -----------------------------------------------------------------------------
check PermissionRequest ask "an unprefixed unmerged branch prompts" \
    "git branch -D chore-mine" "$REPO" GH_FIXTURE=green
check_reason PermissionRequest "feature/, hotfix/" "the prompt names the expected prefixes" \
    "git branch -D chore-mine" "$REPO" GH_FIXTURE=green
check PermissionRequest silent "a feature/ branch does not prompt" \
    "git branch -D feature/mine" "$REPO" GH_FIXTURE=green
check PermissionRequest silent "a merged branch does not prompt" \
    "git branch -D chore-merged" "$REPO" GH_FIXTURE=green
check PermissionRequest ask "a branch name computed at run time prompts" \
    'git branch -D $BRANCH' "$REPO" GH_FIXTURE=green
check PermissionRequest ask "a colon refspec is prefix-checked too" \
    "git push origin :chore-mine" "$REPO" GH_FIXTURE=green
check PreToolUse silent "the prefix rule never denies on PreToolUse" \
    "git branch -D chore-mine" "$REPO" GH_FIXTURE=green
check PermissionRequest silent "the authorship rule never asks on PermissionRequest" \
    "git branch -D feature/theirs" "$REPO" GH_FIXTURE=green

# -----------------------------------------------------------------------------
echo ""
echo "Commands that are not deletions or merges"
# -----------------------------------------------------------------------------
check PreToolUse silent "listing branches" \
    "git branch -a" "$REPO" GH_FIXTURE=green
check PreToolUse silent "listing branches verbosely" \
    "git branch -vv" "$REPO" GH_FIXTURE=green
check PreToolUse silent "creating a branch" \
    "git branch feature/new" "$REPO" GH_FIXTURE=green
check PreToolUse silent "pruning a remote-tracking ref is not deleting work" \
    "git branch -dr origin/feature/theirs" "$REPO" GH_FIXTURE=green
check PreToolUse silent "an ordinary push" \
    "git push origin feature/mine" "$REPO" GH_FIXTURE=green
check PreToolUse silent "viewing a PR" \
    "gh pr view 42" "$REPO" GH_FIXTURE=green
check PreToolUse silent "reading PR checks" \
    "gh pr checks 42" "$REPO" GH_FIXTURE=failing
check PreToolUse silent "an unrelated command" \
    "npm test" "$REPO" GH_FIXTURE=failing
check PreToolUse silent "deleting a branch that does not exist" \
    "git branch -D no-such-branch" "$REPO" GH_FIXTURE=green

# -----------------------------------------------------------------------------
echo ""
echo "Mentioning an operation is not performing one"
# -----------------------------------------------------------------------------
check PreToolUse silent "a merge named inside an echo" \
    'echo "next step: gh pr merge 42"' "$REPO" GH_FIXTURE=failing
check PreToolUse silent "a merge named in a commit message" \
    'git commit -m "gh pr merge once review lands"' "$REPO" GH_FIXTURE=failing
check PreToolUse silent "a deletion named in a log search" \
    'git log --grep="branch -D feature/theirs"' "$REPO" GH_FIXTURE=green
check PreToolUse silent "a deletion named in an echo" \
    'echo "then run git branch -D feature/theirs"' "$REPO" GH_FIXTURE=green

# The command word still has to be found through the shapes it really takes.
check PreToolUse deny "an absolute path to gh is still gh" \
    "/opt/homebrew/bin/gh pr merge 42 --squash" "$REPO" GH_FIXTURE=failing
check PreToolUse deny "a leading environment assignment is skipped" \
    "GH_HOST=github.com gh pr merge 42 --squash" "$REPO" GH_FIXTURE=failing
check PreToolUse deny "an env wrapper is skipped" \
    "env GH_HOST=github.com gh pr merge 42 --squash" "$REPO" GH_FIXTURE=failing
check PreToolUse deny "an absolute path to git is still git" \
    "/usr/bin/git branch -D feature/theirs" "$REPO" GH_FIXTURE=green

# -----------------------------------------------------------------------------
echo ""
echo "Out of scope — no repository, or a repository that is not on GitHub"
# -----------------------------------------------------------------------------
check PreToolUse silent "outside a git repository" \
    "git branch -D feature/theirs" "$BARE_DIR" GH_FIXTURE=green
check PreToolUse silent "a non-GitHub origin is left alone" \
    "git branch -D chore-elsewhere" "$GITLAB_REPO" GH_FIXTURE=green
check PermissionRequest silent "a non-GitHub origin does not prompt either" \
    "git branch -D chore-elsewhere" "$GITLAB_REPO" GH_FIXTURE=green
check PreToolUse silent "a merge in a non-GitHub repository is left alone" \
    "gh pr merge 42" "$GITLAB_REPO" GH_FIXTURE=failing

# -----------------------------------------------------------------------------
echo ""
echo "Optional configuration"
# -----------------------------------------------------------------------------
check PreToolUse silent "GUARD_GITHUB_DISABLE turns the whole guard off" \
    "gh pr merge 42 --squash" "$REPO" GH_FIXTURE=failing GUARD_GITHUB_DISABLE=1
check PreToolUse silent "GUARD_GITHUB_DISABLE covers the branch rules too" \
    "git branch -D feature/theirs" "$REPO" GH_FIXTURE=green GUARD_GITHUB_DISABLE=1
check PermissionRequest silent "GUARD_BRANCH_PREFIXES can accept another prefix" \
    "git branch -D chore-mine" "$REPO" GH_FIXTURE=green GUARD_BRANCH_PREFIXES="chore- spike/"
check PermissionRequest ask "GUARD_BRANCH_PREFIXES replaces the defaults" \
    "git branch -D feature/mine" "$REPO" GH_FIXTURE=green GUARD_BRANCH_PREFIXES="spike/"

echo
echo "-----------------------------------"
echo "Passed: $pass"
echo "Failed: $fail"
echo "-----------------------------------"
[ "$fail" -eq 0 ]
