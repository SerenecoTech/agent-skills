#!/usr/bin/env sh
# SessionStart hook: prints rules/reply-clarity.md so it lands in the session
# context as always-on guidance for replies a person will read.
#
# Fails open. Any failure exits 0 and the session starts without the rules,
# because a hook that blocks session start when it breaks is a hook someone
# uninstalls.
#
# Pure POSIX sh so it runs wherever Claude Code runs a command hook (sh on
# macOS/Linux, Git Bash on Windows) with no other dependency.
#
# The matcher in hooks.json fires on startup, resume, clear and compact, so the
# rules survive /clear and context compaction.

# $0 is the absolute script path substituted into hooks.json by Claude Code, so
# resolve the rules file relative to it rather than trusting an exported
# environment variable.
script_dir=$(dirname -- "$0") || exit 0
rules_path="$script_dir/../rules/reply-clarity.md"
[ -f "$rules_path" ] || exit 0

body=$(cat -- "$rules_path") || exit 0

printf 'REPLY CLARITY (humanize plugin). The rules below apply to every reply written for a person to read. They do not apply to code, tool input, commit messages, subagent prompts, or a report returned to another agent. For documents and copy, use the humanize skill instead.\n\n%s\n' "$body"
exit 0
