# Kontrak database dan integrasi backend JobTrail

Baseline Flutter di `30db71d`. Migrasi ini menetapkan kontrak PostgreSQL untuk
fase metadata. Supabase Auth mengelola identitas email/password dan menyediakan
`auth.users.id`. Integrasi sesi Flutter dijelaskan di [AUTH_UI.md](AUTH_UI.md).
Kontrak Dart tersedia di `lib/data/jobtrail_repository.dart`. Adapter
`SupabaseJobTrailRepository` memakai RPC yang diuraikan di dokumen ini dengan
token sesi pemilik. `JobTrailWire` memvalidasi wire code, UUID, tanggal sipil WIB,
instant ber-offset, revision, relasi dan history `event_no`. Nilai gaji bigint
dikirim sebagai string desimal. Mappings membaca gaji sampai 9007199254740991
rupiah agar Dart Web tetap bisa merepresentasikannya dengan tepat.

## Skema dan relasi

```mermaid
erDiagram
    authUsers ||--o{ applications : owns
    authUsers ||--o{ documents : owns
    applications ||--o{ agendas : schedules
    applications ||--|{ applicationStatusHistory : records
    applications ||--o{ applicationDocuments : links
    documents ||--o{ applicationDocuments : "is linked"

    authUsers["auth.users"] {
        uuid id PK
    }
    applications {
        uuid id PK
        uuid user_id FK
        date applied_on
        integer revision
    }
    agendas {
        uuid id PK
        uuid user_id FK
        uuid application_id FK
        timestamptz scheduled_at
    }
    applicationStatusHistory["application_status_history"] {
        uuid id PK
        uuid user_id FK
        uuid application_id FK
        integer event_no
    }
    documents {
        uuid id PK
        uuid user_id FK
    }
    applicationDocuments["application_documents"] {
        uuid user_id FK
        uuid application_id PK, FK
        uuid document_id PK, FK
    }
```

Semua kolom wajib diisi kecuali yang ditandai nullable. Default tabel berlaku
untuk penulisan internal. Default UI tetap mengikuti [kontrak frontend](ARCHITECTURE.md#model-bersama).

| Tabel dan kolom | Tipe dan default | Kontrak Dart dan batasan |
|---|---|---|
| `auth.users.id` | UUID yang diterbitkan Auth | PK, identitas sesi. Email dan metadata akun tetap dikelola Auth. |
| `applications.id, user_id` | UUID, tanpa default | PK dari UUID stabil yang dialokasikan klien, FK pemilik dari sesi. Pasangan `(user_id, id)` unik. |
| `applications.company, position, source, location` | text, tanpa default | Field `ApplicationDraft`. Trim dan tolak teks kosong. `Situs perusahaan` dan `Website perusahaan` tetap nilai berbeda. |
| `applications.applied_on` | date, tanpa default | `appliedAt` sebagai tanggal sipil terbatas, maksimal hari ini di WIB. |
| `applications.status, work_type` | text, tanpa default | `status` dan `workType`, dengan named CHECK untuk kode baku. |
| `applications.salary_monthly_idr` | bigint nullable, NULL | `salary` bulanan dalam IDR, integer nonnegatif. Snapshot mengirim string desimal untuk menjaga presisi. |
| `applications.notes` | text, `''` | `notes`, string kosong valid. |
| `applications.revision` | integer, 1 | Token versi server, positif. Kirim pada edit, perubahan status, dan hapus. |
| `agendas.id, user_id, application_id` | UUID, tanpa default | PK klien, pemilik dari sesi, FK komposit ke lamaran. |
| `agendas.type` | text, tanpa default | `Agenda.type`, kode baku. |
| `agendas.scheduled_at` | timestamptz, tanpa default | `scheduledAt` sebagai instant terbatas. Tanggal WIB minimal tanggal lamaran. |
| `agendas.location_or_link, notes` | text, tanpa default dan `''` | `locationOrLink` wajib nonkosong, `notes` boleh kosong. |
| `agendas.revision` | integer, 1 | Revisi server positif sejak migrasi `20261126000100`. |
| `application_status_history.id, user_id, application_id` | UUID, `gen_random_uuid()` untuk ID | PK dari server, pemilik dari sesi, FK komposit ke lamaran. |
| `application_status_history.status, changed_at, event_no` | text, timestamptz, integer, dari rutinitas penulisan | `status`, `changedAt`, dan urutan positif yang unik per lamaran. Event baru tidak mundur relatif terhadap event sebelumnya. |
| `documents.id, user_id` | UUID, tanpa default | PK klien dan FK pemilik dari sesi. Pasangan `(user_id, id)` unik. |
| `documents.title, file_name, version, category` | text, tanpa default | `title`, `fileName`, `version` wajib nonkosong. `category` memakai kode baku. Nama file hanya metadata. |
| `documents.updated_at, notes` | timestamptz dari server dan text `''` | `updatedAt` sebagai instant dan `notes` opsional secara isi. |
| `documents.revision` | integer, 1 | Revisi server positif, terpisah dari label versi berkas, sejak migrasi `20261126000100`. |
| `application_documents.user_id, application_id, document_id` | UUID, tanpa default | PK pasangan ID dan dua FK komposit dengan pemilik yang sama. Repository membentuk kembali `Application.documentIds` dari set ini. |
| `applications.create_fingerprint`, `agendas.create_fingerprint`, `documents.create_fingerprint` | bytea, dibuat RPC | SHA-256 payload pembuatan yang dikanonisasi. Kolom internal dan tetap setelah edit. |

Kode status dipetakan langsung dari `RecruitmentStatus.name` dengan nilai
`applied`, `screening`, `test`, `interview`, `offering`, `rejected`.
`WorkType.onSite` menjadi `on_site`, sedangkan `hybrid` dan `remote` langsung.
`AgendaType` menggunakan `interview` dan `test`.
`DocumentCategory.cvResume` menjadi `cv_resume`, sedangkan `portfolio` langsung.
Kirim tanggal sebagai `YYYY-MM-DD` dan bangun ulang dengan `AppDates.date`.
Kirim instant ISO 8601 dengan offset eksplisit, parse ke UTC. Tanggal WIB dihitung
dengan offset tetap UTC+07 agar cocok dengan [AppDates](../lib/core/constants/app_dates.dart).

Lamaran dan dokumen dimiliki akun. Hapus lamaran menghapus agenda, history,
dan tautan, dengan dokumen tetap tersimpan. FK dokumen menolak penghapusan
selama masih ada tautan. Hapus akun menghapus data milik akun melalui cascade.
Primary key dan unique constraint menyediakan indeks identitas. Indeks tambahan
mendukung daftar per pemilik berdasarkan tanggal lamaran, jadwal dan dokumen,
agenda dan history per lamaran, serta pencarian balik tautan dokumen.

## Akses dan kontrak repository

RLS menyediakan SELECT per pemilik untuk `authenticated`. Proyeksi eksplisit
diperlukan untuk tabel yang memiliki fingerprint. Gunakan snapshot RPC sebagai
antarmuka baca utama. Perubahan melalui RPC menggunakan role `jobtrail_mutator`
yang tidak memiliki login, tabel, atau BYPASSRLS. RLS berlaku juga untuk role itu.
Kolom pemilik dan fingerprint tidak mendapat izin UPDATE. Pemanggil anonim
tidak mendapat akses tabel atau RPC. Jembatan privat hanya membaca identitas
`auth.uid()` karena role migrasi Supabase tidak bisa mendelegasikan akses skema Auth.

| Metode repository | RPC dan input | Output |
|---|---|---|
| `loadSnapshot()` | `jobtrail_load_snapshot` tanpa argumen | `reference_date`, `reference_instant`, dan array `applications`, `agendas`, `history`, `documents`, `application_documents`. Setelah migrasi revisi entity, snapshot menyertakan `entity_revision_version: 1` dan revisi agenda/dokumen. Field DTO tidak menyertakan `user_id` atau fingerprint. Gaji berupa string desimal atau null. |
| `createApplication(id, draft)` | `jobtrail_create_application` dengan `p_id`, perusahaan, posisi, sumber, tanggal, status, lokasi, tipe, gaji, catatan, dan `p_document_ids` | `id`, `revision`, `replayed`. Pembuatan lamaran, tautan dan event pertama terjadi dalam satu transaksi. |
| `updateApplication(id, revision, draft)` | `jobtrail_update_application`. Payload lengkap sama seperti create dengan `p_expected_revision`. Kirim null untuk gaji kosong dan array kosong untuk melepaskan semua dokumen. | `id`, `revision` baru. Payload, tautan, dan event status bersifat atomik. |
| `changeStatus(id, revision, status)` | `jobtrail_change_status(p_id, p_expected_revision, p_status)` | `id`, `revision`. Status sama mempertahankan revisi dan history. |
| `deleteApplication(id, revision)` | `jobtrail_delete_application(p_id, p_expected_revision)` | UUID yang dihapus. |
| `saveAgenda(agenda, mode, expectedRevision: ...)` | `jobtrail_save_agenda(p_id, p_create, p_application_id, p_type, p_scheduled_at, p_location_or_link, p_notes, p_expected_revision)` | `id`, `replayed`, `revision`. Update wajib menyertakan revisi yang ditangkap. Create memakai argumen lama. |
| `saveDocument(document, mode, expectedRevision: ...)` | `jobtrail_save_document(p_id, p_create, p_title, p_category, p_file_name, p_version, p_notes, p_expected_revision)` | `id`, `updated_at`, `replayed`, `revision`. Timestamp dari server. Update wajib menyertakan revisi yang ditangkap. Create memakai argumen lama. |
| `deleteAgenda(id, expectedRevision)`, `deleteDocument(id, expectedRevision)` | `jobtrail_delete_agenda(p_id, p_expected_revision)`, `jobtrail_delete_document(p_id, p_expected_revision)` | UUID yang dihapus. |

Signature baru agenda dan dokumen berlaku setelah migrasi
`20261126000100`. Lihat [kontrak revisi entity](ENTITY_REVISION_CONTRACT.md)
untuk kompatibilitas sebelum deploy, contoh integrasi, dan gerbang QA.

Nama parameter draft RPC memakai awalan `p_` di depan nama kolom kamus.
Store menggunakan snapshot konsisten dan mempublikasikan state setelah commit.
Jika refresh gagal setelah commit, ulangi baca dan pertahankan hasil commit.
W13-02 memakai ID hasil commit untuk membuka Board. Store dan navigasi dipasang
per sesi, dibuang saat identitas berubah, serta mengabaikan request sesi lama.
Tampilkan state loading, empty, dan error/retry terpisah. Pengujian persistensi
menggunakan repository fake. Mode mock memakai store in-memory yang sudah ada.

**Retry.** Buat UUID sekali per percobaan create. ID dan payload awal yang cocok
memberikan `replayed: true` selama row masih ada, termasuk setelah edit.
Hasil replay memuat revisi atau timestamp terkini dan tidak menulis ulang data.
Urutan tautan dokumen diabaikan. Duplikat atau null dalam daftar ditolak.
ID yang dipakai dengan payload berbeda menghasilkan konflik. Jangan kirim ulang
create yang sudah diketahui terhapus. Penghapusan permanen tidak menyimpan
tombstone, sehingga server tidak mengingat ID tersebut setelah row dihapus.
Pertahankan kanonisasi payload lama jika kontrak create berubah.
Untuk edit yang mengalami timeout, baca ulang sebelum mencoba dengan revisi baru.

| SQLSTATE | Penanganan di adapter |
|---|---|
| `42501` | Sesi atau akses ditolak. Hentikan write dan periksa status autentikasi. |
| `JT001` | Record tidak tersedia. Gunakan pesan sama untuk ID hilang dan ID milik akun lain. |
| `JT002` | Revisi stale. Ambil snapshot baru dan pertahankan draft pengguna. |
| `JT003` | Tautan dokumen tidak tersedia. Muat inventori lagi dan minta pilihan ulang. |
| `JT004` | ID create konflik. Jangan retry payload berbeda dengan ID lama. |
| `JT005` | Dokumen masih tertaut. Lepas tautan sebelum menghapus. |
| `22023`, `23502`, `23514`, tipe input invalid | Tampilkan kesalahan validasi yang sesuai tanpa menampilkan pesan database mentah. |
| `40001`, timeout atau offline | Ambil ulang state atau retry terkontrol. Pakai ID dan payload asli untuk retry create. |

## Akses per screen

Tabel ini memetakan kontrak per layar. AppShell backend saat ini mengaktifkan
pembacaan untuk Home, Board, Detail, Jadwal, Dokumen dan Statistik. Mutasi dan form
Tambah/Edit dibuka per layar setelah wiring dan validasi masing-masing.
Lihat [handoff integrasi](PERSISTENCE_HANDOFF.md).

| Screen | Operasi data |
|---|---|
| S01 Home | Baca aplikasi dan agenda, hitung target dan notifikasi. Read marker notifikasi lokal. |
| S02 Board | Baca aplikasi, agenda, dan metadata dokumen tertaut, ubah status. |
| S03 Detail | Baca lamaran, agenda, history, dokumen dan tautan, ubah status, hapus lamaran, buat agenda. |
| S04 Add/Edit | Baca draft dan dokumen, buat atau ubah lamaran beserta tautan dan history. |
| S05 Jadwal | Baca agenda dan lamaran, buat agenda. Endpoint edit/delete tersedia untuk integrasi mendatang. |
| S06 Dokumen | Baca, buat, ubah, hapus metadata, dan baca referensi aplikasi. |
| S07 Statistik | Baca lamaran dan history, hitung metrik sesuai [definisi saat ini](DUMMY_DATA.md#definisi-agregasi-yang-sudah-diimplementasikan). |
| Auth | Sesi, register/login email, verifikasi, dan recovery lewat Auth. |

## Keputusan tertunda

- `setWeeklyGoal` ada di store tetapi tidak dipanggil screen, sehingga release
  awal menghitung Senin WIB dan default 8 tanpa tabel baru. Pertahankan API demo.
  Jika target bisa diedit atau berbeda per minggu, setujui penyimpanan preferensi
  atau target mingguan sebelum menghubungkan UI editor.
- Eligibility agenda dan batas tahun picker saat ini aturan UI. Database menjaga
  kepemilikan dan relasi tanggal. Setujui promosi eligibility ke server bila perlu.
- Tautan dokumen tidak menyimpan urutan UI. Penyatuan label sumber dan urutan
  tautan memerlukan keputusan produk. Nilai gaji di luar rentang integer presisi
  Dart Web ditolak saat decoding.
- Google OAuth, file privat, offline, realtime, dan persistensi read marker
  ditunda. Verifikasi Auth email/password, PostgREST, dan kebijakan penghapusan
  akun pada stack Supabase lokal saat pekerjaan integrasi dimulai.

## Pengujian lokal

Gunakan Supabase CLI 3.3.0 dan runtime lokal yang telah disiapkan tim. Jalankan
`supabase start` dari root untuk stack lokal baru. Bila perlu menjalankan migrasi
tertunda pada stack lokal yang sudah ada, gunakan `supabase db push` tanpa
`--remote`. Konfigurasi lokal mengekspos `public`, menonaktifkan seed, dan memakai
redirect localhost. Jangan gunakan `supabase config push` untuk menerapkan
konfigurasi pengembangan ini ke project bersama. Biarkan `.temp/`,
`.branches/`, dan file environment tetap lokal. File contoh hanya boleh berisi
placeholder.

Jalankan hanya pada database lokal disposable. Pada Supabase lokal yang memiliki
skema Auth, terapkan migrasi berurutan lalu jalankan
`psql -X -h 127.0.0.1 -p PORT_LOKAL -v ON_ERROR_STOP=1 -f supabase/tests/database_contract.sql`
dengan user dan database lokal yang sesuai. Tes memakai fixture sementara di dalam transaksi yang diakhiri
ROLLBACK. Untuk PostgreSQL polos pada cluster baru, jalankan terlebih dahulu
`supabase/tests/support/plain_postgres_auth.sql` sebagai admin pada cluster
plain PostgreSQL baru dan disposable. Buat database berawalan `jobtrail_test_`
dan hubungkan `psql` melalui loopback. Shim menolak database dengan skema Auth
yang sudah ada. Ia mensimulasikan role dan claim untuk pengujian RLS tingkat SQL.

## Smoke test Supabase hosted

Target tetap `https://ehzdmsdhdlqmicmwbnwh.supabase.co`. Harness membutuhkan
Node.js 22 atau lebih baru. Gunakan dua akun email/password disposable yang
ditunjuk project owner. Jika belum tersedia, buka **Authentication → Users →
Add user → Send invitation** di dashboard project ini. Kirim undangan ke dua
alamat uji yang dikuasai tim. Masing-masing pemilik akun membuka undangan,
menyelesaikan konfirmasi email, dan menetapkan password melalui alur Auth tim.
Ambil **publishable key** dari pengaturan API project tersebut. Masukkan semua
nilai di terminal lokal melalui prompt berikut. Simpan password dan token di luar repo dan chat.

```powershell
$env:JOBTRAIL_SUPABASE_PUBLISHABLE_KEY = Read-Host 'Publishable key JobTrail'
$env:JOBTRAIL_TEST_A_EMAIL = Read-Host 'Email akun disposable A'
$env:JOBTRAIL_TEST_B_EMAIL = Read-Host 'Email akun disposable B'
$env:JOBTRAIL_TEST_A_PASSWORD = [pscredential]::new(
    'smoke', (Read-Host 'Password akun A' -AsSecureString)
).GetNetworkCredential().Password
$env:JOBTRAIL_TEST_B_PASSWORD = [pscredential]::new(
    'smoke', (Read-Host 'Password akun B' -AsSecureString)
).GetNetworkCredential().Password
try {
    node supabase/tests/hosted_smoke.mjs
} finally {
    Remove-Item Env:JOBTRAIL_SUPABASE_PUBLISHABLE_KEY,
        Env:JOBTRAIL_TEST_A_EMAIL, Env:JOBTRAIL_TEST_A_PASSWORD,
        Env:JOBTRAIL_TEST_B_EMAIL, Env:JOBTRAIL_TEST_B_PASSWORD
}
```

`node supabase/tests/hosted_smoke.mjs --check` memvalidasi input tanpa jaringan.
Run hosted melaporkan PASS per kelompok dan exit 0 hanya jika seluruh asersi dan
verifikasi cleanup berhasil. Run membuat UUID baru, memakai marker unik, dan
melakukan cleanup melalui sesi pemilik. Bila terjadi kegagalan, cleanup tetap
dicoba dengan memeriksa ID, pemilik, dan marker sebelum menghapus. Jika koneksi
terputus atau proses dihentikan, gunakan marker dan ID yang dicetak untuk
memeriksa sisa fixture melalui akun pemilik. Hapus hanya fixture yang cocok.
Akun uji tetap tersedia untuk run berikutnya. Harness menguji jalur HTTP dan
database. Integrasi sesi di aplikasi Flutter perlu diuji terpisah.

### Hasil validasi hosted

**24 November 2026 · Lulus, exit code `0`.** Smoke test dijalankan oleh pengguna
pada project pengembangan JobTrail dengan hasil berikut.

| Pemeriksaan | Hasil |
|---|---|
| Auth | Login email/password berhasil untuk dua akun dengan identitas berbeda. |
| REST dan RPC pemilik | Pembacaan, pembuatan lamaran dengan tautan dokumen, replay payload identik, snapshot, dan satu event history awal lulus. |
| Isolasi RLS | Data akun lain tidak terlihat, mutasi lintas akun ditolak, dan tautan lintas akun memicu rollback. |
| Izin akses | INSERT, UPDATE, dan DELETE langsung yang tidak berizin serta akses anonim ditolak. |
| Integritas mutasi | Konflik revisi ditolak, dokumen tertaut terlindungi, dan penghapusan berantai berjalan sesuai kontrak. |
| Cleanup | Seluruh fixture yang dilacak berhasil dibersihkan. |

**Rekomendasi PR #14 · GO untuk merge.** Validasi backend hosted telah lulus.
Validasi manual Auth Flutter dan integrasi repository masih tertunda. Lihat
[langkah uji Auth Flutter](AUTH_UI.md#manual-chrome-and-android-validation).
