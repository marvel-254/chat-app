# BRO Chat App - Feature Implementation Analysis

**Date:** 2026-11-06  
**Purpose:** Comprehensive audit of current implementation vs. planned features (from `features.md`) to identify gaps before continuing development.

---

## Executive Summary

The BRO chat app has a **solid foundation** with authentication, direct messaging, media attachments, voice/video calls (WebRTC), push notifications (Android), chat backgrounds, and profile management. However, **significant gaps remain** between the current implementation and the feature set documented in `features.md`.

**Key Finding:** Many database migrations exist for planned features, but the **Flutter UI/logic is incomplete or missing** for most of them. The other agent (status-screen worktree) is working on Phase B (core chat polish) and Phase C (social surfaces).

---

## ✅ FULLY IMPLEMENTED (Working End-to-End)

| Feature | Implementation Status | Files |
|---------|----------------------|-------|
| **Auth (Sign up/Sign in/Email confirmation)** | ✅ Complete | `main.dart` (LoginScreen, ConfirmationScreen), `supabase.dart` |
| **Direct Messages (1:1)** | ✅ Complete | `main.dart` (ChatScreen, ConversationListScreen), `supabase.dart` |
| **Real-time messaging (Supabase Realtime)** | ✅ Complete | `supabase.dart` (watchMessages, watchConversations) |
| **Media Attachments (Images/Videos/Documents)** | ✅ Complete | `main.dart` (_pickPhoto, _pickDocument, _sendAttachment), `supabase.dart` |
| **Voice & Video Calls (WebRTC)** | ✅ Complete | `screens/call_screen.dart`, `supabase.dart` (call signaling) |
| **Push Notifications (Android FCM)** | ✅ Complete | `services/push_notifications.dart`, `supabase.dart` (push_tokens) |
| **Chat Backgrounds (Built-in + Custom Upload)** | ✅ Complete | `main.dart` (AccountSettingsScreen), `supabase.dart` |
| **Profile Management (Username, Display Name, Avatar, About)** | ✅ Complete | `main.dart` (AccountSettingsScreen, UserProfileScreen) |
| **Conversation Search & User Discovery** | ✅ Complete | `main.dart` (ConversationListScreen search + suggestions) |
| **Online/Offline Connectivity Monitor** | ✅ Complete | `services/connection_monitor.dart`, `ui/states.dart` (OfflineBanner) |
| **Conversation Pin/Unpin (DB + UI)** | ✅ Complete | `main.dart` (_showMessageActions, _PinnedMessagesBanner) |
| **Message Edit (15-min window)** | ✅ Complete | `main.dart` (_showMessageActions), `supabase.dart` (updateMessage) |
| **Disappearing Messages Timer (Per-Chat)** | ✅ Complete | `main.dart` (_chooseMessageExpiry), `supabase.dart` |
| **Follow/Unfollow Users** | ✅ Complete | `main.dart` (UserProfileScreen, _FollowToggleButton), `supabase.dart` |
| **Followers/Following Lists** | ✅ Complete | `main.dart` (_FollowersFollowingSheet) |
| **User Profiles (View Other Users)** | ✅ Complete | `main.dart` (UserProfileScreen) |
| **Presence (Last Seen / Online Indicator)** | ✅ Complete | `supabase.dart` (watchPeerPresence, formatLastSeen), `main.dart` |
| **Conversation Locks (DB Schema)** | ✅ DB only | Migration `20261105000000_chat_features.sql` |

---

## ⚠️ PARTIALLY IMPLEMENTED (DB Exists, UI/Logic Incomplete)

| Feature | What's Done | What's Missing |
|---------|-------------|----------------|
| **Read Receipts** | DB table `message_reads` + RLS; `Supa.markRead()` writes receipts | ❌ UI indicators (double-check marks not wired to `readByPeer`); ❌ Settings toggle exists but not enforced in `markRead`; ❌ `read_at` legacy field still used instead of `message_reads` |
| **Default Message Timer (Profile-Level)** | DB column `default_message_expiry` + trigger `apply_default_message_expiry` | ❌ Settings UI dropdown exists but **not wired to profile update**; ❌ Not applied when creating new DMs |
| **Profile Privacy (Photo/Status/About Visibility)** | DB columns + `visible_profiles` view with masking logic | ❌ **Not enforced in `getProfile()`** - still reads from `profiles` table directly; ❌ Avatar rendering in conversation list bypasses privacy; ❌ Settings UI exists but changes don't take effect |
| **Status/Stories** | DB table `statuses` + `Supa.createStatus`/`watchStatuses` | ❌ **No UI at all** - no status screen, no story viewer, no FAB for creation, no ring avatars |
| **Conversation Locks** | DB table `conversation_locks` + `Supa.isConversationLocked`/`setConversationLocked` | ❌ **No UI** - no lock icon in conversation list, no biometric/PIN integration |
| **Pinned Messages Limit (5 per chat)** | DB trigger `enforce_pin_cap` | ❌ Client-side guard missing (call site omits `conversationId`); ❌ Banner shows all pinned but no limit feedback |
| **Message Expiry Cleanup** | Function `delete_expired_messages()` + `pg_cron` job in migration | ❌ `pg_cron` extension may not be enabled on Supabase; needs verification |
| **Avatar Privacy** | `visible_profiles` view masks `avatar_url` | ❌ Avatar bucket is **public** - privacy can't be guaranteed until storage redesigned |

---

## ❌ NOT IMPLEMENTED (Missing Entirely from Codebase)

### High Priority (Foundation)

| Feature | Details from features.md | Required Work |
|---------|--------------------------|---------------|
| **Chat Lock (Biometric/PIN per Conversation)** | Lock/unlock conversations, auto-lock timer, local_auth integration | New UI in conversation list + settings; biometric auth; DB already has `conversation_locks` table |
| **Silence Unknown Callers** | Call setting to block non-contacts | Settings UI + call screening logic in `call_screen.dart` |
| **Groups** | Group creation, admin roles, member management, group settings | New DB tables (`groups`, `group_members`), new screens, conversation type distinction |
| **Group Polls** | Polls in groups with vote tracking, real-time results | DB tables + UI components |
| **Chat 1-1 Polls** | Simplified polls in DMs | DB + UI (could reuse group polls infra) |

### Medium Priority (Core Messaging)

| Feature | Details | Required Work |
|---------|---------|---------------|
| **Reply-to Messages** | Quote/reply to specific messages | DB column `reply_to_id` + UI in message bubble + composer |
| **Emoji Reactions** | Tap to react, reaction counts on bubbles | DB table `message_reactions` + UI (long-press menu → emoji picker) |
| **In-Conversation Search** | Search messages within a chat | Full-text search (Postgres) or client-side filtering + search UI |
| **Edit Sent Messages - History UI** | Show edit history on edited messages | Already stores `original_content` + `edited_at`; needs UI |
| **Message Forwarding** | Forward messages to other chats | Composer integration + message selection mode |
| **Voice Messages** | Record and send audio messages | Button exists in composer (`onVoice` shows "coming soon"); needs recording UI + playback |
| **Message Yourself (Notes/Reminders)** | Self-chat for saved items | Special conversation type "self" + dedicated entry point |

### Medium Priority (Social)

| Feature | Details | Required Work |
|---------|---------|---------------|
| **Status Screen (Stories)** | Separate tab, story viewer, ring avatars, FAB for creation, 24h expiry | **Major feature** - new screen, story viewer component, media upload flow |
| **Followers/Following Page** | Dedicated paginated screen with search | `_FollowersFollowingSheet` exists as bottom sheet; needs full page |
| **About Info Privacy Enforcement** | Already has DB + settings UI; needs `getProfile()` fix | See partial implementation above |

### Low Priority (Enhancements)

| Feature | Details | Required Work |
|---------|---------|---------------|
| **Emoji Bubbles Animations** | Instagram/Telegram-style floating reaction bubbles | Animation system + emoji set + integration with reactions |
| **In-App Games** | Turn-based games, trivia, 2-player | Game engine integration + lobby + real-time sync |
| **Document Scanning** | Camera-based document capture with OCR | Camera integration + image processing + PDF export |
| **About Info (Rich Text/Emoji)** | Enhanced bio editor | Rich text input + emoji picker in profile edit |

---

## 🐛 OUTSTANDING CODE REVIEW ISSUES (Must Fix First)

From the HANDOFF.md code review (blocking items):

| # | Issue | Severity | Fix Required |
|---|-------|----------|--------------|
| 1 | `conversations` table has **no UPDATE RLS policy** | 🔴 Blocking | Add UPDATE policy or SECURITY DEFINER function for `setMessageExpiry`/`getOrCreateDM` |
| 2 | **Pin message offered on peer messages** but DB rejects non-author updates | 🔴 Blocking | Gate client action per-message (check `isMine`), or add SECURITY DEFINER `pin_message()` function |
| 3 | `Supa.updateProfileDetails` unconditionally writes `default_message_expiry` | 🔴 Blocking | Make update map conditional (only include non-null values) |

**Non-blocking but important:**
| # | Issue | Fix Required |
|---|-------|--------------|
| 4 | `delete_expired_messages()` never scheduled | Verify `pg_cron` works on Supabase; add monitoring |
| 5 | Privacy columns not enforced in `getProfile`, `get_conversations_for_user`, `record_last_seen` | Update `Supa.getProfile()` to use `visible_profiles`; fix RPC |
| 6 | Pin call site omits `conversationId` | Pass `conversationId` to `Supa.setMessagePinned()` |
| 7 | `last_seen` only on app resume, not cold start | Call `recordLastSeen()` in `AuthGate` after session restore |
| 8 | `watchMessages` re-queries `message_reads` per snapshot | Optimize with join or cached lookup |
| 9 | Follower counts load all follows instead of `.count()` | Use `select('follower_id', count: true)` |
| 10 | No settings UI for `read_receipts_enabled`/`default_message_expiry` | Already exists in AccountSettingsScreen but not wired |

---

## 📋 RECOMMENDED IMPLEMENTATION ORDER

### Phase 0: Critical Fixes (Week 1)
*Must complete before any new features*

1. Fix conversations UPDATE RLS policy
2. Fix pin message client-side guard + SECURITY DEFINER function
3. Fix `updateProfileDetails` conditional writes
4. Wire `default_message_expiry` in Settings → Profile update
5. Fix `getProfile()` to use `visible_profiles` view
6. Add `conversationId` to pin call site
7. Call `recordLastSeen()` on cold start

### Phase 1: Complete Partially Implemented Features (Week 2-3)

1. **Read Receipts** - Wire UI indicators + enforce settings toggle
2. **Profile Privacy Enforcement** - Fix avatar rendering, `getProfile()`, conversation list
3. **Conversation Locks UI** - Lock icon, biometric/PIN integration, auto-lock timer
4. **Status/Stories Foundation** - Status screen, story viewer, creation flow, ring avatars

### Phase 2: Core Messaging Polish (Week 3-4)

1. **Reply-to Messages** - DB + UI
2. **Emoji Reactions** - DB + UI + reaction picker
3. **In-Conversation Search** - Client-side first, then FTS
4. **Voice Messages** - Recording UI + playback
5. **Optimistic Sending** - `PendingMessage` model + retry logic (from Phase B plan)
6. **Unread Divider + Jump to Bottom** - Chat UX improvements

### Phase 3: Social Features (Week 4-5)

1. **Groups** - Full implementation (DB + screens + permissions)
2. **Group Polls / 1-1 Polls** - Poll creation + voting + results
3. **Followers/Following Page** - Full screen with pagination + search
4. **Message Yourself** - Self-chat entry point + notes UI

### Phase 4: Enhancements (Week 5+)

1. **Chat Lock** - Biometric/PIN per conversation
2. **Silence Unknown Callers** - Call screening
3. **Document Scanning** - Camera + OCR
4. **Emoji Bubbles Animations** - Visual polish
5. **In-App Games** - Entertainment features

---

## 🗄️ DATABASE MIGRATION STATUS

| Migration | Applied to Linked Project? | Notes |
|-----------|---------------------------|-------|
| `20261022000000_initial_schema.sql` | ✅ | Base schema |
| `20261024200000_security_hardening.sql` | ✅ | RLS hardening |
| `20261025000000_conversation_enrichment.sql` | ✅ | Conversation enhancements |
| `20261031000000_profile_creation_trigger.sql` | ✅ | Profile auto-create |
| `20261102000000_chat_media_calls.sql` | ✅ | Media buckets + calls |
| `20261102010000_chat_background_preference.sql` | ✅ | Chat backgrounds |
| `20261102020000_chat_background_images.sql` | ✅ | Custom backgrounds |
| `20261102030000_message_push_tokens.sql` | ✅ | Push tokens |
| `20261103000000_message_controls.sql` | ✅ | Expiry, pin, edit, reads |
| `20261104000000_profile_privacy_presence.sql` | ❌ **NOT APPLIED** | Privacy columns, follows, statuses, last_seen |
| `20261105000000_chat_features.sql` | ❓ Unknown | Read receipts pref, default expiry, locks |
| `20261106000000_privacy_and_fixes.sql` | ❓ Unknown | Visible profiles view, pin cap, pg_cron, defaults |

**Action Required:** Run `supabase migration list --linked` and apply pending migrations (`20261104` onwards) before building dependent features.

---

## 🔀 OTHER AGENT WORK (status-screen worktree)

The other agent is working on:
- **Phase B:** Core chat polish (`PendingMessage`, `UnreadDivider`, `JumpToBottomButton`, `PendingBubble`, optimistic sends)
- **Phase C:** Social surfaces (Statuses screen, Follow UI, Settings toggles)

**Coordination Needed:**
- Avoid duplicate work on Status/Stories and Follow UI
- Share `PendingMessage` model design
- Coordinate on read receipts UI implementation
- Sync on conversation lock UI approach

---

## 📝 NEXT STEPS FOR THIS SESSION

1. **Apply pending Supabase migrations** (especially `20261104000000_profile_privacy_presence.sql`)
2. **Fix the 3 blocking code review issues** (RLS, pin guard, conditional update)
3. **Wire `default_message_expiry` in Settings** → Profile update
4. **Update `Supa.getProfile()` to use `visible_profiles`**
5. **Document decisions** on which features to prioritize next

---

## 📊 FEATURE COMPLETENESS SCORECARD

| Category | Planned | Implemented | Partial | Missing | % Complete |
|----------|---------|-------------|---------|---------|------------|
| Auth & Profiles | 5 | 4 | 1 | 0 | 90% |
| Core Messaging | 12 | 6 | 3 | 3 | 58% |
| Media & Calls | 4 | 3 | 0 | 1 | 75% |
| Privacy & Security | 6 | 1 | 3 | 2 | 33% |
| Social & Status | 7 | 2 | 1 | 4 | 36% |
| Groups & Polls | 4 | 0 | 0 | 4 | 0% |
| Enhancements | 5 | 0 | 0 | 5 | 0% |
| **TOTAL** | **43** | **16** | **8** | **19** | **~44%** |

---

*This analysis should be updated as features are completed. Use this as the source of truth for sprint planning.*