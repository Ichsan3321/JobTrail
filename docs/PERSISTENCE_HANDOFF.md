# Handoff persistensi JobTrail

Fondasi berada di branch `feature/backend-persistence`. Semua layar membaca satu
`JobTrailStore` dan satu snapshot akun. AppShell, lima tab, pencarian, filter,
detail dan pratinjau metadata berfungsi sebagai alur baca backend. Tombol tulis
masih dinonaktifkan sampai integrasi tiap layar lulus. CRUD demo tetap tersedia
dengan konfigurasi mock.

## Kontrak untuk pemilik layar

- Ambil entity, riwayat, agenda, dan dokumen melalui lookup atau koleksi immutable
  pada store. Gunakan `referenceDate` sebagai tanggal sipil WIB,
  `referenceInstantUtc` sebagai batas waktu agenda, dan `weeklyGoal.target == 8`.
- Tangkap `applicationRevision(id)` ketika membuka draft/status/hapus. Saat submit
  kirim revisi itu ke metode remote. Jangan menggantinya secara otomatis dengan
  revisi terbaru. Saat konflik, pertahankan draft dan tampilkan perubahan server.
- Buat `ApplicationCreation(draft)` sekali untuk intent tambah. Untuk agenda dan
  dokumen, gunakan `nextAgendaId()` / `nextDocumentId()` sekali dan pertahankan
  model immutable yang sama selama retry create yang ambigu. Gunakan
  `SaveMode.create` atau `SaveMode.update` secara eksplisit. Server memeriksa
  idempotensi create dan relasi pemilik. Bila create dipastikan telah dihapus,
  gunakan intent baru jika pengguna memilih membuat ulang.
- Tunggu `CommittedMutation.receipt` sebelum mengumumkan simpan. Jika
  `snapshotCurrent == false`, jelaskan commit diterima dan ulangi `refresh()`.
  Buka detail/Board berdasarkan ID hanya setelah record ditemukan di snapshot.
  Jika `RepositoryFailure.writeOutcomeUnknown`, hasil write belum terkonfirmasi.
  Baca snapshot sebelum retry update/delete. Render error melalui
  `RepositoryIssue.message`, dan gunakan `isMutating` untuk mencegah tap ganda.
- Setelah await, cek `mounted` serta kepemilikan route sebelum
  `Navigator.pop` atau `ScaffoldMessenger`. Identity gate menghancurkan Navigator
  terlindungi saat logout, pemulihan, kedaluwarsa, atau pergantian akun.

**File bersama yang memerlukan persetujuan lead** meliputi `lib/app.dart`,
`lib/main.dart`, `lib/data/jobtrail_*.dart`, `lib/data/supabase_jobtrail_repository.dart`,
`lib/models/`, `lib/core/routes/app_navigation.dart`,
`lib/core/constants/app_dates.dart`, `lib/widgets/app_shell.dart` dan Auth.
Ajukan perubahan kontrak sebelum mengubahnya. Setiap anggota mengerjakan file
layar sendiri serta tes. Semua branch saran dibuat dari basis foundation yang
sudah direview. Tidak ada SDK client, query tabel atau store kedua di layar.

| Pemilik dan branch saran | File dan API | Integrasi, dependensi, dan penerimaan |
|---|---|---|
| **Ichsan · S01** · `feature/persistence-home` | `lib/screens/home/home_screen.dart`, `lib/widgets/app_shell.dart` · applications, agendas, reference, `weeklyAchieved`, `refresh()` | Pemilik shared integration. Tampilkan status refresh/empty/error dan jaga target 8. Tombol tambah menunggu S04. Tes Home dan Statistik dari snapshot sama serta logout saat refresh. Manual: buka akun kosong dan akun berisi fixture, refresh, lihat konsistensi Board/Jadwal. |
| **Hanif · S02** · `feature/persistence-board` | `lib/screens/board/board_screen.dart`, `board_sheets.dart` · `applicationById`, `agendasFor`, `changeStatusRemote` | Pertahankan filter, urutan dan preview. Integrasikan revision/form state untuk status; dependensi S03 Detail/S04 Add. Tes stale revision, status sama tanpa duplikasi history, dan tap ganda. Manual: preview lalu Detail, cek status hasil rekonsiliasi di Home/Statistik bila uji write sudah diotorisasi. |
| **Lenno · S03** · `feature/persistence-detail` | `lib/screens/detail/application_detail_screen.dart` · `historyFor`, `agendasFor`, `changeStatusRemote`, `deleteApplicationRemote` | Gunakan ID dan event order dari snapshot. Tampilan relasi memakai metadata S06. Aksi edit/agenda bergantung S04/S05. Tes history bertimestamp sama, konflik, delete gagal dan detail ID hilang. Manual: cek agenda terkait, preview dokumen dan Back. Uji cascade dengan fixture khusus setelah otorisasi. |
| **Rifqi · S04** · `feature/persistence-application-form` | `lib/screens/application_form/application_form_screen.dart` · `ApplicationCreation`, `createApplicationRemote`, `updateApplicationRemote`, `applicationRevision` | Pertahankan kedua label sumber, null salary, semua documentIds, dan dirty cancel. Koordinasikan `AppNavigation` dengan lead dan Board S02. W13-02 memakai ID receipt dan `finishForm(id)` setelah snapshot memuat record. Tes timeout/replay dengan ID dan payload identik, konflik draft, serta Add→Board dan Edit→Detail. Manual: review draft, batal, dan verifikasi Edit mempertahankan ID pada akun uji bila write diotorisasi. |
| **Fachriza · S05** · `feature/persistence-schedule` | `lib/screens/schedule/schedule_screen.dart`, `add_agenda_sheet.dart` · `agendasFor`, `nextAgendaId`, `saveAgendaRemote`, `deleteAgendaRemote` | Integrasikan tambah terlebih dahulu, edit/hapus hanya dengan UI yang benar. Jaga relasi lamaran dan tanggal WIB. Dependensi S03 untuk agenda scoping. Tes tanggal lintas UTC/WIB, ID stabil, missing parent dan reload. Manual: cek filter/minggu serta agenda dari Detail, konfirmasi metadata server bila write diotorisasi. |
| **Farhad · S06** · `feature/persistence-documents` | `lib/screens/documents/documents_screen.dart`, `document_preview_sheet.dart` · `documentById`, `nextDocumentId`, `saveDocumentRemote`, `deleteDocumentRemote` | Metadata saja, timestamp dari server. Pelihara tautan S03/S04 dan tampilkan dokumen masih dipakai. Backlog **Document Draft Protection** mencakup Back, dismiss modal, navigasi, dan refresh ketika draft berubah. Tes cancel/proteksi draft, replay, serta konflik dokumen tertaut. Manual: preview metadata, cek relasi, dan uji edit/hapus fixture jika write diotorisasi. |
| **Ziyaad · S07** · `feature/persistence-statistics` | `lib/screens/statistics/statistics_screen.dart` · `applicationsInPeriod`, `distribution`, `history`, `referenceDate`, weekly goal | Statistik sudah dapat membaca snapshot. Selaraskan periode/denominator dengan Ichsan dan history dengan Lenno. Tes fixture kosong, batas periode WIB, status terkini versus event, dan hasil setelah refresh. Manual: bandingkan periode yang sama dengan Home/Board tanpa data demo. |

## QA manual Chrome

Gunakan konfigurasi development yang sudah ada dan dua akun disposable yang sudah
ditetapkan. Instruksi lengkap ada di [AUTH_UI.md](AUTH_UI.md).
Masuk akun A, cek snapshot, refresh, buka detail/modal, lalu logout atau pindah
akun. Masuk B, cek data B saja serta Back tidak membuka route A. Ulangi dengan
koneksi dibatasi saat loading dan gunakan **Coba lagi** setelah koneksi kembali.
Untuk pembuktian perbedaan isi, pakai record uji yang sudah ada di kedua akun.
Jika keduanya kosong, catat keterbatasan. Uji mutasi hosted hanya setelah
otorisasi eksplisit dengan fixture dan rencana cleanup yang disepakati.
