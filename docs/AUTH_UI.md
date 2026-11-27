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
configuration only. `JOBTRAIL_GOOGLE_OAUTH_ENABLED` defaults to `false`.
For a local UI demo without Supabase use
`flutter run -d chrome --web-hostname=localhost --web-port=3000 --dart-define=JOBTRAIL_AUTH_MODE=mock`.
Only debug mock mode offers the labeled demo Home and preview actions.
If Windows desktop plugin symlinks block SDK commands on a machine targeting
only Web or Android, set `$env:FLUTTER_WINDOWS = 'false'` in that PowerShell session.

## Required dashboard settings

The project owner configures **Authentication → URL Configuration** manually.
`http://localhost:3000` is the documented local development Site URL. Keep the
project's existing approved Site URL, origins, and email settings when adding
Google. The app passes its own explicit return URL. The exact development
confirmation and recovery entries are below.

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

## Google OAuth setup for the project lead

1. In Google Cloud Console, select the team-owned JobTrail development project
   or create one under the team's approved account. Open **Google Auth Platform**
   and select **Get started** if this is the first setup. In **Branding**, set
   the app name to `JobTrail`, choose a team-controlled support email, and enter
   a developer contact email. Use the official JobTrail logo if branding uses
   one. Use team-owned URLs if the console requires app links. [Google Auth Platform setup](https://support.google.com/cloud/answer/15544987?hl=en) · [Branding](https://support.google.com/cloud/answer/15549049?hl=en)
2. Choose **External** under **Audience**, keep publishing status at **Testing**,
   and record the lead-approved QA account. Add it under **Test users** if needed.
   Google documents an exception to test-list enforcement for basic identity
   scopes, so use the approved account for QA regardless of that list. In
   **Data Access**, allow only `openid`, `userinfo.email`, and `userinfo.profile`.
   Supabase requests `email` and `profile` by default, and JobTrail adds `openid`.
   [Google audience rules](https://support.google.com/cloud/answer/15549945?hl=en) · [Supabase Google scopes](https://supabase.com/docs/guides/auth/social-sign-in/auth-google)
3. Open **Clients → Create client**, select **Web application**, and name it
   `JobTrail Web (Development)`. Add `http://localhost:3000` under **Authorized
   JavaScript origins**. Add `https://ehzdmsdhdlqmicmwbnwh.supabase.co/auth/v1/callback`
   under **Authorized redirect URIs** and create the client. [Google Web OAuth client setup](https://developers.google.com/identity/protocols/oauth2/web-server) · [Supabase Google setup](https://supabase.com/docs/guides/auth/social-sign-in/auth-google)
4. In the Supabase Dashboard for project `ehzdmsdhdlqmicmwbnwh`, open
   **Authentication → Sign In / Providers → Google**. Compare the displayed
   callback with the URI in step 3, enable Google, enter the Web Client ID and
   Client Secret, and save. Enter the Client Secret only in the Supabase Google
   provider configuration. Keep the defaults for nonce and email verification.
   Keep the existing project signup policy. A first-time Google sign-in may
   create an Auth user if signups are permitted. [Supabase Google provider setup](https://supabase.com/docs/guides/auth/social-sign-in/auth-google)
5. Under **Authentication → URL Configuration → Redirect URLs**, add exactly
   `http://localhost:3000/?auth=google`. Verify that the existing email
   confirmation and recovery URLs above remain present and that the Site URL
   retains its approved value. The Google callback in step 3 belongs in Google
   Cloud, and the localhost callback belongs in the Supabase allowlist.
   `127.0.0.1` and other ports are different origins. [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
6. After configuration, set `"JOBTRAIL_GOOGLE_OAUTH_ENABLED": true` and
   `"JOBTRAIL_WEB_ORIGIN": "http://localhost:3000"` in the ignored local
   `.env.jobtrail.json`. Restart Flutter with the Web command above. The action
   is available only in Supabase mode on Web when the browser origin matches.

### Hosted Google QA

Run after the lead approves the Google test account and any hosted Auth user
creation. Use Chrome on `http://localhost:3000` in one browser profile for the
entire PKCE flow.

1. Start signed out, click **Lanjutkan dengan Google**, and verify the account
   chooser and basic identity permissions on Google's consent screen when shown.
   Cancel once and verify that Login can start again. Closing the tab or using
   browser Back may yield no callback. Reopen the localhost app in that case.
2. Sign in with the approved account. Verify the return to localhost, the clean
   URL after callback handling, and an authenticated Supabase session by checking
   the expected account identity and a loaded dashboard. For a new account,
   verify the empty snapshot. Record outcomes without copying any session data.
3. Reload and verify the same account and snapshot. Open the profile sheet and
   confirm **Keluar**. Verify that Login returns and browser Back or reload
   cannot restore the signed-out dashboard.
4. Sign in as a second approved account with a distinct email address. An
   existing approved email/password account can serve as that second account.
   Compare identities and existing data or empty states, and verify that the
   previous account's data is absent. Use the fake-repository tests for
   distinguishable snapshot markers when both hosted accounts are empty.

### Android follow-up

The Android manifest registers `com.example.jobtrail://auth/confirm` and
`com.example.jobtrail://auth/recovery` through `app_links`. Google remains gated
to Web. Before enabling Android, choose and register a dedicated callback such
as `com.example.jobtrail://auth/google` in the manifest and Supabase allowlist,
extend the platform gate, and validate PKCE return from an external browser both
when the app is running and after a cold start. Review verified Android App Links
before a production rollout. The Supabase-mediated browser flow still returns
from Google through the project's HTTPS callback. [Supabase Android deep linking](https://supabase.com/docs/guides/auth/native-mobile-deep-linking?os=android&platform=flutter&queryGroups=os&queryGroups=platform)

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
history. The same-tab Google launch requests an account chooser. Its result
enters through the shared session controller and only opens the dashboard after
the SDK establishes a session. Recovery purpose is checked against the exchange
response and persisted against the Auth session ID, so a reload or refresh leads
back to password reset.
A successful reset signs out before returning to Login. Cancel also signs out.
An invalid or interrupted callback stays outside the protected app. The SDK
uses browser storage on Web and SharedPreferences on Android.

Authenticated mode loads `jobtrail_load_snapshot` into a fresh account store.
Loading and error views provide **Keluar** and errors allow retry. Once loaded,
the five-tab AppShell displays each screen's own empty state. The Home avatar
opens the account sheet with the authenticated identity, connection status, and
refresh. Signing out from this sheet requires confirmation. The same Supabase
client captures the
request's bearer token and checks account and session before publishing results.
Mutations stay gated in the UI pending screen integration.
[Backend contract](BACKEND_CONTRACT.md) · [Team handoff](PERSISTENCE_HANDOFF.md)

## Manual Chrome and Android validation

Use designated disposable accounts on the JobTrail development project. Repeat
the applicable steps in Chrome and on Android using the commands above.

1. With Google kept off for this regression, start without a local session.
   Check Splash V2, Login, and the disabled Google action. Try an incorrect
   password, then sign in with an existing
   confirmed account. Check snapshot loading, the five tabs, and read-only controls.
   Use only designated test records already present in the account.
2. Refresh Chrome or close and reopen Android, and check snapshot restoration.
   Open the Home avatar and verify the account email and display name, then try
   **Muat ulang data**. Choose **Keluar**, test **Batal**, and confirm logout
   before entering the second account. Check its snapshot or empty state and that Back cannot reveal
   the first account's screens. Simulate a snapshot network failure with Chrome
   DevTools and retry once online. Verify expiry closes the protected screen
   when the existing session expires without refresh. Keep hosted settings unchanged.
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

### Gmail SMTP development QA

On 27 November 2026, the project lead verified the email flow in Chrome at
`http://localhost:3000` against development build `53f23b8`. Registration,
initial and resend confirmation delivery, Supabase email verification, and
password login passed. Recovery email delivery, the localhost recovery return,
password reset, old-password rejection, and login with the updated password
passed. Refresh restored the session. A fresh signup confirmation also opened
the authenticated dashboard. These results cover the localhost flow with actual
email delivery. The exact link redirect chain was not recorded.

Gmail SMTP is for development and demos. Production requires an approved
transactional sender on a verified domain, exact HTTPS callback allowlists, and
confirmation and recovery QA on the deployed origin. [Gmail sending limits](https://support.google.com/mail/answer/22839?hl=en) · [Supabase production checklist](https://supabase.com/docs/guides/deployment/going-into-prod)

Current Figma splash source: V2 storyboard 602:8733, with Spark 602:8736, Trail 602:8774, Reveal 602:8812 and Ready 602:8850. V2 supersedes the earlier 586:* splash frames. The official curved-J/green-dot component 172:1877 is unchanged; the final hero is 148px wide at 393x852, with a 42px wordmark, violet halo/orbits, the official solid career curve, tracking dot and Discover / Apply / Grow progression. The old loading footer is removed. The stage keeps the 393:852 portrait ratio on small devices and wide desktop previews.

Official logo/envelope SVG sources remain under `docs/auth-assets/`, rasterized at 4x into `assets/home/auth-*.png`. V2's thirteen small official layers are preserved under `docs/auth-assets/splash-v2/` and rasterized transparently at 2x into `assets/home/splash-v2-*.png` (148,612 bytes total). Native Flutter interpolation follows the 0/.5/1.3/2.2-second storyboard anchors, then holds Ready. Figma returned no motion tracks for V2; easing between the supplied states is authored and not certified as exact prototype timing. No video or new package is used. See [V2 visual report](SPLASH_V2_REPORT.md).

Auth screen references remain Login 573:8618; Register 573:8645; Forgot 573:8668; Verify 573:8696; error/sent states 579:8671, 579:8707, 579:8743; new password 579:8768. Their layouts and forms are unchanged by the V2 revision.

Password fields disable suggestions, autocorrection and IME personalized learning; new passwords use the new-password autofill hint. Leaving the form cancels the autofill context so demo credentials are not offered for saving. Page changes clear passwords, reset visibility and start a separate scroll position. Loading and error feedback have accessibility labels/live regions. Preview badges and the reset preview title explicitly identify simulation.

Targeted tests use `flutter test test/backend_auth_test.dart test/auth_test.dart test/auth_audit_test.dart test/splash_v2_test.dart`.
Historical splash renders remain in [SPLASH_V2_REPORT](SPLASH_V2_REPORT.md).
