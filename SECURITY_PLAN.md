# E2EE, App Lock, and Block/Report Implementation Plan

## 1. #75: End-to-End Encryption (E2EE)
- **Approach**: Implement a lightweight AES-GCM layer for message content.
- **Key Management**: Use `flutter_secure_storage` to persist local keys; exchange public keys via Supabase profile metadata.
- **UI**: Add a security badge in the chat header to indicate encryption status.

## 2. #70: App Lock
- **Approach**: Utilize `local_auth` (already in `pubspec.yaml`).
- **Persistence**: Store lock status per conversation in Supabase (client-side enforcement).
- **UI**: Add "Locked" state to chat entry in `ConversationListScreen`.

## 3. #62: Block and Report
- **Approach**: Add `blocked_users` table to Supabase.
- **Logic**: Client-side filtering in `Supa.watchConversations()` and message stream.
- **UI**: Add "Block User" and "Report" buttons to the `_showChatMenu` sheet.

## Implementation Steps
1. [ ] Update SQL schema for Blocked Users.
2. [ ] Integrate `flutter_secure_storage` for key management.
3. [ ] Build Encryption Service layer.
4. [ ] Implement App Lock UI and logic.
5. [ ] Implement Block/Report UI and logic.
