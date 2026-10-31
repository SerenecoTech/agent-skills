#!/usr/bin/env bash
# Choose the reviewer.
#
#   select-reviewer.sh
#
# Prints every reviewer provider that can run here, in priority order, one per line. The first
# line is the reviewer to use; the rest are its fallbacks. Exits 3 if none can run.
#
# Priority comes from $ADVERSARIAL_REVIEW_PROVIDERS (space-separated names) when set, otherwise
# from providers/PRIORITY. A provider is a directory under providers/ with a provider.sh; see
# providers/README.md.
set -uo pipefail

PROVIDERS="$(cd "$(dirname "${BASH_SOURCE[0]}")/providers" && pwd)"

if [ -n "${ADVERSARIAL_REVIEW_PROVIDERS:-}" ]; then
  order="$ADVERSARIAL_REVIEW_PROVIDERS"
else
  order="$(grep -v '^[[:space:]]*\(#\|$\)' "$PROVIDERS/PRIORITY")"
fi

found=0
for name in $order; do
  [ -f "$PROVIDERS/$name/provider.sh" ] || { echo "unknown provider '$name'" >&2; continue; }
  # shellcheck disable=SC1090
  if ( . "$PROVIDERS/$name/provider.sh" && provider_available ); then
    echo "$name"
    found=1
  fi
done

[ "$found" -eq 1 ] || { echo "no reviewer provider can run here (tried: $(echo $order))" >&2; exit 3; }
