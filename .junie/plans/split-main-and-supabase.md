---
sessionId: session-261116-203701-1ax7
---

# Overview & Goals

## Overview
Split the 7,867-line `lib/main.dart` (60+ classes) and 1,272-line `lib/services/supabase.dart` into a proper folder structure with focused files. Remove all `.md` documentation files except `HANDOFF.md` and `README.md`. Update `HANDOFF.md` to reflect the new structure.

## Goals
- `main.dart` reduced to ~200 lines (only `main()`, `BroApp`, routing, theme, and color constants).
- Screens extracted into `lib/screens/` with associated widgets in `lib/screens/*/widgets/`.
- `Supa` service split into domain-specific services under `lib/services/`.
- All imports updated so the app compiles and runs without behavior changes.
- All `.md` files removed except `HANDOFF.md` and `README.md`.
- `HANDOFF.md` updated to reflect the new architecture.

## Scope

### In Scope
- Extracting screens and widgets from `main.dart` into organized files.
- Splitting `Supa` into domain services.
- Updating all import paths across the codebase.
- Removing `.md` files (except `HANDOFF.md` and `README.md`).
- Updating `HANDOFF.md`.

### Out of Scope
- Behavioral changes to any feature.
- Adding tests (no test infrastructure exists yet).
- Fixing the silent `catch (_)` blocks (separate task).
- Upgrading dependencies (separate task).
- Adding lint rules (separate task).

# Technical Design

## Current State

`lib/main.dart` (7,867 lines, 60+ classes) contains:
- **Lines 1–110**: Imports, `main()`, `BroApp`, color constants, `_chatBackgroundOptions`, `_chatCanvas()`
- **Lines 112–124**: `_P` color palette class
- **Lines 126–243**: `BackendConfigurationApp` (error screen for missing backend config)
- **Lines 246–384**: `BroApp` + `_BroAppState` (root widget, routing, app lifecycle)
- **Lines 387–406**: `_ReactionPickerItem` (chat widget)
- **Lines 409–444**: `AuthGate` (auth state gate)
- **Lines 447–480**: `_AuthErrorState`
- **Lines 483–862**: `LoginScreen` + `_LoginScreenState` + `_WelcomeHero` + `_AuthField` + `_AuthFieldState`
- **Lines 991–1118**: `ConfirmationScreen` + `_ConfirmationScreenState`
- **Lines 1120–1663**: `ConversationListScreen` + `_ConversationListScreenState`
- **Lines 1665–3428**: `ChatScreen` + `_ChatScreenState` (largest block — ~1,764 lines)
- **Lines 3429–3490**: `_EmptyState` (inline empty state, deprecated — replaced by `ui/states.dart`)
- **Lines 3493–3532**: `_ErrorState` (inline error state, deprecated)
- **Lines 3534–3578**: `_PeerStatusLine`
- **Lines 3580–3642**: `_TypingDots` + `_TypingDotsState` + `_TypingIndicator`
- **Lines 3644–3738**: `_MessageRow`
- **Lines 3740–3786**: `_DateLine`
- **Lines 3788–3860**: `_ReactionsRow`
- **Lines 3862–4011**: `_VoiceMessage` + `_VoiceMessageState`
- **Lines 4013–4153**: `_VoiceNoteDialog` + `_VoiceNoteDialogState`
- **Lines 4155–4306**: `_Bubble`
- **Lines 4308–4437**: `_AttachmentContent`
- **Lines 4439–4530**: `_Composer`
- **Lines 4532–4608**: `_Avatar`
- **Lines 4610–4636**: `_ActionBtn` + `_MenuTile`
- **Lines 4638–5256**: `AccountSettingsScreen` + `_AccountSettingsScreenState` + `_SettingsField` + `_SettingsFieldState`
- **Lines 5258–6251**: `UserProfileScreen` + `_UserProfileScreenState` + profile widgets
- **Lines 6253–6312**: `_NavSidebar` + `_NavItem`
- **Lines 6315–6425**: `_ReplyPreviewBar` + `_ReplyPreviewInline`
- **Lines 6427–6898**: `_EmojiPicker`
- **Lines 6900–7074**: `_GifPicker` + `_GifPickerState`
- **Lines 7076–7842**: `_StickerPicker`
- **Lines 7844–7868**: `_SchedulePresetBtn`

`lib/services/supabase.dart` (1,272 lines) — single `Supa` class with ~80 static methods covering auth, profiles, conversations, messages, storage, search, follows, statuses, contacts, and message requests.

## Target File Structure

```
lib/
  main.dart                          (~200 lines: main(), BroApp, routing, theme, colors)
  theme/
    app_colors.dart                  (color constants, _P palette, _chatCanvas, backgrounds)
  screens/
    auth/
      auth_gate.dart                 (AuthGate, _AuthErrorState)
      login_screen.dart              (LoginScreen, _LoginScreenState, _WelcomeHero, _AuthField)
      confirmation_screen.dart       (ConfirmationScreen, _ConfirmationScreenState)
    chat/
      conversation_list_screen.dart  (ConversationListScreen, _ConversationListScreenState)
      chat_screen.dart               (ChatScreen, _ChatScreenState)
      widgets/
        message_row.dart             (_MessageRow, _DateLine, _PeerStatusLine)
        bubble.dart                  (_Bubble, _AttachmentContent)
        voice_message.dart           (_VoiceMessage, _VoiceMessageState)
        voice_note_dialog.dart       (_VoiceNoteDialog, _VoiceNoteDialogState)
        composer.dart                (_Composer)
        typing_indicator.dart        (_TypingDots, _TypingDotsState, _TypingIndicator)
        reactions_row.dart           (_ReactionsRow, _ReactionPickerItem)
        reply_preview.dart           (_ReplyPreviewBar, _ReplyPreviewInline)
        emoji_picker.dart            (_EmojiPicker)
        gif_picker.dart              (_GifPicker, _GifPickerState)
        sticker_picker.dart          (_StickerPicker)
        schedule_preset_btn.dart     (_SchedulePresetBtn)
        avatar.dart                  (_Avatar)
    settings/
      account_settings_screen.dart   (AccountSettingsScreen, _AccountSettingsScreenState, _SettingsField)
    profile/
      user_profile_screen.dart       (UserProfileScreen, _UserProfileScreenState)
      widgets/
        profile_stat_chip.dart       (_ProfileStatChip)
        followers_sheet.dart         (_FollowersFollowingSheet, _FollowersFollowingSheetState)
        follow_toggle_button.dart    (_FollowToggleButton, _FollowToggleButtonState)
        pinned_messages_banner.dart  (_PinnedMessagesBanner)
        pinned_messages_sheet.dart   (_PinnedMessagesSheet, _PinnedMessagesSheetState)
    navigation/
      nav_sidebar.dart               (_NavSidebar, _NavItem)
  services/
    supabase.dart                    (thin client wrapper only — ~30 lines)
    auth_service.dart                (signUp, signIn, signOut, currentUser, authStateChanges, resendConfirmation, savePushToken, removePushToken)
    profile_service.dart             (getProfile, getProfileByUsername, searchUsers, updateProfile, updateProfileDetails, recordLastSeen)
    conversation_service.dart        (refreshConversations, watchConversations, fetchConversations, getOrCreateDM, conversationsFromRows, _conversationChanges, triggerConversationRefresh, fetchConversationRows, areContacts, addContact, message requests, setConversationLocked, isConversationLocked, updateChatBackground)
    message_service.dart             (watchMessages, sendMessage, sendAttachment, pin/unpin, update message, message expiry)
    storage_service.dart             (uploadAvatar, uploadAttachment, uploadAttachmentFromUrl, attachmentUrl, uploadChatBackground, chatBackgroundUrl, _storagePost, _storageHeaders, _cloudStorageUrl)
    follow_service.dart              (isFollowing, setFollowing, getFollowersCount, getFollowingCount, getFollowers, getFollowing)
    status_service.dart              (createStatus, watchStatuses, fetchStatusesOnce, deleteStatus, recordStatusView, getStatusViewCount, getStatusViewers, uploadStatusMedia, statusMediaUrl)
```

## Key Decisions

1. **No behavioral changes** — every class is moved verbatim. Only imports are updated. This minimizes risk.
2. **Keep private classes with their screens** — `_LoginScreenState` stays in `login_screen.dart`, not extracted separately.
3. **Chat widgets get their own files** — each widget (`_Bubble`, `_Composer`, etc.) becomes a public class in its own file under `lib/screens/chat/widgets/`. The underscore prefix is dropped since they're no longer private to `main.dart`.
4. **Supa split by domain** — methods grouped by responsibility (auth, profile, conversation, message, storage, follow, status). Each service file re-exports the SupabaseClient getter.
5. **Color constants to `theme/app_colors.dart`** — extracted from `main.dart` to a dedicated theme file.
6. **`BackendConfigurationApp` stays in `main.dart`** — it's a top-level error widget, not a screen.

## Approach

Each stage extracts one logical group, updates imports in the new files, then updates the remaining `main.dart` references. After all extractions, `main.dart` imports the new files. This incremental approach ensures the codebase is always in a compilable state after each stage.

## Files to Remove

All `.md` files except `HANDOFF.md` and `README.md`:
- `.github/SECURITY_DEFINER_CHECKLIST.md`
- `ISSUE_PLAN.md`
- `MESH_ARCHITECTURE.md`
- `MESH_TRANSPORTS.md`
- `SECURITY_PLAN.md`
- `agents.md`
- `docs/FEATURES_HANDOFF.md`
- `docs/FEATURE_ANALYSIS.md`
- `docs/FEATURE_TRACEABILITY.md`
- `docs/NEXT_SESSION_TASKS.md`
- `docs/features.md`
- `feature-spaces.md`
- `feature-status.md`
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md` (Xcode-generated, keep)

## HANDOFF.md Updates

Update the Architecture section to reflect the new file structure. Update the local development section. Remove references to the old monolithic structure.

# Delivery Steps

### ✓ Step 1: Remove .md files and update HANDOFF.md
Clean up documentation files and update the handoff guide.
- Delete all `.md` files except `HANDOFF.md`, `README.md`, and `ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md` (Xcode-generated).
- Update `HANDOFF.md` Architecture section to reflect the planned new file structure (screens in `lib/screens/`, services split by domain, theme in `lib/theme/`).
- Update `HANDOFF.md` local development section to reference the new `main.dart` structure.

### ✓ Step 2: Extract theme, auth screens, and navigation from main.dart
Extract the first batch of classes from main.dart into organized files.
- Create `lib/theme/app_colors.dart` with color constants (`_bg`, `_surface`, `_volt`, etc.), `_P` palette class, `_chatBackgroundOptions`, and `_chatCanvas()`.
- Create `lib/screens/auth/auth_gate.dart` with `AuthGate` and `_AuthErrorState`.
- Create `lib/screens/auth/login_screen.dart` with `LoginScreen`, `_LoginScreenState`, `_WelcomeHero`, `_AuthField`, and `_AuthFieldState`.
- Create `lib/screens/auth/confirmation_screen.dart` with `ConfirmationScreen` and `_ConfirmationScreenState`.
- Create `lib/screens/navigation/nav_sidebar.dart` with `_NavSidebar` and `_NavItem`.
- Update all imports in the new files to reference `lib/theme/app_colors.dart` and existing services.
- Update `main.dart` to import the new files instead of containing the classes inline.

### ✓ Step 3: Extract conversation list and chat screen with all widgets
Extract the largest block — chat screen and all its widgets.
- Create `lib/screens/chat/conversation_list_screen.dart` with `ConversationListScreen` and `_ConversationListScreenState`.
- Create `lib/screens/chat/chat_screen.dart` with `ChatScreen` and `_ChatScreenState`.
- Create widget files under `lib/screens/chat/widgets/`: `message_row.dart`, `bubble.dart`, `voice_message.dart`, `voice_note_dialog.dart`, `composer.dart`, `typing_indicator.dart`, `reactions_row.dart`, `reply_preview.dart`, `emoji_picker.dart`, `gif_picker.dart`, `sticker_picker.dart`, `schedule_preset_btn.dart`, and `avatar.dart`.
- Drop underscore prefixes on widget classes since they become public in their own files.
- Update all cross-references between chat widgets (e.g., `_ChatScreenState` referencing `_Bubble`, `_Composer`, etc.).
- Update `main.dart` to import the new files.

### ✓ Step 4: Extract settings and profile screens from main.dart
Extract the remaining screens from main.dart.
- Create `lib/screens/settings/account_settings_screen.dart` with `AccountSettingsScreen`, `_AccountSettingsScreenState`, `_SettingsField`, and `_SettingsFieldState`.
- Create `lib/screens/profile/user_profile_screen.dart` with `UserProfileScreen` and `_UserProfileScreenState`.
- Create `lib/screens/profile/widgets/` with `profile_stat_chip.dart`, `followers_sheet.dart`, `follow_toggle_button.dart`, `pinned_messages_banner.dart`, and `pinned_messages_sheet.dart`.
- Update all imports in the new files.
- Update `main.dart` to import the new files.
- After this stage, `main.dart` should be ~200 lines containing only `main()`, `BroApp`, `_BroAppState`, `BackendConfigurationApp`, routing, and theme.

### * Step 5: Split Supa service into domain services
Split the 1,272-line Supa class into focused services.
- Create `lib/services/auth_service.dart` with auth methods (signUp, signIn, signOut, currentUser, authStateChanges, resendConfirmation, savePushToken, removePushToken).
- Create `lib/services/profile_service.dart` with profile methods (getProfile, getProfileByUsername, searchUsers, updateProfile, updateProfileDetails, recordLastSeen).
- Create `lib/services/conversation_service.dart` with conversation methods (refreshConversations, watchConversations, fetchConversations, getOrCreateDM, conversationsFromRows, message requests, contacts, chat background, conversation lock).
- Create `lib/services/message_service.dart` with message methods (watchMessages, sendMessage, sendAttachment, pin/unpin, update message, message expiry).
- Create `lib/services/storage_service.dart` with storage methods (uploadAvatar, uploadAttachment, uploadAttachmentFromUrl, attachmentUrl, uploadChatBackground, chatBackgroundUrl, _storagePost, _storageHeaders, _cloudStorageUrl).
- Create `lib/services/follow_service.dart` with follow methods (isFollowing, setFollowing, getFollowersCount, getFollowingCount, getFollowers, getFollowing).
- Create `lib/services/status_service.dart` with status methods (createStatus, watchStatuses, fetchStatusesOnce, deleteStatus, recordStatusView, getStatusViewCount, getStatusViewers, uploadStatusMedia, statusMediaUrl).
- Reduce `lib/services/supabase.dart` to a thin client wrapper (~30 lines).
- Update all callers across the codebase (screens, widgets, other services) to import from the new service files instead of `Supa`.

###   Step 6: Final import cleanup and verification
Ensure the entire codebase compiles after all splits.
- Run `flutter pub get` to ensure dependencies are resolved.
- Run `flutter analyze` to verify no import or type errors remain.
- Fix any remaining references to old file paths or class names.
- Verify `main.dart` is ~200 lines and imports all extracted modules.
- Verify `lib/services/supabase.dart` is ~30 lines.
- Confirm no `.md` files remain except `HANDOFF.md`, `README.md`, and the Xcode-generated one.