#!/usr/bin/env bash
# =============================================================================
# Runs every guard test suite and reports a single pass/fail verdict.
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

failed_suites=()

for suite in "$TESTS_DIR"/test-*.sh; do
    name=$(basename "$suite")
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "  $name"
    echo "══════════════════════════════════════════════════════════════════"
    if bash "$suite"; then
        :
    else
        failed_suites+=("$name")
    fi
done

echo ""
echo "══════════════════════════════════════════════════════════════════"
if [ ${#failed_suites[@]} -eq 0 ]; then
    echo -e "${GREEN}All guard suites passed.${NC}"
    exit 0
fi

echo -e "${RED}Failing suites: ${failed_suites[*]}${NC}"
exit 1
