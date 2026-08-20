#!/usr/bin/env bash
# =============================================================================
# Fail if a plugin's files changed without its version changing.
# =============================================================================
# The install cache is keyed by declared version — cache/<mkt>/<plugin>/<version>
# — so an unchanged version means `/plugin update` reports "already at the latest
# version" and refetches nothing, however many commits have landed. This has
# happened once already, which is why the check exists.
#
# Usage:  check-version-bump.sh <base-ref>
#
# A plugin that declares no version is skipped, not failed: version-less plugins
# are keyed on commit SHA instead and always track HEAD, which is how most of
# the official marketplace works. There is nothing to bump.
#
# Escape hatch for a change that genuinely does not warrant a release (a typo in
# a comment, say): put [skip bump] in the commit message.
# =============================================================================

set -uo pipefail

BASE="${1:-}"
if [ -z "$BASE" ]; then
    echo "usage: $0 <base-ref>" >&2
    exit 2
fi

if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
    echo "::warning::base ref '$BASE' is not present; skipping the version-bump check"
    exit 0
fi

# `grep -q` exits on its first match, which SIGPIPEs `git log`; under `pipefail`
# that reads as a failed pipeline, so the marker gets silently ignored. `grep -c`
# consumes all of its input, so the exit status means what it appears to mean.
skip_hits=$( { git log "$BASE..HEAD" --format=%B | grep -ciF '[skip bump]'; } || true)
if [ "${skip_hits:-0}" -gt 0 ]; then
    echo "[skip bump] found in a commit message — version-bump check skipped"
    exit 0
fi

version_at() {  # $1 = ref (empty for worktree), $2 = path
    local ref="$1" path="$2" json
    if [ -z "$ref" ]; then
        json=$(cat "$path" 2>/dev/null) || return 1
    else
        json=$(git show "$ref:$path" 2>/dev/null) || return 1
    fi
    printf '%s' "$json" | jq -r '.version // empty' 2>/dev/null
}

failed=0
checked=0

# Every plugin directory touched between BASE and HEAD.
changed=$(git diff --name-only "$BASE...HEAD" -- plugins/ \
    | awk -F/ 'NF>1 {print $2}' | sort -u)

if [ -z "$changed" ]; then
    echo "No plugin directories changed."
    exit 0
fi

for name in $changed; do
    manifest="plugins/$name/.claude-plugin/plugin.json"

    if [ ! -f "$manifest" ]; then
        echo "  - $name: no plugin.json in the worktree (deleted or not a plugin) — skipped"
        continue
    fi

    new_ver=$(version_at "" "$manifest")
    old_ver=$(version_at "$BASE" "$manifest") || old_ver=""

    if [ -z "$new_ver" ]; then
        echo "  - $name: declares no version — tracks commit SHA, nothing to bump"
        continue
    fi

    if [ -z "$old_ver" ]; then
        echo "  - $name: new plugin at $new_ver — nothing to compare"
        continue
    fi

    checked=$((checked + 1))

    if [ "$old_ver" = "$new_ver" ]; then
        echo "::error::$name changed but its version is still $old_ver. Bump it in $manifest AND in the marketplace entry, or add [skip bump] to the commit message."
        failed=1
        continue
    fi

    # The two manifests have to agree, or the resolved version is a coin toss.
    mkt_ver=$(jq -r --arg n "$name" \
        '.plugins[] | select(.name == $n) | .version // empty' \
        .claude-plugin/marketplace.json 2>/dev/null)

    if [ -n "$mkt_ver" ] && [ "$mkt_ver" != "$new_ver" ]; then
        echo "::error::$name is $new_ver in $manifest but $mkt_ver in the marketplace entry. They must match."
        failed=1
        continue
    fi

    echo "  - $name: $old_ver -> $new_ver ✓"
done

if [ "$failed" -ne 0 ]; then
    exit 1
fi

echo "Version-bump check passed ($checked plugin(s) verified)."
