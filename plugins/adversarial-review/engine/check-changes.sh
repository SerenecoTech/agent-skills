#!/usr/bin/env bash
# Check that a review changed nothing outside its scope.
#
#   check-changes.sh start <repo-root>   snapshot the working tree as the review begins
#   check-changes.sh check <repo-root>   list every path changed since, and flag any the
#                                        review was not allowed to change
#
# The write gate sees only the file tools. This catches a change however it was made — a
# shell redirect, cp, sed -i, a script — by comparing what is on disk rather than predicting
# what a command will do.
#
# The snapshot is a git tree of the whole working tree, tracked and untracked files alike,
# built in a temporary index so the real index is untouched. It does add blob objects to
# .git/objects, which git gc removes once unreferenced. Ignored files are not covered. Nor is a
# change git normalises away on add: a line-ending rewrite under `text eol=lf` produces the same
# blob, so it does not show.
#
# Allowed to change: .claude/adversarial-review/, the appendix state.json declares, and, in a
# fix loop, the authorized_paths globs. With no state.json every change is out of scope.
#
# Exit: 0 nothing out of scope, 1 out-of-scope changes listed, 2 usage error or no snapshot.
set -uo pipefail

usage() { echo "usage: $0 <start|check> <repo-root>" >&2; exit 2; }
[ $# -eq 2 ] || usage
MODE="$1"
REPO="$(cd -P "$2" 2>/dev/null && pwd)" || usage
DIR="$REPO/.claude/adversarial-review"
BASELINE="$DIR/baseline-tree"
STATE="$DIR/state.json"

# Prints the tree id. The temporary index starts as a copy of the real one, so a tracked file
# that now matches an ignore pattern is still covered. A file git cannot read (a sandbox
# denying a .env, say) would stop `git add -A` outright, so it is excluded and named on stderr
# as NOT COVERED, and the snapshot is retried until it succeeds or stops making progress.
# A submodule is recorded only as its commit, so edits inside one are named NOT COVERED too.
snapshot() {
  local tmp tree="" err="" path gitdir done_path
  local -a excluded=()
  tmp="$(mktemp -d)" || return 1
  gitdir="$(git -C "$REPO" rev-parse --absolute-git-dir 2>/dev/null)" || { /bin/rm -rf "$tmp"; return 1; }
  [ -f "$gitdir/index" ] && cp "$gitdir/index" "$tmp/index"
  # Git trusts a file's cached size and mtime unless the index is older than the file, so an
  # edit of the same size within the same second as the last index write can go unseen. An
  # old index timestamp makes every entry look "racily clean", so git compares the content.
  [ -f "$tmp/index" ] && touch -t 200001010000 "$tmp/index"
  # The copy keeps assume-unchanged and skip-worktree marks, which make git add ignore edits
  # to those files or refuse them. Clear them in the copy only, so those edits are seen too.
  # In a sparse checkout, skip-worktree marks the files that are not on disk, so they stay.
  # One flag per update-index call: given both, git applies only one of them.
  clear_marks() {   # $1 ls-files -v tags to match, $2 the update-index flag that clears them
    git -C "$REPO" ls-files -v -z 2>/dev/null | tr '\0' '\n' | sed -n "s/^$1 //p" \
      | tr '\n' '\0' | GIT_INDEX_FILE="$tmp/index" git -C "$REPO" update-index -z "$2" --stdin \
      >/dev/null 2>&1
  }
  clear_marks '[a-z]' --no-assume-unchanged
  if [ "$(git -C "$REPO" config --bool core.sparseCheckout 2>/dev/null)" != "true" ]; then
    clear_marks '[Ss]' --no-skip-worktree
  fi
  # The review's own bookkeeping is left out: it is always allowed, and in a sparse checkout
  # git add refuses new files outside the sparse cone, which would include baseline-tree. When
  # the folder is already gitignored it is skipped anyway, and naming an ignored path, even to
  # exclude it, makes git add fail.
  local -a skip=()
  git -C "$REPO" check-ignore -q .claude/adversarial-review/ 2>/dev/null \
    || skip=(':(exclude).claude/adversarial-review')
  while :; do
    if err="$(GIT_INDEX_FILE="$tmp/index" git -C "$REPO" add -A -- . \
                ${skip[@]+"${skip[@]}"} \
                ${excluded[@]+"${excluded[@]/#/:(exclude,literal)}"} 2>&1 >/dev/null)"; then
      tree="$(GIT_INDEX_FILE="$tmp/index" git -C "$REPO" write-tree 2>/dev/null)"
      break
    fi
    path="$(printf '%s\n' "$err" | sed -nE "s/.*unable to (stat|index file) '(.*)'.*/\2/p" | head -1)"
    [ -n "$path" ] || break
    for done_path in ${excluded[@]+"${excluded[@]}"}; do
      [ "$done_path" = "$path" ] && break 2   # no progress: give up rather than loop
    done
    echo "NOT COVERED   $path (git cannot read it)" >&2
    excluded+=("$path")
  done
  # Read nested repositories from the snapshot itself, not the real index: an untracked clone
  # inside the tree is recorded as a commit too, and its edits are just as invisible.
  if [ -n "$tree" ]; then
    git -C "$REPO" ls-tree -r -z "$tree" 2>/dev/null | tr '\0' '\n' \
      | awk -F'\t' '$1 ~ / commit / {print $2}' | while IFS= read -r sub; do
        echo "NOT COVERED   $sub (a nested repository: only its commit is compared)" >&2
      done
  fi
  /bin/rm -rf "$tmp"
  if [ -z "$tree" ]; then
    printf '%s\n' "$err" | tail -n 3 >&2   # git's own reason, so the failure is diagnosable
    return 1
  fi
  printf '%s\n' "$tree"
}

case "$MODE" in
  start)
    mkdir -p "$DIR" || exit 2
    tree="$(snapshot)" || { echo "could not snapshot $REPO (git's reason is above)" >&2; exit 2; }
    printf '%s\n' "$tree" > "$BASELINE"
    echo "BASELINE: $tree"
    exit 0
    ;;
  check) ;;
  *) usage ;;
esac

[ -s "$BASELINE" ] || { echo "no baseline at $BASELINE; run '$0 start' when the review begins" >&2; exit 2; }
base="$(cat "$BASELINE")"
now="$(snapshot)" || { echo "could not snapshot $REPO" >&2; exit 2; }

loop="verdict"; appendix=""; allowed=()
if [ -f "$STATE" ]; then
  loop="$(jq -r '.loop // "verdict"' "$STATE" 2>/dev/null)"
  appendix="$(jq -r '.appendix // ""' "$STATE" 2>/dev/null)"
  appendix="${appendix#"$REPO"/}"
  if [ "$loop" = "fix" ]; then
    while IFS= read -r p; do [ -n "$p" ] && allowed+=("$p"); done \
      < <(jq -r '(.authorized_paths // [])[]' "$STATE" 2>/dev/null)
  fi
fi

# --no-renames: a rename is a deletion plus an addition, and the deleted path matters too.
# -z: names come unquoted, so non-ASCII names and names with newlines compare as they are.
out_of_scope=0; changed=0
while IFS= read -r -d '' path; do
  [ -n "$path" ] || continue
  changed=$((changed + 1))
  ok=0
  case "$path" in .claude/adversarial-review/*) ok=1 ;; esac
  [ -n "$appendix" ] && [ "$path" = "$appendix" ] && ok=1
  for pattern in ${allowed[@]+"${allowed[@]}"}; do
    # shellcheck disable=SC2254  # the allowlist entries are globs
    case "$path" in $pattern) ok=1 ;; esac
  done
  if [ "$ok" -eq 1 ]; then
    echo "ALLOWED       $path"
  else
    echo "OUT OF SCOPE  $path"
    out_of_scope=$((out_of_scope + 1))
  fi
done < <(git -C "$REPO" diff --no-renames -z --name-only "$base" "$now")

echo "CHANGED: $changed path(s) since the baseline, $out_of_scope out of scope (loop: $loop)"
[ "$out_of_scope" -eq 0 ]
