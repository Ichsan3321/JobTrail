# Kontrak revisi Documents dan Schedule

Migrasi maju `20261126000100_jobtrail_entity_revisions.sql` menambah perlindungan
lost update dan stale delete untuk metadata dokumen dan agenda. Migrasi ini
berjalan setelah `20261124000100` dan `20261124000200`. Kedua migrasi lama tetap
menjadi riwayat deployment. Perubahan ini belum diterapkan pada Supabase hosted.

## Skema dan siklus revisi

`public.documents.revision` dan `public.agendas.revision` bertipe PostgreSQL
`integer NOT NULL DEFAULT 1` dengan `CHECK (revision > 0)`. Row lama memperoleh
revisi 1 tanpa mengubah payload, timestamp, relasi, atau create fingerprint.
Create baru mulai pada 1. Semua full save update yang diterima memakai revisi
saat draft dibuka dan menaikkannya tepat satu kali, termasuk payload identik.
Ini mengikuti `jobtrail_update_application`, yang juga menaikkan revisi pada
setiap full save. Perilaku `jobtrail_change_status` untuk status identik tetap
sama. Label versi berkas `documents.version` tetap dapat diedit sebagai metadata.

Create replay memakai ID dan payload create pertama. Selama row masih ada dan
fingerprint cocok, receipt `replayed: true` memuat revisi terkini tanpa menulis
kembali payload lama, termasuk bila agenda sudah berpindah lamaran. Server tidak
menyimpan tombstone. Bila ID diketahui sudah terhapus, hentikan replay dan buat
intent baru hanya jika pengguna menginginkan record baru.

## RPC

Semua RPC berada dalam skema `public`. Signature berikut adalah signature yang
diterima PostgREST setelah cache skema dimuat ulang.

| RPC | Sebelum | Sesudah |
|---|---|---|
| `jobtrail_load_snapshot` | `() → jsonb` | Signature tetap. Tambahan `entity_revision_version: 1` dan `revision` pada setiap item `agendas` serta `documents`. |
| `jobtrail_save_document` | `(p_id uuid, p_create boolean, p_title text, p_category text, p_file_name text, p_version text, p_notes text DEFAULT '') → jsonb` | Tambahkan `p_expected_revision integer DEFAULT NULL` di akhir. Receipt `{id, updated_at, replayed, revision}`. |
| `jobtrail_save_agenda` | `(p_id uuid, p_create boolean, p_application_id uuid, p_type text, p_scheduled_at timestamptz, p_location_or_link text, p_notes text DEFAULT '') → jsonb` | Tambahkan `p_expected_revision integer DEFAULT NULL` di akhir. Receipt `{id, replayed, revision}`. |
| `jobtrail_delete_document` | `(p_id uuid) → uuid` | `(p_id uuid, p_expected_revision integer) → uuid`. |
| `jobtrail_delete_agenda` | `(p_id uuid) → uuid` | `(p_id uuid, p_expected_revision integer) → uuid`. |

Save mode create menghilangkan `p_expected_revision` dari request. Update wajib
mengirim nilai yang cocok. Default hanya menjaga kompatibilitas create dan
memberi respons aman pada update lama. Keempat signature lama dihapus sebelum
penggantinya dibuat dalam transaksi migrasi yang sama. `NOTIFY pgrst` meminta
refresh cache setelah commit. RPC aplikasi serta Auth tetap sama.

Update dan delete mengunci row sebelum membandingkan revisi. RPC agenda tetap
mengunci lamaran dalam urutan ID sebelum mengambil lock agenda. Perpindahan
memerlukan lamaran tujuan milik akun yang sama dan tanggal sipil WIB agenda
minimal tanggal lamaran tujuan. FK tetap melindungi dokumen tertaut. RLS,
`auth.uid()`, search path kosong, owner RPC `jobtrail_mutator`, dan izin execute
khusus `authenticated` tetap berlaku. Direct table writes tidak diberikan.

| Hasil | Penanganan |
|---|---|
| `JT001` atau `RepositoryIssue.unavailable` | Tampilkan data tidak tersedia. Pesan dan kode sama untuk ID hilang atau di luar akun. |
| `JT002` atau `RepositoryIssue.revisionConflict` | Store mencoba rekonsiliasi, lalu meneruskan konflik. Pertahankan draft, perlihatkan data terbaru jika berhasil dimuat, dan minta pengguna meninjau perubahan. Tangkap revisi baru hanya saat pengguna membuka atau menyetujui intent baru. |
| `JT005` atau `RepositoryIssue.documentInUse` | Dokumen tetap tersimpan. Tampilkan bahwa dokumen masih tertaut dan muat ulang relasi bila perlu. |
| `RepositoryFailure.writeOutcomeUnknown` | Outcome belum terkonfirmasi. Periksa snapshot dan jangan kirim ulang update/delete otomatis. Replay create hanya dengan intent awal yang sama. |
| Receipt terkonfirmasi, `snapshotCurrent == false` | Terangkan bahwa server menerima perubahan. Ulangi baca saja melalui `refresh()`. Saat update/create, cari receipt ID pada snapshot. Saat delete, konfirmasi bahwa ID sudah tidak ada. |

## Flutter dan cara menangkap revisi

`Agenda.revision` dan `AppDocument.revision` immutable. Nilainya `null` dalam
mode mock atau pada snapshot sebelum migrasi. Decoder mewajibkan revisi positif
pada snapshot dengan marker versi 1. Receipt create lama juga dapat tidak
memuat revisi. `AgendaReceipt.revision` dan `DocumentReceipt.revision` wajib
terisi saat decoder menerima receipt update yang valid. Store mengisi koleksi
dari snapshot akun, bukan dari asumsi berdasarkan receipt.

- Baca melalui `store.agendaById(id)` atau `store.documentById(id)` dan
  `store.agendaRevision(id)` atau `store.documentRevision(id)`.
- Ambil record dan revisi sebelum membuka draft atau dialog hapus. Saat revisi
  `null`, pertahankan gate mutation untuk akun backend. Teruskan revisi yang
  sudah ditangkap pada `expectedRevision`. Store tidak memilih revisi untuk layar.
- Saat melakukan await, cek akun, `mounted` dan kepemilikan route sebelum
  menampilkan pesan atau menutup layar. Cegah tap ganda selama intent aktif.

### Farhad · S06 Documents

Untuk PR #17, ganti panggilan hapus lama dengan argumen revisi yang diambil
sebelum konfirmasi. Simpan revisi asli saat menyiapkan draft metadata, termasuk
jika inventori direfresh ketika form terbuka. Pertahankan field draft saat
konflik, tampilkan metadata server, lalu minta review eksplisit. Uji dokumen
tertaut dengan kode `JT005` dan metadata portofolio bebas dengan `JT002` dari
sesi yang memegang revisi lama.

```dart
// Create memakai ID dan payload immutable yang ditetapkan sekali per intent.
await store.saveDocumentRemote(createIntent, SaveMode.create);

// S06 menyimpan revisionAtDraftOpen ketika membaca dokumen untuk draft.
await store.saveDocumentRemote(
  metadataDraft,
  SaveMode.update,
  expectedRevision: revisionAtDraftOpen,
);

// Ambil revisionBeforeConfirm sebelum dialog. Kirim setelah user setuju.
await store.deleteDocumentRemote(documentId, revisionBeforeConfirm);
```

### Fachriza · S05 Schedule

Gunakan `nextAgendaId()` sekali untuk intent baru. Simpan entity dan revisi
awal saat membuka edit. Validasi bahwa lamaran tujuan ada pada snapshot akun
dan tanggal WIB tidak mendahului tanggal lamaran. Server memeriksanya kembali
dalam transaksi. Uji perpindahan lamaran milik akun yang sama, parent hilang,
lintas WIB tengah malam, konflik revisi dan draft yang tetap dapat ditinjau.

```dart
await store.saveAgendaRemote(createIntent, SaveMode.create);
await store.saveAgendaRemote(
  agendaDraft,
  SaveMode.update,
  expectedRevision: revisionAtDraftOpen,
);
await store.deleteAgendaRemote(agendaId, revisionBeforeConfirm);
```

Farhad dan Fachriza membuka aksi update/delete hosted setelah kontrak
terdeploy, smoke dan skenario dua akun yang disetujui lulus, serta UI masing-masing
direview. Aksi mock masih memakai metode lokal yang sudah ada.

## Kompatibilitas dan rollout

| Pemanggil | Backend sebelum migrasi | Backend sesudah migrasi |
|---|---|---|
| Flutter lama baca/create | Kontrak lama. | Field tambahan dapat diabaikan. Argumen create lama tetap diterima. |
| Flutter lama update/delete dokumen atau agenda | Perilaku lama bila aksi diaktifkan. | Update tanpa revisi ditolak `JT002` untuk row yang dimiliki. Delete dengan argumen lama tidak menemukan RPC yang cocok. |
| Flutter baru baca/create | Snapshot dan receipt tanpa revisi tetap terbaca. | Snapshot versi 1 dan receipt membawa revisi. |
| Flutter baru update/delete | Aksi perlu tetap gated. Backend lama tidak mengenali argumen revisi tambahan. | Snapshot, revisi yang ditangkap, dan scope akun menentukan aksi. |
| Harness baru dan manifest v1 | Read-only masih bisa menggunakan snapshot lama. Create/cleanup berhenti sebelum mutasi tanpa marker versi 1. | Manifest v1 dapat dipakai melalui preflight baru. Revisi tidak ditebak dari manifest maupun diganti saat delete berjalan. |
| Harness atau smoke lama | Bergantung pada RPC delete lama. | Hentikan operator lama sebelum cutover. Delete agenda/dokumen dengan signature lama gagal. |

1. Jalankan runner PostgreSQL lokal pada cluster disposable. Jalankan tes
   Flutter, harness offline, dan validasi REST melalui Supabase lokal untuk
   default parameter create, pemetaan error dan schema cache. Runner
   PostgreSQL memverifikasi SQL dan ACL, sedangkan REST membutuhkan PostgREST.
2. Saat lead menyetujui deployment terpisah, konfirmasi migration ledger
   target dan backup. Hentikan runner lama dan writer fixture. Tinjau run
   parsial serta outcome ambigu sebelum window migrasi. Terapkan migrasi
   melalui pipeline yang disetujui. Gunakan perubahan maju untuk perbaikan
   agar RPC unguarded tidak aktif lagi.
3. Verifikasi marker versi 1 pada snapshot akun disposable, signature unik
   dan akses RPC melalui PostgREST. Jalankan uji hosted hanya dalam scope
   yang disetujui secara terpisah. Gunakan harness versi ini setelah cutover.
   Simpan hasil dan putuskan aktivasi UI tiap layar.

## Fixture QA dan batasan relasi

Cleanup memverifikasi identitas, ID dan marker serta mengecek relasi dalam
scope manifest. Ambil revisi yang sudah dibaca dan cocok dengan owner lookup
pada preflight run. Jika revisi berubah sebelum delete, hentikan. RPC menolak
perubahan yang terjadi sesudah pembacaan tersebut. Manifest v1 tetap memakai
ID, fingerprint payload dan checkpoint semula. Saat melanjutkan run lama,
simpan manifest asli, verifikasi lagi dengan backend yang sudah mendukung
revisi, lalu pakai `--settled` hanya setelah outcome yang belum jelas
direkonsiliasi dan operasi sebelumnya selesai.

Revisi per entity melindungi update/delete langsung pada row itu. Penambahan
agenda masih dapat terjadi di antara pemeriksaan relasi dan penghapusan
lamaran karena perubahan agenda tidak menaikkan revisi lamaran. FK tetap
mencegah hapus dokumen yang sedang tertaut pada saat RPC. Gunakan akun secara
eksklusif selama cleanup, termasuk pada smoke, dan hentikan writer lain.
Jangan meneruskan cleanup setelah outcome ambigu. Lihat [Runbook fixture](HOSTED_QA_FIXTURES.md).

## Validasi pada mesin lokal

```powershell
# Path ini menunjuk ke instalasi PostgreSQL lokal yang sudah ada.
python supabase/tests/run_entity_revision_tests.py --pg-bin 'C:/Program Files/PostgreSQL/18/bin'
node --test supabase/tests/hosted_fixtures.test.mjs
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```

Runner SQL membuat cluster sementara yang mendengarkan hanya pada loopback.
Ia memasukkan data sebelum migrasi, menerapkan migrasi, menjalankan tes kontrak,
dan mengamati session loser menunggu lock session winner. Setelah commit,
loser harus menerima `JT002` dan versi/payload winner harus tetap tersimpan.
