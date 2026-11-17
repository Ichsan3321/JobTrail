# JobTrail | AGENTS.md

**Versi 2.0 · Week 12 · 17 November 2026**  
**TEKBER A, Kelompok 1, Institut Teknologi Sepuluh Nopember**  
**Koordinator/integrator: Ichsan Ramadhan**  
**Fase aktif:** persiapan fondasi bersama dan implementasi frontend Flutter.

> BACA SEBELUM MENGERJAKAN APA PUN. File ini berlaku untuk Codex, Claude Code, Gemini, Cursor, ChatGPT, Google AI Studio, dan asisten AI lain yang dipakai anggota. Tujuannya adalah menghasilkan satu aplikasi JobTrail, satu arsitektur, satu dataset, satu design system, dan satu laporan; bukan tujuh project terpisah. Week 12 di sini adalah rencana internal berdasarkan progres Week 11; instruksi resmi Week 12 dan deadline harus dikonfirmasi. Jangan menganggap seluruh target dalam file ini sebagai syarat resmi dosen.

## 1. Protokol wajib sebelum bekerja

1. Identifikasi nama anggota, task ID dari Master Spreadsheet Week 12, screen ID, ruang lingkup, dan deliverable yang diminta. Jika PIC tidak diketahui dan perubahan berisiko menimpa pekerjaan orang lain, minta konfirmasi.
2. Untuk coding agent dengan workspace: baca `AGENTS.md`, `README.md`, dokumen yang sudah tersedia di `docs/`, `pubspec.yaml`, struktur `lib/`, serta file terkait. Periksa `git status -sb`, branch aktif, dan `git diff`. Jangan menghapus atau me-reset perubahan pengguna. Jika dokumen/kontrak yang disebut di sini belum dibuat, tandai belum tersedia; jangan berpura-pura sudah membacanya.
3. Gunakan Figma final sebagai acuan UI; buka frame yang tepat melalui koneksi Figma berizin jika tersedia. Jika tidak, mintalah screenshot/export frame dan state dari anggota. URL saja bukan bukti AI telah menginspeksi layer atau prototype. Jangan merancang ulang UI berdasarkan tebakan.
4. Rencanakan file yang akan disentuh. Kerjakan hanya task milik PIC, gunakan komponen bersama dan kontrak yang sudah ada. Perubahan shared file, route, schema, dependency, atau design system memerlukan koordinasi dengan pemiliknya.
5. Kerjakan secara inkremental. Untuk agent yang tidak bisa mengedit workspace, beri instruksi/kode dengan path yang jelas; jangan mengklaim file telah diubah.
6. Jalankan verifikasi yang sesuai, laporkan hasil nyata, keterbatasan, dan tindakan lanjutan. Jangan mengarang logbook, screenshot, hasil build/test, PR, atau status implementasi.
7. Jangan commit/push/merge/force-push, mengubah konfigurasi remote/izin, menghapus branch, memodifikasi Figma/Docs bersama, atau melakukan tindakan eksternal tanpa instruksi eksplisit anggota berwenang. Jangan mengakses file/secret di luar scope project.

**Sumber kebenaran:** (1) instruksi tugas resmi dan keputusan eksplisit tim terbaru; (2) kontrak kode dan data bersama yang sudah disetujui; (3) Figma final + GSM Week 12; (4) master spreadsheet untuk PIC, task dan status; (5) laporan Week 11 sebagai baseline; (6) saran AI. Jika bertentangan, jangan diam-diam mengubah salah satu: laporkan konflik dan usulan kepada koordinator. Rencana struktur di file ini bukan bukti bahwa file Dart tersebut sudah dibuat.

## 2. Link utama tim

| Resource | URL / lokasi |
|---|---|
| GitHub repository | https://github.com/Ichsan3321/JobTrail |
| Development branch | https://github.com/Ichsan3321/JobTrail/tree/develop |
| Figma Design (link terbaru) | https://www.figma.com/design/292w6TVRmn1YCYbVXuRNp5/JobTrail-%E2%80%94-Mobile-App-UI-UX?node-id=1-3&p=f |
| Google Docs laporan (baseline) | https://docs.google.com/document/d/1Cz7plApW-x0Mb_D9KoZ4TsDEtMt3ja2CXmQo4FyOhW8/edit?tab=t.0 |
| Master Drive | https://drive.google.com/drive/folders/1PXHKfprNf3zwka_H_6UlW_1mOdmVnbx-?hl=ID |
| Referensi Champify | https://drive.google.com/open?id=1DCbPWAX3ELn02KWFX1Nt6CFmAyCbY12K&usp=drive_copy |
| Form progress/logbook (dari Week 11) | https://intip.in/ProgressKelompokTEKBER26 |
| Master Spreadsheet Week 12 | `JobTrail_Master_Week12.xlsx` → masukkan link Google Sheets setelah diunggah |
| Panduan AI | `AGENTS.md` di root repository (file ini) |
| Submission Week 12 / folder bukti | Belum dikonfirmasi; gunakan link resmi setelah tersedia |

Repository bersifat private pada screenshot terakhir. Pastikan undangan collaborator diterima dan AI/akun yang digunakan mempunyai akses yang sah. Jangan meminta token, cookie, password, atau kredensial ditempel dalam prompt. Jangan mengubah akses repository menjadi public hanya agar AI bisa membacanya. Integrasi Figma bersifat opsional; bila MCP tidak tersedia atau limit, gunakan screenshot dan GSM; jangan menggunakan kredensial orang lain. Link frame utama yang diketahui dari audit sebelumnya (pastikan masih menunjuk frame final):

| ID | Figma node ID |
|---|---|
| S01 | `80:4172` |
| S02 | `173:1792` |
| S03 | `214:3519` |
| S04 | `284:7410` |
| S05 | `270:3817` |
| S06 | `64:4354` |
| S07 | `111:5677` |

Untuk membuka node, gunakan file key yang sama dan parameter `node-id`, misalnya `node-id=80-4172`. Screenshot state tambahan harus diambil dari Figma final, bukan dibuat ulang oleh AI.

## 3. Product scope (locked)

**JobTrail** — Job & Internship Application Tracker. Target: mahasiswa pencari magang, mahasiswa tingkat akhir, fresh graduate. Fungsi: mencatat dan mengelola lamaran kerja/magang, melacak status seleksi, agenda wawancara/tes, catatan, informasi CV/portofolio, dan statistik. Bukan platform penyedia lowongan, auto-apply, HRIS, recruiter chat, AI CV generator, atau aplikasi yang otomatis mengakses LinkedIn.

Stack: Flutter/Dart, target pengembangan Android dan Web. Baseline environment koordinator: Flutter 3.47.9 stable dan Git berjalan; `flutter analyze`, `flutter test` default, serta demo default via web-server sudah berhasil. Branch `main` dan `develop` telah disinkronkan berdasarkan output Git terakhir. Belum ada verifikasi bahwa boilerplate baru, collaborator, feature branches, tema, atau data model sudah selesai. Periksa versi aktual pada workspace; jangan upgrade SDK/dependency seluruh tim tanpa persetujuan.

**Target internal Week 12:** fondasi shared, tujuh screen Flutter yang mengikuti Figma, navigasi terhubung, state/interaksi dasar menggunakan satu mock data source, QA Chrome/Android sesuai ketersediaan, dokumentasi progres nyata. Gunakan state in-memory jika perlu. Persistence, login/Sign Up, Supabase/Firebase, file upload nyata, push notifications, dan deployment production adalah backlog sampai instruksi resmi/keputusan tim menetapkannya; dokumentasikan secara jujur. Jangan memperlakukan simulasi atau mock sebagai integrasi nyata.

## 4. Kepemilikan screen, branch, dan dukungan

| PIC | NRP | Screen / direktori utama | Feature branch | Tanggung jawab pendukung |
|---|---|---|---|---|
| Ichsan Ramadhan | 5026241126 | S01 Home / `lib/screens/home/` | `feature/home` | Fondasi project, AGENTS.md, repository, integrasi bersama, final QA |
| Muhammad Hanif Syahnandra | 5026241176 | S02 Board / `lib/screens/board/` | `feature/board` | Kontrak routing, app shell/navbar, uji navigasi lintas screen |
| Lenno Andhika Pramudya Arkadewa | 5026241057 | S03 Detail / `lib/screens/detail/` | `feature/detail` | Dokumentasi implementasi, screenshot, format laporan dan PDF |
| Muhammad Rifqi Ahnaf Novanto | 5026241118 | S04 Add/Edit / `lib/screens/application_form/` | `feature/application-form` | Model lamaran, status, validasi, kontrak CRUD mock |
| Fachriza Rizky Susanto | 5026241092 | S05 Schedule / `lib/screens/schedule/` | `feature/schedule` | Kontrak agenda, relasi lamaran, dataset bersama dengan Ziyaad |
| Ahmad Farhad Mabrury | 5026241034 | S06 Documents / `lib/screens/documents/` | `feature/documents` | Theme, GSM, shared widgets, kontrak metadata dokumen |
| Muhammad Ziyaad Syafiq | 5026241193 | S07 Statistics / `lib/screens/statistics/` | `feature/statistics` | Mock dataset, definisi/perhitungan metrik, rekap progress/logbook |

Tujuh feature branches dibentuk setelah fondasi bersama siap, bukan dari commit awal counter app. Pembagian ini merupakan rencana Week 12, bukan klaim tugas selesai. Task ID `W12-xxx` dan status ada di workbook. PIC boleh melaksanakan tugas support yang didelegasikan tetapi wajib koordinasi ketika menyentuh file shared. Tidak boleh mengimplementasikan screen orang lain untuk menghindari konflik, kecuali koordinator mendelegasikan secara eksplisit.

## 5. Kontrak UI dan user flow

| Screen | Wajib mengikuti Figma | Interaksi dasar yang ditargetkan | Hubungan |
|---|---|---|---|
| S01 Home Dashboard | Header, Weekly Goal, total/interview/offering, jadwal terdekat, lamaran terbaru, navbar, FAB | Notification Overlay, Weekly Goal Details Bottom Sheet, scroll, tap jadwal/lamaran/tambah | S04 tambah, S05 jadwal, S03 detail berdasarkan ID |
| S02 Application Board | Kartu lamaran, status filter, pencarian, Filter & Urutkan, pratinjau, empty state | Filter/search/sort, pratinjau, Buka Detail, Tambah Lamaran | S03 berdasarkan ID, S04 tambah |
| S03 Application Detail | Informasi perusahaan/posisi, sumber, tanggal, tipe kerja, gaji opsional, agenda, history status, catatan | Back sesuai asal, edit, ubah status, dialog hapus, akses jadwal | S04 edit ID yang sama, S05 terkait, setelah hapus kembali aman |
| S04 Add/Edit Application | Form tambah/edit, tanggal, status, lokasi/tipe kerja, gaji, dokumen, catatan | Required validation, date picker, status picker, simpan, konfirmasi batal jika dirty | Tambah → S02; edit → S03; batal kembali ke asal |
| S05 Interview Schedule | Kalender/strip minggu, daftar agenda, filter, empty state, Tambah Agenda | Pilih tanggal/filter, pilih lamaran terkait, detail agenda, simpan mock | S03 berdasarkan applicationId; agenda tidak berdiri tanpa lamaran |
| S06 Documents | Daftar CV/portofolio, pencarian/filter, pratinjau metadata, tambah metadata | Search/filter, preview bottom sheet, tambah/edit metadata jika sesuai desain | Dokumen dipilih di S04 dan ditampilkan di S03 |
| S07 Statistics | Filter periode, ringkasan, distribusi tahapan, metrik pencapaian, tren | Filter Saat Ini/1/2/3 Bulan Terakhir, detail distribusi, scrolling | Data dihitung dari shared state yang sama dengan S01/S02 |

Bottom navigation: **Beranda, Board, Jadwal, Dokumen, Statistik**, urutan tetap; hanya S01, S02, S05, S06, S07 berada di tab bar. S03 dan S04 merupakan detail/form turunan. Gunakan satu app shell dan satu routing strategy. Jangan menambah navbar independen pada setiap screen bila shell sudah menyediakannya. Single source of truth untuk selected tab. Buat callback/routing sesuai kontrak navigator yang sudah ada; jangan membuat route duplikat atau pass data palsu.

Alur inti: Home → tambah → validasi → simpan → Board → pratinjau → Detail → ubah status/edit/agenda → Home & Statistics refleksikan state. Jangan mengarahkan kartu perusahaan berbeda ke satu detail Nusa Digital yang di-hardcode. Back, close sheet, cancel, dialog konfirmasi harus masuk akal. Jika shared CRUD belum tersedia, nyatakan interaksi yang masih mock/placeholder dan koordinasikan kontraknya; jangan membangun repository tandingan di screen.

## 6. GSM (locked)

| Token | HEX | Peran |
|---|---|---|
| Primary | #5B5BF0 | Aksi utama, tab aktif |
| Primary Dark | #4343C9 | Pressed, aksen teks |
| Primary Light | #EEEEFF | Highlight/chip |
| Mint | #2DD4A7 | Progres, sukses, titik logo |
| Peach | #FFB37A | Aksen |
| Peach Tint | #FFF4EC | Surface aksen |
| Navy | #1E2A4A | Teks utama |
| Gray | #5A6380 | Teks sekunder |
| Background | #F7F7FC | Latar |
| Border | #E4E4F0 | Outline/separator |
| White | #FFFFFF | Surface |
| Mint Dark | #10A982 | Titik logomark versi tanpa kotak |

| Status (enum usulan) | Label | Foreground | Background |
|---|---|---|---|
| applied | Applied | #475569 | #F1F5F9 |
| screening | Screening | #B45309 | #FEF3C7 |
| test | Test/Psikotes | #B45309 | #FEF3C7 |
| interview | Interview | #0369A1 | #E0F2FE |
| offering | Offering | #047857 | #D1FAE5 |
| rejected | Rejected | #B91C1C | #FEE2E2 |

Screening dan Test/Psikotes memiliki warna sama tetapi status berbeda. Offering dan Rejected bukan tahap wajib yang berurutan; Rejected dapat terjadi dari berbagai tahap. Gunakan enum dan mapping label yang disetujui di shared model.

- **Poppins** untuk heading utama dan identitas visual; **Plus Jakarta Sans** untuk body, label, form, kartu, caption, nav. Gunakan font yang benar melalui aset berlisensi/proyek atau paket yang disetujui. Jangan mengganti dengan Inter/Roboto diam-diam atau menambahkan file font palsu. Jangan meminta AI mengarang logo; gunakan aset resmi yang tersedia/berizin dari Figma.
- Acuan desain **393 × 852 logical px**, bukan ukuran root yang dipaksa pada semua device. Gunakan `SafeArea`, constraint responsif, scroll yang benar, penanganan keyboard dan text scaling. Untuk preview desktop boleh memakai container mobile yang terpusat sesuai shell; jangan merusak Android.
- Spacing 8/12/16/24/32, radius kartu 20, tombol 14, target sentuh min. sekitar 44 logical px (lebih besar jika perlu). Navbar fixed/di luar scroll body; FAB tidak menutup konten; beri padding bawah cukup. Jangan menggunakan horizontal overflow tanpa tujuan.
- Gunakan komponen bersama: `AppButton`, `StatusChip`, `ApplicationCard`, `StatCard`, `ProgressCard`, `InputField`, `ScheduleCard`, `BottomNavbar`; tambah `SectionHeader`/`EmptyState` jika disetujui. Gunakan definisi yang ada, tidak wajib nama persis jika kontrak repo telah disepakati. Jangan menyalin implementasi shared ke tujuh screen.
- Hindari desain generik AI: gradient dekoratif tambahan, glassmorphism, emoji berlebihan, efek neon, ikon acak, atau redesign layout. Ikuti hierarki dan data Figma; gunakan grafik/aksen hanya sesuai referensi. UI berbahasa Indonesia dengan label status baku.

## 7. Arsitektur kode bersama (rencana awal)

Periksa struktur aktual sebelum membuat file. Nama kelas dan file di bawah adalah rancangan yang harus digunakan secara konsisten setelah disepakati, bukan jaminan sudah ada.

```text
JobTrail/
  AGENTS.md
  README.md
  pubspec.yaml
  assets/ {fonts, icons, images}
  docs/ {GSM.md, ARCHITECTURE.md, DUMMY_DATA.md, CONTRIBUTING.md}
  lib/
    main.dart
    core/ {theme, constants, routes}
    models/                     # application, status/history, agenda, document
    data/                       # fixture and shared state/repository
    widgets/                    # shared reusable UI, app shell if agreed
    screens/
      home/ board/ detail/ application_form/
      schedule/ documents/ statistics/
  test/
```

Gunakan satu entrypoint (`lib/main.dart`), satu `MaterialApp`, satu tema, satu sumber navigasi, satu state/data layer. Pilih pendekatan state management sederhana yang sudah disepakati (misalnya ChangeNotifier/ValueNotifier bawaan); jangan memasang paket state management atau service locator sendiri-sendiri. Pisahkan data, logic, dan UI secukupnya; gunakan constructor injection untuk shared dependencies bila sesuai arsitektur. Tidak perlu clean architecture bertingkat atau codegen jika belum diperlukan. Jangan membuat package Flutter baru. Jangan menyalin proyek HTML/React AI Studio ke repo Flutter: gunakan itu hanya sebagai referensi visual dan implementasikan native Dart widgets.

**Shared file ownership:** Ichsan (entrypoint, fondasi, integrasi, pubspec approval), Hanif (routes/shell/nav), Farhad (theme/widgets/assets), Rifqi (application/status contract), Fachriza (agenda contract), Farhad (document contract), Ziyaad + Fachriza (fixture/aggregate logic). Semua perubahan kontrak lintas screen harus ditinjau Ichsan dan PIC terkait lebih dulu. Jangan langsung mengedit `main.dart`, `pubspec.yaml`, `lib/core`, `lib/data`, `lib/models`, atau `lib/widgets` dalam task screen tanpa izin yang sesuai. Jangan membuat ulang file shared hanya karena error import; periksa branch dan kontrak yang benar.

## 8. Kontrak data dan integrasi mock

Nama berikut adalah kontrak konseptual (nama Dart aktual mengikuti model yang disetujui); ID stabil dan unik. Data satu sumber di `lib/data` (path aktual bisa berubah atas persetujuan). `docs/DUMMY_DATA.md` mencatat fixture, anchor date, dan aturan metrik.

| Entitas | Field minimal (konseptual) |
|---|---|
| Application | id, company, position, source, appliedAt, status, location/workType, optional salary, notes, documentIds |
| StatusHistory | id, applicationId, status, changedAt |
| Agenda | id, applicationId, type (interview/test), scheduledAt, locationOrLink, notes opsional |
| Document | id, title, category (CV/Resume atau Portofolio), fileName, version, updatedAt, notes |
| WeeklyGoal | target (contoh desain 8), weekStart/referenceDate; jumlah tercapai dihitung dari lamaran |

- Simpan referensi via ID, bukan duplikasi object/string perusahaan per screen. Tidak ada agenda/dokumen orphan; aturan penghapusan lamaran dan referensi dokumen perlu disepakati (mis. delete agenda terkait, jangan hapus dokumen bersama otomatis). Rutekan detail/edit dengan ID yang benar. Gunakan null safety, tipe tanggal/waktu nyata, dan enum status. Gunakan format waktu WIB untuk data contoh Indonesia; satu pendekatan timezone konsisten, bukan penambahan offset sembarang.
- Existing visual mock S01: Lentera Tech / Frontend Developer Intern / Applied; Nusa Digital / UI/UX Designer Intern / Interview / 16 Nov 2026 10:00 WIB; Arunika Finance / Business Analyst Intern / Screening / tes 17 Nov 2026 13:00 WIB. Periksa Figma final dan fixture disetujui sebelum menetapkannya; perbedaan lama antar-Figma tidak boleh disalin sebagai dua dataset. Pilih satu versi dan catat keputusan. Angka ilustrasi 24 total, 3 interview, 1 offering, 5/8 target, streak 4 minggu **bukan data riil atau fixture final terverifikasi**.
- Home, Board, Detail, Form, Schedule, Documents, dan Statistics melihat state yang sama. CRUD mock, perubahan status, dan tambah agenda yang telah disetujui harus memperbarui sumber state bersama, bukan angka di-hardcode. Bila hanya UI simulasi, label dokumentasi sebagai simulasi. Data in-memory dapat hilang saat restart; nyatakan keterbatasan.
- Total = jumlah lamaran dalam filter; current interview/offering = status saat ini; distribusi = count per enum / total (total nol → 0 atau empty state). Weekly goal = jumlah aplikasi baru pada minggu terkait / target (target nol → kondisi aman), progress bar dibatasi 0–100% tetapi angka capaian boleh >100% jika didefinisikan. Periode harus sepakat (mis. rolling bulan atau kalender); anchor demo konsisten dan terpisah dari waktu nyata. Label “Besok” hanya jika tanggal benar-benar besok terhadap reference date. Jangan memakai tanggal komputer yang berubah-ubah untuk fixture/test deterministik.
- Interview conversion membutuhkan riwayat status pernah mencapai Interview; response rate memerlukan definisi dan data respons yang disetujui. Jangan memakai current Interview sebagai pengganti conversion atau mengambil angka dari screenshot tanpa data pendukung. Streak perlu data history mingguan; jika belum ada, tampilkan state belum tersedia atau contoh berlabel. Ziyaad menetapkan definisi bersama, bukan setiap AI membuat rumus sendiri.
- Validasi form: perusahaan dan posisi wajib; sumber/tanggal/status mengikuti desain dan aturan model yang disetujui; tanggal/nominal masuk akal; gaji opsional; jangan simpan data invalid. Pengeditan mempertahankan ID; tanggal/format/relasi yang valid. Hapus butuh konfirmasi. Gunakan mock, tidak ada secret dan data personal asli untuk pengujian.

## 9. Git workflow kelompok (jangan melangkahi fondasi)

`main` = baseline stabil; `develop` = integrasi; `feature/*` = pekerjaan anggota; PIC integrator memeriksa PR. Tunggu konfirmasi fondasi di `develop` sebelum membuka feature branch. Ini instruksi contoh untuk anggota, bukan perintah otomatis bagi AI.

```powershell
# Pertama kali (setelah mendapat akses repo)
git clone https://github.com/Ichsan3321/JobTrail.git
cd JobTrail
git fetch origin
git switch develop
git pull --ff-only origin develop
flutter pub get
# Jika branch sendiri BELUM ada di remote:
git switch -c feature/home  # ganti sesuai PIC
# Jika branch sendiri SUDAH dibuat di remote, gunakan:
# git switch --track origin/feature/home
```

Sebelum edit: `git status -sb`; periksa repo dan branch. Sesudah edit: `git diff --stat`, `git diff`, jalankan formatter pada file yang diubah, `flutter analyze`, `flutter test`. Jangan menjalankan formatter masal pada file anggota lain. Jika perlu update dari develop, pastikan working tree bersih, `git fetch origin` lalu `git merge origin/develop` di feature branch; berhenti saat konflik dan koordinasi, jangan memakai force push/reset hard atau menangani semua konflik dengan `ours/theirs` secara membabi buta.

```powershell
# Setelah review lokal; user/PIC yang menjalankan commit dan push
git add lib/screens/home/  # sesuaikan path, tambah test sendiri jika ada
git diff --cached --stat
git commit -m "feat(home): implement weekly goal and dashboard"
git push -u origin feature/home
```

Buat Pull Request ke `develop`, bukan langsung ke `main`. Cantumkan task ID, ringkasan perubahan, screenshot, hasil analyzer/test, risiko, dependensi, dan daftar shared files yang disentuh. Review dan approval integrator sebelum merge. Integrator merge `develop` ke `main` hanya setelah QA bersama dan sesuai pedoman tim. Jangan push hasil yang tidak terkait, kredensial (.env/key), build output, cache tooling, atau file IDE lokal. `pubspec.lock` Flutter app tetap versioned; jangan mengubah dependency tanpa koordinasi. Tidak boleh mengklaim PR merged tanpa bukti.

## 10. QA dan definition of done

Sebuah task baru boleh berstatus Selesai bila output yang ditargetkan ada, bisa diperiksa, dan bukti/link disertakan. Untuk screen, minimal:

- UI sesuai frame dan state Figma yang relevan; GSM final benar; viewport mobile 393 × 852 dan ukuran lain tidak overflow; scroll sampai bawah; navbar, FAB, overlay, serta keyboard tidak menghalangi konten penting.
- Aksi utama dan state empty/error/loading yang relevan jelas; detail/edit membuka ID yang benar; status/history dan jumlah statistik menggunakan state bersama. Back/cancel aman; tidak ada dead tap yang mengklaim aksi sudah bekerja. Batasi state opsional sesuai waktu.
- Format file yang diubah (`dart format <path>`), `flutter analyze`, `flutter test` (test widget/logic yang relevan; update test counter bawaan hanya bila app sudah berubah). Jalankan `flutter run -d chrome` atau `flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080`; buka `http://localhost:8080` bila memakai web-server. Android diuji apabila device/emulator tersedia; jangan klaim platform teruji jika belum. Peringatan Visual Studio desktop tidak memblokir target Android/Web. Jangan sekadar menghapus test agar lulus.
- Uji alur tim: Home→Add→Board→Detail→Edit/Simpan→status→Home/Stats; Home→Schedule→Detail; Documents→Form→Detail; semua 5 tab; kosong/invalid/batal/hapus; scroll dan filter periode; cek regresi setelah PR digabung.
- Bukti: commit/PR yang bisa diakses, screenshot running aktual (bukan hanya Figma), log test aktual, status dan hambatan pada Master Spreadsheet. Selesaikan review dengan PIC terkait. Waktu/target internal bukan bukti.

## 11. Figma, Google Docs, spreadsheet dan support

**Figma:** gunakan file yang sama, `FINAL UI & PROTOTYPE`, frame milik PIC. Ambil konteks visual, asset, komponen, dan state. Jika perlu perubahan desain yang berdampak lintas screen, ajukan perubahan dulu; jangan mengubah file secara diam-diam. Jangan mencampur kode debug dengan hasil Figma.

**Laporan:** gunakan laporan Week 11 sebagai baseline (BAB I–III + kontribusi), bukan mengulang semua narasi. Untuk Week 12, struktur tambahan yang diusulkan: lingkungan pengembangan, GitHub dan arsitektur, implementasi screen, integrasi/navigasi/data mock, pengujian, progres dan backlog. Nomor BAB/subbab pastikan dari instruksi resmi/keputusan tim sebelum menyisipkan. Lenno mengoordinasi dokumen; masing-masing PIC menyerahkan ringkasan implementasi, screenshot asli, path file, aksi yang benar-benar berfungsi, keterbatasan serta link PR. Bahasa Indonesia formal, ringkas per fitur seperti Champify, caption unik/berurutan, link dapat dibuka grader, tidak menjiplak contoh. Kontribusi tanggal/nama/kontribusi aktual bila syaratnya tetap halaman terakhir. Jangan mengklaim backend, autentikasi, upload nyata, atau test bila belum ada.

**Spreadsheet:** gunakan `JobTrail_Master_Week12.xlsx`/Google Sheets tim. Update `Task Tracker` status (`Belum Mulai`, `Proses`, `Review`, `Selesai`, `Terblokir`), bukti dan catatan blocker; `Logbook Kontribusi` hanya untuk pekerjaan aktual, `QA Integrasi` hasil pengujian nyata. Dashboard dan jobdesc menarik formula; jangan menimpa formula. Target 17–22 November adalah usulan internal; deadline resmi belum diverifikasi. Satu file master bersama, bukan tujuh salinan yang tidak sinkron. Pastikan aturan/logbook Week 12 terbaru sebelum submit.

**Support:** gunakan task ID/pemilik di spreadsheet. Saat ada blocker lintas anggota, laporkan branch, task, file, error yang dapat direproduksi, tindakan dicoba, PIC yang dibutuhkan, dan solusi yang diusulkan. Jangan mengganti screen/dependency/API contract untuk mengakali blocker tanpa persetujuan.

## 12. Starter prompt (copy, isi bagian kurung, kirim ke AI)

```text
Baca seluruh AGENTS.md di root repo (atau attachment ini) sebagai panduan wajib JobTrail Week 12.
Saya: [nama/PIC], Task ID: [W12-xxx], Screen/support: [Sxx atau area].
Scope yang saya minta: [jelaskan satu deliverable spesifik].
Branch/lingkungan: [feature branch / hanya chat / Figma / Docs].
Figma referensi: [link frame atau screenshot/export].
Input/kontrak kode yang tersedia: [path file atau lampiran]; keterbatasan: [jika ada].
Periksa AGENTS.md, README, struktur repo, dan kontrak bersama sebelum bekerja.
Jangan mengubah jobdesc, GSM, navigasi, model/dataset, atau file anggota lain tanpa izin.
Ikuti Figma yang benar-benar dapat diakses, atau gunakan screenshot saya; jangan mengklaim akses yang tidak ada.
Jika coding, implementasikan hanya bagian saya dengan Flutter/Dart dan shared state/widget yang sudah ada.
Jangan commit/push/merge atau mengubah file bersama secara otomatis. Uji hanya yang benar-benar dapat dijalankan.
Berikan output siap digunakan, file yang dibuat/diubah, cara menjalankan dan menguji,
hasil test aktual, keterbatasan/blocker, dampak lintas screen, dan update logbook yang faktual.
Jika ada konflik, berhenti pada bagian yang berisiko dan tulis usulan untuk koordinator.
```

Contoh request sesuai PIC (gabungkan dengan starter prompt, bukan izin menimpa shared files):

| PIC | Prompt tugas spesifik |
|---|---|
| Ichsan | Pertama audit fondasi `develop` dan siapkan kontrak/placeholder shared sebelum implementasi S01. Setelah disetujui, implementasikan Home, Notification dan Weekly Goal menggunakan state bersama. |
| Hanif | Implementasikan S02 Board sesuai Figma, termasuk filter/search/pratinjau. Koordinasikan shell/routing dan uji alur detail/tambah dengan Rifqi/Lenno; jangan mengubah schema sendiri. |
| Lenno | Implementasikan S03 dari applicationId dengan history, status/edit/hapus/agenda. Siapkan ringkasan implementasi dan screenshot nyata untuk laporan. |
| Rifqi | Susun kontrak model/CRUD bersama, lalu implementasi S04 tambah/edit dengan validasi dan date/status picker serta dirty cancel. Gunakan shared repository/state. |
| Fachriza | Implementasi S05 dengan relasi agenda ke applicationId, filter kalender, empty state dan tambah agenda mock. Sinkronkan dataset dengan Ziyaad. |
| Farhad | Siapkan GSM/theme dan komponen yang disepakati, lalu implementasi S06 metadata CV/portofolio, filter dan preview. Tidak ada upload nyata sebelum fase backend. |
| Ziyaad | Tetapkan fixture dan metrik yang disetujui; implementasi S07, filter periode, distribusi, tren, dan kasus data kosong dari shared state. Rekap bukti progress. |

## 13. Format laporan hasil AI / PR / logbook

```text
Task ID dan PIC:
Branch:
Output yang dibuat:
File yang dibuat/diubah:
Shared contract yang digunakan:
Cara menjalankan:
Pengujian aktual (command + hasil; atau BELUM DIJALANKAN):
Batasan / blocker:
Dampak atau koordinasi dengan PIC lain:
Bukti / link commit, PR, screenshot (atau BELUM ADA):
Status yang disarankan: Belum Mulai / Proses / Review / Selesai / Terblokir
```

Usulan perubahan: tulis task/PIC, spesifikasi lama, perubahan yang diusulkan, alasan, file/screen/model terdampak, risiko, dan keputusan yang dibutuhkan. Sampai disetujui, jangan mengubah scope. Koordinator memperbarui dokumen serta master spreadsheet agar semua anggota membaca versi yang sama.

**Prinsip akhir: satu repo, satu GSM, satu data source, satu navigasi, satu laporan, tujuh PIC. Integrasikan hasil, jangan mengganti pekerjaan anggota lain.**
