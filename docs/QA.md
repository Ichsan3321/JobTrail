# Hasil QA fondasi

17 November 2026 · Ichsan/integrator (implementasi dibantu coding agent)
Branch `develop` · Task ID W12 belum tersedia · Status disarankan: **Review**.
Tidak ada commit/PR/merge, pembaruan tracker, atau screenshot Figma buatan.
`AGENTS.md` awal belum dilacak Git dan tetap dipertahankan tanpa perubahan.

## Pengujian aktual

| Command/pemeriksaan | Hasil akhir |
|---|---|
| `flutter --version` | Flutter 3.47.9 stable, Dart 3.13.7 |
| `flutter pub get` | Berhasil; tidak ada dependency baru/upgrade; pubspec.lock tidak berubah |
| `dart format lib test` dan file Dart yang diperbaiki sesudahnya | Berhasil |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **22 tests passed**: 12 state/model/date tests + 10 widget/navigation/layout tests |
| `flutter build web` | **Built build/web**; Wasm dry run succeeded; bukan uji runtime Wasm |
| `flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080` | Berhasil menyajikan debug app |
| Chrome headless, build Web lokal, viewport 393×852 | Seluruh 5 tab + Add/Detail/Edit berhasil dibuka; cancel dan agenda terkait berhasil; runtime errors kosong |
| `git diff --check` | Berhasil tanpa whitespace error; Git memberi peringatan konversi LF/CRLF Windows |
| Android runtime | **Belum diuji**; flutter devices hanya menemukan Windows, Chrome, Edge |

Widget test mencakup 393×852, 320×640, 1280×800 pada text scaling 2×,
scroll seluruh tab, navbar tunggal, tombol minimum 48px, ID berbeda, Back/cancel,
ID detail/edit tidak ditemukan, state kosong dan propagasi perubahan state.
API save-result diuji dengan memanggil store dan navigation; tidak ada klaim
form pengguna atau dialog hapus final sudah diimplementasikan.

State test mencakup fixture/ID/relasi/history, CRUD/status, notifikasi, ID tetap,
immutable snapshots, penghapusan cascade, dokumen yang masih dipakai, agenda
orphan/tanggal invalid, edit tanggal yang merusak agenda/history, interval minggu,
target nol/progress cap, restart state dan format WIB deterministik.

## Bukti browser aktual

[Ringkasan smoke test JSON](qa/browser-smoke.json).
Screenshot diambil dari aplikasi Flutter yang berjalan, bukan Figma:

- [Beranda](qa/shell-home.png)
- [Board](qa/shell-board.png)
- [Jadwal](qa/shell-jadwal.png)
- [Dokumen](qa/shell-dokumen.png)
- [Statistik](qa/shell-statistik.png)
- [Tambah](qa/route-add.png)
- [Detail](qa/route-detail.png)
- [Edit](qa/route-edit.png)

Home, Board dan Edit juga diinspeksi secara visual. Screenshot menunjukkan UI
placeholder dengan label PIC, bukan implementasi final screen.
Tombol dan navbar tidak menutupi isi yang diperiksa.

Browser UI automation/Computer Use native pipe tidak tersedia. Fallback memakai
Chrome terpasang dalam profile headless terisolasi melalui DevTools pada localhost;
tidak mengakses profile/browser history pengguna. Build release disajikan lokal
dengan Python http.server pada port 8081 untuk smoke test; tidak dipublikasikan.
Percobaan screenshot awal hanya loading. Percobaan resize pada target debug
yang sudah berisi Flutter memunculkan assertion engine ViewInsets; target browser
baru dengan viewport ditetapkan sebelum navigasi berhasil tanpa runtime error.
Tidak ada perubahan SDK atau workaround aplikasi untuk assertion harness tersebut.

## Batas dan tindak lanjut

- Tidak ada Android/device/emulator QA, keyboard form final, atau audit seluruh
  state Figma. Android compatibility belum dibuktikan melalui build/runtime.
- S01 Figma berhasil diinspeksi; S02–S07 belum. Konflik font/status/posisi Arunika
  tercatat di GSM dan DUMMY_DATA untuk keputusan koordinator + PIC terkait.
- Dataset provisional, angka ilustrasi Figma tidak dijadikan metrik palsu.
  Definisi filter periode/statistik lanjut masih perlu keputusan Ziyaad.
- Aset launcher/favicon bawaan Flutter masih tersedia, belum memakai merek final.
- UI final form/filter/sheets/calendar/charts, autentikasi/backend/persistence/
  upload/notifikasi nyata tidak termasuk fondasi ini.
- Task ID, instruksi/deadline resmi Week 12 dan workbook master belum diverifikasi.
- Review Hanif/Farhad/Rifqi/Fachriza/Ziyaad diperlukan sebelum kontrak dibekukan
  dan koordinator mengonfirmasi fondasi untuk feature branches.

Ringkasan faktual untuk logbook (belum dikirim): persiapan fondasi bersama pada
develop, model/store/tema/navigasi/placeholder/dokumentasi, 22 test lulus,
analyzer bersih, Web build dan smoke test berhasil; menunggu review PIC dan QA Android.
