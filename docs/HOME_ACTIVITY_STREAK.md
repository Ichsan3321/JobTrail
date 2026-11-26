# Home Activity Streak

## Desain dan cakupan

Commit `3417925` menempatkan badge jingga berbentuk pil di samping judul
Weekly Goal dan kartu putih “Konsistensi mingguan” dengan ikon api di bagian
bawah sheet **Target Mingguan**, setelah rincian aktivitas harian. Badge
mengikuti aksi buka sheet yang sama. Keduanya masih placeholder saat
dihapus oleh `fb940b1`. Implementasi ini mengembalikan penempatan dan warna
tersebut dengan hitungan nyata serta empat minggu aktivitas. Istilah
`minggu` tetap sama untuk satu atau beberapa minggu dalam bahasa Indonesia.
Tombol tambah dipertahankan pada sisi kanan, dengan ruang tersendiri di atas
navigasi bawah agar tidak menutupi daftar Home yang bergulir.

## Kontrak untuk S07 Statistik

Panggil `calculateActivityStreak` dari `lib/core/activity_streak.dart` saat
snapshot akun berubah. Masukkan **seluruh** tanggal `application.appliedAt`
akun dan `store.referenceDate`. Filter periode Statistik tetap dapat
diterapkan pada agregat lain. Memfilter tanggal untuk streak akan
memotong minggu terdahulu dan menghasilkan angka berbeda dari Home.

```dart
final result = calculateActivityStreak(
  referenceDate: store.referenceDate,
  appliedDates: store.applications.map((app) => app.appliedAt),
);
```

- Input memakai format `AppDates.date`, yaitu tanggal sipil WIB yang
  direpresentasikan sebagai tengah malam UTC. Input non-sipil ditolak.
  Jika sumber awal berupa instant UTC, gunakan `AppDates.wibDate`
  terlebih dahulu. Pergantian Senin 00.00 WIB setara Minggu 17.00 UTC.
- Tanggal setelah tanggal acuan diabaikan, termasuk tanggal yang masih
  berada dalam minggu berjalan. Setiap minggu Senin–Minggu dengan satu atau
  lebih lamaran dihitung sekali.
- `result.consecutiveWeeks` menghitung minggu aktif berturut-turut, dimulai
  dari minggu berjalan bila sudah aktif. Bila minggu berjalan belum aktif,
  hitung dari minggu sebelumnya. Minggu lampau tanpa aktivitas menghentikan
  hitungan. Minggu berjalan yang kosong memutus streak setelah berakhir.
- `result.hasActivity` menunjukkan apakah ada lamaran valid sampai tanggal
  acuan, termasuk lamaran di luar empat minggu tampilan.
- `result.weeks` adalah empat entri immutable, dari Senin terlama hingga
  Senin minggu berjalan. Status `active` berarti ada lamaran tercatat,
  `inactive` berarti minggu sudah selesai tanpa lamaran, dan `pending`
  berarti minggu berjalan belum memiliki lamaran.
- Gunakan snapshot dan tanggal acuan terbaru setelah refresh atau
  pergantian akun. Jangan cache streak lintas akun. Weekly Goal tetap
  memakai ambang terpisah sebesar 8 lamaran.

| Acuan WIB | Tanggal lamaran pada snapshot | Streak dan keadaan |
|---|---|---|
| 26 Nov 2026 | Kosong | 0 minggu. Tiga minggu lampau tidak aktif dan minggu berjalan menunggu. |
| 26 Nov 2026 | 9, 16 dan 17 Nov | 2 minggu. Dua lamaran 16–17 Nov dihitung sekali. Minggu berjalan menunggu. |
| 26 Nov 2026 | 9, 16 dan 23 Nov | 3 minggu. Minggu berjalan aktif. |
| 26 Nov 2026 | 9, 23 dan 27 Nov | 1 minggu. Minggu 16 Nov kosong, dan 27 Nov diabaikan. |
| 30 Nov 2026 | 9, 16 dan 17 Nov | 0 minggu. Minggu 23 Nov telah berakhir tanpa aktivitas. |
| 5 Jan 2027 | 27 dan 31 Des 2026 serta 4 Jan 2027 | 3 minggu, melewati batas bulan dan tahun. |

Angka mengukur **aktivitas lamaran yang masih tercatat**. Penghapusan atau
koreksi tanggal dapat mengubahnya. Data yang belum tercatat tidak dapat
dibuktikan dari snapshot. Tampilan empat minggu hanya visualisasi. Nilai
streak tetap menghitung semua minggu berurutan yang tersedia.

## QA browser lokal

Chrome DevTools Protocol dan semantik Flutter memverifikasi lima skenario
pada 26 November 2026. Fixture sintetis menunjukkan streak 2 minggu
dengan minggu berjalan menunggu, dan akun kosong menunjukkan streak 0.
Pengukuran browser memastikan jumlah lamaran terbaru berada di atas FAB
dan FAB berada di atas navigasi bawah. Alur mock masih membuka form
Tambah, sedangkan fixture akun memakai FAB nonaktif.

| Viewport dan skenario | Bukti lokal di `.jobtrail-qa/home-streak/` |
|---|---|
| 393 × 852, badge terisi dan kartu empat minggu | `populated-393.png`, `streak-detail-393.png` |
| 393 × 852, streak kosong | `empty-streak-393.png` |
| 320 × 852, FAB akun nonaktif | `narrow-connected-320.png` |
| 320 × 852, FAB mock aktif | `narrow-mock-320.png` |
| 1280 × 900, Home desktop | `desktop-1280.png` |

`results.json` memuat hasil per skenario. Skala teks 2× diuji pada widget
Flutter di viewport 320 × 852. QA ini menggunakan repository fake lokal
sehingga tidak memerlukan akun atau fixture hosted.
