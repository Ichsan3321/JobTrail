# Dataset demo dan metrik bersama

Satu fixture: `lib/data/mock_data.dart`. Semua screen membaca instance
`JobTrailStore` yang sama; screen tidak boleh mengimpor MockData langsung.
Data sintetis, in-memory, hilang setelah restart. Tidak ada data pribadi asli.
Status fixture: **provisional untuk fondasi, belum dataset Figma final terverifikasi**.
Review: Ziyaad + Fachriza (fixture/metrik), Rifqi (status), Ichsan (integrasi).

## Acuan waktu

- `referenceDate`: 17 November 2026, date-only UTC midnight yang mewakili tanggal WIB.
- `referenceInstant`: 17 November 2026 09:00 WIB = 02:00Z.
- Minggu target: Senin 16 November sampai sebelum Senin 23 November 2026; target 8.
- `JobTrailStore.demo()` menggunakan clock tetap referenceInstant untuk mutasi demo.
  `JobTrailStore.empty(referenceDate: ...)` memakai 09:00 WIB pada tanggal acuan itu.
  Clock dapat diinjeksi; jangan mengganti dengan DateTime.now di setiap screen.
- appliedAt/weekStart/referenceDate adalah civil date UTC midnight: buat dengan
  `AppDates.date(year, month, day)`, termasuk nilai dari date picker. Jangan
  memakai `.toUtc()` pada midnight lokal picker untuk membuat date-only.
- scheduledAt/changedAt/updatedAt adalah UTC instant. Parse input WIB eksplisit
  seperti `DateTime.parse('2026-11-16T10:00:00+07:00').toUtc()`.
- `AppDates.formatWib` mengonversi UTC ke WIB (offset resmi tetap +07) hanya untuk
  presentasi. Tidak memakai timezone host atau menambahkan offset ke stored value.
- Pada anchor 17 November, agenda 16 November adalah kemarin; jangan labeli Besok.

## Lamaran

| ID | Perusahaan | Posisi | appliedAt | Current status | Lokasi/tipe | Dokumen |
|---|---|---|---|---|---|---|
| app-lentera | Lentera Tech | Frontend Developer Intern | 12 Nov 2026 | Applied | Bandung/Hybrid | doc-cv |
| app-nusa | Nusa Digital | UI/UX Designer Intern | 1 Nov 2026 | Interview | Jakarta/On-site | doc-cv, doc-portfolio |
| app-arunika | Arunika Finance | Business Analyst Intern | 5 Nov 2026 | Screening | Jakarta/Hybrid | doc-cv |

Sumber sintetis seluruhnya `Situs perusahaan`, salary tidak diisi, notes kosong.
Jangan menganggap field tambahan ini berasal dari Figma.

## Agenda, dokumen, history

| ID agenda | applicationId | Jenis | Waktu WIB | Lokasi |
|---|---|---|---|---|
| agenda-nusa | app-nusa | interview | 16 Nov 2026 10:00 | Google Meet (demo) |
| agenda-arunika | app-arunika | test | 17 Nov 2026 13:00 | Link via email (demo) |

`doc-cv`: CV Demo/CV-Resume/cv_demo.pdf/v1;
`doc-portfolio`: Portofolio Demo/Portofolio/portofolio_demo.pdf/v1.
Keduanya updatedAt 10 November 2026 00:00Z; hanya metadata, file PDF tidak tersedia.
Dokumen dapat berada di inventori tanpa lamaran; referensi documentIds yang hilang
ditolak. Agenda wajib berelasi ke lamaran yang ada.

History sintetis: semua lamaran punya event Applied pada appliedAt pukul 09:00 WIB;
Nusa berubah Interview 13 November 09:00 WIB, Arunika Screening 12 November 09:00 WIB.
Event ini dibuat untuk konsistensi fondasi, bukan riwayat yang diobservasi di Figma.
Mutasi status menambah event; mengulang status yang sama tidak menambah event.
Hapus lamaran menghapus agenda/history terkait, mempertahankan dokumen bersama.
Hapus dokumen yang dipakai ditolak sampai seluruh referensi dilepas lewat edit.

## Definisi agregasi yang sudah diimplementasikan

- Total = jumlah lamaran dalam `applicationsInPeriod(start:, end:)`.
- Interval tanggal = start inklusif, end eksklusif, filter berdasarkan appliedAt.
  API menyediakan batas eksplisit; pemetaan label UI Saat Ini/1/2/3 Bulan Terakhir
  belum dibekukan. Ziyaad perlu mengonfirmasi kalender vs rolling bersama koordinator.
  Placeholder statistik saat ini menampilkan seluruh data, tanpa filter periode.
- Current interview/offering/distribusi = count current enum, bukan jumlah agenda
  atau jumlah event history. Distribusi memuat enam status, termasuk nol.
- Persentase distribusi nantinya = count/total; total nol tampil 0/empty, bukan NaN.
- Weekly achieved = lamaran baru pada [weekStart, weekStart+7 hari), target >= 0.
  Progress = clamp(achieved/target, 0, 1); target nol menghasilkan 0.
  Angka achieved boleh melebihi target, tidak dipotong.
- Baseline fixture: total 3; Applied 1, Screening 1, Test 0, Interview 1,
  Offering 0, Rejected 0; capaian minggu anchor **0/8**.
- Angka desain 24/3/1, 5/8 dan streak 4 minggu tidak dijadikan agregasi palsu.
  Interview conversion, response rate, streak dan tren belum diimplementasikan;
  perlu definisi Ziyaad dan data pendukung. Current interview bukan conversion.

## Konflik yang harus diputuskan

S01 Figma `80:4172` diinspeksi 17 November 2026: Arunika tertulis
**Product Design Intern / Test-Psikotes**, sedangkan AGENTS mencatat existing mock
**Business Analyst Intern / Screening**. Instruksi melarang mengubah scope/model
diam-diam ketika sumber bertentangan. Fixture provisional memakai baseline AGENTS
dan mencatat perbedaan ini; tidak mengklaim telah menyelesaikan rekonsiliasi.
Review frame S02–S07 dan putuskan satu nilai Arunika bersama Ziyaad/Fachriza/Rifqi.
Sesudah keputusan, ubah fixture tunggal dan tabel ini dalam satu perubahan terkoordinasi.
