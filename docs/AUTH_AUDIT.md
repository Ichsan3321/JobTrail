# Auth UI audit — 20 November 2026

Repository `C:\JobTrail`, branch `feature/auth`, baseline HEAD `7fa8c23`. Local, uncommitted audit and fixes; no branch switch, commit, push, deployment or PR creation. Scope is the authentication UI and a simulated frontend, with no real authentication or Supabase integration.

**Recommendation: READY FOR PR for this UI-only scope.** This is not production authentication approval or a complete Figma pixel/prototype sign-off. The specific unverified areas below remain visible for reviewers.

## Results by audit area

| Area | Result | Evidence / boundary |
|---|---|---|
| 1. Diff and requested source review | PASS | Reviewed the tracked diff, new `screens/auth` files, `app.dart`, `main.dart`, `auth_test.dart`, AUTH_UI and repository contracts. Existing tracked test edits only select the debug shell harness or format code; assertions were not removed. |
| 2. Architecture and lifecycle | PASS | One production MaterialApp and root navigator. Existing store/navigation ownership preserved. Controllers and splash ticker dispose; async UI updates check mounted. Provider replacement invalidates stale session checks. Tests cover disposal during restore and sign-in. |
| 3. Official splash branding and storyboard | PASS | Official curved-J/green-dot component 172:1877 replaces the older J reconstruction in auth only. Official SVGs are rasterized transparently; source files retained. Logo size/top coordinates are tested at .4/1.2/2.1 seconds. Release screenshots show the sequence with unobstructed rings/path. |
| 3. Exact Figma animation/prototype easing | NOT VERIFIED | Figma motion-context query for 586:8721 returned `nodes: []`. The four storyboard frames were inspected, but interpolation/easing cannot be certified against a published animation track. |
| 3. Reduced motion | PASS | Immediate reduced-motion startup and toggling the preference during the splash are tested, including exactly one completion. Browser reduced-motion startup also reaches Login. |
| 4. Startup/session abstraction | PASS | Default provider restores signed out. Pending/failed/timed-out checks stay gated; retry, stale results and restored sessions are tested. Sign-in completion alone no longer opens Home: restoreSession must confirm a session. Future backend/security work remains separate. |
| 5. Six auth layouts/navigation | PASS | Login, Register, Forgot Password, Verify Email, Reset Email Sent preview and Set New Password preview exercised in widgets and rendered Chrome at both sizes. Return-to-Login and selected system Back paths are tested. Long pages intentionally scroll. |
| 5. Complete Figma pixel fidelity | NOT VERIFIED | Core hierarchy and official assets reviewed. Repository GSM keeps Poppins for auth headings (24px); inspected auth Figma uses Plus Jakarta Sans (27px). Disabled Google, visibility controls and explicit demo disclosures are intentional scope/accessibility differences. Design-owner sign-off remains separate. |
| 6. Inputs, states and touch targets | PASS | Required/invalid email/blank name/short password/mismatch cases; email/name trimming with password whitespace preserved; independent obscure toggles; password clearing; loading, duplicate suppression, timeout/retry and sanitized error text. All six pages pass Android tap-target and labeled-target guidelines in the responsive matrix. |
| 6. Native keyboard/screen reader | NOT VERIFIED | Keyboard focus plus a 280px inset is simulated in widget tests. No claim of an actual Android keyboard, TalkBack or VoiceOver session. |
| 7. 393x852 / 320x640 responsiveness | PASS | All six pages at both sizes, 1x/2x text, keyboard inset and reachable primary action. Chrome captures at both sizes, with no recorded browser runtime errors. DOM width checks supplement, but do not replace, Flutter overflow assertions. |
| 8. Development Home bypass | PASS | Debug-only button is explicitly labeled. `showAuthentication:false` is also debug-only: profile/release force the gate. A separately compiled release fixture deliberately passed false and still rendered Login with no demo/preview controls. |
| 9. Google and truthful UI | PASS | Google button remains disabled. Default provider rejects every account operation. Verify/reset previews do not call the provider; they have preview badges/disclosures. Reset preview heading no longer says a link was actually sent. |
| 10. S01–S07 and shared navigation | PASS | All 187 prior frontend/state regressions still pass; source under the seven existing screens, shared shell, routes, store and theme is unchanged. Auth also enters the existing Home through a confirmed fake session in tests. This is automated regression evidence, not fresh native-device sign-off for all seven screens. |
| 11. Dependencies/secrets/placeholders | PASS | No pubspec/lockfile changes or new dependencies. No production credentials, token persistence, credential logging or network auth client in the new UI. Synthetic credentials occur only in tests. Existing unused `cupertino_icons` is a pre-existing cleanup candidate and was left unchanged. Unavailable-provider and preview states are explicit. |
| 12. Test quality | PASS | Baseline reproduced: 195 passed (187 prior + 8 initial auth). Identified weak retry, visibility and reduced-motion claims in initial tests. Added 18 focused regressions that check actual behavior rather than relying on the count. Final: 213 passed, zero failures/skips. |
| 13. Rendered QA | PASS | Actual local Chrome screenshots inspected for all six pages at both sizes and for the release splash sequence. Browser errors array empty in final run. No Android/device or manual human QA is claimed. |

## Issues fixed

1. **Release bypass:** the public shell-harness flag could skip auth in any build. It now works only in debug; release was tested with a deliberate false flag.
2. **Session routing:** successful completion of a void sign-in method opened Home without checking a session. A subsequent session check is now required. Pending account operations have timeouts; replacement providers cannot apply stale restore results.
3. **Brand/splash defects:** the older reconstructed J differed from current Figma. Splash geometry and reveal phases did not follow the storyboard, and the bottom glow was absent. Official assets and phase anchors now drive the scene. Rendered QA additionally caught opaque backgrounds in Figma PNG exports, fixed by rasterizing their official transparent SVG sources.
4. **Input handling:** password fields allowed IME learning and used existing-password hints on registration/reset. Added appropriate hints, disabled learning, canceled autofill saving on form disposal, and supported Done submission and keyboard dismissal. Page changes reset password visibility and scroll identity.
5. **Truthfulness/accessibility:** reset previews could display an unqualified sent heading. Preview title/badges now identify simulation, with the disclosure above the brand. Loading feedback has a semantic label/live region. Error details remain sanitized.
6. **Coverage:** added timeout/retry/late-result, provider replacement, verified-session login, disposal, sanitized failures, independent obscuring, backend-free preview, immediate/dynamic reduced motion, storyboard anchors and full viewport/text/keyboard/touch-target coverage.

## Final checks

| Command | Result |
|---|---|
| `flutter analyze` | PASS — no issues |
| `flutter test` (JSON reporter used for counting) | PASS — **213 tests**, zero failures/skips; 187 prior regressions + 26 auth |
| `flutter build web --release` | PASS — `build/web`, actual `lib/main.dart` entrypoint; Wasm dry run succeeded (not a Wasm runtime test) |
| `git diff --check` | PASS — only Git's LF/CRLF conversion advisories |
| `git status -sb` | `feature/auth`; changes remain local/uncommitted |

The extra release probe used an ignored `.buildlog/auth_release_probe.dart` containing `runApp(const JobTrailApp(showAuthentication: false))`, built with `flutter build web --release --target .buildlog/auth_release_probe.dart --output build/auth-release-probe`. It is an isolated audit fixture, not the shipped entrypoint. Browser tools came from the already-installed Playwright runtime; no project package was installed.

## Evidence and limits

[Machine-readable results](qa/auth-audit-evidence.json) include per-file test counts, browser checks and screenshot sampling offsets. Screenshot offsets start when the browser exposes Flutter's accessibility placeholder; they are **not** exact animation timestamps. Exact phase geometry is covered separately by widget tests.

- Release splash: [trace/reveal sample](qa/auth-splash-sample-2.png), [reveal sample](qa/auth-splash-sample-4.png), [ready sample](qa/auth-splash-sample-7.png).
- Login: [393x852](qa/auth-login-393x852.png), [320x640](qa/auth-login-320x640.png).
- Register: [393x852](qa/auth-register-393x852.png), [320x640](qa/auth-register-320x640.png).
- Forgot Password: [393x852](qa/auth-forgot-393x852.png), [320x640](qa/auth-forgot-320x640.png).
- Verify Email preview: [393x852](qa/auth-verify-393x852.png), [320x640](qa/auth-verify-320x640.png).
- Reset Email Sent preview: [393x852](qa/auth-sent-393x852.png), [320x640](qa/auth-sent-320x640.png).
- Set New Password preview: [393x852](qa/auth-reset-393x852.png), [320x640](qa/auth-reset-320x640.png).
- [Release bypass probe](qa/auth-release-bypass-probe.png), [reduced-motion release](qa/auth-reduced-motion-release.png); validation/error captures are also in `docs/qa/auth-*.png`.

Preview captures use a debug build; release intentionally cannot enter these development previews. Narrow screenshots show the top viewport, not the entire scrollable page. Navigation/primary-action reachability was exercised separately.

No real auth, account/email delivery, persistence, verified recovery token, auth-state subscription, logout or server authorization exists. Before integrating a provider, define revocation/session expiry, clearing protected routes/data, operation cancellation, recovery-session validation, delivery semantics, secure storage and real-device accessibility. UI timeout does not cancel a provider's late side effect. Profile guard behavior is evident in `kDebugMode` gating but was not separately executed as a profile build. No Android device was connected; Chrome is the rendered platform actually tested.
