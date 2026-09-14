# guard-hooks

Nine hooks that block dangerous agent actions before they run.

Nothing here depends on the agent choosing to cooperate. A hook runs outside the conversation, so it
applies equally to an agent mid-task, a subagent whose transcript you never see, and an agent acting
on instructions it picked up from a file it read.

## What it blocks

| Attempt                                        | Result                                                     |
| ---------------------------------------------- | ---------------------------------------------------------- |
| `sudo apt install nginx`                       | denied: `Privilege escalation blocked: 'sudo' is the …`    |
| `echo "the sudo rule is unanchored"`           | allowed; the word is data, not the command                 |
| `cat .env.default`                             | allowed; `cat .env.local` is still denied                  |
| `curl -s http://…/install.sh \| sh`            | denied: `Obfuscated execution pattern blocked`             |
| write `/proj/.env`                             | denied: `Cannot write to protected file`                   |
| write an AWS key into `config.js`              | denied: `Potential secret detected in content`             |
| read `~/.config/gh/hosts.yml`                  | denied: the file holds a live credential                   |
| `echo "set: ${GH_TOKEN:+yes}${GH_TOKEN:-no}"`  | denied: `':-' prints the VALUE when the variable is set`   |
| `npm install lodash` beside a `pnpm-lock.yaml` | denied: `pnpm-lock.yaml present — use pnpm instead of npm` |
| `gh pr merge 42` with a red check              | denied: `PR #42 is not clear to merge — e2e (failure)`     |
| `gh pr merge 42` when no workflow ran          | denied: `PR #42 has no check runs at all`                  |
| `git branch -D main`                           | denied: `'main' is a protected branch`                     |
| `git branch -D spike-thing`                    | prompts: no `feature/` or `hotfix/` prefix                 |
| `gh pr merge 42` with checks green             | allowed; the guard blocks bypasses, not merges             |
| write `/proj/.env.example`                     | allowed; distinguished from `.env`                         |
| `echo "set: ${GH_TOKEN:+yes}"`                 | allowed; that form prints `yes` and nothing else           |

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install guard-hooks@sereneco
```

**Restart Claude Code.** Hooks load at session start, so nothing is enforced until you do. Then
check `claude plugin list` shows `Status: ✔ enabled`; a hook that failed to load is reported there
and not by `claude plugin validate`.

Needs `jq` ≥ 1.6, `bash` ≥ 4, `git` and coreutils. `gh` is needed only for the GitHub merge rules.

### If you already wire these up by hand

Installing the plugin while the same scripts are still referenced from `settings.json` runs every
guard twice. Harmless for deny-only guards, but remove the duplicate `PreToolUse` entries so there
is one place to reason about.

## Configuration

Everything works unconfigured. Three optional variables adjust the GitHub rules:

| Variable                   | Default                          | Effect                                            |
| -------------------------- | -------------------------------- | ------------------------------------------------- |
| `GUARD_BRANCH_PREFIXES`    | `feature/ hotfix/`               | Branch prefixes exempt from the prefix prompt     |
| `GUARD_PROTECTED_BRANCHES` | `main master develop production` | Branch names that cannot be deleted               |
| `GUARD_GITHUB_DISABLE`     | unset                            | Any non-empty value disables `github-guard`       |

Both lists replace their defaults rather than adding to them:

```bash
export GUARD_BRANCH_PREFIXES="feature/ hotfix/ spike/ chore/"
```

The repository's own default branch stays protected whatever `GUARD_PROTECTED_BRANCHES` says, so a
repo whose trunk is called `trunk` gets it for free.

## The nine hooks

| Hook                      | Event                                             | Can decide               | If the hook itself errors |
| ------------------------- | ------------------------------------------------- | ------------------------ | ------------------------- |
| `bash-guard.sh`           | PreToolUse `Bash`                                 | deny only                | **fails closed** (denies) |
| `write-guard.sh`          | PreToolUse `Write\|Edit\|MultiEdit\|NotebookEdit` | deny only                | **fails closed** (denies) |
| `read-guard.sh`           | PreToolUse `Read\|NotebookRead`                   | deny only                | **fails closed** (denies) |
| `env-expansion-guard.sh`  | PreToolUse `Bash`                                 | deny only                | **fails closed** (denies) |
| `github-guard.sh`         | PreToolUse + PermissionRequest `Bash`             | deny and ask             | **fails closed** (denies) |
| `rm-guard.sh`             | PreToolUse `Bash`                                 | allow only, never denies | falls through             |
| `toolchain-guard.sh`      | PreToolUse `Bash`                                 | deny only                | **fails open** (allows)   |
| `output-alarm.sh`         | PostToolUse (most tools)                          | **nothing** — see below  | **fails open** (silent)   |
| `git-permission.sh`       | PermissionRequest `Bash`                          | nothing; warns only      | silent                    |

The fail-closed guards are the security boundary, so a broken one denies instead of waving work
through. `toolchain-guard` fails open deliberately: it enforces a project convention rather than a
security property, and a convention check that blocks legitimate commands when it breaks is a check
you will switch off.

**`output-alarm` cannot prevent anything.** PostToolUse runs after the tool, the event accepts no
permission decision, and there is no redaction mechanism in the harness. By the time it runs, the
credential is in the transcript. It exists because knowing a credential leaked is the difference
between rotating it and not. It sets `continue: false` so the session stops rather than building
more work on a credential that now needs rotating.

## Credentials get three layers

No single layer covers the ground:

- **the command**, for tools that exist to print a secret (`gh auth token`, `git credential fill`);
- **the data at rest**, for files that already hold one — the file is on disk before the read, so
  the content decides and no command has to be recognised;
- **the variable**, for `echo "${GH_TOKEN:-no}"` and its relatives, which print a credential without
  involving any credential-related command at all.

Anything that slips all three is caught on the way out by `output-alarm`.

Patterns live once, in `hooks/lib/secret-patterns.sh`, shared by `write-guard`, `read-guard` and
`output-alarm`.

## What each hook does

### bash-guard

Splits the command the way a shell would, using `hooks/lib/shell-segments.awk`, then asks of each
piece whether it is a command or data. A heredoc body, a quoted string and the search pattern of a
`grep` are data, so naming `sudo` in a commit message or reading `.env.example` is allowed, while
`"sudo" rm`, `s\udo rm`, `$(sudo id)` and `bash -c "sudo id"` are all still the command `sudo`.

Six categories:

| #   | Category                    | Caught, for example                                                          |
| --- | --------------------------- | ---------------------------------------------------------------------------- |
| 1   | Privilege escalation        | `sudo`, `su`, `doas`, `pkexec`                                               |
| 2   | Destructive file operations | recursive and forced deletes, wildcard deletes, writes to raw devices        |
| 3   | Dangerous git operations    | history-destroying and force operations                                      |
| 4   | Indirect execution          | piping a download into a shell, `base64 -d \| sh`, `eval` of fetched content |
| 5   | Credential access           | reading private keys, cloud credential files, keychains                      |
| 6   | Network exfiltration        | posting local file contents to a remote host                                 |

Category 6 is the most opinionated and the one most likely to need loosening for your work. The
script says so at that line.

A denial names the rule, the token that matched and the segment it matched in, so you can tell a
real block from a bad rule without reading the hook. A single read-only command whose target is a
guard file is allowed, because auditing what the guard blocks means naming the words it blocks.

Categories 2, 3, 4 and the history rules still match against the whole command rather than command
position, so a destructive shape quoted inside an `echo` is denied. Only categories 1 and 5 are
segment-aware.

### write-guard

Resolves symlinks and relative paths before matching. For a file that does not exist yet it resolves
the parent directory, so a symlink cannot be used to reach a protected target.

- **Protected paths** — `.env` and its environment variants but not `.env.example`; SSH keys; TLS
  keys and certificates; AWS, Azure and GCP credentials; kubeconfig; Docker config; npm, pypi and
  netrc registry auth; `.pgpass`; `.my.cnf`; git credentials and `.gitconfig`; `.htpasswd`;
  `secrets.*`; service-account JSON; `.gnupg/`; password stores.
- **Secrets in content** — AWS access keys, Anthropic and OpenAI keys, GitHub PATs, PEM private key
  blocks, database URIs with inline passwords, and a high-entropy heuristic tuned to leave ordinary
  base64 alone.
- **System directories** — `/etc`, `/boot`, `/sys`, `/proc`, `/dev`, `/root`, plus the macOS
  `/private/...` equivalents.
- **Git internals** — `.git/hooks/` and `.git/config`, a code-execution vector and a
  credential-helper vector respectively.

### read-guard

Opens the file the `Read` tool is about to open, scans it, and denies if it holds a credential.
Catches `.env` files, `~/.config/gh/hosts.yml`, private keys, saved `credential fill` output and
connection strings with passwords in them.

The deny message suggests ways to work with the file without reading the value: `grep -c` to confirm
a key exists, `grep -oE '^[A-Za-z_]+='` to list key names, or a redacted copy.

Two limits. It reads the first 256KB, so a secret past that offset is missed. And a path naming
itself `test`, `fixture`, `example`, `sample`, `mock` or `dummy` is exempt, because repos are full
of deliberately fake secrets — which means a genuine key in `config.example.env` is invisible.

### env-expansion-guard

Denies a command that would print the value of a credential-bearing environment variable. Parameter
expansion is a small fixed grammar, and the dangerous forms are literal substrings that survive any
amount of nesting and quoting. Measured with a token in the variable:

| Form | Prints | |
|---|---|---|
| `${V:+word}` | `word` | safe |
| `${#V}` | the length | safe |
| `${V:0:4}` | a 4-character prefix | safe |
| `[ -n "$V" ]` | nothing | safe |
| `${V:-word}` | **the value** | denied |
| `$V`, `${V}` | **the value** | denied |

It fires only when something in the command can print, so *using* a credential is untouched:
`curl -H "Authorization: Bearer $GH_TOKEN"` and `git push` both run.

Variables match by suffix — `*_TOKEN`, `*_SECRET`, `*_PASSWORD`, `*_API_KEY`, `*_ACCESS_KEY`,
`*_CREDENTIALS` and friends — so a new `SOMETHING_TOKEN` is covered without an edit. Bare `KEY` is
deliberately absent: `PUBLIC_KEY`, `LICENSE_KEY` and `AWS_ACCESS_KEY_ID` are not secrets.

### github-guard

Blocks GitHub operations that step around a safety check, rather than blocking the operations
themselves. A merge whose checks are green goes through untouched.

| Trips on                                                       | Decision |
| -------------------------------------------------------------- | -------- |
| Merging while a check is failing, cancelled, or still running   | deny     |
| Merging when no check ran at all                                | deny     |
| Deleting a protected branch                                     | deny     |
| Deleting a branch carrying unmerged commits you did not author  | deny     |
| Deleting a branch with no `feature/` or `hotfix/` prefix        | ask      |

**The empty-rollup rule is the one worth understanding.** No check runs at all is what a GitHub
Actions outage looks like from the client side: the merge button is green because nothing reported,
not because anything passed. That is when a merge is least safe and least likely to be questioned.

It watches `gh pr merge`, `gh api …/pulls/N/merge`, `git branch -d/-D/--delete`, `git push <remote>
--delete <branch>`, the colon refspec `git push <remote> :<branch>`, and `gh api -X DELETE
…/git/refs/heads/…`. Merge state comes from one GraphQL call reading `statusCheckRollup` on the PR
head, around half a second. The branch rules are local git only.

A branch already merged into the base is exempt from the branch rules, so post-merge cleanup does
not prompt. Squash merges leave the branch tip un-ancestored, so a squash-merged `chore-foo` still
prompts.

**Unverifiable state is treated as unsafe.** If `gh` is missing, logged out, rate-limited, erroring,
or the PR number is computed at run time (`gh pr merge $PR`), the merge is denied rather than waved
through, because otherwise a flaky network is a bypass. An unreadable *branch* name degrades to
`ask` instead.

The guard stays silent outside a git repository, and in any repository whose origin is not GitHub.

### rm-guard

Cuts down permission prompts without widening what is permitted. It returns `allow` only when every
segment of the command is statically decidable:

- each `rm` segment is non-recursive, glob-free and quote-free, resolves through symlinks to
  somewhere strictly inside the project root, and is not a directory;
- each non-`rm` segment is either a known-inert builtin or already matches a `permissions.allow`
  pattern in your settings.

Anything containing `$`, backticks, `$(`, process substitution or redirection falls through to the
normal permission flow, since you cannot then assert what value `rm` will receive.

This hook never denies. `bash-guard` is the deny layer, and keeping them separate is what stops an
`allow` here from over-permitting a compound command with a dangerous sibling.

### toolchain-guard

Reads what the project declares about itself:

- **JS/TS**, lock file priority `bun` > `pnpm` > `yarn`. A `bun.lock` or `bun.lockb` blocks npm,
  npx, yarn and pnpm; `pnpm-lock.yaml` blocks npm, npx and yarn; `yarn.lock` blocks npm for
  install, add, remove and ci. `package.json#packageManager` enforces whatever it names.
- **Python.** With `VIRTUAL_ENV` active it blocks explicit global `pip` paths, `python3 -m pip`, and
  explicit global tool paths. A `uv.lock` blocks bare `pip` and `pip3`.

It also blocks two shapes unrelated to toolchains, which live here because they are the same kind of
check.

**Interpreter heredocs and deleting one-liners.** `python3 << EOF`, and
`node -e "require('fs').unlinkSync(...)"` and equivalents. Neither can be meaningfully
permission-scoped, because the interpreter can do anything an allow rule would have to cover.

**Commands whose stdout is a credential.** `git credential fill`, a credential helper's own `get`,
`gh auth token`, and `gh auth status --show-token`. These break nothing and print a live secret, and
an agent's stdout becomes conversation transcript. A token printed there has to be rotated, not
deleted.

Two narrow exemptions:

- `git credential fill` runs when **that command** resets the helper list (`-c credential.helper=`
  with an empty value) and nothing on it puts a helper back. The reset protects the command it is
  written on, not its neighbours. `git credential approve` and `reject` always run — they read stdin
  and print nothing.
- `gh auth token` runs when **its own stdout** goes to a file. `2>/dev/null` does not count, nor a
  redirect belonging to another command on the line, nor `/dev/stdout`, `/dev/stderr`, `/dev/tty` or
  `/dev/fd/N` as targets.

Matching follows what the shell does, within reach of a regex. `\gh` and `/opt/homebrew/bin/gh` are
both `gh`, and quotes around a single word are transparent, so `gh auth "token"` is caught. A quoted
run containing whitespace is prose belonging to whatever command owns the quotes, so
`git commit -m "block git credential fill"` runs. A `$(…)` inside those quotes is not prose: the
shell runs it, so `echo "$(gh auth token)"` is denied.

### output-alarm

Scans what came back. Raises an alarm and stops the session if a credential is in it.

It covers the class no PreToolUse hook can: a printer nobody enumerated.
`security find-generic-password -w`, `aws configure get`, `op read`, a token echoed out of a shell
variable, a push error containing `https://x-access-token:ghs_…@github.com`. None are recognisable
in advance; all are obvious in the output.

Strict patterns only. A contextual tier matches a stub helper printing `password=STUB`, and halting
a session on a heuristic is not a trade worth making. The consequence is that it misses unstructured
secrets: a bare passphrase from `op read` has no shape to match.

### git-permission

Warns on force pushes, `reset --hard`, `clean -f`, `checkout -- .`, `restore .`, `branch -D` and
`rebase`. It never blocks. These are legitimate operations that deserve a second look at which
branch you are on.

## Limitations

- **Pattern matching is not a sandbox.** These guards catch the common shapes of a dangerous command
  and raise the cost of a mistake. A determined bypass through an encoding nobody anticipated is
  still possible, and defending against that is a sandbox's job.
- **`rm-guard` returns `allow`,** which Claude Code treats as more permissive than `ask`. The
  static-decidability rules above are the only thing keeping that narrow.
- **Secret detection is a list of known shapes.** A credential format that is not on the list
  passes. No denial is not evidence that a file is clean.
- **Category 6 of `bash-guard` produces false positives** in work that legitimately posts file
  contents to an API.
- **`github-guard` reads the command word, not the shell's intent.** It recognises `gh` and `git`
  through an absolute path, a leading `VAR=value`, and an `env` wrapper, but a merge reached through
  an interpreter — `bash -c "gh pr merge 42"` — presents `bash` as its command word and is not
  checked.
- **`github-guard`'s prefix prompt can be escaped by an allow-list.** `ask` exists only on
  `PermissionRequest`, which fires only when a call would otherwise prompt, so a
  `Bash(git branch -D *)` entry in `permissions.allow` skips it. The deny rules run on `PreToolUse`
  and have no such hole.
