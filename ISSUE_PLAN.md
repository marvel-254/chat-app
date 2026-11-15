# Security Issues and Hardening Plan

## 1. Move Rate Limiting to Backend
- **Observation**: `MessageSafety.validateContent` currently enforces rate-limiting on the client-side (Flutter). While this provides good UX, it is not a robust security control, as an attacker could bypass the client and interact directly with the Supabase API to flood the `messages` table.
- **Priority**: Medium
- **Recommended Fix**: Implement a `before insert` trigger on the `messages` table or an Edge Function that verifies the message frequency per `sender_id`. Use a tracking table to store `last_message_at` for each user.

## 2. Transition E2EE to ECDH Key Exchange
- **Observation**: The current E2EE service derives symmetric keys deterministically using `SHA-256(userIdA | userIdB)`. This provides encryption at rest, but lacks Perfect Forward Secrecy (PFS)—if a user's persistent identity key is compromised, all historical messages can be decrypted.
- **Priority**: Low
- **Recommended Fix**: Implement an Elliptic Curve Diffie-Hellman (ECDH) key exchange protocol for initial session establishment. This would allow each session to have unique ephemeral keys, protecting historical communication if long-term keys are leaked.

## 3. Continuous Audit of `SECURITY DEFINER` Functions
- **Observation**: The app relies heavily on `SECURITY DEFINER` Postgres functions (e.g., `get_or_create_dm`) to bypass standard RLS for administrative operations.
- **Priority**: Informational (Maintenance)
- **Recommended Fix**: Establish a formal review step for all future `SECURITY DEFINER` functions in the `supabase/migrations/` CI pipeline. Ensure all new functions explicitly set `search_path = ''` to prevent search-path hijacking attacks, and strictly audit the input parameters for SQL injection.
