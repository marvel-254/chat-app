# Chat Features Documentation

This document describes the upcoming features for the BRO chat application, organized by category and including implementation details, next steps, and design considerations.

## 🔒 Security & Privacy Features

### Chat Lock
- **Status:** Planning
- **Description:** Allow users to lock individual conversations with biometric authentication (fingerprint/face ID) or PIN protection
- **Implementation:**
  - Add lock/unlock functionality per conversation
  - Integrate with local auth (device biometrics)
  - Secure database rows with RLS when locked
- **Next Steps:**
  - Design UI for lock icon in conversation list
  - Implement biometric integration
  - Add auto-lock timer setting

### Profile Photo Privacy
- **Status:** Planning
- **Description:** Control who can view user's profile photo
- **Privacy Options:**
  - Everyone
  - My contacts only
  - Nobody
- **Implementation:**
  - Store privacy preference in user profile
  - Filter avatar displays based on privacy setting
  - Handle cached image disclosure
- **Next Steps:**
  - Add privacy selector in Settings → Privacy
  - Update conversation list avatar rendering
  - Implement privacy change audit

### Status Privacy
- **Status:** Planning
- **Description:** Control who can see user's online/status status
- **Privacy Options:**
  - Everyone
  - My contacts only
  - Nobody (appear offline)
- **Implementation:**
  - Update presence status storage per user
  - Filter "last seen" and "online" indicators
  - Respect privacy when showing typing indicators
- **Next Steps:**
  - Add status privacy options in Settings
  - Update realtime presence logic
  - Design "appear offline" toggle

### About Info Privacy
- **Status:** Planning
- **Description:** Control visibility of "About"/profile bio information
- **Privacy Options:** Same as status privacy (Everyone / Contacts / Nobody)
- **Implementation:**
  - Store about info privacy preference
  - Filter bio text display based on settings
  - Handle search visibility
- **Next Steps:**
  - Add privacy option in profile editing
  - Update profile API responses
  - Design privacy change flow

## 💬 Messaging Features

### Disappearing Messages
- **Status:** Planning
- **Description:** Messages that automatically delete after being viewed or after a timer expires
- **Implementation Options:**
  - Timer-based: delete after 24h/7d/30d
  - View-once: delete after first view
  - Manual: admin-controlled
- **Database Changes:**
  - Add `expires_at` timestamp to messages
  - Add `is_disappearing` boolean flag
  - Implement cleanup job for expired messages
- **Next Steps:**
  - Design UI for disappearing toggle per chat
  - Implement message expiration logic
  - Add visual indicator for disappearing messages

### Default Message Timer
- **Status:** Planning
- **Description:** Set default time after which messages auto-delete in new conversations
- **Timer Options:**
  - Disabled (no auto-delete)
  - 24 hours
  - 7 days
  - 30 days
- **Implementation:**
  - Store default timer in user profile
  - Apply timer to new conversations by default
  - Allow per-chat override
- **Next Steps:**
  - Add timer selector in Settings → Messages
  - Implement default application on new chat creation
  - Add override per conversation

### Pin Important Messages
- **Status:** Planning
- **Description:** Pin specific messages to the top of conversation for easy reference
- **Implementation:**
  - Allow pinning any sent message
  - Show pinned messages at conversation top
  - Limit number of pinned messages (e.g., 3-5)
- **Database:**
  - Add `is_pinned` flag to messages
  - Add `pinned_at` timestamp
- **Next Steps:**
  - Add pin action long-press on messages
  - Design pinned messages display UI
  - Implement pin limit enforcement

### Read Receipts
- **Status:** Planning
- **Description:** Show when recipients have read messages
- **Implementation:**
  - Track message read status per recipient
  - Show "read" timestamps in UI
  - Option to disable read receipts (privacy)
- **Database:**
  - Add `read_by` table or JSON field
  - Add `read_receipts_enabled` user preference
- **Next Steps:**
  - Implement read tracking on message delivery
  - Design read indicator UI
  - Add privacy toggle for read receipts

### Edit Sent Messages
- **Status:** Planning
- **Description:** Allow editing of sent messages within a time window
- **Implementation:**
  - Time limit for editing (e.g., 15 minutes)
  - Show "edited" label on modified messages
  - Maintain edit history visibility
- **Database:**
  - Add `edited_at` timestamp
  - Add `is_edited` boolean flag
- **Next Steps:**
  - Add edit option in message menu (time-limited)
  - Implement edit UI with before/after state
  - Design edit indication for recipients

### Emoji Bubbles Animations (Instagram/Telegram Feature)
- **Status:** Planning
- **Description:** Animated emoji reactions that appear as bubbles around conversation
- **Implementation:**
  - Collection of animated emoji (heart, thumbs up, laughter, etc.)
  - Tap to send emoji reaction to messages
  - Display bubbles floating around conversation screen
- **Design:**
  - Smooth entrance/exit animations
  - Configurable bubble behavior (float, pop, etc.)
  - Dark/light mode compatible
- **Next Steps:**
  - Design emoji set and animation frames
  - Implement reaction tap handler
  - Add bubble animation system
  - Integrate with existing reaction system

## 👥 Social Features

### Followers and Following
- **Status:** Planning
- **Description:** Follow other users and see their updates/status
- **Implementation:**
  - Follow/unfollow functionality
  - Follower/following counts
  - Feed of followed users' updates
- **Database:**
  - Add `followers` and `following` relationship tables
  - User profile follows count fields
- **Next Steps:**
  - Design follow UI in profile screen
  - Implement follow API endpoints
  - Add followers/following page

### Followers and Following Page
- **Status:** Planning
- **Description:** Dedicated page to manage and view followers/following
- **Implementation:**
  - Tab or section in profile for followers/following
  - Paginated list of followers/following
  - Search and filter options
- **Next Steps:**
  - Create followers/following screen UI
  - Implement list fetching with pagination
  - Add search/filter capabilities

### Last Seen Online
- **Status:** Planning
- **Description:** Display when users were last active online
- **Implementation:**
  - Track last activity timestamp
  - Show "online", "last seen today/yesterday", "last seen on date"
  - Respect privacy settings (status privacy controls visibility)
- **Database:**
  - Update last_seen on app activity/foreground transitions
  - Store per-user last_seen timestamp
- **Next Steps:**
  - Implement last_seen tracking logic
  - Design online indicator UI
  - Integrate with status privacy settings

### Status Screen
- **Status:** Planning
- **Description:** A dedicated screen for sharing personal updates that separates them from friends' conversation updates
- **Features:**
  - **Personal Status Posts:** Users can share text, photos, or mood updates that appear in a separate status section
  - **Separation from Chat Updates:** Personal statuses are distinctly separated from direct conversation messages
  - **Avatar-Based Status Indicators:** Circular avatar icons with status indicators (online/offline, status updates) displayed throughout the app
  - **Floating Action Button for Updates:** Prominent FAB on the status screen for creating new status updates quickly
  - **Story-Like Interface:** Swipe to view friends' status updates with tap to reply or react
- **Implementation:**
  - Status posting flow with media capture or selection
  - Privacy controls for who can view personal status (Everyone / My Contacts / Custom)
  - Avatar status updates that sync with profile status
  - Floating button handler for new status creation
  - Status expiration timer (24h default, configurable)
- **Database Changes:**
  - Add `statuses` table with user_id, content, media_url, expires_at, privacy
  - Add `user_status` table for current avatar/status state
  - Update user profiles with status privacy preference
- **Next Steps:**
  - Design status screen UI with FAB and avatar indicators
  - Implement status creation flow (camera/gallery + text)
  - Add privacy selector for status visibility
  - Implement status expiration and cleanup
  - Add status viewing interface with swipe navigation

### Groups
- **Status:** Planning
- **Description:** Create and manage group conversations
- **Implementation:**
  - Group creation with name/description/photo
  - Group admin roles and permissions
  - Group member management (add/remove members)
  - Group-specific settings (permissions, themes)
- **Database:**
  - Add groups table
  - Add group_members junction table
  - Add group admins tracking
- **Next Steps:**
  - Design group creation flow
  - Implement group API endpoints
  - Add group UI/screens (info, members, settings)

### Group Polls
- **Status:** Planning
- **Description:** Create polls within group conversations
- **Implementation:**
  - Poll creation with multiple options
  - Vote tracking per user
  - Poll results display (real-time or after voting)
  - Poll expiration options
- **Database:**
  - Add polls table (linked to groups)
  - Add poll_options table
  - Add poll_votes tracking
- **Next Steps:**
  - Design poll creation UI
  - Implement poll voting logic
  - Add results display component

### Chat 1-1 Polls
- **Status:** Planning
- **Description:** Create polls in one-on-one conversations
- **Implementation:**
  - Simplified poll UI for 1-1 chats
  - Two or more option polls
  - Real-time vote tallying
- **Database:**
  - Polls linked to conversations (including 1-1)
  - Voting tracking per user
- **Next Steps:**
  - Design 1-1 poll UI
  - Implement poll creation and voting
  - Add quick poll templates

### Message Yourself
- **Status:** Planning
- **Description:** Self-chat feature for notes, reminders, and quick saves
- **Implementation:**
  - Special conversation type "self"
  - Store notes, reminders, saved messages
  - Pin important self-messages
  - Search within self-chat
- **Use Cases:**
  - Temporary notes
  - Saved links and media
  - Reminder messages
- **Database:**
  - Mark conversation as type "self"
  - Self-message tracking
- **Next Steps:**
  - Design self-chat UI
  - Implement self-conversation creation
  - Add note-taking features

### Message Yourself (Notes/Reminders)
- **Also covers:** Quick save links/media, temporary storage within app

## 📱 Utility Features

### Document Scanning Using Camera
- **Status:** Planning
- **Description:** Use device camera to scan and upload documents directly
- **Implementation:**
  - Camera interface with document framing guide
  - Auto-document boundary detection
  - OCR processing (optional) for text extraction
  - Image enhancement (contrast, cropping, flattening)
- **Integration:**
  - Add to attachment picker
  - Support PDF export
  - Multi-page document support
- **Next Steps:**
  - Design camera scanning UI
  - Implement document boundary detection
  - Add image processing pipeline
  - Integrate with message attachment flow

### In-App Games
- **Status:** Planning
- **Description:** Lightweight games playable within chat conversations
- **Game Types:**
  - Turn-based word games
  - Trivia challenges
  - 2-player competitive games
  - Single-player distractions
- **Implementation:**
  - Game lobby within chat
  - Invite friends to play
  - Real-time game state sync
  - Score tracking and leaderboards
- **Database:**
  - Games table with configurations
  - Active game sessions tracking
  - Player scores and history
- **Next Steps:**
  - Design game selection UI
  - Implement first game prototype
  - Add game invitation system
  - Develop multiplayer synchronization

### About Info
- **Status:** Planning
- **Description:** User profile "About" section / bio text
- **Implementation:**
  - Bio text field in profile
  - Character limit formatting
  - Rich text/emoji support
  - Privacy controls for who can see
- **Database:**
  - Add `about` text field to profiles
  - Add `about` privacy preference
- **Next Steps:**
  - Add bio editing in profile screen
  - Implement character counter
  - Add privacy filtering

## 🎨 Design & Animation

### Emoji Bubbles Animations
- **See above** under "Emoji Bubbles Animations (Instagram/Telegram Feature)"

## 📊 Summary Table

| Feature | Status | Priority | Related Features |
|---------|--------|----------|------------------|
| Chat Lock | Planning | High | Security, Biometrics |
| Disappearing Messages | Planning | High | Message Timer |
| Default Message Timer | Planning | Medium | Disappearing Messages |
| Silence Unknown Callers | Planning | Medium | Call Settings |
| Followers/Following | Planning | Medium | Social Graph |
| Last Seen Online | Planning | Medium | Presence, Privacy |
| Profile Photo Privacy | Planning | High | Status Privacy |
| Status Screen | Planning | Medium | Statuses, Status Privacy |
| Statuses | Planning | Medium | Status Privacy |
| Status Privacy | Planning | High | Last Seen, Online Indicator |
| Pin Important Messages | Planning | Medium | Message Management |
| Document Scanning | Planning | Medium | Camera, Attachments |
| Read Receipts | Planning | Medium | Message Tracking |
| About Info | Planning | Low | Profile Editing |
| About Info Privacy | Planning | Medium | Profile Privacy |
| Groups | Planning | High | Conversations, Admin |
| Group Polls | Planning | Medium | Groups, Polls |
| Chat 1-1 Polls | Planning | Medium | Polls, 1-1 Chats |
| Message Yourself | Planning | Low | Self-Chat, Notes |
| Edit Sent Messages | Planning | Medium | Message Management |
| Emoji Bubbles Animations | Planning | Low | Animations, Reactions |
| In-App Games | Planning | Low | Entertainment, Engagement |

## 🚀 Next Steps Priority Order

1. **High Priority (Foundation):**
   - Chat Lock implementation
   - Profile Photo Privacy
   - Status Privacy
   - Last Seen Online tracking

2. **Medium Priority (Core Messaging):**
   - Disappearing Messages + Default Timer
   - Read Receipts
   - Pin Messages
   - Edit Sent Messages

3. **Medium Priority (Social):**
   - Status Screen (avatar indicators, FAB, personal vs friends updates)
   - Followers/Following + Page
   - Groups + Group Polls
   - 1-1 Polls

4. **Low Priority (Enhancements):**
   - Emoji Bubbles Animations
   - In-App Games
   - Document Scanning
   - About Info enhancements

## 📋 Implementation Notes

- **Database migrations** will be needed for all new features
- **Privacy settings** must be consistently applied across all UI elements
- **Backward compatibility** should be maintained where possible
- **Performance considerations** for real-time features (last seen, read receipts)
- **User opt-in** for new features with clear privacy disclosures
- **Testing** required for edge cases (privacy overrides, race conditions)

All features are currently in planning phase and will require database schema updates, API endpoint additions, and UI/UX design implementation.