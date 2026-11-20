# JobTrail

Job & Internship Application Tracker untuk mahasiswa dan fresh graduate. Flutter/Dart; target pengembangan Android dan Web. Status: **kandidat integrasi frontend Week 12 untuk review**, bukan aplikasi production yang terhubung backend.

Tujuh screen terintegrasi: S01 Home, S02 Board, S03 Detail, S04 Tambah/Edit Lamaran, S05 Jadwal, S06 Dokumen, dan S07 Statistik. Data sintetis disimpan dalam satu `JobTrailStore` in-memory dan hilang saat aplikasi dimulai ulang. Tidak ada autentikasi, persistence, backend/Supabase, unggah file nyata, push notification, atau deployment production dalam fase ini.

## Menjalankan

```powershell
flutter pub get
flutter run -d chrome
```

Alternatif: `flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080`, lalu buka `http://localhost:8080`. Untuk perangkat yang tersedia, gunakan `flutter devices` dan `flutter run -d <device-id>`. Gunakan SDK dan lockfile proyek tanpa upgrade dependency yang tidak disetujui.

## Interaksi dan data

- Home menampilkan target mingguan, ringkasan, agenda dan lamaran dari store; notifikasi bersifat lokal/demo.
- Board menyediakan pencarian, filter, urutan dan pratinjau sebelum Detail. Detail membuka ID yang benar, status/history, hapus dengan konfirmasi, agenda terkait dan pratinjau metadata dokumen.
- Form tambah/edit memvalidasi input, mempertahankan ID saat edit dan meminta konfirmasi pembatalan draft. Tambah sukses kembali ke Board; edit kembali ke Detail.
- Jadwal menampilkan filter dan kalender serta menambah agenda terkait lamaran yang memenuhi syarat. Simpan memperbarui store dan tampilan yang mendengarkan perubahan.
- Dokumen mendukung pencarian, tambah/edit/hapus dan pratinjau **metadata saja**. File tidak diunggah atau dibuka. Dokumen yang masih direferensikan tidak dapat dihapus.
- Statistik menghitung distribusi status terkini, target mingguan, konversi interview tercatat dan tren dari store; periode memfilter berdasarkan tanggal lamaran. Streak dan response rate tidak diklaim sebagai data nyata.

`referenceDate` adalah tanggal sipil demo; `referenceInstantUtc` menggunakan clock terinjeksi (default 17 November 2026 09:00 WIB). Instant agenda, history dan metadata disimpan UTC dan ditampilkan WIB. Agenda sebelum instant acuan adalah lewat; tepat pada atau setelahnya belum lewat.

App memiliki satu MaterialApp, root navigator dan AppShell lima tab; tiap tab memiliki header sendiri. Fokus keyboard/semantik target mingguan, label form, pilihan filter dan ukuran target telah diperbaiki dan diuji sebagian. QA screen reader/device tetap diperlukan.

## Verifikasi

```powershell
flutter analyze
flutter test
git diff --check
```

Lihat [QA](docs/QA.md) untuk bukti dan batasannya, [release checklist](docs/FRONTEND_RELEASE.md), [arsitektur](docs/ARCHITECTURE.md), [GSM](docs/GSM.md), [data dan metrik](docs/DUMMY_DATA.md), dan [kontribusi](docs/CONTRIBUTING.md). [AGENTS.md](AGENTS.md) tetap mengatur koordinasi dan ownership.
