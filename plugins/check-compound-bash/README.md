# check-compound-bash

check-compound-bash is a PreToolUse hook on the Bash tool. It splits compound commands (pipes, `&&`, `||`, `;`, subshells, `$(...)`, `bash -c`) into segments using [shfmt](https://github.com/mvdan/sh)'s AST, then checks every segment against the `Bash(...)` rules in your Claude Code settings files. It never approves anything Claude Code's native permission rules would not already allow. It only removes the confirmation prompt for compound commands whose parts are all already allowed.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install check-compound-bash@sereneco
```

Restart Claude Code. Hooks load at session start, so nothing runs until you do.

Needs `bash` 4.3 or later, [`shfmt`](https://github.com/mvdan/sh) and `jq`. On macOS: `brew install shfmt jq`. The script re-execs itself with a Homebrew `bash` if the system `/bin/bash` is older than 4.3.

## What it does

On every `Bash` tool call, the hook reads the command, decides whether it is compound (it contains `|`, `&`, `;`, `` ` ``, `$(`, `<(` or `>(`), and if so parses it with `shfmt -tojson` and walks the resulting AST to pull out each individual sub-command, including ones inside `$(...)`, `bash -c '...'` and `sh -c '...'` wrappers.

It checks each sub-command against `Bash(...)` rules read from, in order:

- `~/.claude/settings.json`
- `~/.claude/settings.local.json`
- `<repo-root>/.claude/settings.json`
- `<repo-root>/.claude/settings.local.json`

`<repo-root>` is the git worktree's common directory when you are inside a worktree. Outside a worktree it is the repository top level. Outside a git repository entirely, it falls back to `./.claude/settings.json` and `./.claude/settings.local.json` in the current directory.

A simple, non-compound command skips the shfmt parse entirely and is checked directly against the same allow and deny rules.

## Outcomes

| Outcome | Condition | Result |
| --- | --- | --- |
| Allow | every segment matches an allow rule and no segment matches a deny rule | hook exits 0 with an allow decision. The confirmation prompt is skipped |
| Deny | any segment matches a deny rule | hook exits 2 and blocks the command. A deny message explains why |
| Fall through | anything else, including an unparseable command or no allow rules at all | hook exits 0 with no decision. Claude Code's native permission prompt runs as usual |

The hook checks the deny rules even when every segment already matches an allow rule. Claude Code's own deny-first precedence would still block such a command, but checking deny here keeps the hook's decision self-consistent instead of relying on that override.

## Matching rules

An allow rule is a literal, start-anchored prefix match. `Bash(ls *)` matches `ls` and `ls -la`, but not `lsof`. An embedded `*` inside an allow rule is treated as a literal character, not a wildcard.

A deny rule accepts a literal prefix too, but also a native-style glob, so trailing or mid-command flags get caught. `*` matches any run of characters, including spaces, anywhere in the command. A trailing ` *` (or `:*`) means "space, or end of string".

| Deny rule | Blocks | Reason |
| --- | --- | --- |
| `Bash(find * -delete*)` | `find . -delete` | `*` matches the path argument, `-delete*` matches the flag anywhere after it |
| `Bash(sed -i*)` | every in-place `sed` call | trailing `*` matches any suffix, including no suffix at all |

Deny matching is a strict superset of the literal prefix case, so it mirrors Claude Code's own deny matcher.

## Fails open

If `shfmt` or `jq` is missing, if the command cannot be parsed, or if no allow rules are loaded from any settings file, the hook exits 0 and lets Claude Code's native prompt handle the command.

## Migrating from a hand-wired hook

Some users already have a hand-written equivalent at `~/.claude/hooks/approve-compound-bash.sh`, registered under `hooks.PreToolUse` in `~/.claude/settings.json`. The script this plugin ships is the same logic under a new name. If you have that entry, remove it from `~/.claude/settings.json` after installing this plugin, or the check runs twice on every Bash call.

## Debugging

Run the hook with `--debug` to print each matching decision to stderr, alongside the allow decision JSON it writes to stdout:

```bash
$ echo '{"tool_input":{"command":"git status && ls -la"}}' \
    | bash plugins/check-compound-bash/hooks/check-compound-bash.sh --debug --permissions '["Bash(git status)","Bash(ls *)"]'
[check-compound] Command: git status && ls -la
[check-compound] Loaded 2 allow, 0 deny prefixes, 0 deny globs
[check-compound] Compound command
[check-compound] MATCH (allow): 'git status' -> 'git status'
[check-compound] MATCH (allow): 'ls -la' -> 'ls'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
```

`--permissions` and `--deny` take JSON arrays of `Bash(...)` strings and are for testing only. Without them the hook reads your real settings files.

A denied segment produces exit code 2 and a JSON deny message on stderr instead:

```bash
$ echo '{"tool_input":{"command":"git status && danger-thing --now"}}' \
    | bash plugins/check-compound-bash/hooks/check-compound-bash.sh --debug --permissions '["Bash(git status)"]' --deny '["Bash(danger-thing *)"]'
[check-compound] Command: git status && danger-thing --now
[check-compound] Loaded 1 allow, 1 deny prefixes, 1 deny globs
[check-compound] Compound command
[check-compound] MATCH (allow): 'git status' -> 'git status'
[check-compound] MATCH (deny): 'danger-thing --now' -> 'danger-thing'
[check-compound] Not all commands approved
[check-compound] MATCH (deny): 'danger-thing --now' -> 'danger-thing'
[check-compound] Denied segment found: danger-thing --now
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny"
  },
  "systemMessage": "Compound command contains a denied sub-command"
}
```

Run the hook in `parse` mode to see exactly how it splits a command, one segment per line, without checking any rules:

```bash
$ echo 'git status && ls -la | head' | bash plugins/check-compound-bash/hooks/check-compound-bash.sh parse
git status
ls -la
head
```

## Limitations

- Allow-rule matching treats an embedded `*` as a literal character. A command that Claude Code's own native matcher would auto-approve on a mid-wildcard allow rule can still stop at this hook and fall through to the prompt.
- A command `shfmt` cannot parse falls through to the native prompt rather than being auto-approved. The script rewrites one known problem case, `[[ ! $x =~ pattern ]]`, before parsing. Other unparseable syntax is not rewritten.
- Recursing into `bash -c` or `sh -c` only works for the exact `[env] [/path/to/](ba)sh -c '...'` quoting shape. When the inner command cannot be parsed, the whole wrapper is checked as one literal string against the allow and deny rules, and will usually not match either.
