#!/usr/bin/env bash
# =============================================================================
# writing-quality.sh — RED/GREEN comparison harness for the humanize plugin.
# =============================================================================
# Runs the prompts in prompts/ through `claude -p`, once without the plugin
# (baseline, RED) and once with it loaded via --plugin-dir (plugin, GREEN),
# then scores every output with score.sh and prints a summary table.
#
# Usage:
#   writing-quality.sh [--models sonnet,opus] [--out DIR]
#                       [--scenarios procedural,descriptive,copy,reply]
#                       [--score-only DIR] [--reps N]
#
# `--setting-sources project` is passed on every --plugin-dir call so neither
# condition picks up the developer's own ~/.claude skills or hooks — otherwise
# a loose humanize-like skill in someone's home directory could contaminate
# the baseline (RED) run and understate the plugin's effect.
#
# The plugin's SessionStart hook does not run under --plugin-dir from a
# sandboxed session (Claude Code must first mkdir a data directory under
# ~/.claude/plugins/data, which the sandbox refuses). Pass
# --plugin-config-dir with a CLAUDE_CONFIG_DIR where humanize is installed to
# exercise the hook; the reply scenario depends on it.
#
# This is a measurement, not a gate: it exits 0 even when GREEN is worse than
# RED. It only exits non-zero for a usage error (bad flag, bad --score-only
# directory) before any measurement is attempted.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCORE_SH="$SCRIPT_DIR/score.sh"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

VALID_SCENARIOS=(procedural descriptive copy reply)

usage() {
    cat >&2 <<'USAGE'
Usage: writing-quality.sh [--models sonnet,opus] [--out DIR]
                           [--scenarios procedural,descriptive,copy,reply]
                           [--score-only DIR] [--reps N]
                           [--plugin-config-dir DIR]

  --models      Comma-separated model aliases/ids to run. Default: sonnet
  --out         Output directory. Default: plugins/humanize/tests/out/<timestamp>
  --scenarios   Comma-separated scenario names to run. Default: all four.
  --score-only  Re-score an existing output directory. No claude calls made.
  --reps        Repetitions per scenario/model/condition. Default: 1.
  --plugin-config-dir
                A CLAUDE_CONFIG_DIR that has humanize installed and enabled.
                When given, the plugin condition runs against that config
                instead of --plugin-dir, which is the only way the plugin's
                SessionStart hook runs (inline plugins need a data directory
                under ~/.claude/plugins/data that a sandboxed session cannot
                create). Required for the reply scenario to mean anything.
                Build one with:
                  export CLAUDE_CONFIG_DIR=/tmp/humanize-test
                  claude plugin marketplace add /path/to/this/repo
                  claude plugin install humanize@sereneco
USAGE
}

MODELS="sonnet"
OUT=""
SCENARIOS="procedural,descriptive,copy,reply"
SCORE_ONLY_DIR=""
REPS=1
PLUGIN_CONFIG_DIR=""
MODELS_SET=0
SCENARIOS_SET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --plugin-config-dir)
            [ $# -ge 2 ] || { echo "writing-quality.sh: --plugin-config-dir needs a value" >&2; exit 2; }
            PLUGIN_CONFIG_DIR="$2"
            [ -d "$PLUGIN_CONFIG_DIR" ] || { echo "writing-quality.sh: --plugin-config-dir: no such directory: $2" >&2; exit 2; }
            shift 2
            ;;
        --models)
            [ $# -ge 2 ] || { echo "writing-quality.sh: --models needs a value" >&2; exit 2; }
            MODELS="$2"
            MODELS_SET=1
            shift 2
            ;;
        --out)
            [ $# -ge 2 ] || { echo "writing-quality.sh: --out needs a value" >&2; exit 2; }
            OUT="$2"
            shift 2
            ;;
        --scenarios)
            [ $# -ge 2 ] || { echo "writing-quality.sh: --scenarios needs a value" >&2; exit 2; }
            SCENARIOS="$2"
            SCENARIOS_SET=1
            shift 2
            ;;
        --score-only)
            [ $# -ge 2 ] || { echo "writing-quality.sh: --score-only needs a value" >&2; exit 2; }
            SCORE_ONLY_DIR="$2"
            shift 2
            ;;
        --reps)
            [ $# -ge 2 ] || { echo "writing-quality.sh: --reps needs a value" >&2; exit 2; }
            REPS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "writing-quality.sh: unrecognised argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if ! [[ "$REPS" =~ ^[1-9][0-9]*$ ]]; then
    echo "writing-quality.sh: --reps must be a positive integer, got: $REPS" >&2
    exit 2
fi

IFS=',' read -r -a SCENARIO_ARR <<< "$SCENARIOS"
for s in "${SCENARIO_ARR[@]}"; do
    ok=0
    for v in "${VALID_SCENARIOS[@]}"; do [ "$s" = "$v" ] && ok=1; done
    if [ "$ok" -ne 1 ]; then
        echo "writing-quality.sh: invalid scenario '$s'. Valid: ${VALID_SCENARIOS[*]}" >&2
        exit 2
    fi
    if [ ! -f "$PROMPTS_DIR/$s.txt" ]; then
        echo "writing-quality.sh: missing prompt file for scenario '$s': $PROMPTS_DIR/$s.txt" >&2
        exit 2
    fi
done

IFS=',' read -r -a MODEL_ARR <<< "$MODELS"
for m in "${MODEL_ARR[@]}"; do
    if [ -z "$m" ]; then
        echo "writing-quality.sh: empty model name in --models '$MODELS'" >&2
        exit 2
    fi
done

SCORE_ONLY=0
if [ -n "$SCORE_ONLY_DIR" ]; then
    SCORE_ONLY=1
    if [ ! -d "$SCORE_ONLY_DIR" ]; then
        echo "writing-quality.sh: --score-only directory does not exist: $SCORE_ONLY_DIR" >&2
        exit 2
    fi
    OUT="$SCORE_ONLY_DIR"
elif [ -z "$OUT" ]; then
    OUT="$SCRIPT_DIR/out/$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$OUT"

# -----------------------------------------------------------------------------
# Header/column lookup: read score.sh's own column names so the summary picks
# fields by name instead of a hardcoded index that would drift out of sync.
# -----------------------------------------------------------------------------
declare -A COLIDX
i=0
while IFS= read -r col; do
    COLIDX["$col"]=$i
    i=$((i + 1))
done < <(bash "$SCORE_SH" --header | tr '\t' '\n')

field() {
    # $1 = tab-separated score line, $2 = column name
    local line="$1" name="$2"
    awk -F'\t' -v idx=$((COLIDX["$name"] + 1)) '{ print $idx }' <<< "$line"
}

# -----------------------------------------------------------------------------
# Generation: skipped entirely in --score-only mode.
# -----------------------------------------------------------------------------
if [ "$SCORE_ONLY" -eq 0 ]; then
    RAW_DIR="$OUT/raw"
    mkdir -p "$RAW_DIR"

    for scenario in "${SCENARIO_ARR[@]}"; do
        prompt_file="$PROMPTS_DIR/$scenario.txt"
        prompt_text=$(cat "$prompt_file")
        for model in "${MODEL_ARR[@]}"; do
            for condition in baseline plugin; do
                rep=1
                while [ "$rep" -le "$REPS" ]; do
                    base="${scenario}-${model}-${condition}-${rep}"
                    echo "writing-quality.sh: running $base ..." >&2

                    # --max-turns is generous because a model given repo cwd
                    # sometimes explores before answering; a run that hits the
                    # cap returns no result and scores as zero words.
                    cmd=(claude --model "$model" --max-turns 10 \
                        -p "$prompt_text" --output-format stream-json --verbose)
                    config_dir="${CLAUDE_CONFIG_DIR:-}"
                    if [ "$condition" = "plugin" ] && [ -n "$PLUGIN_CONFIG_DIR" ]; then
                        # Installed route: the config dir is clean apart from
                        # the plugin, so no --setting-sources filter is needed
                        # and the SessionStart hook runs.
                        config_dir="$PLUGIN_CONFIG_DIR"
                    else
                        cmd+=(--setting-sources project)
                        if [ "$condition" = "plugin" ]; then
                            cmd+=(--plugin-dir "$PLUGIN_ROOT")
                        fi
                    fi

                    raw_file="$RAW_DIR/${base}.jsonl"
                    err_file="$RAW_DIR/${base}.stderr"
                    if [ -n "$config_dir" ]; then
                        (cd "$REPO_ROOT" && CLAUDE_CONFIG_DIR="$config_dir" "${cmd[@]}") > "$raw_file" 2> "$err_file"
                    else
                        (cd "$REPO_ROOT" && "${cmd[@]}") > "$raw_file" 2> "$err_file"
                    fi
                    rc=$?
                    if [ "$rc" -ne 0 ]; then
                        echo "writing-quality.sh: WARN claude exited $rc for $base — see $err_file" >&2
                    fi

                    clean_file="$RAW_DIR/${base}.clean.jsonl"
                    jq -R 'fromjson? // empty' "$raw_file" > "$clean_file" 2>/dev/null || true

                    # -s (slurp) + "last" picks the final result object at the JSON
                    # level before any text is emitted — piping jq -r's raw text
                    # output through `tail -n1` would instead grab only the last
                    # *line* of a multi-paragraph result, truncating it.
                    jq -rs '[.[] | select(.type=="result")] | last | .result // empty' \
                        "$clean_file" 2>/dev/null > "$OUT/${base}.md"

                    jq -r '
                        select(.type=="assistant")
                        | .message.content[]?
                        | select(.type=="tool_use")
                        | [.name, ((.input | tostring)[0:120])]
                        | @tsv
                    ' "$clean_file" 2>/dev/null > "$OUT/${base}.tools"

                    rep=$((rep + 1))
                done
            done
        done
    done
fi

# -----------------------------------------------------------------------------
# Discover runs to score. Filenames are <scenario>-<model>-<condition>-<rep>.md.
# Scenario names never contain '-', so the first field is always the scenario
# and the last two fields are always condition/rep; anything in between is
# the model name (which can itself contain dashes, e.g. a full model id).
# -----------------------------------------------------------------------------
declare -a RUN_FILES=()
while IFS= read -r -d '' f; do
    RUN_FILES+=("$f")
done < <(find "$OUT" -maxdepth 1 -type f -name '*.md' -print0 | sort -z)

if [ "${#RUN_FILES[@]}" -eq 0 ]; then
    echo "writing-quality.sh: no result files found in $OUT" >&2
    exit 0
fi

SUMMARY_TSV="$OUT/summary.tsv"
printf 'scenario\tmodel\tcondition\trep\tskill_invoked\twords\tlong_sentences\tbanned_words\tem_dashes\tcontractions\thedges\tanaphora\tsame_length_runs\tviolations\n' > "$SUMMARY_TSV"

printf '%-12s %-24s %-9s %-4s %-13s %-6s %-14s %-12s %-9s %-12s %-7s %-9s %-16s %-10s\n' \
    scenario model condition rep skill_invoked words long_sentences banned_words em_dashes contractions hedges anaphora same_length_runs violations

for f in "${RUN_FILES[@]}"; do
    base=$(basename "$f" .md)
    IFS='-' read -r -a parts <<< "$base"
    n=${#parts[@]}
    scenario="${parts[0]}"
    rep="${parts[$((n - 1))]}"
    condition="${parts[$((n - 2))]}"
    model=$(IFS='-'; echo "${parts[*]:1:$((n - 3))}")

    if [ "$SCENARIOS_SET" -eq 1 ]; then
        keep=0
        for s in "${SCENARIO_ARR[@]}"; do [ "$s" = "$scenario" ] && keep=1; done
        [ "$keep" -eq 1 ] || continue
    fi
    if [ "$MODELS_SET" -eq 1 ]; then
        keep=0
        for m in "${MODEL_ARR[@]}"; do [ "$m" = "$model" ] && keep=1; done
        [ "$keep" -eq 1 ] || continue
    fi

    ok=0
    for v in "${VALID_SCENARIOS[@]}"; do [ "$scenario" = "$v" ] && ok=1; done
    [ "$ok" -eq 1 ] || continue

    score_line=$(bash "$SCORE_SH" "$f" --kind "$scenario")

    tools_file="$OUT/${base}.tools"
    skill_invoked=0
    if [ -f "$tools_file" ] && grep -qi $'^Skill\t.*humanize' "$tools_file" 2>/dev/null; then
        skill_invoked=1
    fi

    words=$(field "$score_line" words)
    long_sentences=$(field "$score_line" long_sentences)
    banned_words=$(field "$score_line" banned_words)
    em_dashes=$(field "$score_line" em_dashes)
    contractions=$(field "$score_line" contractions)
    hedges=$(field "$score_line" hedges)
    anaphora=$(field "$score_line" anaphora)
    same_length_runs=$(field "$score_line" same_length_runs)
    violations=$(field "$score_line" violations)

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$scenario" "$model" "$condition" "$rep" "$skill_invoked" "$words" "$long_sentences" \
        "$banned_words" "$em_dashes" "$contractions" "$hedges" "$anaphora" "$same_length_runs" "$violations" \
        >> "$SUMMARY_TSV"

    printf '%-12s %-24s %-9s %-4s %-13s %-6s %-14s %-12s %-9s %-12s %-7s %-9s %-16s %-10s\n' \
        "$scenario" "$model" "$condition" "$rep" "$skill_invoked" "$words" "$long_sentences" \
        "$banned_words" "$em_dashes" "$contractions" "$hedges" "$anaphora" "$same_length_runs" "$violations"
done

echo ""
echo "── baseline vs plugin, mean violations per scenario/model ──"

awk -F'\t' '
    NR == 1 { next }
    {
        key = $1 SUBSEP $2
        if ($3 == "baseline") { bsum[key] += $14; bn[key]++ }
        if ($3 == "plugin")   { psum[key] += $14; pn[key]++ }
        seen[key] = 1
    }
    END {
        for (key in seen) {
            split(key, parts, SUBSEP)
            if (bn[key] > 0 && pn[key] > 0) {
                b = bsum[key] / bn[key]
                p = psum[key] / pn[key]
                printf "%s\t%s\t%s\t%s\n", parts[1], parts[2], b, p
            }
        }
    }
' "$SUMMARY_TSV" | sort | while IFS=$'\t' read -r scenario model bviol pviol; do
    is_less=$(awk -v b="$bviol" -v p="$pviol" 'BEGIN { print (p < b) ? 1 : 0 }')
    if [ "$is_less" -eq 1 ]; then
        printf "%-12s %-24s ${GREEN}baseline violations %s -> plugin violations %s (GREEN)${NC}\n" "$scenario" "$model" "$bviol" "$pviol"
    else
        printf "%-12s %-24s ${RED}baseline violations %s -> plugin violations %s (RED)${NC}\n" "$scenario" "$model" "$bviol" "$pviol"
    fi
done

echo ""
echo "Summary written to $SUMMARY_TSV"
exit 0
