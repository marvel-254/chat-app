# BRO Auth & Account Hardening Plan (Free-Tier Stack)

Status: Proposed (2026-11-25).

## 1. Current State & Gaps

Audited from the current tree:

- **Weak password policy**: `validatePassword` (`lib/screens/auth/auth_validation.dart`) and `supabase/config.toml` (`minimum_password_length = 6`) accept any 6-character password (e.g. `123456`) with no complexity, strength feedback, or leaked-password check.
- **No Two-Factor Authentication (2FA)**: No `mfa` enrollment, challenge, or assurance-level check exists anywhere in `lib/`, even though Supabase Auth supports TOTP MFA on the free tier (`[auth.mfa.totp]` in `supabase/config.toml`).
- **Incomplete Password Recovery flow**: `Supa.resetPasswordForEmail` (`lib/services/supabase.dart`) does not pass a `redirectTo` URL, and neither `AuthGate` (`lib/screens/auth/auth_gate.dart`) nor `lib/main.dart` handles `AuthChangeEvent.passwordRecovery` to route users to a dedicated "Set new password" screen.
- **Email confirmation disabled in local config**: `enable_confirmations = false` in `supabase/config.toml` (production must have email confirmation enabled + custom SMTP so accounts cannot be claimed with unverified addresses).
- **No bot / brute-force protection**: `[auth.captcha]` in `supabase/config.toml` is unconfigured, and `LoginScreen` (`lib/screens/auth/login_screen.dart`) has no client-side cooldown/backoff after repeated failures.
- **Single-device sign-out & missing re-auth**: `Supa.signOut()` only signs out the current device (`SignOutScope.others` is not exposed in Settings), and sensitive account changes do not require recent re-authentication.

---

## 2. Implementation Phases (All $0 / Free Tier)

### Phase 1: Password Policy, Strength Meter & Leaked-Password Check

1. **Client & server length/complexity**:
   - Update `validatePassword` (`lib/screens/auth/auth_validation.dart`) to require **at least 8 characters** (recommended 10+) and at least two character classes (e.g., letters + numbers/symbols).
   - Update `supabase/config.toml` (`minimum_password_length = 8`, `password_requirements = "lower_upper_letters_digits"`) and match in the hosted Supabase Auth settings.
2. **Live strength indicator on sign-up**:
   - Add a lightweight strength bar (Weak / Fair / Strong) in `LoginScreen` (`_isSignUp` mode) and in the Change Password / Reset Password forms.
3. **Free leaked-password check (HIBP k-anonymity)**:
   - Supabase's built-in HaveIBeenPwned toggle requires Pro, so implement a free **k-anonymity Range API** check (`https://api.pwnedpasswords.com/range/<prefix>`):
     - Hash the candidate password locally with SHA-1 (already available via `crypto` / Dart), send only the **first 5 hex characters** of the hash, and check if the remaining suffix appears in the returned list.
     - Fail open with a short timeout (e.g. 2s) if offline/unreachable so sign-up never blocks on third-party uptime.

### Phase 2: Complete Password Recovery Flow

1. **Explicit `redirectTo`**:
   - Pass `redirectTo` in `Supa.resetPasswordForEmail(email)` (`lib/services/supabase.dart`) pointing to the web app URL (e.g. `https://bro.omixsystems.store/app/#/reset-password` or configured deep link) and allowlist the URL in Supabase Auth Redirect URLs.
2. **Handle `AuthChangeEvent.passwordRecovery`**:
   - Listen for `AuthChangeEvent.passwordRecovery` in `lib/main.dart` / `AuthGate` (`lib/screens/auth/auth_gate.dart`) and route directly to a dedicated `/reset-password` screen.
3. **Reset Password screen**:
   - Require entering and confirming a new strong password (using Phase 1 validators + HIBP check), call `Supa.client.auth.updateUser(UserAttributes(password: newPassword))`, then navigate to `/conversations`.

### Phase 3: TOTP Two-Factor Authentication (2FA)

1. **Enrollment in Account Settings (`lib/screens/settings/account_settings_screen.dart`)**:
   - Add a **Two-Factor Authentication** section using Supabase's free TOTP MFA APIs:
     - `Supa.client.auth.mfa.enroll(factorType: FactorType.totp)` -> display QR code (`totp.qrCode` SVG/URI) and copyable manual secret (`totp.secret`).
     - Verify the initial 6-digit code with `challenge()` + `verify()` before marking 2FA enabled.
     - Support unenrolling (`unenroll(factorId)`) after re-verification.
2. **Login challenge (`AuthGate` / `LoginScreen`)**:
   - After password sign-in (and on session restore in `AuthGate`), check `Supa.client.auth.mfa.getAuthenticatorAssuranceLevel()`:
     - If `currentLevel == aal1` and `nextLevel == aal2`, route to a **2FA Verification** screen (`challengeAndVerify` / `challenge` + `verify`) before granting access to `/conversations`.

### Phase 4: Session & Sensitive-Action Hardening

1. **Sign out all other devices**:
   - Add a **"Sign out other devices"** action in Account Settings / Linked Devices calling `Supa.client.auth.signOut(scope: SignOutScope.others)`.
2. **Re-authentication gate**:
   - Require current password (or TOTP code if AAL2 is enabled) before changing email, changing password, or deleting the account.
3. **Audit error messages**:
   - Verify `friendlyErrorMessage` (`lib/ui/errors.dart`) returns generic copy on sign-in failures (e.g. `"Email or password didn't match"`) and password resets (`"If an account exists for that email..."`) to prevent account enumeration.

### Phase 5: Bot Protection & Passwordless / OAuth

1. **Cloudflare Turnstile (Free)**:
   - Configure Turnstile in Cloudflare (free) and Supabase Auth (`[auth.captcha]` -> `provider = "turnstile"`).
   - Render the Turnstile widget on web sign-up, sign-in, and password reset and pass `captchaToken` to `signUp`, `signInWithPassword`, and `resetPasswordForEmail`.
2. **Client-side retry backoff**:
   - After 3+ consecutive failed sign-in attempts in `LoginScreen`, enforce a brief progressive cooldown (e.g. 5s -> 15s -> 30s) with a countdown timer.
3. **Free OAuth providers**:
   - Enable **Google** and/or **GitHub** OAuth in Supabase Auth (`signInWithOAuth`) to reduce password-reuse exposure at $0 cost.

---

## 3. Free Platforms & Services Stack

| Need | Recommended Free Platform | Free Allowance / Notes |
| --- | --- | --- |
| **Auth, MFA (TOTP), OAuth, Sessions** | **Supabase Auth (Free tier)** | 50,000 MAUs, TOTP MFA, Google/GitHub OAuth, RLS |
| **Transactional Auth Emails (SMTP)** | **Brevo** *(alternative to Resend)* | **300 emails/day free forever** (~9,000/mo), SMTP relay, no card required |
| **Transactional Auth Emails (Alt 1)** | **SMTP2GO** | **1,000 emails/month free**, reliable SPF/DKIM setup |
| **Transactional Auth Emails (Alt 2)** | **Mailjet** | **200 emails/day (6,000/mo) free forever**, standard SMTP |
| **Transactional Auth Emails (Alt 3)** | **Resend** | **3,000 emails/month (100/day) free** |
| **CAPTCHA / Bot Protection** | **Cloudflare Turnstile** | Free tier, native Supabase Auth integration |
| **Edge WAF & Rate Limiting** | **Cloudflare Free Plan** | Free DNS proxy, DDoS protection, basic WAF rules on custom domain |
| **Leaked Password Check** | **HIBP Range API** | Free, anonymous 5-char SHA-1 prefix lookup (`api.pwnedpasswords.com`) |
| **Auth Error & Spike Monitoring** | **Sentry** (already integrated) | Free developer tier for tracking auth failures & anomalies |

---

## 4. Verification Checklist

- Unit tests for `validatePassword` (length, character classes, edge cases) and HIBP range prefix matching (mocked HTTP responses + fail-open timeout).
- Widget tests for `LoginScreen` (strength meter, cooldown behavior), `/reset-password` recovery flow, and 2FA challenge gate.
- `flutter analyze --no-fatal-infos` and `flutter test` pass after each phase.
- Manual end-to-end test in production: sign-up with email confirmation -> sign-in -> enroll TOTP 2FA -> sign-out -> sign-in with 2FA -> password reset email -> sign out other devices.
