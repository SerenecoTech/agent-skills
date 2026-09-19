---
name: mac-design-explore
description: Explore and remix runnable native macOS interface alternatives, visually refine a specified SwiftUI or AppKit view, or check readiness for that workflow. Use for interface design decisions and evidence-led visual corrections, not general feature implementation or code review.
metadata:
  version: "0.3.1"
---

# Native macOS design exploration

Help the user choose an interface by comparing real native implementations against the same task. Build, inspect, choose, and remix. Treat tool results and captured output as evidence; treat design judgments as hypotheses until tested.

## Entry point

Select from the request without a mode-selection question:

- **Explore:** compare different approaches to the same task, then await the user's choice unless autonomous selection was authorized.
- **Refine:** capture a baseline of a specified view or chosen direction, define the visible outcome, and make a scoped correction. Work in a temporary copy unless the user authorized a product fix. Preserve its structure except for changes explicitly requested in a remix or redesign.
- **Check setup:** inspect the project and available capabilities read-only. Use section 2's discovery guidance and relevant tool references, but skip its build/launch/capture proof and all other execution steps. Report available, unavailable, and unverified capabilities, what each limitation prevents, and the next useful step. Stop without creating files, building, launching, installing, or changing configuration.

Implementing an already agreed feature or fixing an unrelated functional bug belongs to ordinary development. When an ambiguous request fits that work better, leave this workflow out. A request to fix the actual app authorizes that scoped product edit; no special word such as "apply" is required, and existing authorization persists. A request to explore, show a prototype, or choose a favorite does not authorize production integration. If refinement's destination is genuinely unclear, proceed in a temporary copy and show it; clarify only before integrating.

## Isolation, retention, and recovery

For explore/refine, inspect project instructions, build configuration, and existing edits first. Create a unique OS temporary workspace and announce its absolute path. Put prototypes, fixtures, build output, logs, images, and a compact `run-notes.md` there. This file is an evidence index and recovery aid, not a project planning system. Keep project-level workflow/state files out of the repository.

Use synthetic fixtures and in-memory services. Give a harness a distinct bundle identifier and app/window name. Inspect launch paths, startup services, storage, and relevant entitlements before running a project-derived prototype: a copied project or different bundle identifier alone does not isolate shared containers, keychain groups, or live services. Prototype runs must not contact live services, migrate production stores, or change the real app's preferences. If an isolated runtime cannot be established, compile or provide source as appropriate and report launch/interaction checks as blocked.

Keep exploratory source edits in a disposable copy or harness, including when existing modules are needed. Do not patch the original project just to host a prototype. If the build route cannot support that boundary, report the limitation rather than modifying the original as a workaround.

For authorized product fixes, record the starting diff and your scoped changes; preserve unrelated and concurrent edits. Keep requested changes that merely lack visual/interaction verification, reporting that status. If your patch causes a known build or functional regression, remove only your changes when they can be cleanly separated. If they cannot, preserve the current file and report the conflict and exact affected locations; never restore a whole-file snapshot over newer work. Do not claim a fix is complete while a known regression remains.

**Retain artifacts by default**, including on cancellation. Report their paths; OS temporary storage can disappear and is not an archive. When durable retention is requested, copy the named artifacts to the requested location, preserve existing files, verify the copy, and report it. Ask for a destination only if the request and project context provide none. Delete owned artifacts only on request, checking ownership and paths first. Never clear shared caches or reset the working tree. Record owned process IDs, start identity, and bundle IDs immediately at launch. On completion or cancellation, when control is available, stop only those prototype processes after verifying their identity; a reused PID is not sufficient. Interruption cleanup is not guaranteed. On resumption, inspect notes, files, processes, and project changes; current observed state takes precedence over notes. Correct stale notes, and preserve/report uncertain ownership rather than deleting.

Use available dependencies and normal project build resolution within existing permissions. Do not install optional tools, alter global settings, or change dependency versions to make the workflow run. Report missing prerequisites instead.

## 1. Define success and bound the work

Read enough of the existing interface to establish its audience, task, constraints, and supported window behavior. **Read and state the actual minimum macOS target** from build settings or `Package.swift` before choosing APIs. For a new project without a declared target, state a provisional target or ask when the choice materially affects the design.

Define one or two representative tasks with a start state and an observable completion condition. For example: find a specified document, inspect its details, and return with the previous selection intact. Choose two or three task-relevant comparison criteria such as successful completion, retained context, required actions, recoverability, or keyboard access. For refinement, name the observed defect and its acceptance condition, such as labels remaining readable at the supported minimum width. Ask only for information that materially changes the work; otherwise state assumptions and proceed.

Keep fixtures, task starting state, window dimensions, and appearance matched across alternatives. Judge them against the same criteria. Agent walkthroughs are proxy evidence, not usability studies; do not invent user timings, preference scores, or research findings.

State an effort budget before building. Honor the user's time, cost, and variant limits. Without a supplied time limit, begin with a **provisional 30-minute exploration checkpoint or 15-minute refinement checkpoint**, excluding user-wait time. Record the start and check elapsed time before expensive operations and between stages.

When no explicit time limit was supplied, you may calibrate once after the first fully inspected direction, or the refinement baseline, using measured build, capture, and walkthrough effort on the actual route. Do this before the provisional checkpoint expires. Announce the total checkpoint, including time already spent, and the remaining planned count before further implementation. A minimal route proof alone is not a reliable estimate for app-dependent views. Match scope to the budget as described in section 3; never extend an explicit user limit or silently reduce their requested count. After calibration, do not extend or reset the clock without a new user request.

At the checkpoint, safely conclude or cancel the current operation, preserve work, and report partial results and what remains. Use bounded tool timeouts where available; report blocked/hung operations instead of waiting indefinitely. Start no new build/generation cycle. If elapsed time cannot be measured, disclose that: allow only the announced initial batch and at most six repair attempts total, including shared setup recovery, with the per-direction caps also applying. Report before any further work. These bounds limit autonomous effort, not the number of user-led rounds.

## 2. Discover capabilities and prove the build route

Inspect the session's actual skill/tool inventory and relevant installed instructions. Use exposed names and namespaces, not guessed commands. A failed guess at a directory does not prove an integration is absent. Cheap checks such as `command -v swift`, `command -v xcodebuild`, or a capture tool's help can establish presence; they cannot establish working SDKs, project builds, graphical access, or capture permissions. Label untested capabilities unverified.

Optional companions can supply narrow expertise: macOS platform guidance, SwiftUI implementation checks, native window capture such as Peek, or design critique such as Impeccable. Use project conventions and current platform documentation when they are absent. Do not import companion planning lifecycles or spawn agents/review panels just because their instructions suggest it. Check supplied API advice against the actual deployment target. Correct iOS simulator destinations, iOS-only preview traits, or simulator capture instructions to the macOS build/run route before use.

When evaluating Peek readiness or using Peek for capture, read [references/peek.md](references/peek.md). It supplies the tool-specific procedure; no separate Peek or `design-review` skill is required. For setup-only requests, use only its discovery guidance and leave capture permissions unverified unless already demonstrated in this session.

Choose the route from the project:

- Self-contained views: use a minimal temporary native harness.
- Views depending on app modules, signing, entitlements, or substantial packages: prefer the existing build system and scheme in an isolated copy, with the runtime protections above. Keep working Swift-package or custom routes; Xcode schemes are not mandatory for every project.
- If a harness starts reproducing the app's build graph, switch early rather than rebuilding that infrastructure. Avoid rewriting production configuration to make previews convenient.

Before implementing the batch, prove one minimal build–launch–capture path compatible with the planned host. A rendered preview is usable only if the capture tool can see it; a window-only tool needs a running native host. Limit shared setup recovery to two focused attempts within the overall budget, counted against the aggregate repair fallback when applicable. If still blocked, report the blocker and available unverified work rather than multiplying the failure across five variants. A minimal host proves the route, not every variant or app integration.

When optional image generation is requested or materially useful, inspect its actual installed interface and respect authorization for external transmission and paid generation. Keep it inside the budget. Label images **speculative — not a native render**. Generated imagery cannot replace missing implementation screenshots; reinterpret useful ideas through native controls and verify the implementation.

## 3. Explore meaningful alternatives

Skip this section for direct refinement. Default to five proposed directions, respecting an explicit requested count. Give each a stable ID, a descriptive name, a task hypothesis, and a meaningful tradeoff before implementing it. Use section 1's budget to choose how many can be built and checked in this round; state any reduction and why. An explicit user time limit takes precedence over completing a requested count, but any resulting shortfall remains incomplete work.

Use navigation/information architecture, primary interaction, window/pane composition, and density/disclosure as prompts for divergence. Two independent structural differences are a useful heuristic, not a quota. Explain the different task strategy: changing navigation and rearranging the same panes does not automatically count as two independent ideas. Color, typography, materials, corner radii, and decoration alone do not establish an alternative strategy.

Reject directions that omit the core task or violate preserved constraints. When only two or three worthwhile strategies fit, explain and build those rather than padding the batch. If the user explicitly requested a count, retain that target; report any shortfall with reasons rather than claiming completion. A tightly constrained question may warrant alternatives on one consequential dimension; explain why that comparison is informative.

Implement each surviving direction as a named SwiftUI/AppKit view with representative fixtures and sufficient local interaction to test its hypothesis. A screenshot, HTML facsimile, pseudocode, or unrendered preview declaration does not count as a runnable native direction. Share fixtures without forcing all directions into a common layout. Record how the stable ID maps to its source and launch argument or selector. Isolate variant failures where practical; one failed direction should not hide working ones.

## 4. Build, inspect, and compare evidence

Apply this section to every direction, refinement, and remix:

1. **Build and render.** Record the actual command, build exit status, and log path. Preserve the build process's status when filtering logs. Launch the intended artifact and select the current variant; a shared-host build covers compilation of included variants, not their rendering or inspection. Use the installed capture tool's help/instructions for supported selectors. App-name matching may be fuzzy: verify the exact process/window and visible variant marker, not just a similar app name, and ensure the image represents the current sources.
2. **Inspect actual images.** Capture and open the native image using available tools. Verify hierarchy, readability, clipping, toolbar fit, and task visibility. For each resizable, dual-appearance variant, use the same small/light, wide/light, and small/dark conditions, changing one factor at a time. Add wide/dark when an appearance/layout interaction warrants it. Include this inspection effort in budget calibration and report the sampled coverage, not a full matrix. Fixed-size or single-appearance views use the applicable subset with stated constraints. Record dimensions and appearance. Change appearance locally to the app/preview, not in system preferences.
3. **Exercise the task.** Perform the same task from the same fixture starting state; record actual actions, outcome, lost/preserved context, keyboard/focus behavior, and relevant empty, loading, or error behavior. Check accessibility labels and focus order with available inspection tools when relevant; disclose what was not checked. Distinguish tool-driven interactions from code reading or static screenshots. When interaction tools are absent, mark the task untested and provide reproducible user-side steps.
4. **Repair and recapture.** Fix material defects before presenting a direction as ready. Allow at most two focused repair attempts per direction within the overall budget; then show the blocker and continue with the others. After any source change, mark affected evidence stale until rebuilt and rechecked. Refinement's total pass bound below takes precedence over nested repair loops.

Keep `run-notes.md` concise: a short task/criteria summary, target, budget/start, owned paths/process identities, pointers to any authorized product diff, variant-to-source/launch mapping, and an evidence table. Update at stage boundaries, with process identities recorded at launch. Prefer links to logs and snapshots over copying their contents. For each variant or revision, record:

| State | Required supporting evidence |
| --- | --- |
| Built | Command, exit status, log, and a tool-computed digest or preserved snapshot of relevant sources, fixtures, and build configuration, including local edits; repository HEAD alone is insufficient |
| Rendered | Launch/preview route and matching native image path |
| Visually inspected | Image actually opened; dimensions, appearance, and observed findings |
| Interaction checked | Actions actually performed and observed outcomes; automation trace when available |

Use passed, failed, blocked, or not checked for each state, with its scope and evidence links. Record skipped checks and stale evidence explicitly. Verify cited files exist before reporting. This index supports audit and recovery; it is not independent certification. Do not label source-only work, an unopened screenshot, or a partially checked batch fully verified.

If building or capture is unavailable, provide existing source/images, exact intended run steps, and the specific missing capability or user action. For uncaptured visual fixes, describe the change as unverified and request a capture when needed; do not claim the view now looks right.

## 5. Present, refine, and finish

Show labeled native screenshots or an optional contact sheet with readable labels and full-resolution images. Use existing composition tools. If embedding is unavailable, provide existing absolute paths and launch instructions. For each ID, state its hypothesis, observed task results, strongest benefit, main tradeoff, and four verification states. Distinguish observations from expected benefits. Explain meaningful differences in coverage or conditions; do not rank a partially tested option as if coverage were equal.

Recommend a direction using the agreed criteria, then await the user's choice unless autonomous selection was authorized. Support combinations such as one direction's navigation with another's inspector. Name incompatible interactions and resolve them coherently; create one remix, or two only for a meaningful unresolved tradeoff. Keep lineage in the evidence index. A requested remix authorizes its stated structural changes, not unrelated redesign.

For every direct or post-choice refinement, capture a baseline, then allow **at most three patch–build–inspect/task-check passes total per refinement request**, including all repair work. The baseline is separate from these passes but inside the time budget. Compare against the stated outcome under matched conditions. Stop earlier when the outcome is met, two consecutive passes produce no improvement, the time checkpoint is reached, or progress requires an unrequested structural change or an unrelated project fix. If time expires after a patch, mark its evidence stale/unverified; do not add an uncounted repair cycle or claim the prior screenshot verifies it. Report what improved, what remains, and the next useful step. Keep the acceptance target fixed unless the user changes it. A subsequent user request begins a new bounded round.

At completion, report the chosen result, limitations, evidence index, and retained artifact paths. Follow the isolation section's rules for owned processes and authorized product changes, including any regression or conflict. Apply explicit durable-retention, deletion, or integration instructions already given; a choice alone authorizes neither production integration nor deletion. If the user only chose a direction, leave its artifacts available for the next refinement rather than guessing the exploration has ended.
