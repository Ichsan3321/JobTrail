# Arsitektur integrasi frontend JobTrail

Kontrak database dan handoff repository tersedia di [BACKEND_CONTRACT.md](BACKEND_CONTRACT.md).

`AGENTS.md` mengatur ownership. Mode mock menggunakan store in-memory dengan
clock deterministik. Mode Supabase menggunakan snapshot akun dari kontrak yang sama
untuk semua layar.

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
    jobtrail_store.dart          # ChangeNotifier, state snapshot, CRUD mock, agregasi
    jobtrail_repository.dart     # kontrak domain, snapshot, receipt, error
    jobtrail_wire.dart           # codec PostgREST dan validasi snapshot
    supabase_jobtrail_repository.dart # adapter ke RPC yang sudah ada
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

`JobTrailApp` membuat satu store dan navigator per scope. Mode mock memakai
`JobTrailStore.demo()`; `JobTrailApp(store: store)` menerima store QA yang
di-dispose oleh caller. Mode Supabase membuat `JobTrailStore.connected(repository)`
untuk sesi autentikasi aktif. Login, logout, expiry, recovery dan pergantian akun
mengganti scope terlindung sesuai lifecycle Auth. Scope menutup store dan repository
lama. Satu client Supabase yang sudah ada memasok RPC dengan token yang diikat ke
sesi yang memulai operasi.

UI menggunakan `ListenableBuilder(listenable: store, builder: ...)` untuk perubahan data.
Shell mendengarkan navigation. `IndexedStack` mempertahankan state lima tab; setiap tab memiliki header sendiri dan shell hanya memiliki navbar.
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

## Lifecycle backend dan interface bersama

Store memulai pembacaan snapshot asinkron. `phase` beralih dari `loading` ke
`ready`, `empty` atau `error`. Pembacaan paralel berbagi satu Future.
`refresh()` juga menjadi mekanisme retry. Snapshot yang lolos decoding diterbitkan
sekaligus dan menyediakan tanggal acuan WIB, instant UTC, revision lamaran,
serta target mingguan default 8. Home dan Statistik membaca derivasi store yang sama.

`createApplicationRemote`, `updateApplicationRemote`, `changeStatusRemote`,
`deleteApplicationRemote`, `saveAgendaRemote`, `deleteAgendaRemote`,
`saveDocumentRemote` dan `deleteDocumentRemote` menyediakan fondasi tulis
asinkron. Store menolak mutasi paralel dan memperbarui data setelah rekonsiliasi.
Receipt dan `snapshotCurrent` membedakan commit terkonfirmasi dan status refresh.
Conflict serta write outcome yang tidak pasti tetap dikembalikan sebagai kegagalan
bertipe, dengan refresh rekonsiliasi bila masih dalam sesi yang sama. Mutasi demo
sinkron diblokir oleh store akun. Lihat [kontrak serta handoff](PERSISTENCE_HANDOFF.md)
untuk retry ID, expected revision dan status layar.

## Interface JobTrailStore dan mutasi mock

| API | Kontrak |
|---|---|
| `JobTrailStore.demo({clock})` | Fixture tunggal; mutasi default memakai clock anchor tetap |
| `JobTrailStore.empty({referenceDate, clock})` | State kosong untuk QA; tidak membuat dataset tandingan |
| `referenceDate`, `referenceInstantUtc`, `weeklyGoal` | Tanggal sipil demo, instant UTC dari clock terinjeksi dan target aktif |
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

Alur penyimpanan S04:

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

## Integrasi dan batas fase ini

Ketujuh screen sudah terintegrasi. Board membuka pratinjau sebelum Detail; Detail membuka Form, jadwal terkait, atau pratinjau metadata dokumen berdasarkan ID. Detail tanpa agenda menawarkan sheet agenda untuk status eligible. Jadwal terkait mereset filter tipe untuk konteks baru, sementara filter jadwal umum dipertahankan. Sheet dokumen digunakan bersama oleh Detail dan Dokumen dan membaca store secara reaktif.

Clock demo terinjeksi menyediakan `referenceInstantUtc`; perbandingan agenda memakai instant UTC, sedangkan pengelompokan kalender memakai tanggal sipil WIB. Dokumen disimpan sebagai metadata saja. Integrasi backend tahap ini menyediakan pembacaan metadata. Upload dan push notification berada di luar cakupan. `saveAgenda` adalah upsert dan `deleteAgenda` tersedia pada store; jangan menyimpulkan bahwa seluruh operasi agenda memiliki kontrol UI. Status implementasi dan bukti QA ada di [QA](QA.md).
