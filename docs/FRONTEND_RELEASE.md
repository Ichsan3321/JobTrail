# Checklist kandidat integrasi frontend Week 12

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
