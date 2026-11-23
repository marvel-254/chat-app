# BRO desktop + circles improvement plan

Status: Phase A shipped in v1.5.5, Phase B shipped in v1.5.6. Phase C and D pending. Scope: `lib/` UI and services plus timestamped Supabase migrations. No route changes, no brand refresh, no other projects.

## 1. Diagnosis (from the current tree)

### Desktop

- `ResponsiveAppShell` (`lib/widgets/responsive_app_shell.dart`) has one wide mode: a 240 px `NavSidebar` plus a single content column capped at 1180 px. There is no secondary pane.
- `ConversationListScreen` (`lib/screens/chat/conversation_list_screen.dart:371`) uses that same shell. Tapping a conversation calls `context.go('/chat/...')` (`:903`), so the list disappears.
- `ChatScreen` has a large-screen variant (`lib/screens/chat/chat_screen.dart:2126`), but it is only nav rail + chat, still no conversation pane. The `adaptiveBreakpoint` is 600 px (`lib/theme/app_colors.dart:16`), so "large" triggers on tablets too.
- Result: on a wide desktop the app behaves like an oversized phone. Roughly half the viewport is unused, and navigation loses context every time a chat opens.

### Circles

- `CircleDetailScreen` (`lib/screens/circle_detail_screen.dart`) builds a raw `Scaffold` with hardcoded colors (`0xFF121318`, `0xFF1E1F25`, `0xFF444932`, `0xFFC5C9AC`). It bypasses `ResponsiveAppShell`, so on desktop the navigation rail disappears and the screen does not match the rest of the app.
- `CirclesScreen` cards also use hardcoded colors instead of `app_colors` tokens (`lib/screens/circles_screen.dart:_CirclesCard`).
- The invite action is not an invite. `_inviteMember` searches a username, displays "direct messaging them instead", and opens a DM (`circle_detail_screen.dart:101-155`). There is no invite or request RPC in the linked database (confirmed: `create_circle`, `join_circle`, `leave_circle`, `get_circle_members`, `get_user_circles` exist; no invite function).
- Member removal writes directly to `circle_participants` from the client (`:170-180`), bypassing any server-side admin check.
- Circle detail fetches every circle and filters client-side (`circle_detail_screen.dart:31-34`).
- `watchMyCircles()` polls every 60 seconds (`lib/services/circles.dart:53-56`). No Realtime subscription, so membership and member-count changes are stale for up to a minute.
- `Circle.avatarPath` exists in the model and `create()` accepts it, but there is no upload or picker UI anywhere.
- No widget or service tests cover circles. `test/` only mentions circles incidentally.
- `CirclesScreen._createCircle` calls `linkConversation(circleId, circleId)`, using the circle id as a conversation id. Verify against `create_conversation_for_circle` before touching.

## 2. Product checks before building

- Who is this for: BRO users who live on desktop for long chat sessions and users running small groups (clubs, teams, family).
- Pain: context is lost on every chat open; circles cannot actually invite anyone; circle data lags.
- 10-star version: a three-pane desktop workspace with instant group management and live membership.
- Anti-goals: no logo/type/colour rebrand, no route or URL changes, no E2EE work in this tranche, no new design system. Keep the existing volt-on-charcoal language.
- Success signals: a user can open a chat without losing the list; an admin can invite and remove a member from one place; membership changes appear in under 5 seconds; circles screens have automated coverage.

## 3. Priority order

| Priority | Item | Impact | Confidence | Effort | Why first |
|---|---|---|---|---|---|
| P0 | Real circle invites and server-side member management | 5 | 5 | 3 | The headline feature does not work today and has a security hole |
| P0 | Put circle detail inside `ResponsiveAppShell` and use theme tokens | 4 | 5 | 1 | Cheap, fixes desktop identity immediately |
| P0 | Realtime circle updates with polling fallback | 4 | 4 | 2 | Removes the 60s stale window |
| P1 | Three-pane desktop workspace (nav + list + detail) | 5 | 4 | 5 | Biggest desktop win, largest refactor |
| P1 | Circle avatars, search and member previews | 3 | 4 | 3 | Makes circles feel finished |
| P1 | Tests for circles UI, services and DB functions | 4 | 5 | 2 | Prevents regressions on the next release |
| P2 | Collapsible icon rail, keyboard navigation, unread badges | 3 | 3 | 3 | Polish after the core works |

## 4. Implementation phases

### Phase A: P0 circles correctness (shipped in v1.5.5)

1. Migration `supabase/migrations/<timestamp>_circle_invites.sql`
   - `circle_invites` table: `circle_id`, `invitee_id`, `inviter_id`, `status` (`pending`/`accepted`/`declined`), timestamps, unique `(circle_id, invitee_id)`, RLS limited to the invitee, the inviter and circle admins.
   - `SECURITY DEFINER` functions with `set search_path = ''`: `invite_to_circle(p_circle_id, p_username)` (admin or public-circle member; validates block list and privacy), `accept_circle_invite(p_invite_id)`, `decline_circle_invite(p_invite_id)`, `remove_circle_member(p_circle_id, p_user_id)` (admin only), `get_circle(p_circle_id)` (single-row read).
   - Volatile, not stable, per the existing circle-function convention. Grant EXECUTE to `authenticated` only. Revoke from `anon`/`public`.
   - Add a PGlite test under `supabase/tests/` using the existing harness pattern, then push with `supabase db push --linked --include-all` after a dry run.
2. `lib/services/circles.dart`: replace direct table writes with the RPCs. Add `watchInvites()`, `getCircle(id)`, `invite`, `acceptInvite`, `declineInvite`, `removeMember`. Keep `getAllCircles` and the existing polling stream as fallback.
3. `lib/screens/circle_detail_screen.dart`: replace the fake DM invite with a username dialog that calls `Circles.invite`; show pending invites with accept/decline; use `Circles.removeMember`; load through `Circles.getCircle`. Wrap the screen in `ResponsiveAppShell` so the nav rail stays visible. Switch all hardcoded colors to `app_colors`.
4. `lib/screens/circles_screen.dart`: card colors to `app_colors`; add an invitations section with counts; keep `AppLoader`, `AppErrorState`, `AppEmptyState` states.
5. Verify: `flutter analyze --no-fatal-infos`, `flutter test`, PGlite suites, then tag and confirm the release carries all three APKs.

### Phase B: Realtime circles (shipped in v1.5.6)

1. Implemented as `Circles._watch()` in `lib/services/circles.dart`: a broadcast stream per surface using `client.channel(...)` with `postgres_changes` on `circles`, `circle_participants` and `circle_invites`. `watchMyCircles`, `watchPendingInvites` and `watchCircleChanges` share it. Channels and the 60s fallback poll are cancelled in `onCancel`, and screen callbacks guard `if (!mounted) return;`.
2. Bursts collapse through `lib/services/circle_realtime.dart` (`CircleRealtime.schedule`), with unit tests for coalescing and cancellation. The 60s poll remains as a safety net.
3. `test/circle_invite_tile_test.dart` covers the keyed join and decline tile; `test/circle_realtime_test.dart` covers the debouncer. The full-stream widget test remains outstanding.

### Phase C: Desktop workspace

1. Add `lib/widgets/desktop_workspace_shell.dart`: nav rail (reuse `NavSidebar`), a fixed 320 px list pane, and an `Expanded` detail pane. Trigger at a new `desktopWideBreakpoint = 1200.0` in `app_colors.dart`. Keep the existing 840 px shell for non-chat surfaces.
2. Extract the conversation list body from `ConversationListScreen` into a reusable `ConversationListPane` with an `onSelected` callback and a `selectedId` for active highlighting. No route changes: wide screens render both panes; narrow screens keep `context.go('/chat/:id')`.
3. Apply the same pattern to circles: circle list pane plus `CircleDetailScreen` in the detail pane. This removes the need for the full-page `Navigator.push` in `circles_screen.dart`.
4. Add a keyboard pass: Escape clears selection on wide screens, arrow keys move between list items, focus rings use the existing accent token. Keep motion to existing `PressScale`/`FadeSlideIn`; add nothing decorative.
5. Verify with a widget test at 1280 px that both panes exist and selection updates the detail pane without navigation, plus the existing analyzer/test gate.

### Phase D: Circle completeness

1. Avatar upload in create/edit dialogs using the `profile-media` bucket pattern already used for chat backgrounds (`lib/services/supabase.dart:771-820`). Store the path in `circles.avatar_path` through `Circles.updateCircle`.
2. Search field in the circle list, member avatar stack on cards, role labels, and unread count from the linked circle conversation if available.
3. Audit `create_circle` plus `create_conversation_for_circle` against the linked DB and fix the `linkConversation(circleId, circleId)` call if it is wrong.
4. Close the loop with tests and a release.

## 5. Risks

- Invite RLS is the risky part. A `security_invoker=false` view or a helper inside a masking `CASE` still needs EXECUTE on `authenticated`; test with `set local role authenticated` before shipping.
- Realtime `postgres_changes` on membership tables can leak ids into channels if topics are broad. Scope channels per user and rely on RLS.
- The three-pane refactor touches routing-adjacent code. Keep routes unchanged and add the pane as a pure layout layer to limit blast radius.
- A post-tag fix requires a new patch tag. Do not rewrite an existing release tag.

## 6. Recommended first move

Phase A. It fixes a feature that currently cannot do its main job, closes a client-side authorization hole, and is independently shippable. Phase C can then build on a circles detail screen that already behaves correctly on desktop.
