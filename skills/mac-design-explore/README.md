# mac-design-explore

mac-design-explore compares native macOS interfaces by building them and looking at them. It builds several SwiftUI or AppKit versions of the same screen, runs each one, captures real screenshots, walks the same task through each, and reports what it actually observed. It also refines a single view against a stated visual defect, and it answers whether the machine is set up for any of that before work starts.

Instructions only. No scripts, no hooks, no runtime, no required companion skills.

## Install

```bash
npx skills add serenecotech/agent-skills --skill mac-design-explore
```

That is the [skills CLI](https://github.com/vercel-labs/skills). It asks which agents to install to and whether to symlink or copy. Add `-g` for `~/.claude/skills/` instead of this project, and `-a claude-code -y` to skip the prompts.

It installs `SKILL.md` and `references/peek.md` together. The reference file is not optional, because `SKILL.md` reads it when capture comes up.

To install without the CLI, copy the folder:

```bash
cp -R skills/mac-design-explore "$HOME/.claude/skills/mac-design-explore"
```

Both locations and the `/mac-design-explore` invocation follow the [Claude Code skill documentation](https://code.claude.com/docs/en/skills).

If a `mac-design-explore` folder is already there, back it up outside the skills directory first. Two copies of one skill name under different discovery paths confuse selection.

Then confirm `metadata.version: "0.3.1"` in the installed `SKILL.md` and start a fresh session.

Update later with `npx skills update mac-design-explore`, and remove it with `npx skills remove mac-design-explore`.

## Three entry points

The skill picks one from the request. It does not ask which mode to use.

| Entry point | What it does                                                                                                     |
| ----------- | ---------------------------------------------------------------------------------------------------------------- |
| Explore     | Builds alternative interfaces for one task, compares them under matched conditions, then waits for your choice   |
| Refine      | Captures a baseline of a named view, states the acceptance condition, and makes a scoped correction              |
| Check setup | Inspects the project and the available tools read-only, then stops without building, launching, or writing files |

Implementing an agreed feature or fixing an unrelated functional bug is ordinary development. The skill stays out of that work.

## Example requests

```text
/mac-design-explore Explore alternatives for this document library.
Preserve search and collections. Compare finding a document, inspecting
its details, and returning without losing the selection. Use synthetic data.

/mac-design-explore Refine and apply a fix for clipped sidebar labels at
the supported minimum window width. Preserve the navigation structure.

/mac-design-explore Check setup for native macOS exploration.
```

Follow up with a choice or a remix, such as "Use B's navigation and A's inspector".

A request to fix the actual app authorizes that scoped edit. No magic word is needed, and the authorization persists. Choosing a favourite direction authorizes neither production integration nor deletion.

## What it needs

| Capability | Needed for | Without it |
| --- | --- | --- |
| Swift toolchain, `swift` or `xcodebuild` | Compiling any direction | The skill reports the missing prerequisite and stops |
| A running graphical session | Launching a native host | Directions compile, and render and interaction states stay blocked |
| A window capture tool, such as [Peek](https://github.com/frr149/peek) | Native screenshots | Visual inspection is reported as blocked, not as passed |
| An image-reading tool | Opening the captured PNG | A capture exists but is not inspected, and the skill says so |
| An interaction or automation tool | Walking the task | The task is marked untested, with reproducible user-side steps |

The skill does not install anything, change dependency versions, or alter global settings to make itself run. It reports the gap instead.

Optional companions supply narrow expertise when they are present: macOS platform guidance, SwiftUI checks, native capture, design critique. The skill discovers them from the session rather than requiring them.

### Peek

[references/peek.md](references/peek.md) holds the Peek-specific procedure: command discovery, capture, window-selection limits, permissions, and the optional panel features. Read it when checking Peek readiness or using Peek to capture.

Three constraints from that reference matter most. Basic capture selects the largest normal window of a matched app, and 0.1.1 exposes no window-title, window-ID, or PID selector, so target a single-window harness with a unique name. Pixel capture needs Screen Recording authorization for whichever application hosts the command, not for Terminal by assumption. `--all` writes fixed paths under `/tmp/peek/` and ignores `--output`, so the skill uses it only on an explicit request.

The upstream Peek README points at a `skills/design-review/SKILL.md` that was absent at the revision checked. That separate workflow is not a dependency here.

## Evidence states

Each direction or revision carries four separate states, each recorded as passed, failed, blocked, or not checked.

| State               | What it requires                                                                                                             |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Built               | The command, its exit status, the log, and a digest or snapshot of the sources, fixtures, and configuration that produced it |
| Rendered            | The launch route and the matching native image path                                                                          |
| Visually inspected  | The image actually opened, with dimensions, appearance, and findings                                                         |
| Interaction checked | Actions actually performed, and the outcomes observed                                                                        |

A successful build does not imply a render. A capture does not imply inspection. Source-only work is never reported as verified. After any source change, affected evidence is marked stale until rebuilt and rechecked.

Resizable views with both appearances are sampled at small/light, wide/light, and small/dark, changing one factor at a time. That is a bounded sample, not a full matrix and not accessibility testing. Agent walkthroughs are proxy evidence. The skill does not invent user timings, preference scores, or research findings.

## Effort bounds

Without a time limit from you, the skill starts on a provisional 30-minute exploration checkpoint or a 15-minute refinement checkpoint. It can recalibrate once, from the first fully inspected direction or the refinement baseline, and it announces the new total before continuing. An explicit limit from you takes precedence and is never extended.

Each refinement request allows at most three patch-build-inspect passes in total, with the baseline outside that count. Each direction allows at most two focused repair attempts. Shared setup recovery allows two. At a checkpoint the skill stops, preserves the work, and reports what remains, rather than starting another build cycle.

Five requested directions that do not fit an explicit budget produce a reported shortfall. They do not produce an overrun or a false completion.

## Isolation and retention

Prototypes, fixtures, build output, logs, images, and a compact `run-notes.md` live in a unique OS temporary workspace whose absolute path the skill announces at the start.

Exploratory source edits stay in a disposable copy or harness. The original project is not patched to host a prototype. A copied directory or a different bundle identifier is not treated as runtime isolation on its own, because shared containers, keychain groups, and live services survive both. If an isolated runtime cannot be established, the run compiles or hands over source and reports launch and interaction as blocked.

Artifacts are retained by default, including after cancellation. OS temporary storage can disappear, so ask for a copy to a named destination when you want it to last. Owned artifacts are deleted only on request. Shared caches and the working tree are never reset.

For an authorized product fix, the skill records the starting diff and preserves concurrent edits. A change that lacks visual verification is kept and labelled. A change that causes a known regression is removed only when it separates cleanly. When it does not, the current file is preserved and the conflict is reported, and no whole-file snapshot is restored over newer work.

## Validation status

Version 0.3.1 passed structural validation and two document reviews. Peek command help was read against the locally installed 0.1.1 binary on 19 September 2026, and the behavioural constraints were read from upstream source at a pinned revision. Those reviews were read-only. Neither one executed the skill.

No native build, screenshot capture, interactive walkthrough, or comparative benchmark has been run against a real app. The checkpoints, instruction adherence, and practical overhead are still open questions. The first real run is the first test.

## Layout

```text
SKILL.md              the workflow, its entry points, budgets, isolation and evidence rules
README.md             this file
references/peek.md    Peek command procedure, read on demand
```

Those three files are the whole skill, and `npx skills add` installs exactly them. Anything else added here gets copied into every install, so keep maintainer notes out of this directory.

## Portability

Plain Markdown with YAML frontmatter and one relative reference link. Nothing reads `${CLAUDE_PLUGIN_ROOT}`, and there is no hook, so the skill ports to any agent that reads skills from a directory. The macOS toolchain is the only hard dependency.
