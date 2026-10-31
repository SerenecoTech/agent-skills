#!/usr/bin/env bash
# =============================================================================
# Shared secret patterns
# =============================================================================
# Sourced by write-guard (content being written), read-guard (content being
# read) and output-alarm (content that came back). One copy, because three
# copies of a security-critical list is three lists that drift.
#
# Two tiers, and the split is not cosmetic:
#
#   STRICT      shapes that are a credential and almost nothing else — a
#               prefixed token, a PEM header, a JWT, an AWS key id. Safe to act
#               on without further context.
#   CONTEXTUAL  key-looks-like-a-secret plus a long value. Catches formats
#               nobody has enumerated, at the cost of matching a stub or a
#               placeholder. Fine when the cost of a false positive is a denied
#               write or read; not fine when it halts a session.
#
# Nothing here ever prints a matched value in full. `secret_scan` reports the
# pattern and a shape hint, because a guard that echoes the secret it found has
# leaked it into the transcript itself.
#
# One editing note, learned the hard way: this file is guarded by its own
# patterns. Writing a pattern that contains a literal secret header — as the
# old GCP entry did, spelling out a PEM banner in full — makes the file
# undeliverable, because write-guard matches it on the way in. Keep patterns
# expressed as patterns.
# =============================================================================

SECRET_PATTERNS_STRICT=(
    # AWS
    'AKIA[0-9A-Z]{16}'
    'aws_secret_access_key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9/+=]{40}'

    # Anthropic
    'sk-ant-api[0-9]{2}-[a-zA-Z0-9_-]{95,}'

    # OpenAI
    'sk-proj-[a-zA-Z0-9_-]{32,}'
    'sk-[a-zA-Z0-9]{32,}'

    # GitHub. Five prefixes are issued, not two: ghp_ personal, gho_ OAuth,
    # ghu_ user-to-server, ghs_ server-to-server, ghr_ refresh. The OAuth one
    # is what the August 2026 incident leaked, and the old gh[ps]_ missed it.
    'gh[pousr]_[a-zA-Z0-9]{36,}'
    'github_pat_[a-zA-Z0-9_]{82}'

    # GitLab
    'glpat-[a-zA-Z0-9_-]{20,}'

    # Slack
    'xox[baprs]-[a-zA-Z0-9-]+'

    # Discord
    '[MN][A-Za-z0-9]{23}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}'

    # Google Cloud service accounts. The key material inside one is caught by
    # the PEM pattern below; this catches the wrapper.
    '"type"[[:space:]]*:[[:space:]]*"service_account"'

    # Azure
    'DefaultEndpointsProtocol=https;AccountName=[^;]+;AccountKey=[A-Za-z0-9+/=]{88}'

    # PEM private keys, any flavour
    'BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY'

    # JWTs
    'eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'

    # Stripe
    'sk_live_[a-zA-Z0-9]{24,}'
    'rk_live_[a-zA-Z0-9]{24,}'

    # SendGrid
    'SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}'

    # Twilio
    'SK[a-z0-9]{32}'

    # npm / PyPI
    'npm_[a-zA-Z0-9]{36}'
    'pypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{70,}'

    # Connection strings carrying a password
    '(postgres|mysql|mongodb(\+srv)?):\/\/[^:]+:[^@]{8,}@'
)

SECRET_PATTERNS_CONTEXTUAL=(
    '(api_?key|api_?secret|access_?token|oauth_?token|secret_?key|private_?key|password)[[:space:]]*[:=][[:space:]]*["'"'"']?[a-zA-Z0-9_+=/.-]{20,}["'"'"']?'
    # `git credential fill` and helper `get` output
    '^password=.{8,}'
)

# Contextual patterns matched case-insensitively. A name is as often API_KEY or
# apiKey as api_key. Only the quoted 40+ character literal is safe to widen
# this way: the pattern above also takes unquoted values, and folding its case
# would match every `apiKey: process.env.SOME_LONG_NAME`.
SECRET_PATTERNS_CONTEXTUAL_NOCASE=(
    '(key|secret|token|password|auth|credential)[[:space:]]*[:=][[:space:]]*["'"'"'][a-zA-Z0-9+/=_-]{40,}["'"'"']'
)

# Paths whose secrets are conventionally fake. Same rule write-guard has always
# used. It is a real blind spot — a genuine key in a file called *.example is
# invisible — kept because the alternative is denying every fixture in the repo.
SECRET_EXEMPT_PATH_RE='(test|mock|fixture|example|sample|dummy|\.spec\.|\.test\.)'

secret_path_is_exempt() {
    printf '%s' "${1:-}" | grep -qiE "$SECRET_EXEMPT_PATH_RE"
}

# secret_scan <text> [strict|all]
# Prints "<pattern><TAB><first 8 chars>…(<length> chars)" and returns 0 on a hit.
# Returns 1 and prints nothing otherwise. Never prints the whole match.
secret_scan() {
    local text="${1:-}" tier="${2:-all}"
    secret_scan_list -E "$text" "${SECRET_PATTERNS_STRICT[@]}" && return 0
    [ "$tier" = "strict" ] && return 1
    secret_scan_list -E "$text" "${SECRET_PATTERNS_CONTEXTUAL[@]}" && return 0
    secret_scan_list -iE "$text" "${SECRET_PATTERNS_CONTEXTUAL_NOCASE[@]}"
}

# secret_scan_list <grep flags> <text> <pattern>...
# The first pattern that matches, reported as secret_scan describes.
secret_scan_list() {
    local flags="$1" text="$2" p m
    shift 2
    for p in "$@"; do
        if printf '%s' "$text" | grep -q "$flags" -e "$p" 2>/dev/null; then
            m=$( { printf '%s' "$text" | grep -o "$flags" -e "$p" 2>/dev/null || true; } | head -n 1)
            printf '%s\t%s…(%s chars)' "$p" "$(printf '%s' "$m" | cut -c1-8)" "${#m}"
            return 0
        fi
    done
    return 1
}
