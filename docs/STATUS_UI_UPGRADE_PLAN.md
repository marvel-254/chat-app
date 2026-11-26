# Status UI upgrade plan

Status: Phases A-D implemented and gate-verified, 2026-11-25. Scope is `lib/screens/status_*.dart` plus `lib/theme/app_colors.dart` and status tests. No route or schema changes. Evidence is from the current working tree.

## Why this is next

The status surfaces are the last BRO UI cluster still using a private duplicate palette and raw full-page scaffolds, while chats, circles, calls, auth and settings now use shared tokens and `ResponsiveAppShell`.

| File | Evidence | Priority |
| --- | --- | --- |
| `lib/screens/status_composer.dart` | Private `_C` duplicates tokens at lines 13-18 with a non-shell background `0xFF050505`; background gradients at lines 24-27 duplicate `app_colors.chatBackgroundOptions`; raw `Scaffold` at line 149 | P0 |
| `lib/screens/status_viewer.dart` | Private `_C` at lines 14-26; one raw hex at line 299; raw `Scaffold` at line 209 | P0 |
| `lib/screens/status_screen.dart` | Private `_C` at lines 13-19 duplicates canonical tokens; already uses `ResponsiveAppShell` at line 164 but renders a plain `ListView` at line 102 | P1 |
| `lib/theme/app_colors.dart` | Canonical tokens and background options are the single source of truth | Reference |
| `lib/widgets/responsive_app_shell.dart` | Shared compact/tablet/desktop frame at lines 11-101 | Reference |

## Phases

### Phase A: token alignment, no visual redesign
1. Delete every private `_C` palette in the three status files. Import `../theme/app_colors.dart' as app_colors` and use `app_colors.P.*`.
2. Move the composer/viewer gradient lists into `app_colors.dart` as `statusWashes` and `statusBackdrops`, preserving their exact current colours and order, then reference those constants from both surfaces. Do not substitute `chatBackgroundOptions`; those are chat backgrounds with different colours.
3. Replace the raw `0xFF292A2F` in `status_viewer.dart:299` with `app_colors.surfaceHigh`.
4. Gate: analyzer clean; status feed test and status viewer test pass.

### Phase B: composer shell and desktop layout
1. Replace the raw `Scaffold` in `status_composer.dart` with `ResponsiveAppShell` (`navIndex: 2`, `showBottomNavigation: false`, explicit back action).
2. Constrain the composer card on desktop with `ConstrainedBox(maxWidth: 720)` inside the shell body. Keep media picking, background selection and the caption field unchanged.
3. Give the background swatches hover/focus states using `app_colors.volt` and keep the selected state readable in dark mode.
4. Gate: analyzer clean; pump the composer at 390 px and 1280 px in a widget test and assert no overflow.

### Phase C: viewer polish
1. Keep the viewer full-screen. It is an immersive story surface, so do not add the app bar or bottom navigation.
2. Replace private tokens with `app_colors` and align the progress bar, controls and reply field to the shared palette.
3. Wire the existing `_next`, `_previous`, `_pause`, `_resume` and `_delete` handlers to keyboard shortcuts (Left, Right, Space, Escape) and visible hover tooltips on desktop.
4. Gate: analyzer clean; extend `test/status_viewer_test.dart` for the keyboard path.

### Phase D: status feed on large screens
1. Keep `ResponsiveAppShell`, but replace the plain `ListView` with `LayoutBuilder`. Below 960 px keep the current vertical list.
2. At >= 960 px use `GridView.builder` with `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 360)` so status tiles form a restrained bento grid instead of stretching edge to edge.
3. Keep `FadeSlideIn`, `PressScale`, `RefreshIndicator` and the existing empty/error states.
4. Gate: analyzer clean; add a 1280 px widget test asserting grid rendering and unchanged nav index.

### Phase E: full verification
1. `flutter analyze --no-fatal-infos` with no errors or warnings.
2. `flutter test --no-pub --concurrency=4`, full pass count reported.
3. `flutter build web --release --no-wasm-dry-run` for the release bundle.

## Risks

- The main working tree currently has concurrent edits in unrelated files. Verify status changes in an isolated `git worktree` and never stage another agent's files.
- Status washes and backdrops are palette choices, not persisted names, but their colours are visible. Phase A preserves exact values and order.
- The viewer is a gesture-driven story surface. Adding the standard shell would regress the mobile experience.
- Keyboard shortcuts must not fire while a reply field has focus; check focus before handling keys.

## Recommended first move

Phase A and Phase B together. They remove the duplicated palette and fix the most visible raw scaffold before touching interaction logic.

Go with Phase A + B now?

## Completion record

- Phase A: private palettes removed; `statusWashes` and `statusBackdrops` are canonical in `app_colors.dart`.
- Phase B: composer uses `ResponsiveAppShell`, with a 720 px constrained card on desktop and hover/focus states on mood controls.
- Phase C: viewer keeps its full-screen layout, adds Left/Right/Space/Escape/Delete shortcuts and click cursors on tap zones.
- Phase D: status feed uses a 360 px max-cross-axis grid at >=960 px and keeps the vertical list below that. `StatusScreen` now accepts injected `watchStatuses` and `currentUserId` for tests.
- Verification in an isolated worktree with only these changed files: analyzer clean, 168/168 tests pass, web release build succeeds. The main tree still has unrelated concurrent edits, so those files were not staged or committed.

