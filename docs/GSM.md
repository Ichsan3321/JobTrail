# GSM JobTrail

Sumber token terkunci: `AGENTS.md` §6; implementasi `lib/core/constants/app_tokens.dart`
dan `lib/core/theme/app_theme.dart`. Tidak ada perubahan aturan AGENTS.

| Token | HEX |
|---|---|
| primary | #5B5BF0 |
| primaryDark | #4343C9 |
| primaryLight | #EEEEFF |
| mint | #2DD4A7 |
| mintDark | #10A982 |
| peach | #FFB37A |
| peachTint | #FFF4EC |
| navy | #1E2A4A |
| gray | #5A6380 |
| background | #F7F7FC |
| border | #E4E4F0 |
| white | #FFFFFF |

| RecruitmentStatus | Label | Foreground | Background |
|---|---|---|---|
| applied | Applied | #475569 | #F1F5F9 |
| screening | Screening | #B45309 | #FEF3C7 |
| test | Test/Psikotes | #B45309 | #FEF3C7 |
| interview | Interview | #0369A1 | #E0F2FE |
| offering | Offering | #047857 | #D1FAE5 |
| rejected | Rejected | #B91C1C | #FEE2E2 |

Spacing `AppSpacing`: xs=8, sm=12, md=16, lg=24, xl=32.
`AppRadius`: card=20, button/input=14, chip=999.
Target sentuh tombol minimal 44×48; navbar minimal tinggi 64 per item.
Text scaling tidak dimatikan. Gunakan layout responsif, SafeArea dan scroll.
393×852 adalah viewport QA, bukan ukuran root wajib. Preview desktop maksimum 600.

`AppTypography`: heading 24/600 Poppins, section 18/600 Poppins,
body 14/400 Plus Jakarta Sans, label 12/600 Plus Jakarta Sans.
Theme menyediakan headlineLarge 32, headlineMedium 24, headlineSmall/titleLarge 18,
bodyLarge 16, bodyMedium 14. Ini baseline tipografi shared; PIC cocokkan ukuran
screen final dengan Figma tanpa mengganti family atau membuat tema kedua.

## Aset font

Font asli dibundel lokal, tanpa dependency baru atau runtime HTTP:

- [Poppins, Google Fonts](https://github.com/google/fonts/tree/main/ofl/poppins):
  Regular 400, SemiBold 600, Bold 700; `assets/fonts/poppins/OFL.txt`.
- [Plus Jakarta Sans, Google Fonts](https://github.com/google/fonts/tree/main/ofl/plusjakartasans):
  font variable upright, didaftarkan untuk weight 400/500/600/700;
  `assets/fonts/plus_jakarta_sans/OFL.txt`.

Unduhan 17 November 2026, SIL Open Font License 1.1; file license asli dipertahankan.
Kedua OFL dibundel sebagai assets dan diregistrasikan melalui LicenseRegistry di main.
Belum ada kebutuhan italic. Tidak ada logo buatan atau aset perusahaan palsu.
Icon Material pada placeholder harus ditinjau/diganti aset resmi oleh Farhad/Hanif
saat implementasi visual final.

## Inspeksi dan konflik Figma

S01 `80:4172` berhasil dibaca dengan get_design_context beserta screenshot pada
17 November 2026. Frame lain/state overlay belum diinspeksi. Ini bukan audit
seluruh Figma atau bukti kesesuaian UI final.

- S01 memiliki label navbar Board/Jadwal/Statistik ber-font Inter, sedangkan GSM
  mengunci Plus Jakarta Sans. Fondasi memakai Plus Jakarta Sans sesuai AGENTS.
- Chip Test di S01 memakai #C2410C/#FFEDD5, berbeda dari GSM #B45309/#FEF3C7.
  Fondasi memakai mapping GSM terkunci.
- Referensi S01 memuat dekorasi/logo dan ikon vektor. Fondasi tidak mereproduksi
  screen itu; tidak ada klaim bahwa aset visual final sudah diimplementasikan.

Keputusan yang diperlukan: Ichsan + Farhad/Hanif menyelaraskan layer Figma dengan
GSM atau menyetujui revisi GSM sebelum implementasi final. File Figma tidak diubah.
