# Arsitektur fondasi JobTrail

17 November 2026 · PIC/integrator: Ichsan Ramadhan · branch kerja: `develop`.
Task ID W12 belum tersedia: workbook master tidak ditemukan di workspace.
Fondasi dibuat atas otorisasi koordinator. Kontrak ini perlu review PIC shared
sebelum tim memulai implementasi screen final. `AGENTS.md` tetap otoritatif.

## Struktur dan batas tanggung jawab

```text
lib/
  main.dart                      # satu entrypoint
  app.dart                       # satu MaterialApp; lifecycle store/navigation
  core/
    constants/                   # app_tokens.dart, app_dates.dart
    theme/app_theme.dart
    routes/app_navigation.dart
  models/                        # immutable application/draft, status, agenda,
                                 # document metadata, status history, weekly goal
  data/
    mock_data.dart               # satu fixture, hanya bootstrap
    jobtrail_store.dart          # satu ChangeNotifier + CRUD + agregasi
  widgets/                       # shell/navbar dan komponen shared
  screens/
    home/                        # S01 Ichsan
    board/                       # S02 Hanif
    detail/                      # S03 Lenno
    application_form/            # S04 Rifqi
    schedule/                    # S05 Fachriza
    documents/                   # S06 Farhad
    statistics/                  # S07 Ziyaad
test/
  jobtrail_store_test.dart
  widget_test.dart
assets/fonts/                    # font asli + OFL per family
```

`JobTrailApp` membuat tepat satu `JobTrailStore.demo()` dan `AppNavigation`.
Dependency diteruskan melalui constructor, tanpa provider/service locator/codegen.
`JobTrailApp(store: store)` mendukung test/preview kosong; caller bertanggung jawab
dispose store yang diinjeksi. Store merupakan dependency tetap selama app terpasang;
gunakan instance/key app baru bila mengganti store. Store milik app otomatis di-dispose.

UI menggunakan `ListenableBuilder(listenable: store, builder: ...)` untuk perubahan data.
Shell mendengarkan navigation. `IndexedStack` mempertahankan state lima tab.
Tidak ada repository, selected tab, MaterialApp, atau navbar tambahan di screen.
Screen tab menyediakan body; Detail/Form menyediakan Scaffold turunan tanpa navbar.
Lebar preview maksimum 600 logical px; device yang lebih sempit memakai lebar tersedia.
Body memakai SafeArea dan scroll. Navbar berada di luar scroll body.

## Model bersama

| Tipe | Interface/field |
|---|---|
| `ApplicationDraft` | company, position, source, appliedAt, status, location, workType, salary?, notes, documentIds |
| `Application extends ApplicationDraft` | id stabil; `Application.fromDraft(id, draft)` menormalisasi teks utama; `withStatus(status)` membuat draft baru |
| `RecruitmentStatus` | applied, screening, test, interview, offering, rejected; `.label` baku |
| `WorkType` | onSite, hybrid, remote; `.label` |
| `Agenda` | id, applicationId, type, scheduledAt, locationOrLink, notes |
| `AgendaType` | interview, test; `.label` |
| `AppDocument` | id, title, category, fileName, version, updatedAt, notes |
| `DocumentCategory` | cvResume, portfolio; `.label` |
| `StatusHistory` | id, applicationId, status, changedAt |
| `WeeklyGoal` | target, weekStart |

Semua field final. List `documentIds` disalin menjadi immutable. Gaji opsional
adalah integer rupiah per bulan, tanpa format/pemisah; `null` berarti tidak diisi.
Status enum tidak mewajibkan jalur linear; rejection bisa dari status mana pun.
Entity baru belum tentu valid sampai lolos validasi store. UI menangkap
`ArgumentError` (input invalid) dan `StateError` (ID/relasi tidak tersedia), lalu
menampilkan pesan Indonesia yang sesuai; jangan menelan error atau mengklaim sukses.

## Interface JobTrailStore

| API | Kontrak |
|---|---|
| `JobTrailStore.demo({clock})` | Fixture tunggal; mutasi default memakai clock anchor tetap |
| `JobTrailStore.empty({referenceDate, clock})` | State kosong untuk QA; tidak membuat dataset tandingan |
| `referenceDate`, `weeklyGoal` | Acuan demo dan target aktif |
| `applications`, `agendas`, `documents`, `history` | Snapshot immutable, jangan diubah langsung |
| `applicationById(id)`, `documentById(id)` | Lookup nullable; tangani ID hilang |
| `nextAgendaId()`, `nextDocumentId()` | Alokasi ID unik satu sesi untuk metadata baru; pertahankan saat edit |
| `agendasFor(applicationId)` | Snapshot terurut waktu naik |
| `historyFor(applicationId)` | Terurut waktu naik; waktu sama mengikuti urutan pencatatan |
| `addApplication(draft) -> String` | Validasi, buat ID, catat status awal, notify sekali |
| `updateApplication(id, draft)` | Ganti payload lengkap, pertahankan ID, history baru hanya jika status berubah |
| `changeStatus(id, status)` | Memakai jalur update yang sama; status sama tidak menghasilkan event/notify |
| `deleteApplication(id)` | Hapus lamaran, agenda, history terkait; dokumen tetap disimpan; UI wajib konfirmasi dahulu |
| `saveAgenda(agenda)` | Upsert ID stabil, wajib applicationId tersedia; timestamp UTC dan tidak mendahului appliedAt |
| `deleteAgenda(id)` | Hapus ID yang tersedia |
| `saveDocument(document)` | Upsert metadata; tidak mengunggah/membuka file |
| `deleteDocument(id)` | Ditolak bila masih direferensikan lamaran; lepaskan documentIds melalui update dahulu |
| `setWeeklyGoal(goal)` | Target >= 0, weekStart tanggal Senin |
| `applicationsInPeriod({start, end})` | appliedAt >= start dan < end; batas null berarti tanpa batas |
| `distribution({start, end})` | Map immutable semua status termasuk count 0, memakai current status |
| `weeklyAchieved`, `weeklyProgress` | Jumlah pada minggu target; progress aman saat target nol dan dibatasi 0–1 |

Saat edit, isi draft dengan seluruh data terbaru termasuk documentIds/notes/salary;
field yang tidak dikirim bukan partial patch. `salary: null` mengosongkan gaji.
Perusahaan/posisi/sumber/lokasi wajib; tanggal date-only UTC tidak boleh melewati
referenceDate demo. Dokumen harus ada dan unik; gaji tidak negatif. Tanggal edit
tidak boleh melewati history atau agenda yang sudah ada. Clock perubahan tidak boleh mundur
melewati history terakhir. Mutasi gagal tidak mengubah state/notify.
Agenda/dokumen memakai ID stabil unik yang disediakan caller; gunakan
`nextAgendaId()`/`nextDocumentId()` untuk record baru, jangan memakai nama perusahaan
sebagai ID atau mengubah ID saat edit. Upsert ID yang sama memang mengganti metadata.

## Navigasi: kontrak untuk Hanif, Lenno, Rifqi, Fachriza

`AppTab`: home, board, schedule, documents, statistics. Label tetap:
Beranda, Board, Jadwal, Dokumen, Statistik. `AppNavigation.selectedTab` satu-satunya
selected tab. `navigatorKey` merupakan navigator root milik satu MaterialApp.
Route native `MaterialPageRoute` memakai API bertipe berikut; jangan menambahkan
named routes paralel. Nama di RouteSettings hanya identitas untuk observasi,
bukan dukungan URL deep link/browser refresh pada route detail.

| API | Pemakaian |
|---|---|
| `showTab(tab, {applicationId})` | Kembali ke shell/root dan pilih tab; applicationId opsional memfilter Jadwal |
| `openDetail(applicationId)` | Push S03 dengan ID; Back mengembalikan tab asal |
| `openAdd()` | Push S04 tambah; cancel mempertahankan asal; hasil save valid memilih Board |
| `openEdit(applicationId)` | Panggil dari S03; push S04 edit dengan ID yang sama; save/cancel pop kembali ke detail |
| `finishForm(savedId)` | Setelah CRUD sukses; pop hasil ID valid. Tidak menyimpan sendiri |
| `back()` | Pop route; sebelum cancel form dirty, S04 wajib dialog konfirmasi |

Contoh integrasi S04 nanti (bukan implementasi form final):

```dart
final id = applicationId == null
    ? store.addApplication(draft)
    : applicationId!;
if (applicationId != null) store.updateApplication(id, draft);
navigation.finishForm(id);
```

S03 setelah konfirmasi hapus: `store.deleteApplication(applicationId)` lalu
`navigation.showTab(AppTab.board)`. Membuka agenda terkait:
`navigation.showTab(AppTab.schedule, applicationId: applicationId)`.
ID detail/edit yang tidak tersedia menampilkan pesan aman dengan Back tersedia.
Jadwal resolve perusahaan melalui store, bukan duplikasi string perusahaan.

## Komponen shared

Komponen fondasi ber-GSM, belum disahkan sebagai hasil high fidelity Figma.
Material icons pada shell adalah placeholder, bukan aset logo/icon Figma final.

| Komponen | Parameter utama |
|---|---|
| AppButton | label, onPressed nullable (disabled) |
| StatusChip | status; warna melalui extension RecruitmentStatusColors |
| ApplicationCard | application, onTap |
| StatCard | label, value |
| ProgressCard | achieved, target; progress cap dan target nol aman |
| InputField | label, controller (milik caller), validator?, keyboardType?, maxLines |
| ScheduleCard | agenda, application ter-resolve, onTap |
| BottomNavbar | selectedTab, onSelected; hanya dipasang AppShell |
| EmptyState | message |
| PlaceholderContent | screenId, title, owner, children; hapus pemakaiannya saat PIC mengimplementasikan UI final |

## Batas fase ini

Tidak ada auth/backend/persistence/upload/notifikasi nyata/deployment.
Tidak ada form final, status picker, delete dialog, kalender, pencarian, grafik,
notification overlay atau goal sheet. CRUD diuji melalui API store; placeholder
S04 hanya menampilkan konteks tambah/edit dan tombol Batal. Save route diuji
melalui API kontrak, bukan klaim alur form pengguna lengkap.
Review bersama diperlukan sebelum membekukan kontrak dan membuka feature branches.
