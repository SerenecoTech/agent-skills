# Peek: native capture for this workflow

Read when checking Peek readiness or choosing it to capture a native prototype. This reference supplies command knowledge; `SKILL.md` controls scope, budgets, isolation, and evidence. Peek creates images; the agent's image-reading tool must open them, and separate interaction tools are needed for general task walkthroughs.

## Discover the installed interface

Checked against locally installed **Peek 0.1.1** help and upstream source on **19 September 2026**. Recheck help at use time, especially when the version differs:

```sh
command -v peek
peek --version
peek --help
peek app --help
```

If absent, report it and use another available tool only if it can capture the verified owned prototype window specifically. Otherwise mark capture blocked. A whole-desktop capture is not an acceptable fallback for this workflow. Do not install Peek as a side effect. The upstream README references a `skills/design-review/SKILL.md` file that was absent at the checked revision; that separate expert-panel workflow is not a dependency here.

For **setup-only** requests, stop at discovery and documentation: do not capture, launch an app, scan its accessibility tree, or generate configuration. Help working establishes CLI availability, not capture permission or operational readiness.

## Capture a known native window

1. Launch the owned, isolated prototype through the main skill's verified build route. Give it a unique app name, one visible test window where possible, and a visible variant/revision marker. Set the required size and appearance through the harness or another available control tool; Peek 0.1.1 has no resize or appearance flags.
2. If needed during execution, `peek list` reports app name, window count, and main-window dimensions as tab-separated values. It does not identify every individual window or prove capture permission. Inspect only the relevant target information.
3. Replace the example app name and output path below with the actual running harness and a fresh absolute path inside this run's workspace. Use distinct filenames for each variant, revision, size, and appearance; preserve earlier evidence.

```sh
peek app "ActualHarnessName" --output "/absolute/run-workspace/A-r1-small-light.png"
```

4. Check the command's real exit status, retain stderr on failure, and check that the successful command produced the requested new PNG. Basic capture prints its output path. A path printed by an earlier attempt, or an existing file after a failed command, is not current evidence.
5. Open that PNG with the available image-reading tool. Verify the visible marker, expected controls, and intended window. Record the command, path, window size, appearance, source identity, and findings in the main skill's evidence index. Record window dimensions separately from PNG pixel dimensions: upstream 0.1.1 capture requests a doubled pixel size.

Successful capture establishes neither visual inspection nor successful interaction. Keep those verification states separate.

## Window selection limits

In 0.1.1, app matching tries case-insensitive names, normalized names, then substrings. Different matched app names can produce an ambiguity error. Same-name processes can remain indistinguishable through this CLI. Use the exact unique harness name and verify the resulting image.

Basic capture selects the **largest normal window** of the matched app, falling back to other discovered windows if no normal window is available. `peek app --help` exposes **no window-title, window-ID, or PID selector**. A smaller inspector or secondary window therefore cannot be targeted reliably just by naming the app. Use a single-window owned harness or another tool with explicit selection; do not invent flags or close unrelated user windows. Discovery is limited to on-screen windows, so do not assume a minimized, hidden, or other-Space window is available.

## Permissions and failures

Pixel capture uses ScreenCaptureKit and needs Screen Recording authorization for the execution context. Accessibility access is used by tree scanning and panel navigation, not the basic capture code path. The README describes terminal-host permissions; when running through another host, report the actual macOS prompt or error and responsible application rather than assuming Terminal is the host.

If permission is denied, explain the specific Privacy & Security setting the user must enable and mark the affected check blocked. Do not change privacy settings, repeatedly trigger prompts, or count successful help output as authorization. Reattempt after the permission or environment changes. Other errors may indicate a missing/disappeared window or failure to write the output; inspect the error before prescribing a permission fix.

## Panel features are a separate, optional operation

Use basic `peek app` for this workflow by default. It requires no Peek panel configuration.

`--panel` and `--all` require per-app configuration and can press/select controls through Accessibility. They change app state; they are not passive screenshots or general keyboard/mouse automation. A successful panel command does not prove the intended navigation occurred: verify the visible state and any claimed interaction outcome.

Only use panel actions when needed within the requested task, against an isolated prototype launched for this run whose identity was verified before the action. A similar or fuzzy-matched app name is insufficient. If the CLI cannot distinguish the intended process from another same-name app, do not perform panel actions. First read installed `peek scan --help` and relevant configuration documentation. Respect the main skill's ban on incidental global configuration changes. Existing configuration can be inspected; writing `~/.config/peek/` requires an explicit configuration request. Never generate configuration just to make a basic screenshot work.

In upstream 0.1.1, `--all` writes fixed paths under `/tmp/peek/<AppName>/<Panel>.png` and does not use the supplied `--output` value. It can overwrite prior captures outside the run workspace. Do not use `--all` in this workflow unless the user explicitly requests it. Prefer individual captures with fresh explicit paths. For an explicit `--all` request, explain the output exception, determine the actual paths from the configuration, and check for existing files before running; use individual captures instead if existing evidence would be overwritten without authorization. Record exact created paths and copy new evidence into the run workspace. Do not delete the shared `/tmp/peek` directory.

## Sources and validation limits

- [Upstream README](https://github.com/frr149/peek/blob/f05b86ca844b8187aac24e02b48612cc89e12dc3/README.md): usage and the separate design-review reference.
- [App command](https://github.com/frr149/peek/blob/f05b86ca844b8187aac24e02b48612cc89e12dc3/Sources/Peek/Commands/AppCommand.swift): flags, matching, window choice, panel behavior, output paths.
- [Window discovery](https://github.com/frr149/peek/blob/f05b86ca844b8187aac24e02b48612cc89e12dc3/Sources/Peek/Capture/WindowDiscovery.swift) and [capture](https://github.com/frr149/peek/blob/f05b86ca844b8187aac24e02b48612cc89e12dc3/Sources/Peek/Capture/WindowCapture.swift): selection, visibility, pixel size, and capture errors.
- [Accessibility navigation](https://github.com/frr149/peek/blob/f05b86ca844b8187aac24e02b48612cc89e12dc3/Sources/Peek/Accessibility/AXNavigator.swift): permission checks and state-changing panel actions.

Local validation covered version and command help. Behavioral details above were checked against the cited source, not by executing native captures or panel interactions. Installed help is authoritative for exposed options; source-dependent behavior should be rechecked for a different version or build. No end-to-end capture capability is claimed until demonstrated on the actual target.
