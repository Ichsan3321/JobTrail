# Frontend release

## Week 13 academic Web demo

The public HTTPS demo requires lead approval and a hosted smoke test. The demo
covers signed-in read flows. Connected Add/Edit and schedule writes remain gated
and this release leaves the existing CRUD controls in place. Use local debug
mock mode for a form or schedule write walkthrough. Public production is
**NO-GO**.

### Build and configuration

Use Flutter **3.47.9** with Dart **3.13.7** for this candidate. `pubspec.yaml`
requires Dart `^3.13.7`. Build a reviewed SHA with the committed `pubspec.lock`.
Use the existing `.env.jobtrail.example` as the template for an ignored JSON
file such as `.env.jobtrail.demo.json`. Dart defines are compiled into the
bundle. Changing the origin or configuration requires a rebuild. Include only
public client configuration and use a Supabase `sb_publishable_` key.

| Environment | Dart defines | Supabase Site URL and redirects |
| --- | --- | --- |
| Local debug mock | `JOBTRAIL_AUTH_MODE=mock` | None. The sample data entry is debug-only. |
| Local connected | `JOBTRAIL_AUTH_MODE=supabase`, `JOBTRAIL_SUPABASE_URL`, `JOBTRAIL_SUPABASE_PUBLISHABLE_KEY`, `JOBTRAIL_WEB_ORIGIN=http://localhost:3000`, `JOBTRAIL_GOOGLE_OAUTH_ENABLED=false` | Documented development Site URL `http://localhost:3000`. Allow `http://localhost:3000/?auth=confirm` and `http://localhost:3000/?auth=recovery`. |
| Hosted academic demo | Same connected defines with `JOBTRAIL_WEB_ORIGIN=https://<assigned-project>.pages.dev` and `JOBTRAIL_GOOGLE_OAUTH_ENABLED=false` | Owner adds exact `https://<assigned-project>.pages.dev/?auth=confirm` and `https://<assigned-project>.pages.dev/?auth=recovery`. Preserve the approved shared Site URL unless the owner explicitly designates the demo origin as the default fallback. Preserve existing approved local and Android entries. |
| Future public production | Dedicated approved backend and HTTPS origin, built separately. Google stays off unless independently approved. | Set Site URL to the canonical HTTPS origin. Allow the exact `/?auth=confirm` and `/?auth=recovery` URLs on that origin. Complete production sender setup and hosted security QA before release. |

The client passes explicit return URLs. `JOBTRAIL_WEB_ORIGIN` defaults to
`http://localhost:3000`, so check the final demo define before building. The
callback code matches scheme, host, port and root path and clears the URL after
handling. Verify email links honor the explicit return URLs. Complete each
PKCE flow in the same browser profile and origin where it started. Give each
approved preview its own build and exact allowlist entries if it needs auth QA.
Do not reuse the release bundle on a different preview origin. Keep Google off
and omit its callback for the demo. A separately approved Google rollout would
need `https://<approved-app-origin>/?auth=google` in Supabase and the Supabase
project's `/auth/v1/callback` in Google Cloud. See [Authentication](AUTH_UI.md)
and [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls).

### Approved deployment procedure

1. Confirm the reviewed release SHA, demo scope, team-controlled Cloudflare
   account, and designated release operator. Use **Cloudflare Pages Direct
   Upload** with the assigned `pages.dev` root hostname. Create a Direct Upload
   project with a production branch such as `demo-release` and record the
   exact hostname before building. Use the free provider hostname. See
   [Direct Upload](https://developers.cloudflare.com/pages/get-started/direct-upload/).
   Vercel is the fallback. If separately approved, use its assigned root HTTPS
   hostname and rebuild and verify the exact callbacks for that origin.
2. Have the Supabase owner approve the exact email return URLs above and record
   the current Site URL and signup policy. Use approved demo accounts. Gmail
   SMTP is suitable only for development and the academic demo. A public URL
   exposes the signup form. If backend signup is open, visitors can trigger
   confirmation emails and consume the shared Gmail and Supabase mail quotas.
   Review the approved signup policy and delivery limits before sharing.
3. From an isolated checkout of the approved SHA, set the ignored demo JSON
   from the table, then run the commands below. On Windows without plugin
   symlink support, setting `$env:FLUTTER_WINDOWS = 'false'` in the Web-only
   shell before `flutter pub get --offline` worked with a populated package
   cache. Use `--no-pub` for build/analyze/test only after dependencies are ready.

   ```powershell
   flutter pub get
   flutter analyze --no-pub
   flutter build web --release --no-pub --base-href / --no-web-resources-cdn --dart-define-from-file=.env.jobtrail.demo.json --output build/web-demo
   python -m http.server 4176 --bind 127.0.0.1 --directory build/web-demo
   ```

   Start the local server after the build succeeds to inspect the compiled files
   and startup. To check actual callbacks, use the configured HTTPS origin
   after publication. Use a separate build bound to the fixture origin for
   synthetic callback checks. The bundle includes
   fonts, images and CanvasKit. Keep the root path and retain all asset
   directories. Route names for Detail and Form are internal Navigator state.
   A reload starts at the app entry and restores the session when one exists.
4. Scan the exact outgoing artifact and record its file hashes, approved Git
   SHA, SDK version and build flags. Upload only `build/web-demo` using the
   Pages dashboard or `wrangler pages deploy build/web-demo --project-name
   <project> --branch demo-release`. Use a logged-in release operator and
   record the Wrangler version if using CLI. For callback requests, serve `/`
   while preserving the query. Use `Referrer-Policy: no-referrer` and browser
   cache revalidation for the unhashed app files. A Direct Upload staging
   folder can include a Pages `_headers` file with `/*`, `Cache-Control:
   no-cache`, and `Referrer-Policy: no-referrer`. Do not apply immutable cache
   headers to unhashed `index.html`, `flutter_bootstrap.js`, or `main.dart.js`.
   The tested Flutter SDK ships a self-cleaning service worker stub. Keep it
   in the build to retire legacy workers, and check that a fresh session has
   no active worker. See [Pages headers](https://developers.cloudflare.com/pages/configuration/headers/)
   and [Flutter Web FAQ](https://docs.flutter.dev/platform-integration/web/faq).
5. Before broad sharing, verify HTTPS, response headers and CanvasKit startup,
   root/query behavior, signed-out reload, email login with an approved account,
   the user snapshot, session restoration and logout. With separate approval
   for mail and account actions, verify fresh confirmation and password
   recovery on that same HTTPS origin. Capture outcomes without credentials,
   callback parameters or personal account details. Keep the local email QA
   evidence distinct from this hosted smoke test.

For rollback, retain the prior approved artifact and its deployment ID. Select
**Rollback to this deployment** on the last verified production deployment or
re-upload the retained artifact if the deployment is unavailable. On the first
release there is no previous deployment. Before launch, designate the owner
who can replace the canonical deployment with a static maintenance page, stop
sharing the URL, and check access to any preview or deployment URLs still in
circulation. Agree on an approved access restriction or takedown procedure if
those URLs must be disabled. Recheck the canonical hostname,
cache, auth and snapshot after rollback. Review Supabase settings separately
if they changed. See [Pages rollbacks](https://developers.cloudflare.com/pages/configuration/rollbacks/).

### Local readiness evidence

At `c2a44d06244a3ba1c0368ad3485d38e7e7c357fe`, Flutter analyze found zero
issues and 41 focused Auth tests passed. Three root-path release builds passed
with bundled CanvasKit. Headless Chrome loaded the static files, stayed on the
configuration error after reload with missing backend values, and showed the
signed-out UI with a synthetic backend configuration. Synthetic confirmation
and recovery errors cleared the query and stayed signed out after reload.
Explicit release mock also stayed at Login. The fresh browser had no active
service worker. No live code exchange, hosted account session or hosted email
delivery was exercised during this pass.

## Historical Week 12 frontend integration checklist

Status: **review**, bukan rilis production/backend.

- [x] Tujuh screen frontend terhubung ke satu store demo in-memory dan navigasi bersama.
- [x] Lamaran, agenda dan metadata dokumen memakai relasi ID serta perubahan state reaktif; statistik dihitung dari store.
- [x] Clock UTC/WIB bersama, filter jadwal terkait, pratinjau dokumen, aksesibilitas dasar dan smoke/responsive widget tests tersedia.
- [x] Baseline dilaporkan: analyzer bersih, 187 tests lulus, diff check lulus; rincian dan batas bukti di [QA](QA.md).
- [x] Project lead melaporkan pemeriksaan Chrome terbatas pada Board dan Statistik di 393 x 852 dan 320 x 640.
- [ ] Reviewer memeriksa perubahan, hasil verifikasi terkini dan konflik dengan `develop`; project lead menyetujui merge.
- [ ] Sepakati risiko QA tersisa sebelum merge: browser ter-render tujuh screen belum lengkap, Android runtime dan screen reader belum diuji, serta overflow Board historis belum terbukti hilang untuk semua kondisi.
- [ ] Konfirmasi kebutuhan bukti Week 12 dan hasil review PIC terkait; jangan menganggap pemeriksaan Figma selektif sebagai sign-off visual lengkap.

Data hilang saat restart; dokumen hanya metadata; notifikasi lokal/demo. Autentikasi, Supabase/backend, penyimpanan, upload dan push notification nyata adalah fase berikutnya, memerlukan keputusan/approval terpisah.

## Draft PR

**Base:** `develop`
**Compare:** `integration/frontend`
**Title:** Integrate seven JobTrail frontend screens

### Description

Integrate Home, Board, Detail, Add/Edit, Schedule, Documents and Statistics around a shared in-memory store and ID-based navigation. Includes the shared demo clock, related schedule and document preview flows, header and accessibility corrections, and responsive regression fixes.

Validation: `flutter analyze`, `flutter test` (187 passed on 20 November 2026 at HEAD 46967a2) and `git diff --check`. Project lead manually checked Board and Statistics in Chrome at 393 x 852 and 320 x 640, including Board resize/filter scrolling and vertical scrolling. The earlier intermittent Board summary overflow did not recur in those checks.

This is a frontend demo: data is not persisted, document previews are metadata only, and no backend/Supabase is integrated. Full seven-screen rendered browser QA, Android runtime and device screen-reader QA remain outstanding.

Reviewer checklist:

- [ ] Review shared store, ID navigation, clock and cross-screen update behavior.
- [ ] Review responsive/accessibility changes and outstanding QA risks.
- [ ] Confirm current analyzer/test results and approve integration into `develop`.
