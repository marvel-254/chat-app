# BRO Chat App - Next Session Task List

**Priority Order:** Critical fixes → Complete partial features → New features  
**Estimated:** 2-3 sessions to clear critical backlog

---

## 🔴 SESSION 1: Critical Fixes (Must Do First)

These block other work and affect data integrity.

### 1. Fix Conversations UPDATE RLS Policy
**File:** `supabase/migrations/` (new migration)
**Problem:** `Supa.setMessageExpiry()` and `Supa.getOrCreateDM()` silently fail - no UPDATE policy on `conversations` table.
**Fix:** Add migration with UPDATE policy or SECURITY DEFINER function.

```sql
-- Option A: Narrow UPDATE policy (recommended)
create policy "Participants update conversation settings" on conversations
  for update to authenticated using (
    exists (
      select 1 from conversation_participants cp
      where cp.conversation_id = id and cp.user_id = auth.uid()
    )
  );
```

### 2. Fix Pin Message - Client Guard + SECURITY DEFINER Function
**Files:** `lib/main.dart` (_showMessageActions), new migration
**Problem:** Pin action offered on peer messages but DB trigger rejects non-author updates.
**Fix A (Client):** Only show "Pin" for `mine == true` messages.
**Fix B (Server):** Add SECURITY DEFINER `pin_message(message_id, pinned)` that checks ownership and 5-pin limit.

```sql
-- Migration: add pin_message function
create or replace function public.pin_message(msg_id uuid, do_pin boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  msg_conversation uuid;
  msg_sender uuid;
  pin_count int;
begin
  select conversation_id, sender_id into msg_conversation, msg_sender
  from public.messages where id = msg_id;
  
  if msg_sender <> auth.uid() then
    raise exception 'only the message author may pin this message';
  end if;
  
  if do_pin then
    select count(*) into pin_count
    from public.messages
    where conversation_id = msg_conversation and pinned_at is not null and id <> msg_id;
    
    if pin_count >= 5 then
      raise exception 'a conversation can have at most 5 pinned messages';
    end if;
    
    update public.messages set pinned_at = now() where id = msg_id;
  else
    update public.messages set pinned_at = null where id = msg_id;
  end if;
end;
$$;
grant execute on function public.pin_message(uuid, boolean) to authenticated;
```

### 3. Fix `Supa.updateProfileDetails` - Conditional Writes
**File:** `lib/services/supabase.dart` (updateProfileDetails method)
**Problem:** Unconditionally writes `default_message_expiry` as `'0 seconds'` when null.
**Fix:** Only include non-null values in update map.

```dart
static Future<void> updateProfileDetails({
  required String about,
  required String photoVisibility,
  required String statusVisibility,
  required String aboutVisibility,
  bool readReceiptsEnabled = true,
  Duration? defaultMessageExpiry,
}) async {
  final updates = <String, dynamic>{
    'about': about.trim().isEmpty ? null : about.trim(),
    'photo_visibility': photoVisibility,
    'status_visibility': statusVisibility,
    'about_visibility': aboutVisibility,
    'read_receipts_enabled': readReceiptsEnabled,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
  
  // Only include if explicitly set (not null)
  if (defaultMessageExpiry != null) {
    updates['default_message_expiry'] = defaultMessageExpiry == Duration.zero
        ? '0 seconds'
        : '${defaultMessageExpiry.inSeconds} seconds';
  }
  
  await client.from('profiles').update(updates).eq('id', currentUser!.id);
}
```

### 4. Wire `default_message_expiry` in Settings → Profile
**File:** `lib/main.dart` (AccountSettingsScreen _save method)
**Problem:** Dropdown exists but value not passed to `updateProfileDetails`.
**Fix:** Pass `_defaultMessageExpiry` to the update call (already there but broken by #3).

### 5. Fix `Supa.getProfile()` to Use `visible_profiles` View ✅ DONE
**File:** `lib/services/supabase.dart` (getProfile method)
**Problem:** Reads from `profiles` table directly, bypassing privacy masking.
**Fix:** Query `visible_profiles` instead.

```dart
static Future<Profile?> getProfile(String uid) async {
  final res = await client
      .from('visible_profiles')  // Changed from 'profiles'
      .select()
      .eq('id', uid)
      .maybeSingle();
  return res != null ? Profile.fromJson(res) : null;
}
```

### 6. Add `conversationId` to Pin Call Site
**File:** `lib/main.dart` (_showMessageActions → action == 'pin')
**Problem:** `Supa.setMessagePinned` called without `conversationId`, skipping client-side 5-pin guard.
**Fix:** Pass `widget.conversationId` (already in ChatScreen state).

```dart
await Supa.setMessagePinned(message.id, message.pinnedAt == null,
    conversationId: widget.conversationId);  // Add this
```

### 7. Call `recordLastSeen()` on Cold Start ✅ DONE
**File:** `lib/main.dart` (AuthGate or _BroAppState initState)
**Problem:** `last_seen` only updated on app resume, not cold start.
**Fix:** Call after auth state resolves to session.

```dart
// In AuthGate, after session != null:
unawaited(Supa.recordLastSeen());
```

---

## 🟡 SESSION 2: Complete Partial Features

### 8. Read Receipts - Wire UI + Enforce Toggle 🔄 IN PROGRESS (Service layer done, UI pending)
**Files:** `lib/main.dart` (_Bubble read indicator), `lib/services/supabase.dart` (markRead)
**Tasks:**
- Use `msg.readByPeer` (from `message_reads`) for double-check mark instead of legacy `read_at`
- In `markRead()`, check `_readReceiptsEnabled` before writing receipt (already in code but verify)
- Update conversation list unread count logic to use `message_reads`

### 9. Profile Privacy Enforcement - Full Pass
**Files:** `lib/main.dart` (ConversationListScreen avatar, UserProfileScreen), `lib/services/supabase.dart`
**Tasks:**
- Conversation list: Use `conv.peerAvatarUrl` from RPC (already privacy-aware in migration `20261106`)
- User profile: Avatar + About + Last Seen should respect privacy via `visible_profiles`
- Settings: Privacy toggles should immediately affect visibility (test with two accounts)

### 10. Conversation Locks - UI Implementation
**Files:** `lib/main.dart` (ConversationListScreen, ChatScreen), new `lib/screens/lock_screen.dart`
**Tasks:**
- Add lock icon in conversation list (show when `conv.isLocked`)
- Lock/Unlock action in chat menu (long-press conversation or chat menu)
- Biometric/PIN prompt using `local_auth` package
- Auto-lock timer setting (1 min, 5 min, 15 min, immediately)

### 11. Apply Pending Migrations ✅ DONE (20261104, 20261105, 20261106, 20261107)
**Command:** `supabase db push --linked`
**Migrations needed:** `20261104000000_profile_privacy_presence.sql`, `20261105000000_chat_features.sql`, `20261106000000_privacy_and_fixes.sql`
**Verify:** `pg_cron` job for `delete_expired_messages` is running.

---

## 🟢 SESSION 3: New Features (Priority Order)

### 13. Emoji Reactions
**DB:** Migration `20261107000000_reactions_and_reply.sql` ✅ Applied
**UI:** Long-press message → emoji picker → reaction pills on bubble
**Files:** `lib/widgets/reaction_picker.dart`, `lib/main.dart` (_Bubble), `lib/services/supabase.dart` (already has addReaction/removeReaction/watchReactions)

### 14. Reply-to Messages
**DB:** Migration `20261107000000_reactions_and_reply.sql` ✅ Applied (reply_to_id column)
**UI:** Quote bubble above composer, tap to scroll to original
**Files:** `lib/main.dart` (ChatScreen composer, _MessageRow), `lib/services/supabase.dart` (already has sendMessageWithReply/getReplyPreview)

### 15. Optimistic Sending + PendingMessage (Phase B)
**Files:** New `lib/models/pending_message.dart`, `lib/main.dart` (ChatScreen _send/_sendAttachment)
**Model:** `localId`, `status` (sending/sent/failed/queued), `toOptimisticMessage()`, `retryCount`
**UI:** `PendingBubble` with tap-to-retry, `UnreadDivider`, `JumpToBottomButton`

### 16. Follow UI - Full Page (You Own This) ✅ DONE
**Scope:** Convert existing bottom sheet to full screen with pagination + search
**Files:** `lib/followers_following_screen.dart` ✅ Created, `lib/main.dart` ✅ Updated ✅ DONE (lib/followers_following_screen.dart)
**Scope:** Convert existing bottom sheet to full screen with pagination + search
**Files:** `lib/main.dart` (_FollowersFollowingSheet → new screen), new `lib/screens/followers_following_screen.dart`
**Backend:** Already exists (`user_follows` table, `Supa.getFollowers`/`getFollowing`/`getFollowersCount`/`getFollowingCount`)
**UI Components:**
- Full screen (not bottom sheet) accessible from profile tabs
- Tabbed: Followers / Following
- Paginated infinite scroll (currently loads all)
- Search/filter by username
- Pull-to-refresh
- Follow/Unfollow buttons per row (already in `_FollowToggleButton`)

### 13. Status/Stories Foundation (Phase C)
**Scope:** Major feature - new screen, story viewer, creation flow
**Files:** New `lib/screens/status_screen.dart`, `lib/screens/status_viewer.dart`, `lib/widgets/status_ring_avatar.dart`
**Backend:** Already exists (`statuses` table, `Supa.createStatus`/`watchStatuses`)
**UI Components:**
- Status tab in navigation (sidebar + bottom nav)
- Ring avatars on conversation list + profile screen
- FAB on status screen for creation
- Story viewer with swipe navigation, tap to reply/react
- 24h expiry + privacy selector (Everyone/Contacts/Followers)

### 14. Reply-to Messages
**DB:** Add `reply_to_id` to `messages` table (self-ref FK)
**UI:** Quote bubble above composer, tap to scroll to original
**Files:** Migration, `lib/main.dart` (ChatScreen composer, _MessageRow)

### 15. Emoji Reactions
**DB:** New `message_reactions` table (message_id, user_id, emoji, created_at)
**UI:** Long-press message → emoji picker → reaction pills on bubble
**Files:** Migration, `lib/widgets/reaction_picker.dart`, `lib/main.dart` (_Bubble)

### 16. Optimistic Sending + PendingMessage (Phase B)
**Files:** New `lib/models/pending_message.dart`, `lib/main.dart` (ChatScreen _send/_sendAttachment)
**Model:** `localId`, `status` (sending/sent/failed/queued), `toOptimisticMessage()`, `retryCount`
**UI:** `PendingBubble` with tap-to-retry, `UnreadDivider`, `JumpToBottomButton`

### 17. Voice Messages
**Files:** `lib/services/voice_note.dart` (exists but unused), `lib/main.dart` (Composer onVoice)
**UI:** Hold-to-record, slide to cancel, playback in bubble

---

## 📋 QUICK REFERENCE: FILES TO MODIFY

| Task | Primary Files |
|------|---------------|
| RLS Fix | New migration in `supabase/migrations/` |
| Pin Function | New migration + `lib/main.dart` (_showMessageActions) |
| Conditional Update | `lib/services/supabase.dart` (updateProfileDetails) |
| Default Expiry Wire | `lib/main.dart` (AccountSettingsScreen _save) |
| getProfile Fix | `lib/services/supabase.dart` (getProfile) |
| Pin conversationId | `lib/main.dart` (_showMessageActions) |
| Cold Start last_seen | `lib/main.dart` (AuthGate) |
| Read Receipts UI | `lib/main.dart` (_Bubble), `lib/services/supabase.dart` (markRead) |
| Privacy Enforcement | `lib/main.dart` (ConversationListScreen, UserProfileScreen) |
| Conversation Locks UI | `lib/main.dart` + new `lib/screens/lock_screen.dart` |
| **Follow UI (Full Page)** | `lib/main.dart` + new `lib/screens/followers_following_screen.dart` |
| Status Screen | New `lib/screens/status_screen.dart`, `lib/screens/status_viewer.dart` | [Move to Session 4]
| Reply-to | Migration ✅ Applied + `lib/main.dart` (UI pending) |
| Reactions | Migration ✅ Applied + `lib/widgets/reaction_picker.dart` + `lib/main.dart` (UI pending) |
| PendingMessage | New `lib/models/pending_message.dart` + `lib/main.dart` (Session 3 priority) |

---

## ✅ DEFINITION OF DONE FOR EACH TASK

- [ ] Code compiles (`flutter analyze` passes)
- [ ] Tests pass (`flutter test`)
- [ ] Manual verification on web build (`./scripts/build.sh web`)
- [ ] No regression in existing features
- [ ] Documentation updated if API changes

---

## 🤝 COORDINATION WITH OTHER AGENT

| Area | Other Agent (status-screen) | This Agent | Coordination |
|------|----------------------------|------------|--------------|
| PendingMessage | Implementing | Will implement | Share model design |
| Status/Stories | Implementing | Will implement | Split: they do viewer, we do creation? |
| Follow UI | Not started | **Full page (Session 3)** ✅ DONE | We own this - converted bottom sheet to full screen |
| Read Receipts | Not started | Will do | We take this |
| Conversation Locks | Not started | Will do | We take this |

**Action:** Sync with other agent before starting Session 3 features.

---

*Update this list as tasks are completed. Check off items in real-time during development.*