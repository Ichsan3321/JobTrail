# Cinematic Splash V2 — visual revision

20 November 2026 · `C:\JobTrail` · `feature/auth` · local, uncommitted changes.

Implemented from the [updated V2 Figma storyboard](https://www.figma.com/design/292w6TVRmn1YCYbVXuRNp5/JobTrail?node-id=602-8733), inspected before editing. The earlier V1 frames are not the visual target for this revision.

## Result

The official curved-J mark with green dot now reaches **148 logical pixels** at the 393x852 reference viewport, up from 98px. The wordmark is 42px, up from 36px. Large violet halos and two orbits surround the hero; the solid violet-to-mint career curve is visible beneath it, with a green tracking dot following that curve. The Discover / Apply / Grow panel replaces the old generic loading footer.

One native AnimationController drives synchronized size, position, opacity, halo visibility, tracking and progression. It reaches Ready at 2.2 seconds, holds until 2.65 seconds, then fades into Login over 220ms: **2.87 seconds nominal total** when session restoration is already resolved. Reduced motion skips both the sequence and transition.

| Stage | Figma node | Time | Logo size / top at 393x852 |
|---|---|---|---|
| Ignite / Spark | 602:8736 | 0s | 52px / 269px; 28% opacity |
| Career trail | 602:8774 | .5s | 92px / 245px; 95% opacity |
| Full brand reveal | 602:8812 | 1.3s | 148px / 223px |
| Final branded frame | 602:8850 | 2.2s | 148px / 217px |

## Rendered screenshots

These are actual Chrome renders. Figma exports are labeled separately and were not used as full-screen implementation images.

| Stage | Figma V2 reference | Flutter 393x852 | Flutter 320x640 |
|---|---|---|---|
| Initial logo | [Figma](qa/splash-v2/figma-ignite.png) | [Ignite](qa/splash-v2/ignite-393x852.png) | [Ignite](qa/splash-v2/ignite-320x640.png) |
| Career trail | [Figma](qa/splash-v2/figma-trail.png) | [Trail](qa/splash-v2/trail-393x852.png) | [Trail](qa/splash-v2/trail-320x640.png) |
| Full brand reveal | [Figma](qa/splash-v2/figma-reveal.png) | [Reveal](qa/splash-v2/reveal-393x852.png) | [Reveal](qa/splash-v2/reveal-320x640.png) |
| Ready | [Figma](qa/splash-v2/figma-ready.png) | [Ready](qa/splash-v2/ready-393x852.png) | [Ready](qa/splash-v2/ready-320x640.png) |
| Live fade to Login | — | [Transition](qa/splash-v2/transition-393x852.png) | [Transition](qa/splash-v2/transition-320x640.png) |
| Signed-out destination | — | [Login](qa/splash-v2/login-393x852.png) | [Login](qa/splash-v2/login-320x640.png) |
| Reduced motion toggled during startup | — | [Login, no fade](qa/splash-v2/reduced-motion-393x852.png) | [Login, no fade](qa/splash-v2/reduced-motion-320x640.png) |

[Wide desktop preview, 1280x1000](qa/splash-v2/ready-desktop-1280x1000.png) confirms that the 393x852 stage stays centered and does not stretch across the desktop. At 320x640 the stage uniformly scales to approximately 295x640, with narrow dark side gutters, preserving the complete portrait composition. The hero is approximately 111px wide there, retaining its proportion to the canvas.

**Capture method:** exact storyboard images use an isolated release QA host of the production `SplashV2Scene` at fixed timeline times. The host does not reimplement the artwork. Separately, the actual `lib/main.dart` release entrypoint ran through the opening at both sizes; live compositor captures recorded the cross-fade and final signed-out Login. Both types of evidence were visually inspected. Fixed-stage captures are not presented as live animation timestamps. No manual human/device QA is claimed.

The screenshot harness initially missed the fade because its standard screenshot path waited for Login fonts. Direct compositor capture recorded the real transition without that wait. The final browser run recorded **zero page/console errors**. [Machine-readable evidence](qa/splash-v2/evidence.json) records stage times, live capture offsets and preservation checks.

## Differences from Figma and remaining limits

- The four storyboard states and official artwork guide the implementation. Figma's recursive motion query for 602:8733 returned `nodes: []`; native easing between states is authored (ease-out/ease-in-out cubic), not a verified export of prototype transition settings.
- The wordmark, tagline and footer use the existing Plus Jakarta Sans font, as shown in V2. Browser/Flutter font metrics leave small baseline/ink-position differences. The top eyebrow uses letter spacing rather than literal spaces between every letter.
- The progression labels use a flexible row, with slightly different horizontal spacing from Figma's absolute text positions. This keeps the panel balanced and avoids overlap when text scaling increases. The panel and stage progress geometry follow V2.
- The tracking dot follows arc-length samples of the official curve. Its center is about 2–3px from the marker centers in the Trail/Reveal storyboards, where the Figma marker sits slightly above the curve. The curve artwork itself is unchanged.
- Small source layers are transparent raster exports at 2x, animated with native transforms/opacity. Orbit stroke thickness therefore scales during expansion; this is not a pixel-identical vector stroke animation. No video, blur-heavy effect or package was added.
- Android hardware, TalkBack/VoiceOver, GPU frame-time profiling and exact Figma prototype timing remain unverified. Chrome renders and widget tests do not establish those results.

## Preserved behavior and changed files

`app.dart`, `main.dart`, `AuthProvider`, `AuthBrand`, `pubspec.yaml` and `pubspec.lock` have identical hashes to the start of this revision. The complete `AuthScreen` class is also unchanged: Login, Register, Forgot Password, Verify Email and password-reset form logic/layouts were not edited.

The only auth-gate change is the direct splash transition. A session invalidation replaces the transition container immediately, removing Home without leaving a fading protected screen. Incoming/outgoing transition content cannot receive taps; outgoing semantics are excluded. Signed-out startup, session checks, debug-only Home preview, disabled Google and existing security protections remain covered by tests.

Files changed by this revision:

- `lib/screens/auth/cinematic_splash.dart`: V2 timeline and production scene; portrait framing; official layers and tracking curve.
- `lib/screens/auth/auth_screen.dart`: AuthGate fade and immediate session-invalidation behavior only.
- `test/auth_audit_test.dart`: existing storyboard anchor assertion updated from V1 to V2.
- `test/splash_v2_test.dart`: 10 new tests covering mobile/desktop framing at 1x/2x text, logo proportions, tracking positions, fade timing, immediate removal of invalidated Home and enabling reduced motion during startup without delaying Login input.
- `assets/home/splash-v2-*.png`: 13 small layers, **148,612 bytes total**. `docs/auth-assets/splash-v2/*.svg` preserves the official sources. The obsolete V1 runtime career-path PNG was removed; its source remains in the earlier audit assets.
- `docs/AUTH_UI.md`, this report and `docs/qa/splash-v2/`: current behavior, reference/capture images and evidence.

## Verification

| Check | Result |
|---|---|
| `flutter analyze` | PASS — no issues |
| `flutter test` | PASS — **223 tests**, zero failures/skips; all prior 213 plus 10 V2 tests |
| `flutter build web --release` | PASS — actual `lib/main.dart` entrypoint built to `build/web`; Wasm dry run succeeded, not a Wasm runtime test |
| `git diff --check` | PASS |
| Chrome visual QA | PASS for the recorded V2 stages, both mobile sizes, live transition/Login and desktop framing |

No Supabase, OAuth, real authentication, dependency installation, commit, push, merge, PR creation or branch switch was performed. Preview servers used only localhost and were stopped after QA.
