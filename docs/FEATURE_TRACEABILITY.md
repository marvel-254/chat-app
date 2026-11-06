# Feature Traceability Matrix

**Maps each feature from `features.md` to implementation status**

---

## Security & Privacy Features

| Feature (features.md) | Status | DB Migration | Flutter UI | Flutter Logic | Notes |
|----------------------|--------|--------------|------------|---------------|-------|
| **Chat Lock** | 🔴 Missing | `20261105` (conversation_locks) | ❌ | ❌ | Needs biometric/PIN UI, lock icon in conversation list |
| **Profile Photo Privacy** | 🟡 Partial | `20261104` (photo_visibility) | ✅ Settings UI | ❌ Not enforced | `visible_profiles` view exists but `getProfile()` bypasses it; avatar bucket is public |
| **Status Privacy** | 🟡 Partial | `20261104` (status_visibility) | ✅ Settings UI | ❌ Not enforced | `visible_profiles` masks `last_seen_at` but `getProfile()` doesn't use it |
| **About Info Privacy** | 🟡 Partial | `20261104` (about_visibility) | ✅ Settings UI | ❌ Not enforced | `visible_profiles` masks `about` but `getProfile()` doesn't use it |

---

## Messaging Features

| Feature (features.md) | Status | DB Migration | Flutter UI | Flutter Logic | Notes |
|----------------------|--------|--------------|------------|---------------|-------|
| **Disappearing Messages** | ✅ Complete | `20261103` (expires_at) | ✅ Per-chat timer menu | ✅ Supa.setMessageExpiry | Timer options: Off/24h/7d/30d |
| **Default Message Timer** | 🟡 Partial | `20261105` (default_message_expiry + trigger) | ✅ Settings dropdown | ❌ Not wired | Dropdown exists in AccountSettingsScreen but value not passed to updateProfileDetails |
| **Pin Important Messages** | ✅ Complete | `20261103` (pinned_at) + `20261106` (enforce_pin_cap) | ✅ Long-press menu + banner | ⚠️ Missing conversationId | Client-side 5-pin guard skipped; pin offered on peer messages (should be gated) |
| **Read Receipts** | 🟡 Partial | `20261103` (message_reads) + `20261105` (read_receipts_enabled) | ❌ No UI indicators | ⚠️ Legacy read_at used | Double-check marks not wired to message_reads; toggle exists but not enforced |
| **Edit Sent Messages** | ✅ Complete | `20261103` (edited_at, original_content) | ✅ Long-press → Edit | ✅ 15-min guard | Edit history stored but no UI to show it |
| **Emoji Bubbles Animations** | 🔴 Missing | - | ❌ | ❌ | Requires reactions system first |
| **Reply-to Messages** | 🔴 Missing | - | ❌ | ❌ | Deferred to Phase C |
| **Message Forwarding** | 🔴 Missing | - | ❌ | ❌ | Not in features.md but standard |
| **Voice Messages** | 🟡 Stub | - | ❌ (button shows "coming soon") | ❌ | `voice_note.dart` service exists but unused |

---

## Social Features

| Feature (features.md) | Status | DB Migration | Flutter UI | Flutter Logic | Notes |
|----------------------|--------|--------------|------------|---------------|-------|
| **Followers and Following** | ✅ Complete | `20261104` (user_follows) | ✅ Profile screen + bottom sheet | ✅ isFollowing/setFollowing | Bottom sheet exists; full page needed |
| **Followers/Following Page** | 🟡 Partial | - | 🟡 Bottom sheet | ✅ | `_FollowersFollowingSheet` is a bottom sheet; needs full screen with pagination |
| **Last Seen Online** | ✅ Complete | `20261104` (last_seen_at) | ✅ Profile + chat header | ✅ watchPeerPresence | Respects status_visibility via visible_profiles |
| **Status Screen** | 🔴 Missing | `20261104` (statuses table) | ❌ | ❌ | Major feature: needs status screen, story viewer, ring avatars, FAB, creation flow |
| **Statuses (Posts)** | 🟡 DB Only | `20261104` (statuses) | ❌ | ✅ Supa.createStatus/watchStatuses | Service methods exist; no UI |
| **Groups** | 🔴 Missing | - | ❌ | ❌ | No DB tables yet |
| **Group Polls** | 🔴 Missing | - | ❌ | ❌ | Depends on Groups |
| **Chat 1-1 Polls** | 🔴 Missing | - | ❌ | ❌ | Could be simpler than group polls |
| **Message Yourself** | 🔴 Missing | - | ❌ | ❌ | Self-chat conversation type |

---

## Utility Features

| Feature (features.md) | Status | DB Migration | Flutter UI | Flutter Logic | Notes |
|----------------------|--------|--------------|------------|---------------|-------|
| **Document Scanning** | 🔴 Missing | - | ❌ | ❌ | Camera + OCR + PDF export |
| **In-App Games** | 🔴 Missing | - | ❌ | ❌ | Game engine + lobby + sync |
| **About Info** | ✅ Complete | `20261104` (about column) | ✅ Profile edit + display | ✅ | 160 char limit in UI |

---

## Design & Animation

| Feature (features.md) | Status | DB Migration | Flutter UI | Flutter Logic | Notes |
|----------------------|--------|--------------|------------|---------------|-------|
| **Emoji Bubbles Animations** | 🔴 Missing | - | ❌ | ❌ | Same as Messaging row |

---

## Legend

| Symbol | Meaning |
|--------|---------|
| ✅ Complete | Fully working end-to-end (DB + UI + Logic) |
| 🟡 Partial | DB exists, some UI/Logic but gaps remain |
| 🔴 Missing | Not implemented at all |
| ⚠️ Issue | Known bug or incomplete wiring |

---

## Priority Classification (from features.md)

### High Priority (Foundation)
| Feature | Current | Target |
|---------|---------|--------|
| Chat Lock | 🔴 Missing | Implement biometric/PIN per conversation |
| Profile Photo Privacy | 🟡 Partial | Enforce via `visible_profiles` + redesign avatar storage |
| Status Privacy | 🟡 Partial | Fix `getProfile()` to use `visible_profiles` |
| Last Seen Online | ✅ Complete | ✅ Done |

### Medium Priority (Core Messaging)
| Feature | Current | Target |
|---------|---------|--------|
| Disappearing Messages | ✅ Complete | ✅ Done |
| Default Message Timer | 🟡 Partial | Wire Settings dropdown |
| Silence Unknown Callers | 🔴 Missing | Add to call settings |
| Pin Important Messages | ✅ Complete | Fix client guard + conversationId |
| Read Receipts | 🟡 Partial | Wire UI indicators + enforce toggle |
| About Info | ✅ Complete | ✅ Done |
| About Info Privacy | 🟡 Partial | Fix `getProfile()` |
| Edit Sent Messages | ✅ Complete | Add edit history UI |

### Medium Priority (Social)
| Feature | Current | Target |
|---------|---------|--------|
| Status Screen | 🔴 Missing | Full implementation (major) |
| Followers/Following | ✅ Complete | Convert bottom sheet to full page |
| Groups | 🔴 Missing | New DB + screens (major) |
| Group Polls | 🔴 Missing | Depends on Groups |
| Chat 1-1 Polls | 🔴 Missing | Simplified polls |
| Message Yourself | 🔴 Missing | Self-chat type |

### Low Priority (Enhancements)
| Feature | Current | Target |
|---------|---------|--------|
| Emoji Bubbles Animations | 🔴 Missing | After reactions |
| In-App Games | 🔴 Missing | Post-launch |
| Document Scanning | 🔴 Missing | Camera + ML Kit |
| About Info enhancements | ✅ Complete | Rich text/emoji support |

---

## Database Migration Coverage

| Migration | Features Enabled | Applied? |
|-----------|------------------|----------|
| `20261022000000_initial_schema.sql` | Auth, DMs, Messages | ✅ |
| `20261024200000_security_hardening.sql` | RLS hardening | ✅ |
| `20261025000000_conversation_enrichment.sql` | Conversation metadata | ✅ |
| `20261031000000_profile_creation_trigger.sql` | Auto-profile creation | ✅ |
| `20261102000000_chat_media_calls.sql` | Media buckets, calls | ✅ |
| `20261102010000_chat_background_preference.sql` | Chat backgrounds | ✅ |
| `20261102020000_chat_background_images.sql` | Custom backgrounds | ✅ |
| `20261102030000_message_push_tokens.sql` | Push notifications | ✅ |
| `20261103000000_message_controls.sql` | Expiry, pin, edit, reads | ✅ |
| `20261104000000_profile_privacy_presence.sql` | Privacy, follows, statuses, last_seen | ❌ **PENDING** |
| `20261105000000_chat_features.sql` | Read receipts pref, default expiry, locks | ❓ Unknown |
| `20261106000000_privacy_and_fixes.sql` | Visible profiles, pin cap, pg_cron, defaults | ❓ Unknown |

**Critical:** Run `supabase migration list --linked` and apply pending migrations before building dependent features.

---

## Flutter File Coverage

| Feature Area | Primary Files | Status |
|--------------|---------------|--------|
| Auth | `main.dart` (LoginScreen, ConfirmationScreen, AuthGate) | ✅ |
| Conversation List | `main.dart` (ConversationListScreen) | ✅ |
| Chat Screen | `main.dart` (ChatScreen, _MessageRow, _Bubble, _Composer) | ✅ |
| Call Screen | `screens/call_screen.dart` | ✅ |
| Settings | `main.dart` (AccountSettingsScreen) | ✅ |
| User Profile | `main.dart` (UserProfileScreen, _FollowersFollowingSheet) | ✅ |
| Supabase Service | `services/supabase.dart` | ✅ (needs getProfile fix) |
| Push Notifications | `services/push_notifications.dart` | ✅ |
| Connection Monitor | `services/connection_monitor.dart` | ✅ |
| Voice Notes | `services/voice_note.dart` | 🟡 Stub |
| UI States | `ui/states.dart` | ✅ |
| Models | `models/profile.dart` | ✅ |

---

## Gap Summary by Category

| Category | Total Features | ✅ Done | 🟡 Partial | 🔴 Missing | Completion |
|----------|----------------|---------|------------|------------|------------|
| Security & Privacy | 4 | 0 | 3 | 1 | 38% |
| Messaging | 9 | 3 | 3 | 3 | 50% |
| Social | 8 | 1 | 2 | 5 | 25% |
| Utility | 3 | 1 | 0 | 2 | 33% |
| Design/Animation | 1 | 0 | 0 | 1 | 0% |
| **TOTAL** | **25** | **5** | **8** | **12** | **37%** |

---

## Next Migration Priorities

1. **Apply `20261104000000_profile_privacy_presence.sql`** - Enables privacy columns, follows, statuses, last_seen
2. **Apply `20261105000000_chat_features.sql`** - Read receipts preference, default message expiry, conversation locks
3. **Apply `20261106000000_privacy_and_fixes.sql`** - Visible profiles view, pin cap enforcement, pg_cron cleanup, default expiry trigger
4. **New: Conversations UPDATE RLS** - Fix blocking issue #1
5. **New: SECURITY DEFINER pin_message()** - Fix blocking issue #2
6. **New: Groups tables** - For Groups feature (future)
7. **New: message_reactions table** - For Emoji Reactions (future)
8. **New: reply_to_id on messages** - For Reply-to (future)

---

*Update this matrix as features are completed. Source of truth for sprint planning.*