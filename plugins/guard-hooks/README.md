# guard-hooks

Security guardrails that run as hooks rather than as instructions. A rule written in a prompt is
a request the model can reason its way past; a `PreToolUse` hook is configured outside the
model's control and refuses the call regardless of intent.

Five hooks, 266 tests.

## Requirements

| Dependency | Required | Used for |
|---|---|---|
| `jq` (≥ 1.6) | yes | every hook parses its event and emits its decision as JSON |
| `bash` (≥ 4) | yes | all hooks and tests |
| coreutils / POSIX text tools | yes | `grep -E`, `tr`, `realpath`, `dirname`, `basename` |
| `git` | no | only `git-permission.sh` inspects git commands, and it parses text rather than calling git |

## The hooks

| Hook | Event | Decision it can make | On its own error |
|---|---|---|---|
| `bash-guard.sh` | PreToolUse `Bash` | **deny** only | **fail closed** (deny) |
| `write-guard.sh` | PreToolUse `Write\|Edit\|MultiEdit\|NotebookEdit` | **deny** only | **fail closed** (deny) |
| `rm-guard.sh` | PreToolUse `Bash` | **allow** only — never denies | fall through |
| `toolchain-guard.sh` | PreToolUse `Bash` | **deny** only | **fail open** (allow) |
| `git-permission.sh` | PermissionRequest `Bash` | none — emits a warning message | silent |

The two fail-closed guards are the security boundary, so a broken guard denies rather than waves
work through. `toolchain-guard` fails open on purpose: it enforces a project convention, not a
security property, and a convention check that blocks legitimate commands when it breaks gets
switched off — which is worse than not having it.

### bash-guard — denies dangerous commands

Normalises the command first (strips most quoting and escaping, collapses whitespace) so the
patterns are not defeated by `s\u\d\o`. Six categories:

| # | Category | Examples caught |
|---|---|---|
| 1 | Privilege escalation | `sudo`, `su`, `doas`, `pkexec` |
| 2 | Destructive file operations | recursive/forced deletes, wildcard deletes, writes to raw devices |
| 3 | Dangerous git operations | history-destroying and force operations |
| 4 | Indirect execution / obfuscation | piping a download into a shell, `base64 -d \| sh`, `eval` of fetched content |
| 5 | Credential/secret access | reading private keys, cloud credential files, keychains |
| 6 | Network exfiltration | posting local file contents to a remote host |

Category 6 is the most opinionated and the most likely to need loosening for your work; it is
commented as such in the script.

### write-guard — denies dangerous writes

Resolves symlinks and relative paths before matching, including resolving the parent directory
for files that do not exist yet, so a symlink cannot be used to reach a protected target.

- **Protected paths** — `.env` and its environment variants (but **not** `.env.example`), SSH
  keys, TLS keys and certificates, AWS/Azure/GCP credentials, kubeconfig, Docker config, npm /
  pypi / netrc registry auth, `.pgpass`, `.my.cnf`, git credentials and `.gitconfig`,
  `.htpasswd`, `secrets.*`, service-account JSON, `.gnupg/`, password stores.
- **Secret detection in content** — AWS access keys, Anthropic / OpenAI keys, GitHub PATs, PEM
  private key blocks, database URIs with inline passwords, plus a high-entropy heuristic. The
  heuristic is tuned to leave ordinary base64 use alone.
- **System directories** — `/etc`, `/boot`, `/sys`, `/proc`, `/dev`, `/root`, and the macOS
  `/private/...` equivalents.
- **Git safety** — writes into `.git/hooks/` and `.git/config`, which are code-execution and
  credential-helper vectors respectively.

### rm-guard — pre-approves provably-safe deletes

This one exists to reduce prompt fatigue without widening what is permitted. It emits `allow`
**only** when every segment of the command is statically decidable:

- each `rm` segment is non-recursive, glob-free, quote-free, and resolves — through symlinks —
  strictly inside the project root, and does not target a directory;
- each non-`rm` segment is either a known-inert builtin or already matches a `permissions.allow`
  pattern in your settings.

Anything containing `$`, backticks, `$(`, process substitution, or redirection falls through to
the normal permission flow, because the value handed to `rm` cannot then be asserted. It never
denies — `bash-guard` is the deny layer, and keeping the two separate means this hook's `allow`
can never over-permit a compound command that has a dangerous sibling.

### toolchain-guard — enforces the project's package manager

Reads the project's own declarations rather than a global preference:

- **JS/TS**, lock-file priority `bun` > `pnpm` > `yarn`: `bun.lock`/`bun.lockb` blocks npm, npx,
  yarn and pnpm; `pnpm-lock.yaml` blocks npm, npx and yarn; `yarn.lock` blocks npm for
  install/add/remove/ci. `package.json#packageManager` enforces whatever it declares.
- **Python**: with `VIRTUAL_ENV` active, blocks explicit global `pip` paths, `python3 -m pip`,
  and explicit global tool paths. `uv.lock` blocks bare `pip`/`pip3`.

### git-permission — warns, never blocks

Surfaces a message on force pushes, `reset --hard`, `clean -f`, `checkout -- .`, `restore .`,
`branch -D` and `rebase`. Advisory by design: these are legitimate operations that merely
deserve a second look at which branch you are on.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install guard-hooks@serenecotech
```

**Hooks load at session start** — restart before expecting anything to be enforced. Then check
`claude plugin list` shows `Status: ✔ enabled`; a hook that fails to load is reported there and
**not** by `claude plugin validate`.

### If you already wire these by hand

Installing the plugin while the same scripts are also referenced from `settings.json` runs each
guard twice. Harmless for the deny guards, but remove the duplicate `PreToolUse` entries so
there is one place to reason about.

## Testing

```bash
bash tests/run-all.sh          # all suites, non-zero exit on any failure
bash tests/test-bash-guard.sh  # or one at a time
```

266 tests: 67 bash-guard, 55 rm-guard, 124 toolchain-guard, 20 write-guard. Each suite resolves
the guard relative to itself, so the tests run from any checkout.

## Limits it states rather than hides

- **Pattern matching is not a sandbox.** These guards raise the cost of a mistake and catch the
  common shapes of a dangerous command. A determined bypass through an unanticipated encoding is
  possible, and defence against that belongs to a real sandbox, not to a regex.
- **`rm-guard` emits `allow`,** which Claude Code treats as more permissive than `ask`. Its
  static-decidability rules are what keep that narrow; loosening them widens real permissions.
- **The secret-detection patterns are a known-shapes list.** A credential format not in the list
  passes. Absence of a denial is not evidence a file is clean.
- **Category 6 of `bash-guard` will produce false positives** in work that legitimately posts
  file contents to an API.
