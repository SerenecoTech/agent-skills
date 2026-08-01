# guard-hooks

Five hooks that block dangerous agent actions before they run: privilege escalation, obfuscated
command execution, writes to credential files, secrets committed into source, and the wrong package
manager. 266 tests.

Nothing here depends on the agent choosing to cooperate. A hook runs outside the conversation, so it
applies equally to an agent mid-task, a subagent you never see the transcript of, and an agent
acting on instructions it picked up from a file it read.

## What it looks like

Real output from the guards, not paraphrased:

| You (or your agent) attempt | Result |
|---|---|
| write `/proj/.env` | denied: `Cannot write to protected file: /proj/.env` |
| write an AWS key into `config.js` | denied: `Potential secret detected in content: AKIA…` |
| `sudo apt install nginx` | denied: `Privilege escalation blocked` |
| `curl -s http://…/install.sh \| sh` | denied: `Obfuscated execution pattern blocked` |
| `npm install lodash` beside a `pnpm-lock.yaml` | denied: `pnpm-lock.yaml present — use pnpm instead of npm` |
| `git push --force origin main` | allowed, with a warning to check the branch |
| write `/proj/.env.example` | allowed; the guard distinguishes it from `.env` |

The secret-detection message echoes the credential it matched, shortened here. Writing this README
tripped that guard on the first attempt, which is roughly the intended experience.

## The five hooks

| Hook | Event | Can decide | If the hook itself errors |
|---|---|---|---|
| `bash-guard.sh` | PreToolUse `Bash` | deny only | **fails closed** (denies) |
| `write-guard.sh` | PreToolUse `Write\|Edit\|MultiEdit\|NotebookEdit` | deny only | **fails closed** (denies) |
| `rm-guard.sh` | PreToolUse `Bash` | allow only, never denies | falls through |
| `toolchain-guard.sh` | PreToolUse `Bash` | deny only | **fails open** (allows) |
| `git-permission.sh` | PermissionRequest `Bash` | nothing; warns only | silent |

The two fail-closed guards are the security boundary, so a broken one denies instead of waving work
through. `toolchain-guard` fails open deliberately: it enforces a project convention rather than a
security property, and a convention check that blocks legitimate commands when it breaks is a check
you will switch off.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install guard-hooks@sereneco
```

**Restart Claude Code.** Hooks load at session start, so nothing is enforced until you do. Then
check `claude plugin list` shows `Status: ✔ enabled`; a hook that failed to load is reported there
and not by `claude plugin validate`.

### If you already wire these up by hand

Installing the plugin while the same scripts are still referenced from `settings.json` runs every
guard twice. That's harmless for deny-only guards, but remove the duplicate `PreToolUse` entries so
there's one place to reason about.

## What each hook does

### bash-guard

Normalises the command first, stripping most quoting and escaping and collapsing whitespace, so
`s\u\d\o` doesn't slip past. Then six categories:

| # | Category | Caught, for example |
|---|---|---|
| 1 | Privilege escalation | `sudo`, `su`, `doas`, `pkexec` |
| 2 | Destructive file operations | recursive and forced deletes, wildcard deletes, writes to raw devices |
| 3 | Dangerous git operations | history-destroying and force operations |
| 4 | Indirect execution | piping a download into a shell, `base64 -d \| sh`, `eval` of fetched content |
| 5 | Credential access | reading private keys, cloud credential files, keychains |
| 6 | Network exfiltration | posting local file contents to a remote host |

Category 6 is the most opinionated and the one most likely to need loosening for your work. The
script says so at that line.

### write-guard

Resolves symlinks and relative paths before matching, and for a file that doesn't exist yet it
resolves the parent directory, so a symlink can't be used to reach a protected target.

- **Protected paths** — `.env` and its environment variants but not `.env.example`; SSH keys; TLS
  keys and certificates; AWS, Azure and GCP credentials; kubeconfig; Docker config; npm, pypi and
  netrc registry auth; `.pgpass`; `.my.cnf`; git credentials and `.gitconfig`; `.htpasswd`;
  `secrets.*`; service-account JSON; `.gnupg/`; password stores.
- **Secrets in content** — AWS access keys, Anthropic and OpenAI keys, GitHub PATs, PEM private key
  blocks, database URIs with inline passwords, and a high-entropy heuristic tuned to leave ordinary
  base64 alone.
- **System directories** — `/etc`, `/boot`, `/sys`, `/proc`, `/dev`, `/root`, plus the macOS
  `/private/...` equivalents.
- **Git internals** — `.git/hooks/` and `.git/config`, which are a code-execution vector and a
  credential-helper vector respectively.

### rm-guard

Cuts down permission prompts without widening what's permitted. It returns `allow` only when every
segment of the command is statically decidable:

- each `rm` segment is non-recursive, glob-free and quote-free, resolves through symlinks to
  somewhere strictly inside the project root, and isn't a directory;
- each non-`rm` segment is either a known-inert builtin or already matches a `permissions.allow`
  pattern in your settings.

Anything containing `$`, backticks, `$(`, process substitution or redirection falls through to the
normal permission flow, since you can't then assert what value `rm` will receive.

This hook never denies. `bash-guard` is the deny layer, and keeping them separate is what stops an
`allow` here from over-permitting a compound command with a dangerous sibling.

### toolchain-guard

Reads what the project declares about itself:

- **JS/TS**, lock file priority `bun` > `pnpm` > `yarn`. A `bun.lock` or `bun.lockb` blocks npm,
  npx, yarn and pnpm; `pnpm-lock.yaml` blocks npm, npx and yarn; `yarn.lock` blocks npm for
  install, add, remove and ci. `package.json#packageManager` enforces whatever it names.
- **Python.** With `VIRTUAL_ENV` active it blocks explicit global `pip` paths, `python3 -m pip`,
  and explicit global tool paths. A `uv.lock` blocks bare `pip` and `pip3`.

### git-permission

Warns on force pushes, `reset --hard`, `clean -f`, `checkout -- .`, `restore .`, `branch -D` and
`rebase`. It never blocks. These are all legitimate operations that just deserve a second look at
which branch you're on.

## Tests

```bash
bash tests/run-all.sh          # every suite; exits non-zero on any failure
bash tests/test-bash-guard.sh  # or one at a time
```

266 tests: 67 for bash-guard, 124 for toolchain-guard, 55 for rm-guard, 20 for write-guard. Each
suite finds its guard relative to its own location, so they run from any checkout.

## Limitations

- **Pattern matching is not a sandbox.** These guards catch the common shapes of a dangerous command
  and raise the cost of a mistake. A determined bypass through an encoding nobody anticipated is
  still possible, and defending against that is a sandbox's job, not a regex's.
- **`rm-guard` returns `allow`,** which Claude Code treats as more permissive than `ask`. The
  static-decidability rules above are the only thing keeping that narrow, so loosening them widens
  real permissions.
- **Secret detection is a list of known shapes.** A credential format that isn't on the list passes.
  No denial is not evidence that a file is clean.
- **Category 6 of `bash-guard` will produce false positives** in work that legitimately posts file
  contents to an API.
