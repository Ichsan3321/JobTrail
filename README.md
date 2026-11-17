# JobTrail

Job & Internship Application Tracker untuk mahasiswa dan fresh graduate.
Flutter/Dart, target Android dan Web. TEKBER A · Kelompok 1 · ITS.

**Status: fondasi shared Week 12, menunggu review integrasi.** Tujuh screen masih
placeholder; UI Figma final dan interaksi lengkap merupakan tugas masing-masing PIC.
State memakai satu dataset demo in-memory dan hilang setelah restart. Belum ada
autentikasi, backend, persistence, upload nyata atau deployment production.

Panduan kolaborasi otoritatif: [AGENTS.md](AGENTS.md).
Fondasi disiapkan atas otorisasi Ichsan selaku koordinator pada branch `develop`.
Task ID W12 belum diverifikasi karena workbook master tidak tersedia di workspace.
Tidak ada commit/push/merge atau perubahan remote yang dilakukan.

## Menjalankan

Environment terverifikasi: **Flutter 3.47.9 stable, Dart 3.13.7**.
Tidak ada dependency baru; font Poppins dan Plus Jakarta Sans beserta OFL dibundel lokal.

```powershell
flutter pub get
flutter run -d chrome
```

Alternatif server lokal:

```powershell
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080
```

Buka http://localhost:8080. Untuk Android, hubungkan device/emulator lalu jalankan
`flutter devices` dan `flutter run -d <device-id>`. Pengujian Android pada pekerjaan
fondasi ini belum dilakukan karena tidak ada device Android terdeteksi.
Gunakan SDK proyek yang sama; jangan upgrade dependencies/SDK bersama tanpa koordinasi.

## Yang sudah tersedia

- Satu `JobTrailApp`, `MaterialApp`, tema GSM, dan font lokal.
- Model immutable, fixture tunggal, `JobTrailStore` berbasis ChangeNotifier.
- CRUD API in-memory untuk lamaran/status, agenda, metadata dokumen dan weekly goal.
- Validasi input, referensi ID, history status dan agregasi dasar dari state yang sama.
- Shell lima tab: Beranda, Board, Jadwal, Dokumen, Statistik.
- Route bertipe Detail, Add/Edit berdasarkan applicationId, back/cancel dan save-result contract.
- Komponen dasar reusable dan tujuh placeholder yang dapat diganti secara independen oleh PIC.
- Test state/integritas referensi, navigasi, state kosong dan layout responsif/text scaling.

Placeholder S04 hanya menampilkan mode tambah/edit dan Batal. CRUD dan hasil save
route diuji melalui API, bukan form pengguna lengkap. Status picker, hapus konfirmasi,
filter/search, kalender, sheets/overlay dan grafik final belum diimplementasikan.
Icon launcher/favicon bawaan Flutter dan Material icons pada shell masih sementara;
aset merek resmi perlu disiapkan Farhad. Tidak ada klaim logo Figma telah diterapkan.

## Struktur akhir fondasi

```text
JobTrail/
  AGENTS.md                        # dipertahankan tanpa perubahan
  README.md
  pubspec.yaml                     # registrasi font lokal
  pubspec.lock                     # dependency lock dipertahankan
  assets/fonts/
    poppins/                       # Regular, SemiBold, Bold + OFL.txt
    plus_jakarta_sans/              # variable upright + OFL.txt
  docs/
    ARCHITECTURE.md
    GSM.md
    DUMMY_DATA.md
    CONTRIBUTING.md
    QA.md
    qa/                            # screenshot aplikasi berjalan + browser-smoke.json
  lib/
    main.dart
    app.dart
    core/
      constants/                   # app_tokens.dart, app_dates.dart
      theme/                       # app_theme.dart
      routes/                      # app_navigation.dart
    models/                        # application.dart, recruitment_status.dart,
                                   # status_history.dart, agenda.dart,
                                   # app_document.dart, weekly_goal.dart
    data/                          # mock_data.dart, jobtrail_store.dart
    widgets/                       # app_shell, bottom_navbar, app_button,
                                   # status_chip, application_card, stat_card,
                                   # progress_card, input_field, schedule_card,
                                   # empty_state, placeholder_content
    screens/
      home/home_screen.dart
      board/board_screen.dart
      detail/application_detail_screen.dart
      application_form/application_form_screen.dart
      schedule/schedule_screen.dart
      documents/documents_screen.dart
      statistics/statistics_screen.dart
  test/
    jobtrail_store_test.dart
    widget_test.dart
  android/                         # scaffold dipertahankan, label JobTrail
  web/                             # metadata/nama/warna GSM; ikon masih bawaan
  ios/ linux/ macos/ windows/       # scaffold bawaan, tidak diuji pada fase ini
```

## Kontrak untuk pengembang

Baca [ARCHITECTURE](docs/ARCHITECTURE.md) untuk interface constructor, store,
models dan navigasi; [GSM](docs/GSM.md) untuk token/font;
[DUMMY_DATA](docs/DUMMY_DATA.md) untuk fixture/tanggal/metrik;
[CONTRIBUTING](docs/CONTRIBUTING.md) untuk ownership, workflow dan QA.

Screen menerima store/navigation melalui constructor. Gunakan `ListenableBuilder`
dan komponen shared, tanpa repository/MaterialApp/navbar/dataset tambahan.
Detail/Edit mengirim ID; S04 menyimpan melalui store lalu `navigation.finishForm(id)`.
Semua perubahan kontrak shared memerlukan koordinasi sesuai AGENTS.

## Verifikasi

```powershell
dart format <path-yang-diubah>
flutter analyze
flutter test
flutter build web
```

Hasil aktual dan batas pengujian fondasi dicatat di [QA](docs/QA.md).
Widget test mencakup viewport 393×852, 320×640 dan 1280×800 dengan text scaling 2×.
Test ini tidak membuktikan kesesuaian visual screen final atau dukungan Android runtime.

## Langkah tim berikutnya

1. Ichsan dan pemilik shared mereview kontrak routing/model/tema/fixture sebelum
   mengonfirmasi baseline develop dan membuka feature branches.
2. Konfirmasi task ID/master tracker, aturan Week 12 dan deadline resmi.
3. Putuskan konflik AGENTS–Figma yang dicatat di GSM dan DUMMY_DATA. Baru S01
   yang sudah diinspeksi melalui koneksi Figma; S02–S07/state tambahan belum diaudit.
4. PIC mengganti placeholder screen sendiri berdasarkan frame final dan kontrak ini.
5. Uji alur lengkap setelah form/interaksi tersedia, lakukan QA Android, kumpulkan
   screenshot running dan PR ke develop. Status tracker diperbarui berdasarkan bukti nyata.
