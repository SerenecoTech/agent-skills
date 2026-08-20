# guard-hooks

Eight hooks that block dangerous agent actions before they run: privilege escalation, obfuscated
command execution, writes to credential files, reads of credential files, secrets committed into
source, printing a credential to the transcript, and the wrong package manager. 468 tests.

Nothing here depends on the agent choosing to cooperate. A hook runs outside the conversation, so it
applies equally to an agent mid-task, a subagent you never see the transcript of, and an agent
acting on instructions it picked up from a file it read.

Credentials get three layers, because no single one covers the ground:

- **the command**, for tools that exist to print a secret (`gh auth token`, `git credential fill`);
- **the data at rest**, for files that already hold one — the file is on disk before the read, so
  the content decides and no command has to be recognised;
- **the variable**, for `echo "${GH_TOKEN:-no}"` and its relatives, which print a credential without
  involving any credential-related command at all.

Anything that slips all three is caught on the way out by `output-alarm`, which cannot prevent the
leak — nothing at PostToolUse can — but turns a silent one into a known one that gets rotated.

## What it looks like

Real output from the guards, not paraphrased:

| You (or your agent) attempt                    | Result                                                     |
| ---------------------------------------------- | ---------------------------------------------------------- |
| write `/proj/.env`                             | denied: `Cannot write to protected file: /proj/.env`       |
| write an AWS key into `config.js`              | denied: `Potential secret detected in content: AKIA…`      |
| `sudo apt install nginx`                       | denied: `Privilege escalation blocked`                     |
| `curl -s http://…/install.sh \| sh`            | denied: `Obfuscated execution pattern blocked`             |
| `npm install lodash` beside a `pnpm-lock.yaml` | denied: `pnpm-lock.yaml present — use pnpm instead of npm` |
| read `~/.config/gh/hosts.yml`                  | denied: `Not reading …: it holds what looks like a live credential` |
| `echo "set: ${GH_TOKEN:+yes}${GH_TOKEN:-no}"`  | denied: `':-' prints the VALUE when the variable is set`   |
| `git push --force origin main`                 | allowed, with a warning to check the branch                |
| write `/proj/.env.example`                     | allowed; the guard distinguishes it from `.env`            |
| `echo "set: ${GH_TOKEN:+yes}"`                 | allowed; that form prints `yes` and nothing else           |

The secret-detection message echoes the credential it matched, shortened here. Writing this README
tripped that guard on the first attempt, which is roughly the intended experience.

## The eight hooks

| Hook                      | Event                                             | Can decide               | If the hook itself errors |
| ------------------------- | ------------------------------------------------- | ------------------------ | ------------------------- |
| `bash-guard.sh`           | PreToolUse `Bash`                                 | deny only                | **fails closed** (denies) |
| `write-guard.sh`          | PreToolUse `Write\|Edit\|MultiEdit\|NotebookEdit` | deny only                | **fails closed** (denies) |
| `read-guard.sh`           | PreToolUse `Read\|NotebookRead`                   | deny only                | **fails closed** (denies) |
| `env-expansion-guard.sh`  | PreToolUse `Bash`                                 | deny only                | **fails closed** (denies) |
| `rm-guard.sh`             | PreToolUse `Bash`                                 | allow only, never denies | falls through             |
| `toolchain-guard.sh`      | PreToolUse `Bash`                                 | deny only                | **fails open** (allows)   |
| `output-alarm.sh`         | PostToolUse (most tools)                          | **nothing** — see below  | **fails open** (silent)   |
| `git-permission.sh`       | PermissionRequest `Bash`                          | nothing; warns only      | silent                    |

The fail-closed guards are the security boundary, so a broken one denies instead of waving work
through. That cuts both ways for `read-guard`: if it breaks, nothing can be read and work stops
immediately, which is loud and gets fixed. The alternative failure — reading every credential file
silently — is not.

`toolchain-guard` fails open deliberately: it enforces a project convention rather than a security
property, and a convention check that blocks legitimate commands when it breaks is a check you will
switch off. `env-expansion-guard` fails closed despite also running on every Bash call, because its
prototype shipped a `pipefail` bug that made it fail open and allow everything silently — exactly
the failure a security control must not have.

**`output-alarm` cannot prevent anything.** PostToolUse runs after the tool; the event accepts no
permission decision, and there is no redaction or suppression mechanism in the harness. By the time
it runs, the credential is in the transcript. It exists because it is the only layer that covers
printers nobody enumerated, and because knowing a credential leaked is the difference between
rotating it and not. It sets `continue: false` so the session stops rather than building more work
on top of a credential that now needs rotating.

Patterns live once, in `hooks/lib/secret-patterns.sh`, shared by `write-guard`, `read-guard` and
`output-alarm`. They were three copies until one of them was fixed and the others were not: the
`gh[ps]_` pattern matched personal and server tokens but missed `gho_`, which is the OAuth prefix
and the exact token type the August 2026 incident leaked.

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

It also blocks two shapes that have nothing to do with toolchains but live here because they are
the same kind of check:

- **Interpreter heredocs and deleting one-liners.** `python3 << EOF`, and
  `node -e "require('fs').unlinkSync(...)"` and equivalents. Neither can be meaningfully
  permission-scoped, because the interpreter can do anything an allow rule would have to cover.
- **Commands whose stdout is a credential.** `git credential fill`, a credential helper's own
  `get`, `gh auth token`, and `gh auth status --show-token` (or `-t`, the same flag). These break
  nothing and print a live secret, and an agent's stdout becomes conversation transcript, which is
  summarised into session memory. A token printed there has to be rotated, not deleted.

  `git credential fill` is allowed only when **that command** resets the helper list
  (`-c credential.helper=` with an empty value) and nothing on it puts a helper back. The reset
  protects the command it is written on, not its neighbours, so
  `git -c credential.helper= credential fill; git credential fill` is denied for the second one.
  Things
  that put one back, all verified against git 2.55 with a stub helper: a bare name
  (`-c credential.helper=osxkeychain`); a `!…` value, which is a shell snippet that can call the
  store itself; **a path ending in `git-credential-osxkeychain`, `-store`, `-cache`, `-manager` and
  friends**, because the stores ship as executables under git's exec-path and naming one by path is
  the same store spelled longer; and three routes that are not the `credential.helper=` spelling at
  all — a URL-scoped `credential.https://host.helper=`, `--config-env`, and `-c include.path=` to a
  config that already configures one.

  `gh auth token` is allowed when **its own stdout** goes to a file. Things that look like that and
  are not: `2>/dev/null` (stderr, while stdout still prints); a redirect on another command in the
  line, on a backgrounded neighbour (`gh auth token & echo x > f`), or inside a command
  substitution; a redirect of any descriptor other than 1, including `0>` and `12>`; a second
  unredirected occurrence later on the same line; and `/dev/stdout`, `/dev/stderr`, `/dev/tty`,
  `/dev/fd/N` as targets. `>|`, `{ … ; } > f` and `( … ) > f` do count. `git credential approve` and
  `reject` are allowed — they read stdin and print nothing.

  Matching follows what the shell does, within reach of a regex. `\gh` is `gh` (a backslash only
  suppresses an alias); `/opt/homebrew/bin/gh` is `gh`; quotes around a single word are transparent,
  so `gh auth "token"` is caught; a quoted redirect target is the same target, so
  `> "/dev/stdout"` does not count as safe. A quoted run containing whitespace is prose belonging to
  whatever command owns the quotes, so `git commit -m "block git credential fill"` and
  `grep -rn "git credential fill" docs/` run — including multi-line commit bodies. A `$(…)` or
  backtick inside those quotes is **not** prose: the shell runs it, so its body is matched on its
  own and `echo "$(gh auth token)"` is denied. A separator inside quotes is data, not a separator.

  Quoting the binary's own name (`"gh" auth token`) does not help, a separator inside quotes is
  data rather than a separator, and a backslash-escaped quote is a literal — the quote scan honours
  escapes, so `sed -i "s/\"/x/g" f > /tmp/o; gh auth token` still denies the second command.

  Three things this deliberately does not reach. `bash -c "gh auth token"` is allowed: nothing a
  regex does can read inside quotes and not read inside prose, and prose is the commoner case. A
  redirect established earlier by `exec > f` is not tracked, so `exec > f; gh auth token` is denied
  although it is safe. And a group holding more than one command keeps only its last command's
  view of the redirect, so `{ gh auth token; echo done; } > f` is denied although it is safe;
  `{ echo start; gh auth token; } > f` is allowed. Both over-blocks err toward denying a print.

  This section exists because of a real incident, not a hypothetical: `git credential fill` was
  used to check which fields a helper receives, the stub helper returned nothing, git fell through
  to the machine's osxkeychain helper, and an OAuth token carrying `admin:org` and
  `admin:public_key` was printed into a transcript. Four adversarial review rounds against the
  first implementation found twenty-four ways past it or around it; the tests in `Section 6b` to
  `6e` are those cases, one test per defect. Eight of the twenty-four were introduced by the fix to
  an earlier one, which is the honest measure of how well regexes model a shell: this section
  denies more than it did and is still a heuristic, not a parser.

### read-guard

Opens the file the `Read` tool is about to open, scans it, and denies if it holds a credential. No
command to recognise and no shell to parse — the file exists before the tool runs, so the content
answers the question directly. Catches `.env` files, `~/.config/gh/hosts.yml`, private keys, saved
`credential fill` output and connection strings with passwords in them.

Two limits worth knowing. It reads the first 256KB, so a secret past that offset is missed. And a
path naming itself `test`, `fixture`, `example`, `sample`, `mock` or `dummy` is exempt, because the
repo is full of deliberately fake secrets — which means a genuine key in `config.example.env` is
invisible. That is the same trade `write-guard` has always made.

The deny message suggests ways to work with the file without reading the value: `grep -c` to confirm
a key exists, `grep -oE '^[A-Za-z_]+='` to list key names, or a redacted copy.

### env-expansion-guard

Denies a command that would print the value of a credential-bearing environment variable.

Written after a second real incident. An agent probing a container ran, three layers deep inside
`docker exec … zsh -lc '…'`:

```bash
echo "GH_TOKEN set: ${GH_TOKEN:+yes}${GH_TOKEN:-no}"
```

That reads as a set/unset probe and is not one. `:-` substitutes the default only when the variable
is **empty**, so with a token present it prints `yes` followed by the token. The output was
`GH_TOKEN set: yesgho_…`. No credential command appears anywhere in that line — the printer is
`echo` — so nothing in `toolchain-guard`'s model can see it, and no amount of better shell parsing
would change that.

What makes this checkable is that parameter expansion is a small fixed grammar, and the dangerous
forms are literal substrings that survive any amount of nesting and quoting. Measured with a token
in the variable:

| Form | Prints | |
|---|---|---|
| `${V:+word}` | `word` | safe |
| `${#V}` | the length | safe |
| `${V:0:4}` | a 4-character prefix | safe |
| `[ -n "$V" ]` | nothing | safe |
| `${V:-word}` | **the value** | denied |
| `$V`, `${V}` | **the value** | denied |

It only fires when something in the command can print, so using a credential is untouched:
`curl -H "Authorization: Bearer $GH_TOKEN"` and `git push` both run. Variables are matched by
suffix — `*_TOKEN`, `*_SECRET`, `*_PASSWORD`, `*_API_KEY`, `*_ACCESS_KEY`, `*_CREDENTIALS` and
friends — so a new `SOMETHING_TOKEN` is covered without an edit. Bare `KEY` is deliberately absent:
`PUBLIC_KEY`, `LICENSE_KEY` and `AWS_ACCESS_KEY_ID` are not secrets.

### output-alarm

Scans what came back. Raises an alarm and stops the session if a credential is in it.

It prevents nothing, and the README says so twice on purpose. What it covers is the class no
PreToolUse hook can: a printer nobody enumerated. `security find-generic-password -w`,
`aws configure get`, `op read`, a token echoed out of a shell variable, a push error containing
`https://x-access-token:ghs_…@github.com` — none of these are recognisable in advance, all of them
are obvious in the output.

Strict patterns only. The contextual tier matches a stub helper printing `password=STUB`, and
halting a session on a heuristic is not a trade worth making. The consequence is that it also misses
unstructured secrets: a bare passphrase from `op read` has no shape to match, and the generic
high-entropy rule that would catch it fires five times on `git log --format=%H`.

### git-permission

Warns on force pushes, `reset --hard`, `clean -f`, `checkout -- .`, `restore .`, `branch -D` and
`rebase`. It never blocks. These are all legitimate operations that just deserve a second look at
which branch you're on.

## Tests

```bash
bash tests/run-all.sh          # every suite; exits non-zero on any failure
bash tests/test-bash-guard.sh  # or one at a time
```

468 tests: 253 for toolchain-guard, 67 for bash-guard, 55 for rm-guard, 29 for
env-expansion-guard, 23 for read-guard, 21 for output-alarm, 20 for write-guard. Each suite finds
its guard relative to its own location, so they run from any checkout.

`test-read-guard.sh` asserts that every hook in this plugin can still be read, including
`lib/secret-patterns.sh`. A secret detector's own source is full of secret-shaped text, and an
earlier draft of the pattern file could not be written to disk at all because `write-guard` matched
a PEM banner spelled out inside one of its patterns.

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
