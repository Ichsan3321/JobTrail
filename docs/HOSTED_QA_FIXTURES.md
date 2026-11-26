# JobTrail · Runbook fixture QA hosted

Harness Node.js (≥20) menggunakan password sign-in, verifikasi Auth
`/auth/v1/user`, dan RPC snapshot dari kontrak yang ada. Mode default
`check` hanya memvalidasi konfigurasi. `verify --hosted-read` membaca snapshot
setelah login. `create --execute` dan `cleanup --execute` mengirim mutasi RPC.
Seluruh perintah bekerja pada satu akun yang dipilih.

Hubungi lead melalui kanal privat untuk memperoleh kredensial akun disposable
yang sudah disetujui dan publishable key proyek development. Gunakan
`test-a@example.com` untuk pemeriksaan akun kosong dan `test-b@example.com`
untuk run terisi pertama. Akun Hanif, Lenno, Rifqi, Fachriza, Farhad dan Ziyaad
memakai email disposable masing-masing. Harness mengizinkan hanya delapan
identitas tersebut pada origin `https://ehzdmsdhdlqmicmwbnwh.supabase.co`.
Kecocokan email dan UUID pemilik diperiksa setelah sign-in. Permintaan dengan
redirect ditolak.

Untuk meminta izin tulis, cantumkan akun, profil, skenario modul, waktu mulai
dan selesai, penanggung jawab cleanup, serta record tambahan yang diperlukan.
`--execute` dipakai setelah lead menyetujui pembuatan atau pembersihan pada akun
itu. Selama cleanup, hentikan semua aktivitas tulis pada akun tersebut,
  termasuk aplikasi atau harness di tab maupun terminal lain. Revisi
  melindungi penghapusan langsung lamaran, agenda, dan dokumen. FK melindungi
  dokumen tertaut. Pemeriksaan snapshot seluruh relasi belum atomik dengan
  cascade lamaran. Agenda yang ditautkan bersamaan dapat ikut terhapus tanpa
  menaikkan revisi lamaran. Penggunaan akun eksklusif tetap wajib.

## Profil dan ekspektasi

| Profil | Fixture awal dan penggunaan |
|---|---|
| `empty` | Verifikasi kelima koleksi snapshot kosong. Laporkan hitungan jika akun terisi. |
| `standard` | 6 lamaran, satu per status. 1 sebelum minggu WIB dan 5 pada minggu berjalan. Weekly Goal 5/8 (62,5%). 3 agenda, dengan 2 mendatang termasuk 1 interview. 1 dokumen, 1 tautan, 6 event awal. |
| `board` · S02 Hanif | 3 lamaran. Screening, Interview, Offering. Variasi sumber, tipe kerja, tanggal. Lamaran `transition` dimulai di Screening, revisi 1, dan mempunyai satu event. |
| `detail` · S03 Lenno | 2 lamaran, 1 agenda dan 1 dokumen terhubung ke `cascade`. Setelah hapus lamaran yang diotorisasi, cek agenda, tautan dan history ikut hilang, dokumen dan `untouched` tetap ada. |
| `form` · S04 Rifqi | 1 lamaran bertaut dokumen, gaji null dan ID payload stabil. Uji pengisian kembali field dan revisi. Untuk uji create dari UI dengan UUID baru, catat terpisah dan minta otorisasi cleanup ID tersebut. |
| `schedule` · S05 Fachriza | 2 lamaran dan 3 agenda, termasuk 23:59 dan 00:01 pada dua tanggal WIB yang berurutan. Periksa pengelompokan tanggal, urutan, tautan, dan batas tanggal agenda terhadap lamaran. |
| `documents` · S06 Farhad | 1 CV tertaut dan 1 portofolio bebas, plus 1 lamaran. Uji penolakan penghapusan CV tertaut, edit metadata portofolio, dan pembatalan draft. |
| `statistics` · S07 Ziyaad | 7 lamaran, dengan contoh pada dan sehari sebelum batas 1/2/3 bulan. Total baseline Semua/1/2/3 bulan adalah 7/2/4/6. Ada 1 lamaran dengan history interview. Denominator konversi mengikuti total periode. |

Tanggal, agenda dan metrik awal memakai jam server. Laporan menunjukkan
metrik pada waktu persiapan serta pada snapshot terbaru. Jika tanggal bergeser,
hitung ulang ekspektasi UI memakai metrik terbaru. Akun dengan record lain
akan memiliki total akun yang berbeda dari total fixture. `changed`, `missing`
dan `applicationChecks` menunjukkan perubahan terhadap baseline, termasuk
perubahan yang sengaja dibuat dalam QA. Hasil verify baseline dapat `FAIL`
setelah mutasi QA yang sah.

## Validasi pertama oleh lead · PowerShell

Jalankan dari root dengan akun A. Key boleh dipakai ulang dalam sesi PowerShell
yang sama. Password dimasukkan lewat prompt tertutup dan diteruskan hanya
melalui environment proses, lalu dihapus dari environment.

```powershell
Set-Location C:\JobTrail
$env:JOBTRAIL_SUPABASE_PUBLISHABLE_KEY = Read-Host 'JobTrail publishable key'
$env:JOBTRAIL_QA_EMAIL = 'test-a@example.com'
$qaPassword = Read-Host 'Disposable account password' -AsSecureString
$env:JOBTRAIL_QA_PASSWORD = [System.Net.NetworkCredential]::new('', $qaPassword).Password
try {
  node supabase/tests/hosted_fixtures.mjs check
  if ($LASTEXITCODE -ne 0) { throw 'Configuration check failed' }
  node supabase/tests/hosted_fixtures.mjs verify --profile empty --hosted-read
} finally {
  Remove-Item Env:JOBTRAIL_QA_PASSWORD -ErrorAction SilentlyContinue
  $qaPassword.Dispose()
}
```

Setelah izin tulis untuk B, masukkan password B. Jalankan dry-run, lalu create.
Simpan **Manifest run UUID** yang muncul. Jika create gagal, UUID itu menunjuk
manifest lokal untuk rekonsiliasi. Jika kegagalan terjadi sebelum manifest
terbentuk, belum ada RPC tulis dari run tersebut.

```powershell
$env:JOBTRAIL_QA_EMAIL = 'test-b@example.com'
$qaPassword = Read-Host 'Disposable account password' -AsSecureString
$env:JOBTRAIL_QA_PASSWORD = [System.Net.NetworkCredential]::new('', $qaPassword).Password
try {
  node supabase/tests/hosted_fixtures.mjs create --profile standard
  if ($LASTEXITCODE -ne 0) { throw 'Dry-run failed' }
  node supabase/tests/hosted_fixtures.mjs create --profile standard --execute
  if ($LASTEXITCODE -ne 0) { throw 'Create failed; retain run UUID' }
  $qaRun = Read-Host 'Manifest run UUID'
  node supabase/tests/hosted_fixtures.mjs verify --manifest $qaRun --hosted-read
} finally {
  Remove-Item Env:JOBTRAIL_QA_PASSWORD -ErrorAction SilentlyContinue
  $qaPassword.Dispose()
}
```

Untuk akun anggota, gunakan blok kedua dengan email dan profil yang sesuai,
misalnya `hanif@example.com` dan `board`. Buka Flutter menggunakan konfigurasi
lokal yang sudah ada, lalu login dengan akun yang sama.

```powershell
flutter run -d chrome --web-hostname=localhost --web-port=3000 --dart-define-from-file=.env.jobtrail.json
```

Ambil screenshot UI sebelum/sesudah dari data sintetis. Pangkas email,
identifier pemilik, URL berisi parameter Auth dan area DevTools yang berisi
header. Cantumkan commit, profil, label fixture, waktu WIB, dan ekspektasi vs
hasil pengujian. Bagikan ringkasan agregat atau `applicationChecks` yang
relevan, dan simpan manifest lengkap hanya di mesin operator. Ikuti
[panduan Home](HOME_INTEGRATION_QA.md) dan [handoff layar](PERSISTENCE_HANDOFF.md).

## QA-07 · Board Hanif

1. Siapkan profil `board` di akun Hanif yang diotorisasi. Simpan baseline
   `applicationChecks`: `transition` = Screening, revisi 1, event #1 Screening.
   Uji filter status, sumber/tipe, dan preview ke Detail dengan ID lamaran sama.
2. Di branch dengan mutasi Board, ubah `transition` ke Interview. Periksa
   receipt dan rekonsiliasi UI, kemudian reload. Laporan sesudah perubahan
   harus menunjukkan revisi 2, event #1 Screening dan #2 Interview.
   Mengirim status Interview lagi tidak menambah event atau revisi.
3. Untuk konflik, buka editor status di tab A pada revisi 2. Di tab B ubah
   record yang sama ke Offering dan tunggu rekonsiliasi (revisi 3). Simpan
   draft status berbeda dari tab A. Harapkan konflik revisi, state server
   tetap Offering, draft tetap dapat ditinjau, dan tidak ada event ekstra.
   Jika UI belum mengekspos skenario revisi, catat sebagai belum teruji.
4. Cocokkan Board, Detail history dan Statistik setelah refresh dengan home
   summary. Pada fixture murni, setelah langkah 2 ada 2 Interview dan 1
   Offering. Setelah langkah 3 ada 1 Interview dan 2 Offering. Cek history
   tetap berurutan dan Weekly Goal/total lamaran tidak berubah.
5. Simpan bukti ringkas, tutup sesi QA, dan koordinasikan cleanup. Gunakan
   snapshot hasil verify untuk membedakan drift yang direncanakan dari anomali.

## Cleanup dan pemulihan

Harness ini mensyaratkan `entity_revision_version: 1` dari snapshot sebelum
create atau cleanup. Manifest v1 tetap berlaku. Simpan manifest lama dan
verifikasi ulang sesudah migrasi. Bila backend belum mendukung revisi,
create/cleanup berhenti sebelum mutasi. Gunakan harness baru sesudah cutover.
Lihat [kontrak revisi entity](ENTITY_REVISION_CONTRACT.md) untuk rollout.

Jalankan kembali prompt password dengan akun pemilik manifest. Tutup sesi UI
dan proses lain akun tersebut, lalu gunakan dry-run dan izin cleanup lead.

```powershell
$qaRun = Read-Host 'Manifest run UUID'
$qaPassword = Read-Host 'Disposable account password' -AsSecureString
$env:JOBTRAIL_QA_PASSWORD = [System.Net.NetworkCredential]::new('', $qaPassword).Password
try {
  node supabase/tests/hosted_fixtures.mjs cleanup --manifest $qaRun
  if ($LASTEXITCODE -ne 0) { throw 'Dry-run failed' }
  node supabase/tests/hosted_fixtures.mjs cleanup --manifest $qaRun --execute
} finally {
  Remove-Item Env:JOBTRAIL_QA_PASSWORD -ErrorAction SilentlyContinue
  $qaPassword.Dispose()
}
```

- Pertahankan marker persis pada field `notes` setiap record saat melakukan
  pengujian edit. Cleanup hanya menargetkan ID dari manifest yang dibangun
  ulang dari profil dan UUID run. Ia memeriksa pemilik, marker, relasi keluar,
  serta revisi ketiga jenis entity. Revisi dari preflight dipertahankan
  sepanjang percobaan cleanup dan dikirim pada setiap delete. Jika berubah,
  hentikan dan tinjau ulang sebelum memulai percobaan baru. Urutannya agenda,
  lamaran, dokumen. Riwayat dan tautan
  fixture dihapus lewat cascade lamaran. Record baru dari UI di luar manifest
  membutuhkan identifikasi dan cleanup terpisah yang disetujui.
- Timeout, pembatalan dan kegagalan transport dapat terjadi setelah server
  menerima RPC. Hentikan percobaan lain. Baca snapshot dengan verify, periksa
  status `IN_FLIGHT`/`UNCERTAIN` pada manifest dan konfirmasi ke lead bahwa RPC
  sebelumnya sudah selesai sebelum menetapkan `--settled`. Snapshot kosong
  sesaat saja tidak membuktikan RPC telah berhenti.
- Untuk melanjutkan create yang masih parsial, jalankan
  `node supabase/tests/hosted_fixtures.mjs create --manifest $qaRun --execute`.
  Tambahkan `--settled` hanya setelah rekonsiliasi. ID serta payload lama
  dipakai ulang, record terkonfirmasi yang hilang tidak dibuat ulang, dan
  create dihentikan setelah percobaan cleanup dimulai.
- Untuk cleanup yang belum lengkap, periksa record tersisa dan sebabnya.
  Jika ada relasi di luar run atau marker berubah, koordinasikan tindakan
  terhadap ID yang tepat. Jangan ubah plan atau marker secara massal.
  Ulangi cleanup dengan `--settled` setelah ketidakpastian diselesaikan.
  Status akhir adalah `PASS` (exit 0), `FAIL` (1), atau `PARTIAL CLEANUP` (2).
- Manifest berada di `.jobtrail-qa/<run-uuid>.json` dan memuat owner UUID,
  marker, payload sintetis dan status, tanpa kredensial/token. Jika proses
  berhenti mendadak, lock lokal dapat tertinggal. Setelah memastikan proses
  mati dan RPC yang mungkin dikirim sudah selesai, hapus hanya
  `.jobtrail-qa/<run-uuid>.lock` untuk run itu dan lanjutkan dari manifest.
  Simpan manifest sampai hasil cleanup disetujui.

Di akhir sesi, bersihkan environment yang tersisa bila diperlukan:

```powershell
Remove-Item Env:JOBTRAIL_QA_EMAIL, Env:JOBTRAIL_SUPABASE_PUBLISHABLE_KEY -ErrorAction SilentlyContinue
```

## Tes offline

```powershell
node --test supabase/tests/hosted_fixtures.test.mjs
```

Tes menggunakan fetch palsu dan repository simulasi untuk kontrak fixture
deterministik. Baseline mencatat 14 tes harness dan 277 tes Flutter lulus.
QA-07 untuk perubahan status hosted tetap memerlukan otorisasi dan build S02
dengan alur tulis yang sudah disetujui.

## Hasil browser hosted · 25 November 2026

Profil `standard`, run `13707ca1-5dbd-4285-9342-fb1e6a795351`. Otomasi Chrome
dijalankan terhadap Flutter di `http://localhost:3000` menggunakan Chrome
DevTools Protocol dan pohon aksesibilitas Flutter. Lead memasukkan kredensial
langsung di Chrome. Navigasi, logout, pembacaan snapshot dan asersi dilakukan
oleh otomasi. Transport browser membatasi POST hosted yang diizinkan ke
snapshot dan endpoint Auth. Tidak ada mutasi fixture atau cleanup.

Acuan snapshot akun B `2026-11-25T14:30:23.885492+00:00` (tanggal WIB
`2026-11-25`). Data hidup pada acuan tersebut menunjukkan 6 lamaran, 5/8
(62,5%), 3 agenda dengan 2 mendatang (1 interview), 1 metadata dokumen,
1 tautan, dan 6 event status. Konversi 1/6 (sekitar 16,67%) tampil sebagai 17%.

**Hasil: 20 PASS, 0 FAIL, 0 BLOCKED.**
Lokasi bukti `.jobtrail-qa/browser/` di root JobTrail. `matrix.json` mencatat
hasil otomasi dan `server-metrics.json` menyimpan waktu acuan serta agregat.
Screenshot adalah bukti lokal. Bagikan hanya berkas bukti yang telah diperiksa,
tanpa direktori profil Chrome. Browser Back menguji entri riwayat localhost
yang tersedia. Rute Detail pernah dibuka melalui UI pada sesi B.

| Skenario | Ekspektasi | Aktual | Status | Bukti | Tindak lanjut |
|---|---|---|---|---|---|
| 01 Home | Total 6, satu Offering, target dan agenda sesuai jam server | 6 applications; weekly 5/8 (62,5%); 1 upcoming interview(s); Offering 1. | PASS | `01-home.png` | Cocokkan kembali jika tanggal WIB berubah. |
| 02a Weekly Goal | Sheet terbuka dengan capaian dan target yang sama | Weekly Goal opened and displayed server-relative achieved count and target. | PASS | `02-weekly.png` | — |
| 02b Notifikasi | Tiga notifikasi agenda dan ringkasan mingguan | Notification sheet opened with three agenda notifications and weekly progress. | PASS | `02-notifications.png` | — |
| 03 Detail dan riwayat | Buka aplikasi Offering dan tampilkan event Offering awal dengan waktu WIB | Offering opened by the fixture card; dated Offering event observed; status and delete controls absent. | PASS | `03-detail-history.png` | — |
| 04 Pencarian dan filter Board | Enam status, pencarian Offering, filter Screening | Board showed six status counts of one; search excluded nonmatching rows and Screening isolated its fixture card. | PASS | `04-board-search.png`, `04-board-filter.png` | — |
| 05 Filter dan relasi Jadwal | Tiga agenda, filter Test, dan buka lamaran Offering yang terkait | Schedule showed three agendas, Test filter isolated the fixture test, and its link opened the Offering application. | PASS | `05-schedule-filter.png`, `05-schedule-linked.png` | — |
| 06 Pratinjau metadata | Nama berkas sintetis, kategori CV, dan lamaran terkait terlihat | Preview showed the one CV metadata record, synthetic filename and linked Offering application. | PASS | `06-documents.png` | — |
| 07a Statistik | Enam status dengan satu lamaran tiap status, konversi 1/6 (sekitar 16,67%) | Six status counts of one; one-month filter selected; conversion numerator 1/6 displayed as 17%. | PASS | `07-statistics-distribution.png`, `07-statistics-conversion.png` | UI membulatkan konversi menjadi 17%. |
| 07b Filter periode | Pilih 1, 2, 3 bulan serta Saat Ini dan lihat periode aktif | Each of 1, 2 and 3 months and Saat Ini became the current period; all showed 6 fixtures because all dates are inside each window. | PASS | `07-period-1.png`, `07-period-2.png`, `07-period-3.png`, `07-period-s.png` | Fixture standar masuk semua jendela. Gunakan profil statistics untuk batas periode. |
| 08 Reload browser B | Data akun B dan relasi tetap ada setelah reload | Full browser reload restored B and matched all fixture IDs, six history records, and one link. | PASS | `08-reload-b.png` | — |
| 09 Logout B | Konfirmasi logout menampilkan Login | App confirmed sign-out and Chrome displayed Login. | PASS | `09-logout-b.png` | — |
| 10 Isolasi A | Kelima tab kosong dan tidak menampilkan data B | A identity verified; all five snapshot collections zero; no B fixture detected on any of five visited tabs. | PASS | `10-a-beranda.png`, `10-a-board.png`, `10-a-jadwal.png`, `10-a-dokumen.png`, `10-a-statistik.png` | — |
| 11a Browser Back setelah logout | Entri localhost sebelumnya tidak memulihkan data B | Chrome traversed a real previous localhost history entry; Login remained visible. No B fixture detail or data appeared. Previous URL: / | PASS | `11-back-logout.png` | Entri Back yang tersedia adalah /. |
| 11b Browser Back setelah masuk A | A tetap aktif, data dan Detail B tidak muncul | Chrome traversed a real previous localhost history entry; Account A remained active. No B fixture detail or data appeared. Previous URL: / | PASS | `11-back-a.png` | Entri Back yang tersedia adalah /. |
| 12 Kembali ke B | Semua ID fixture dan riwayat tetap sama | B identity restored after switching through A; browser snapshot retained all fixture IDs. | PASS | `12-return-b.png` | — |
| 13 Kegagalan refresh dan retry | Gagal baca snapshot, tampilkan data lama dan retry, lalu pulihkan data | CDP blocked only the snapshot request; stale warning and retry appeared; retry reloaded all fixture IDs and cleared error. | PASS | `13-refresh-failure.png`, `13-refresh-restored.png` | — |
| 14a Viewport 393 × 852 | Lima tab bisa dipilih dan area navigasi tidak terpotong | All five tabs were operable at exact 393 × 852; no top-level horizontal scrolling or clipped tab hit areas. | PASS | `14-393-beranda.png`, `14-393-board.png`, `14-393-jadwal.png`, `14-393-dokumen.png`, `14-393-statistik.png` | — |
| 14b Viewport 320 × 852 | Lima tab bisa dipilih dan area navigasi tidak terpotong | All five tabs were operable at exact 320 × 852; no top-level horizontal scrolling or clipped tab hit areas. | PASS | `14-320-beranda.png`, `14-320-board.png`, `14-320-jadwal.png`, `14-320-dokumen.png`, `14-320-statistik.png` | Saat scroll di posisi tertentu, FAB Home menutupi bagian label jumlah Lamaran Terbaru. |
| 15a Gate Home | Tambah lamaran dilaporkan nonaktif oleh aksesibilitas | Home Add is explicitly disabled in Chrome accessibility tree. | PASS | `01-home.png` | — |
| 15b Gate layar lain | Tambah di Board/Jadwal/Dokumen tidak membuka form dan aksi dokumen hanya preview | Tapping the visible Add control in Board, Schedule and Documents opened no form; document menu offered preview only. Board and Schedule nevertheless look active. | PASS | `14-393-board.png`, `14-393-jadwal.png`, `15-documents-menu.png` | Selaraskan tampilan dan semantik tombol Tambah Board/Jadwal dengan keadaan nonaktif. |

### Riwayat streak Home

Commit `3417925` menambahkan badge “Streak belum tersedia” pada Weekly Goal
dan kartu “Konsistensi mingguan” yang juga menampilkan status belum tersedia.
Kode saat itu tidak menghitung streak. Empat minggu adalah angka ilustrasi
desain. Commit `fb940b1` menghapus keduanya saat AppShell akun diperhalus
dan placeholder pengembangan dibersihkan.

Usulan untuk perubahan terpisah: hitung dari `appliedAt` pada snapshot akun
dengan tanggal acuan `referenceDate` dan bucket Senin–Minggu WIB. Sepakati
terlebih dahulu definisi konsistensi, misalnya minimal satu lamaran tercatat
per minggu berturut-turut. Minggu berjalan dapat menambah streak ketika
memenuhi ambang dan tidak memutuskannya sebelum berakhir. Gunakan derivasi
yang sama di Home dan Statistik. Nyatakan hasil sebagai streak aktivitas
tercatat jika snapshot dapat kehilangan lamaran yang dihapus atau jika
cakupan historis tidak diketahui. Uji Senin 00.00 WIB, minggu kosong,
akun kosong, dan pembaruan setelah refresh.

## Penutupan run dan kesiapan tim · 25 November 2026

| Pemeriksaan | Status | Bukti ringkas |
|---|---|---|
| Suite Flutter dan harness offline | PASS | Baseline 277 tes Flutter dan 14 tes harness Node. Finalisasi tidak mengubah harness atau kode Flutter. |
| Hosted create dan verifikasi terpisah | PASS | Profil `standard` di akun B. 6 lamaran, 3 agenda, 1 dokumen, 6 event awal, dan 1 tautan. |
| Browser QA, isolasi, dan pemulihan jaringan | PASS | 20 PASS, 0 FAIL, 0 BLOCKED. B → A → B, reload, gagal baca snapshot, retry, serta kontrol tulis yang tetap gated teramati. |
| Penutupan Chrome QA dan keadaan manifest awal | PASS | Jendela QA khusus ditutup dan endpoint DevTools berhenti. 10 create `CONFIRMED`, semua delete `PENDING`, tanpa lock run atau checkpoint tulis ambigu saat peninjauan. |
| Preflight hosted dan cleanup dry-run | PASS | Snapshot 25 November 2026 21.42 WIB. Identitas Auth cocok dengan pemilik manifest, ID dan payload termasuk marker cocok, keenam revisi lamaran = 1, history cocok, dan semua hitungan di luar fixture = 0. Exit verify/dry-run 0/0. |
| Penggunaan eksklusif dan izin lead | PASS | Lead mengonfirmasi semua sesi lain akun B berhenti dan RPC sebelumnya selesai tanpa hasil ambigu, lalu memberikan izin eksplisit untuk manifest ini. |
| Cleanup manifest | PASS | Pada 25 November 2026 21.47 WIB, 10 checkpoint delete `CONFIRMED` dan nol record fixture tersisa. |
| Verifikasi terpisah akun A dan B | PASS | Masing-masing snapshot mengembalikan nol lamaran, agenda, dokumen, event history, dan tautan. |

Ringkasan preflight dan postcheck berada di `.jobtrail-qa/finalize-preflight.json`
dan `.jobtrail-qa/finalize-cleanup.json`. Manifest akhir tetap disimpan dengan
status cleanup `PASS`. Bukti mentah dan profil Chrome tetap lokal dan diabaikan
Git. Pemeriksaan
client atas relasi tidak atomik dengan delete. Revisi lamaran melindungi
perubahan lamaran, tetapi agenda yang ditautkan secara bersamaan tidak
menaikkan revisi itu dan dapat ikut terhapus lewat cascade.

### Tindak lanjut UI

| Temuan | Pemilik | Tindak lanjut |
|---|---|---|
| Aksi Tambah Board tetap terlihat aktif meski tidak membuka form | Hanif · S02 Board | Samakan gaya dan semantik dengan status nonaktif sampai persistence siap. |
| Aksi Tambah Jadwal tetap terlihat aktif meski tidak membuka form | Fachriza · S05 Jadwal | Tampilkan status nonaktif pada UI dan aksesibilitas. |
| FAB Home dapat menutupi sebagian jumlah Lamaran Terbaru pada lebar 320 piksel | Ichsan · S01 Home | Periksa jarak konten dari FAB pada posisi scroll yang terdampak. |

### Otorisasi hosted QA untuk tim

1. Pemilik layar mengajukan akun disposable, profil, skenario, jendela waktu,
   operasi yang dibutuhkan, dan penanggung jawab cleanup. Lead mencatat
   persetujuan baca, tulis, dan cleanup sesuai cakupan masing-masing.
2. Jalankan dry-run dan verifikasi read-only. Operator memasukkan password
   melalui prompt lokal tertutup. Simpan UUID run dan ringkasan hasil.
3. Jalankan create atau mutasi modul hanya sesuai persetujuan. Untuk cleanup,
   hentikan browser dan writer lain, selesaikan RPC sebelumnya, periksa
   kepemilikan, marker, revisi dan relasi, lalu minta izin cleanup spesifik
   untuk UUID tersebut. Jangan gunakan akun secara bersamaan saat cleanup.
4. Jika hasil parsial atau ambigu, simpan manifest dan ringkasan, hentikan
   mutasi lain, dan rekonsiliasi melalui prosedur pemulihan di atas. Jika
   cleanup lulus, verifikasi snapshot akun target dan akun kontrol secara
   independen sebelum menyatakan run selesai.
