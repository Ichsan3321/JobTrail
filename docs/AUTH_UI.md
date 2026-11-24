# Authentication UI and startup

## Run locally

The entry point defaults to `supabase`. Copy the trackable example, then
replace its placeholder with the development project's publishable key in the
ignored local file. Invalid or missing configuration shows a startup message.

```powershell
Copy-Item .env.jobtrail.example .env.jobtrail.json
# Edit .env.jobtrail.json locally to insert the project's publishable key.
flutter pub get
flutter run -d chrome --web-hostname=localhost --web-port=3000 --dart-define-from-file=.env.jobtrail.json
flutter devices
flutter run -d ANDROID_DEVICE_ID --dart-define-from-file=.env.jobtrail.json
```

Keep `JOBTRAIL_WEB_ORIGIN` aligned with the exact browser origin. The real
configuration accepts Supabase HTTPS project URLs and `sb_publishable_` keys.
A compiled Flutter build can expose its Dart defines, so include public
configuration only. For a local UI demo without Supabase use
`flutter run -d chrome --web-hostname=localhost --web-port=3000 --dart-define=JOBTRAIL_AUTH_MODE=mock`.
Only debug mock mode offers the labeled demo Home and preview actions.
If Windows desktop plugin symlinks block SDK commands on a machine targeting
only Web or Android, set `$env:FLUTTER_WINDOWS = 'false'` in that PowerShell session.

## Required dashboard settings

The project owner configures **Authentication → URL Configuration** manually.
Keep existing approved origins and email settings intact. For the development
setup above, set **Site URL** to `http://localhost:3000` and add these exact
redirect URLs.

| Platform | Confirmation | Recovery |
|---|---|---|
| Web | `http://localhost:3000/?auth=confirm` | `http://localhost:3000/?auth=recovery` |
| Android | `com.example.jobtrail://auth/confirm` | `com.example.jobtrail://auth/recovery` |

Email/password must be enabled. Registration is available when project signup
policy permits it, and the Auth UI supports confirmation being required. Keep
the current confirmation policy. Supabase's default SMTP only sends to
authorized project-team addresses and currently limits the project to two
messages per hour. Report email-dependent tests as blocked when eligible
delivery is unavailable. [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
· [Supabase SMTP limits](https://supabase.com/docs/guides/auth/auth-smtp)

## Session lifecycle and repository handoff

`SupabaseAuthProvider` extends the existing injectable boundary. The SDK
persists and refreshes the session, and the controller exposes loading,
signed-out, authenticated, recovery, and error states. New Auth events supersede
in-flight restoration. Expiry and logout close the protected tree. Logging out
removes the local session and requests sign-out for the current Supabase session.
Changing accounts replaces the entire protected navigator and disposes the
previous store, including any protected routes and modal overlays.

The adapter accepts only the configured callback origins and exchanges codes
using PKCE. The request and callback must share the same browser profile or
Android app installation. On Web, callback parameters are removed from browser
history. Recovery purpose is checked against the exchange response and persisted
against the Auth session ID, so a reload or refresh leads back to password reset.
A successful reset signs out before returning to Login. Cancel also signs out.
An invalid or interrupted callback stays outside the protected app. The SDK
uses browser storage on Web and SharedPreferences on Android.

Authenticated mode presents an integration-pending screen with **Keluar**.
It creates an empty account-scoped store and exposes no CRUD until the shared
repository is wired. The future repository must verify the active identity,
consume the canonical snapshot/RPC contract, reject results from disposed
scopes, and distinguish loading, empty, retry, and committed writes.
[Backend contract](BACKEND_CONTRACT.md#akses-dan-kontrak-repository)

## Manual Chrome and Android validation

Use designated disposable accounts on the JobTrail development project. Repeat
the applicable steps in Chrome and on Android using the commands above.

1. Start without a local session. Check Splash V2, Login, and the disabled
   Google action. Try an incorrect password, then sign in with an existing
   confirmed account. Verify the pending screen has no demo data or write controls.
2. Refresh Chrome or close and reopen Android. Check session restoration, then
   sign out and sign in with the second account. Check that Back does not reveal
   the prior protected screen. When a session expires without refresh, verify
   the protected screen closes. Leave hosted token settings as configured.
3. With authorized mail delivery, register a designated disposable address. If
   confirmation is required, open its message on the requesting platform. On
   Chrome check the exact localhost port and that the code leaves the URL. On
   Android check that the link opens JobTrail both from a stopped app and from
   an already-running app using separate valid links. Exercise resend only when
   the mailbox and rate limit permit it.
4. Request password recovery from Login. Open the fresh link and check that
   **Buat password baru** appears before any protected content, including after
   a reload. Submit a new password, confirm the return to Login, and sign in
   with the new password. Reusing or opening an expired link should show safe
   feedback. Test cancellation with a separate fresh link.

The automated suite uses fake session providers. Hosted sign-in, delivery,
callback handoff, device refresh, and recovery need separate manual results.

Current Figma splash source: V2 storyboard 602:8733, with Spark 602:8736, Trail 602:8774, Reveal 602:8812 and Ready 602:8850. V2 supersedes the earlier 586:* splash frames. The official curved-J/green-dot component 172:1877 is unchanged; the final hero is 148px wide at 393x852, with a 42px wordmark, violet halo/orbits, the official solid career curve, tracking dot and Discover / Apply / Grow progression. The old loading footer is removed. The stage keeps the 393:852 portrait ratio on small devices and wide desktop previews.

Official logo/envelope SVG sources remain under `docs/auth-assets/`, rasterized at 4x into `assets/home/auth-*.png`. V2's thirteen small official layers are preserved under `docs/auth-assets/splash-v2/` and rasterized transparently at 2x into `assets/home/splash-v2-*.png` (148,612 bytes total). Native Flutter interpolation follows the 0/.5/1.3/2.2-second storyboard anchors, then holds Ready. Figma returned no motion tracks for V2; easing between the supplied states is authored and not certified as exact prototype timing. No video or new package is used. See [V2 visual report](SPLASH_V2_REPORT.md).

Auth screen references remain Login 573:8618; Register 573:8645; Forgot 573:8668; Verify 573:8696; error/sent states 579:8671, 579:8707, 579:8743; new password 579:8768. Their layouts and forms are unchanged by the V2 revision.

Password fields disable suggestions, autocorrection and IME personalized learning; new passwords use the new-password autofill hint. Leaving the form cancels the autofill context so demo credentials are not offered for saving. Page changes clear passwords, reset visibility and start a separate scroll position. Loading and error feedback have accessibility labels/live regions. Preview badges and the reset preview title explicitly identify simulation.

Targeted tests use `flutter test test/backend_auth_test.dart test/auth_test.dart test/auth_audit_test.dart test/splash_v2_test.dart`.
Historical splash renders remain in [SPLASH_V2_REPORT](SPLASH_V2_REPORT.md).
