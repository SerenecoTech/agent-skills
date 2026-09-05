#!/usr/bin/env bash
# =============================================================================
# score.sh — deterministic writing-quality metrics for one text file.
# =============================================================================
# Usage:
#   score.sh FILE [--kind procedural|descriptive|copy|reply]
#   score.sh --header
#
# Prints one tab-separated line of metrics for FILE (or, with --header, the
# column names for that line). Every metric is computed with grep/awk/sed on
# a cleaned copy of the text: fenced code blocks and inline code are removed,
# and markdown bullet/header/bold markers are stripped, before words,
# sentences, or any pattern counts are taken. This keeps CLI commands, code
# samples and file paths inside the sample text from tripping the prose
# checks below.
#
# See plugins/humanize/tests/README usage in writing-quality.sh for how this
# is driven across scenarios/models/conditions. Kept standalone so a single
# sample can be checked by hand: bash score.sh fixtures/slop.md --kind descriptive
# =============================================================================

set -uo pipefail

HEADER_COLS="file\tkind\twords\tsentences\tmax_sentence_words\tlong_sentences\tem_dashes\tsemicolons\tcontractions\ttrailing_participials\tbanned_words\thedges\tnot_just\tintensifiers\tallows_you\tby_gerund\tanaphora\tsame_length_runs\tsummary_closer\tpreamble\tviolations"

usage() {
    echo "Usage: score.sh FILE [--kind procedural|descriptive|copy|reply]" >&2
    echo "       score.sh --header" >&2
}

if [ "${1:-}" = "--header" ]; then
    printf '%b\n' "$HEADER_COLS"
    exit 0
fi

if [ $# -lt 1 ]; then
    usage
    exit 2
fi

FILE="$1"
shift

KIND="descriptive"
while [ $# -gt 0 ]; do
    case "$1" in
        --kind)
            KIND="${2:-}"
            shift 2
            ;;
        --header)
            printf '%b\n' "$HEADER_COLS"
            exit 0
            ;;
        *)
            echo "score.sh: unrecognised argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

case "$KIND" in
    procedural|descriptive|copy|reply) ;;
    *)
        echo "score.sh: --kind must be one of procedural|descriptive|copy|reply, got: $KIND" >&2
        exit 2
        ;;
esac

if [ ! -f "$FILE" ]; then
    echo "score.sh: no such file: $FILE" >&2
    exit 2
fi

CAP=25
[ "$KIND" = "procedural" ] && CAP=20
# creative-copy deliberately mixes short sentences with long ones up to 35
# words, so the documentation cap would penalise a rule that skill enforces.
[ "$KIND" = "copy" ] && CAP=35

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/score.XXXXXX")
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

CLEAN="$WORKDIR/clean.txt"
SENTENCES="$WORKDIR/sentences.txt"

# -----------------------------------------------------------------------------
# 0. Unwrap a whole-document fence. Models asked to "output only the markdown"
#    often wrap the entire answer in ```markdown ... ```. That is prose, not a
#    code sample, so drop the outer pair before code blocks are stripped.
#    Fires when the first non-blank line is a fence tagged markdown, md, text
#    or nothing, and its closing fence sits at or past the midpoint of the file
#    (so a real code sample at the top of a document is left alone). Anything
#    after the closing fence (a trailing note from the model) is kept as prose.
# -----------------------------------------------------------------------------
awk '
    { lines[NR] = $0 }
    END {
        first = 1; while (first <= NR && lines[first] ~ /^[[:space:]]*$/) first++
        close_at = 0
        if (first <= NR && lines[first] ~ /^[[:space:]]*```(markdown|md|text)?[[:space:]]*$/) {
            for (i = first + 1; i <= NR; i++) {
                if (lines[i] ~ /^[[:space:]]*```[[:space:]]*$/) { close_at = i; break }
            }
        }
        wrapped = (close_at > 0 && close_at * 2 >= NR)
        for (i = 1; i <= NR; i++) {
            if (wrapped && (i == first || i == close_at)) continue
            print lines[i]
        }
    }
' "$FILE" > "$WORKDIR/unwrapped.txt"

# -----------------------------------------------------------------------------
# 1. Strip fenced code blocks (whole block, fences included).
# -----------------------------------------------------------------------------
awk '
    /^[[:space:]]*```/ { infence = !infence; next }
    infence { next }
    { print }
' "$WORKDIR/unwrapped.txt" > "$WORKDIR/nofence.txt"

# -----------------------------------------------------------------------------
# 2. Strip inline code spans, then markdown bullet/header/bold/italic markers.
#    Order matters: inline code first, so a code span containing "#" or "*"
#    does not get mistaken for a heading or emphasis marker.
# -----------------------------------------------------------------------------
sed -E \
    -e 's/`[^`]*`//g' \
    -e 's/^[[:space:]]*(#{1,6})[[:space:]]*//' \
    -e 's/^[[:space:]]*[-*+][[:space:]]+//' \
    -e 's/^[[:space:]]*[0-9]+[.)][[:space:]]+//' \
    -e 's/\*\*//g' \
    -e 's/__//g' \
    -e 's/\*//g' \
    "$WORKDIR/nofence.txt" > "$CLEAN"

# -----------------------------------------------------------------------------
# 3. Join into one flowing stream (newline -> space), then split into one
#    sentence per line on '.', '!' or '?' followed by whitespace/end.
# -----------------------------------------------------------------------------
tr '\n' ' ' < "$CLEAN" | sed -E 's/[[:space:]]+/ /g' > "$WORKDIR/flow.txt"

sed -E 's/([.!?])[[:space:]]+/\1\n/g' "$WORKDIR/flow.txt" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | grep -v '^$' > "$SENTENCES" || true

WORDS=$(awk '{ n += NF } END { print n + 0 }' "$CLEAN")

# -----------------------------------------------------------------------------
# 4. Per-sentence metrics: count, max length, long-sentence count, by_gerund,
#    anaphora runs, same-length runs. All from the one-sentence-per-line file.
# -----------------------------------------------------------------------------
AWK_OUT=$(awk -v cap="$CAP" '
    function firstword(s,    w) {
        w = s
        sub(/^[[:space:]]+/, "", w)
        sub(/[[:space:]].*$/, "", w)
        gsub(/[^A-Za-z0-9]/, "", w)
        return tolower(w)
    }
    {
        n = NF
        sentences++
        if (n > maxw) maxw = n
        if (n > cap) longcount++
        if ($0 ~ /^By [a-z]+ing/) bygerund++

        fw = firstword($0)
        if (fw != "" && fw == prevword) {
            arun++
        } else {
            arun = 1
        }
        prevword = fw
        if (arun == 3) anaphora++

        if (lrun == 0) {
            lmin = n; lmax = n; lrun = 1
        } else {
            newmin = (n < lmin) ? n : lmin
            newmax = (n > lmax) ? n : lmax
            if (newmax - newmin <= 5) {
                lmin = newmin; lmax = newmax; lrun++
            } else {
                lmin = n; lmax = n; lrun = 1
            }
        }
        if (lrun == 3) samelen++
    }
    END {
        print sentences+0, maxw+0, longcount+0, bygerund+0, anaphora+0, samelen+0
    }
' "$SENTENCES")
read -r SENTENCES_N MAX_SENT_WORDS LONG_SENT BY_GERUND ANAPHORA SAME_LEN_RUNS <<< "$AWK_OUT"

# -----------------------------------------------------------------------------
# 5. Regex-pattern metrics on the cleaned flowing text (grep -o | wc -l).
#    Each grep is wrapped so "no matches" (exit 1) counts as zero instead of
#    failing the script under `set -o pipefail`.
# -----------------------------------------------------------------------------
count_matches() {
    # $1 = grep flags (word-split intentionally), $2 = pattern, $3 = file
    local flags="$1" pattern="$2" file="$3"
    grep $flags -o -E "$pattern" "$file" 2>/dev/null | grep -c . || true
}

FLOW="$WORKDIR/flow.txt"

EM_DASH_CHAR=$(count_matches "" '—' "$FLOW")
EN_DASH_SPACED=$(count_matches "" ' – ' "$FLOW")
DOUBLE_HYPHEN_SPACED=$(count_matches "" ' -- ' "$FLOW")
EM_DASHES=$((EM_DASH_CHAR + EN_DASH_SPACED + DOUBLE_HYPHEN_SPACED))

SEMICOLONS=$(count_matches "" ';' "$CLEAN")

CONTRACTION_PATTERN="['’](ll|re|ve|d|m)|n['’]t|\b(it|that|there|here)['’]s"
CONTRACTIONS=$(count_matches "-i" "$CONTRACTION_PATTERN" "$FLOW")

TRAILING_PARTICIPIAL_PATTERN=', (making|allowing|enabling|ensuring|highlighting|underscoring|reflecting|solidifying|helping|giving|providing|creating|leading)\b'
TRAILING_PARTICIPIALS=$(count_matches "-i" "$TRAILING_PARTICIPIAL_PATTERN" "$FLOW")

BANNED_WORDS_PATTERN='\b(delve|tapestry|landscape|navigate|leverage|foster|robust|utilize|nuanced|multifaceted|pivotal|underscore|underscores|holistic|synergy|paradigm|transformative|groundbreaking|cutting-edge|harness|streamline|cornerstone|encompass|encompasses|facilitate|facilitates|moreover|furthermore|nevertheless|myriad|plethora|seamless|seamlessly|comprehensive|crucial|vital|testament|showcase|showcases|elevate|empower|empowers|effortlessly|simply|easily)\b'
BANNED_WORDS=$(count_matches "-i" "$BANNED_WORDS_PATTERN" "$FLOW")

HEDGES_PATTERN='\b(should|may|might|could)\b'
HEDGES=$(count_matches "-i" "$HEDGES_PATTERN" "$FLOW")

NOT_JUST_PATTERN='not just|isn'"'"'t just|is not just|more than just|not only'
NOT_JUST=$(count_matches "-i" "$NOT_JUST_PATTERN" "$FLOW")

INTENSIFIERS_PATTERN='\b(truly|really|incredibly|absolutely|extremely)\b'
INTENSIFIERS=$(count_matches "-i" "$INTENSIFIERS_PATTERN" "$FLOW")

ALLOWS_YOU_PATTERN='\b(allows|enables|empowers) you to\b'
ALLOWS_YOU=$(count_matches "-i" "$ALLOWS_YOU_PATTERN" "$FLOW")

SUMMARY_CLOSER=0
grep -q -E 'In summary|In conclusion|Overall,|To sum up' "$FLOW" 2>/dev/null && SUMMARY_CLOSER=1

PREAMBLE=0
FIRST_LINE=$(grep -m1 -v '^[[:space:]]*$' "$FILE" 2>/dev/null || true)
if printf '%s' "$FIRST_LINE" | grep -q -E '^(Great|Sure|Certainly|Absolutely|Let me|I'"'"'ll|Here'"'"'s|Here is)'; then
    PREAMBLE=1
fi

# -----------------------------------------------------------------------------
# 6. Weighted violations total, per the spec:
#    long_sentences + em_dashes + semicolons + trailing_participials +
#    banned_words + not_just + intensifiers + allows_you + by_gerund +
#    anaphora + same_length_runs + summary_closer + preamble, plus
#    contractions when kind is procedural/descriptive, plus hedges when kind
#    is procedural/reply.
# -----------------------------------------------------------------------------
VIOLATIONS=$((LONG_SENT + EM_DASHES + SEMICOLONS + TRAILING_PARTICIPIALS + BANNED_WORDS + NOT_JUST + INTENSIFIERS + ALLOWS_YOU + BY_GERUND + ANAPHORA + SAME_LEN_RUNS + SUMMARY_CLOSER + PREAMBLE))

case "$KIND" in
    procedural|descriptive) VIOLATIONS=$((VIOLATIONS + CONTRACTIONS)) ;;
esac
case "$KIND" in
    procedural|reply) VIOLATIONS=$((VIOLATIONS + HEDGES)) ;;
esac

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$FILE" "$KIND" "$WORDS" "$SENTENCES_N" "$MAX_SENT_WORDS" "$LONG_SENT" "$EM_DASHES" "$SEMICOLONS" \
    "$CONTRACTIONS" "$TRAILING_PARTICIPIALS" "$BANNED_WORDS" "$HEDGES" "$NOT_JUST" "$INTENSIFIERS" \
    "$ALLOWS_YOU" "$BY_GERUND" "$ANAPHORA" "$SAME_LEN_RUNS" "$SUMMARY_CLOSER" "$PREAMBLE" "$VIOLATIONS"
