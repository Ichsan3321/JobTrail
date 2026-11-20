# Kontribusi Week 12

Baca seluruh `AGENTS.md` sebelum bekerja. Dokumen ini membantu onboarding,
tidak mengganti aturan kepemilikan dan approval integrator.

## Konteks integrasi saat ini

Tujuh screen telah terintegrasi pada `integration/frontend` sebagai kandidat PR ke `develop`. Instruksi berikut tetap berlaku untuk perubahan lanjutan; referensi fondasi dan feature branch adalah konteks historis, bukan status screen saat ini.

## Sebelum membuka feature branch

Koordinator mereview kontrak fondasi bersama PIC, kemudian mengonfirmasi baseline
`develop` siap. Pembuatan branch/pull/commit/push bukan tindakan otomatis asisten.
Task ID W12, workbook resmi, instruksi Week 12 dan deadline perlu dikonfirmasi.
Tidak ada update spreadsheet/logbook eksternal yang dilakukan oleh fondasi ini.

| PIC | Direktori screen | Branch | Review support |
|---|---|---|---|
| Ichsan | lib/screens/home | feature/home | entrypoint/fondasi/integrasi |
| Hanif | lib/screens/board | feature/board | navigation/shell |
| Lenno | lib/screens/detail | feature/detail | laporan/bukti implementasi |
| Rifqi | lib/screens/application_form | feature/application-form | application/status CRUD |
| Fachriza | lib/screens/schedule | feature/schedule | agenda/fixture |
| Farhad | lib/screens/documents | feature/documents | theme/widgets/document/assets |
| Ziyaad | lib/screens/statistics | feature/statistics | fixture/agregasi/logbook |

Periksa `git status -sb`, branch dan diff; jangan reset/menghapus perubahan rekan.
Feature branches dimulai dari fondasi develop yang sudah dikonfirmasi, bukan counter app.
Gunakan alur fetch/switch/pull/branch di AGENTS hanya setelah akses dan fondasi siap.
PR target `develop`, integrator memeriksa dan menyetujui merge.

## Mengimplementasikan screen

1. Tetapkan PIC, task ID, screen/state dan deliverable dari master tracker.
2. Baca ARCHITECTURE, GSM, DUMMY_DATA dan kontrak Dart aktual.
3. Inspeksi frame/state Figma final milik PIC atau gunakan export berizin.
   Inspeksi selektif tujuh frame dan beberapa state sudah dilakukan; itu bukan sign-off visual. Resolve konflik yang tercatat sebelum perubahan desain.
4. Ubah screen yang dikoordinasikan dengan pemiliknya. Pertahankan constructor store/navigation.
   Dengarkan store dengan ListenableBuilder; jangan membuat fixture/repository sendiri.
5. Pakai komponen shared dan tema. Screen tab tidak membuat navbar/MaterialApp sendiri.
   Routing detail/edit memakai ID. S04 mengirim ApplicationDraft lengkap.
6. Perubahan shared/interface/dependency harus dikoordinasikan dengan Ichsan dan PIC
   pemilik sebelum diedit. Jangan menyalin file shared untuk menghindari koordinasi.
7. Implementasi interaksi final (form dirty cancel, hapus konfirmasi, filter, sheets)
   tetap milik PIC. Dokumentasikan placeholder yang belum berfungsi dengan jujur.

## Verifikasi lokal

```powershell
flutter pub get
dart format <file-atau-direktori-yang-diubah>
flutter analyze
flutter test
flutter run -d chrome
# Alternatif:
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080
```

Buka http://localhost:8080 untuk web-server. Uji 393×852 dan ukuran lain, text scaling,
scroll sampai bawah, lima tab, Back, ID berbeda, kosong, invalid, batal, hapus,
keyboard dan insets. Uji Android jika device/emulator tersedia, laporkan jika belum.
Jangan menghapus test agar lulus atau memformat file rekan secara massal.
Widget/regression tests mencakup interaksi form dan lintas screen; bukan bukti QA visual atau Android lengkap.

## Handoff dan PR

Gunakan format §13 AGENTS: task/PIC, branch, output, file berubah, kontrak shared,
cara menjalankan, command dan hasil aktual, blocker, dampak lintas screen, bukti,
status yang disarankan. PR mencantumkan screenshot running aktual dan shared files.
Tidak ada commit/PR/screenshot/logbook yang boleh dikarang.
Koordinator mengisi tracker bersama setelah bukti dan review tersedia.
Gunakan status **Review** untuk kandidat integrasi yang menunggu tinjauan bersama; hasil QA dan sign-off visual harus dicatat secara terpisah. Jangan commit cache/build/secrets.
