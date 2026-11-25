# Week 13 · S01 Home dan integrasi

Baseline `c9c31dd` pada `feature/persistence-home`. S01 memakai snapshot akun
dari store yang sama dengan layar lainnya. AppShell, store, Auth, RPC, dan
layar S02–S07 memakai implementasi fondasi yang sudah terintegrasi.

## Penerimaan S01

| Pemeriksaan | Bukti |
|---|---|
| Ringkasan | Fixture widget memeriksa total, jumlah masuk minggu ini, jumlah jadwal interview mendatang, status Interview dan Offering, serta urutan lamaran terbaru. Ringkasan Statistik dibandingkan dengan snapshot Home yang sama. |
| Weekly Goal | Target 8, rentang Senin hingga Senin berikutnya menurut tanggal sipil WIB. Kasus refresh pada pergantian Minggu ke Senin (17:00 UTC), filter hari, dan capaian 9/8 dengan progress 100% diuji. |
| Agenda dan navigasi | Agenda tepat pada waktu acuan masih tampil. Agenda lampau hanya muncul sebagai riwayat notifikasi dengan label waktu sesuai. Dua agenda pertama diurutkan menurut waktu. Kartu dan notifikasi membuka Detail menggunakan ID lamaran. Tautan Jadwal memilih tab S05. |
| Lifecycle akun | Suite fondasi mencakup initial loading, empty, refresh gagal dan retry, serta pergantian akun saat loading. Uji S01 mencakup refresh snapshot berisi data, rekonsiliasi dua tab, dan logout saat refresh aktif diikuti login akun lain. |
| Aksesibilitas | Target hari Weekly Goal minimal 48 × 48 logical px pada 393 × 852 dan 320 × 852 dengan skala teks 2. Layout sempit membungkus tombol ke baris berikutnya. |
| Mutasi | Tombol Tambah pada mode backend tetap dinonaktifkan. Status baca notifikasi masih lokal per sesi. |
| Hosted | Home akun kosong pada fondasi sudah diterima menurut baseline tim. QA hosted untuk revisi S01 dan akun berisi data masih menunggu eksekusi manual. |

## Gerbang Tambah Lamaran

Aktifkan aksi Home setelah PR S04 milik Rifqi direview dan digabung **serta**
alur terintegrasi memanggil `createApplicationRemote` dengan satu intent dan
UUID stabil. Pastikan pengiriman ganda dicegah, retry create memakai payload
asli, dan timeout atau konflik mempertahankan draft dan status yang jujur.
Setelah receipt diterima, rekonsiliasi snapshot hingga ID ada. Gunakan ID itu
untuk alur W13-02 ke Board. Verifikasi jumlah serta target minggu Home dan
Statistik setelah refresh atau reload. Uji integrasi akun yang sah wajib lulus
sebelum kontrol backend dibuka. Pertahankan alur tambah mode mock.

## Pemeriksaan setelah setiap PR anggota

Jalankan tes modul yang berubah, lalu cek lima tab, snapshot akun setelah
refresh, navigasi ID, empty/error/retry, dan isolasi antarakun. Mutasi yang
dinyatakan berhasil harus muncul di snapshot setelah reload.

| PR | Pemeriksaan lintas layar |
|---|---|
| S02 Hanif | Filter Board dan pratinjau memakai ID yang benar. Status yang dikonfirmasi server tercermin di Home dan Statistik. |
| S03 Lenno | Recent, agenda, dan notifikasi membuka Detail yang benar. Perubahan status atau hapus tercermin di ringkasan setelah rekonsiliasi. |
| S04 Rifqi | Terapkan gerbang Tambah di atas. Hasil tersimpan kembali ke Board dan draft edit bertahan ketika revisi konflik. |
| S05 Fachriza | Jadwal Terdekat membuka tab Jadwal. Verifikasi urutan UTC, label tanggal WIB, dan perubahan terkait lamaran yang sama. |
| S06 Farhad | Metadata hasil rekonsiliasi tersedia di Detail/Form. Simpan, batal, dan proteksi draft tidak merusak tautan yang sudah ada. |
| S07 Ziyaad | Cocokkan total dan status terkini pada periode yang sama dengan Home. Weekly Goal tetap memakai minggu WIB saat ini terlepas dari filter periode. |

## QA Chrome hosted

Dari `C:\JobTrail`, gunakan konfigurasi development lokal yang sudah disiapkan:

```powershell
flutter run -d chrome --web-hostname=localhost --web-port=3000 --dart-define-from-file=.env.jobtrail.json
```

- Akun kosong. Pada 393 × 852, periksa nilai nol, target 8, empty state lokal,
  avatar, dan penjelasan tombol Tambah. Buka Weekly Goal dengan keyboard serta
  pointer. Ulangi di viewport sempit dengan skala teks besar.
- Akun berisi data uji. Cocokkan ringkasan dengan daftar fixture yang tercatat.
  Periksa urutan agenda dan lamaran, tanggal WIB, buka tiap jalur Detail, dan
  bandingkan Home–Statistik pada periode yang sama.
- Putuskan jaringan saat refresh dari menu akun. Periksa kegagalan dan snapshot
  sebelumnya, aktifkan koneksi kembali, lalu retry. Ulangi refresh dengan
  throttling dan logout terkonfirmasi saat refresh berjalan. Masuk akun lain
  dan tekan Back untuk memastikan data dan route sebelumnya tidak dapat dibuka.

**Fixture untuk persetujuan terpisah.** Satu akun disposable tanpa record dan
satu dengan minimal tiga lamaran sintetis bertanggal berbeda, termasuk kasus
sebelum dan sesudah Senin WIB, status Interview dan Offering, serta setidaknya
satu agenda lampau dan dua agenda mendatang yang terkait ke ID berbeda.
Catat ID fixture dan ekspektasi per akun. Gunakan record uji yang sudah ada
bila mencukupi. Pembuatan atau penghapusan hosted memerlukan persetujuan
eksplisit. Setelah tes tulis nantinya disetujui, hapus hanya ID fixture dengan
akun pemilik melalui RPC yang berlaku. Hapus agenda uji dan lepas kaitan
dokumen sebelum menghapus metadata, lalu periksa snapshot akhir. Simpan hasil
lulus/gagal tanpa kata sandi, token, atau data pribadi di log QA.

