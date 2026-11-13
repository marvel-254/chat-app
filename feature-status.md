# Feature Plan: Status

Status allows users to share their current state, activity, or availability. It aims to increase social context within the BRO ecosystem.

## Objectives
- Allow users to set a custom status message.
- Display status indicators in user profiles and conversation lists.
- Explore ephemeral status (stories) functionality.

## Roadmap
1. [ ] Define Data Model (Supabase: `user_status` extension to `profiles`)
2. [ ] UI: Create Set Status/Modal Pane
3. [ ] UI: Display status indicators in chat headers/conversation lists
4. [ ] Logic: Implement status update trigger
5. [ ] Logic: Broadcast status updates in real-time to active conversation participants
