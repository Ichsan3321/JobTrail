import 'package:flutter/material.dart';

import '../../core/constants/app_dates.dart';
import '../../core/constants/app_tokens.dart';
import '../../data/jobtrail_repository.dart';
import '../../data/jobtrail_store.dart';
import '../../models/agenda.dart';
import '../../models/application.dart';
import '../../models/recruitment_status.dart';
import '../../widgets/status_chip.dart';
import 'schedule_agenda_card.dart';
import 'schedule_format.dart';

/// Opens the S05 "Tambah Agenda Seleksi" sheet (Figma `334:4369`).
/// Returns the saved agenda ID, or null when cancelled. In backend mode the ID
/// can belong to a write the server confirmed while the snapshot is still
/// stale; the caller reveals it only once a later read contains it.
///
/// Only fields that exist on [Agenda] are shown. Figma's Nama agenda, waktu
/// selesai, Mode pelaksanaan and Pengingat are deferred until the shared model
/// gains them (decision on PR #4).
Future<String?> showAddAgendaSheet(
  BuildContext context, {
  required JobTrailStore store,
  DateTime? initialDate,
  String? initialApplicationId,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Drag-to-dismiss calls Navigator.pop and would bypass the dirty-form
  // confirmation, so closing goes through X, Batal, barrier or back.
  enableDrag: false,
  backgroundColor: AppColors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
  ),
  builder: (_) => AddAgendaSheet(
    store: store,
    initialDate: initialDate,
    initialApplicationId: initialApplicationId,
  ),
);

/// Agenda can only be planned for applications in an active selection stage
/// (Figma helper text on "Lamaran terkait").
const agendaEligibleStatuses = {
  RecruitmentStatus.screening,
  RecruitmentStatus.test,
  RecruitmentStatus.interview,
};

TextStyle _text(
  double size, {
  Color color = AppColors.navy,
  FontWeight weight = FontWeight.w400,
  String family = AppTypography.bodyFamily,
}) => TextStyle(
  fontFamily: family,
  fontSize: size,
  color: color,
  fontWeight: weight,
);

class AddAgendaSheet extends StatefulWidget {
  const AddAgendaSheet({
    super.key,
    required this.store,
    this.initialDate,
    this.initialApplicationId,
  });
  final JobTrailStore store;
  final DateTime? initialDate;
  final String? initialApplicationId;

  @override
  State<AddAgendaSheet> createState() => _AddAgendaSheetState();
}

class _AddAgendaSheetState extends State<AddAgendaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _dateFieldKey = GlobalKey<FormFieldState<void>>();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  late final List<Application> _eligible;
  late final String? _initialAppId;
  // A prefill outside the supported range is ignored (JT-BUG-012).
  late final DateTime? _initialDate =
      widget.initialDate != null &&
          ScheduleFormat.isInRange(widget.initialDate!)
      ? widget.initialDate
      : null;
  late String? _appId;
  late DateTime? _date = _initialDate;
  AgendaType? _type;
  TimeOfDay? _time;
  bool _submitted = false;
  String? _error;

  /// Create intent: one ID per payload, allocated on the first submit.
  String? _agendaId;

  /// Payload whose server outcome is unknown. While set, the form is locked
  /// and a retry resends this exact immutable agenda (same ID and payload).
  Agenda? _pending;

  /// True while the last reconciling read failed: whether [_pending] reached
  /// the server is unknown, so only a read ("Muat ulang") is offered until a
  /// fresh snapshot shows the ID (saved) or proves it absent (resend allowed).
  bool _needsReload = false;

  /// ID of a create the server confirmed (receipt received) that the current
  /// snapshot does not show yet. Recovery is read-only: it is never resent.
  String? _confirmedId;

  /// A fresh read no longer contains [_confirmedId]; nothing is resent.
  bool _confirmedGone = false;

  bool _saving = false;
  bool _reloading = false;

  JobTrailStore get store => widget.store;
  bool get _locked =>
      _saving || _reloading || _pending != null || _confirmedId != null;

  /// A pending intent may be resent only after a successful read proved its
  /// ID absent; a store in error state has no such proof.
  bool get _mustReload =>
      _confirmedId != null ||
      (_pending != null && (_needsReload || store.phase == StorePhase.error));

  @override
  void initState() {
    super.initState();
    _eligible =
        store.applications
            .where((a) => agendaEligibleStatuses.contains(a.status))
            .toList()
          ..sort((a, b) => a.company.compareTo(b.company));
    final requested = widget.initialApplicationId;
    // Prefill only when the item exists in the dropdown.
    _initialAppId = _eligible.any((a) => a.id == requested) ? requested : null;
    _appId = _initialAppId;
  }

  @override
  void dispose() {
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _appId != _initialAppId ||
      _type != null ||
      _date != _initialDate ||
      _time != null ||
      _location.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty;

  Future<void> _handlePop(bool didPop) async {
    // A request in flight cannot be cancelled; keep the sheet until it settles.
    if (didPop || _saving) return;
    final navigator = Navigator.of(context);
    // A confirmed agenda has nothing to discard: hand its ID to the schedule,
    // which reveals it once a read contains it.
    if (_confirmedId == null && _dirty && !await _confirmDiscard()) return;
    if (!mounted || _saving) return;
    final confirmed = _confirmedId;
    // The unknown or unseen write may have committed; reconcile by reading.
    if ((_pending != null || confirmed != null) && !store.isRefreshing) {
      store.refresh();
    }
    navigator.pop(confirmed);
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('agenda-discard-dialog'),
        title: Text(
          'Buang agenda ini?',
          style: _text(17, weight: FontWeight.w700),
        ),
        content: Text(
          _pending != null
              ? 'Status penyimpanan agenda ini belum pasti. Jika ditutup, '
                    'periksa daftar jadwal setelah data dimuat ulang.'
              : 'Data yang sudah diisi belum disimpan dan akan hilang.',
          style: _text(14, color: AppColors.gray),
        ),
        actions: [
          TextButton(
            key: const ValueKey('agenda-discard-keep'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Lanjut mengisi'),
          ),
          TextButton(
            key: const ValueKey('agenda-discard-confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: RecruitmentStatus.rejected.foreground,
            ),
            child: const Text('Buang'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  void _revalidate() {
    if (_submitted) {
      _formKey.currentState?.validate();
    } else if (_date != null && _appId != null) {
      // Date-vs-appliedAt conflict is shown as soon as both are known.
      _dateFieldKey.currentState?.validate();
    }
  }

  void _setApp(String? id) {
    setState(() {
      _appId = id;
      _error = null;
    });
    _revalidate();
  }

  Future<void> _pickDate() async {
    // Always clamped so showDatePicker's initialDate assertion cannot fire.
    final initial = ScheduleFormat.clampToRange(_date ?? store.referenceDate);
    DateTime local(DateTime d) => DateTime(d.year, d.month, d.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: local(initial),
      firstDate: local(ScheduleFormat.firstDate),
      lastDate: local(ScheduleFormat.lastDate),
      helpText: 'Pilih tanggal agenda',
      cancelText: 'Batal',
      confirmText: 'Pilih',
      fieldLabelText: 'Tanggal',
      fieldHintText: 'dd/mm/yyyy',
      errorFormatText: 'Format tanggal tidak valid',
      errorInvalidText: 'Tanggal di luar rentang',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _date = AppDates.date(picked.year, picked.month, picked.day);
      _error = null;
    });
    _revalidate();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
      initialEntryMode: TimePickerEntryMode.input,
      helpText: 'Jam mulai (WIB)',
      cancelText: 'Batal',
      confirmText: 'Pilih',
      hourLabelText: 'Jam',
      minuteLabelText: 'Menit',
      errorInvalidText: 'Masukkan jam yang valid',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _time = picked;
      _error = null;
    });
    _revalidate();
  }

  String? _validateDate() {
    final date = _date;
    if (date == null) return 'Tanggal wajib diisi';
    if (!ScheduleFormat.isInRange(date)) {
      return 'Tanggal harus antara '
          '${ScheduleFormat.dayMonthYear(ScheduleFormat.firstDate)} dan '
          '${ScheduleFormat.dayMonthYear(ScheduleFormat.lastDate)}';
    }
    final app = _appId == null ? null : store.applicationById(_appId!);
    if (app != null && date.isBefore(app.appliedAt)) {
      return 'Tanggal tidak boleh sebelum tanggal lamaran '
          '(${ScheduleFormat.dayMonthYear(app.appliedAt)})';
    }
    return null;
  }

  static const _parentMissing =
      'Lamaran terkait sudah tidak tersedia. Pilih lamaran lain.';
  static const _outcomeUnknown =
      'Status penyimpanan belum pasti. Ketuk "Kirim ulang" untuk mengirim '
      'agenda yang sama; agenda tidak akan tergandakan.';
  static const _reloadNeeded =
      'Status penyimpanan belum pasti dan data terbaru belum termuat. Ketuk '
      '"Muat ulang" untuk memeriksa apakah agenda sudah tersimpan.';
  static const _confirmedStale =
      'Agenda tersimpan di server, tetapi data terbaru belum termuat. Ketuk '
      '"Muat ulang" untuk menampilkannya.';
  static const _confirmedMissing =
      'Agenda sempat tersimpan, tetapi tidak ada pada data terbaru. Agenda '
      'tidak dikirim ulang; periksa jadwal Anda.';
  // JT004: the client ID is not this account's record (an identical retry on
  // an own row replays instead), so nothing was saved under this intent.
  static const _createConflict =
      'Agenda belum tersimpan. Ketuk Simpan untuk mencoba lagi.';

  Future<void> _save() async {
    if (_saving || _reloading || _confirmedId != null) return;
    var agenda = _pending;
    if (agenda == null) {
      setState(() {
        _submitted = true;
        _error = null;
      });
      if (!_formKey.currentState!.validate()) return;
      final time = _time!;
      agenda = Agenda(
        id: _agendaId ??= store.nextAgendaId(),
        applicationId: _appId!,
        type: _type!,
        scheduledAt: ScheduleFormat.parseWib(_date!, time.hour, time.minute),
        locationOrLink: _location.text.trim(),
        notes: _notes.text.trim(),
      );
    }
    if (store.isConnected) {
      await _saveRemote(agenda);
    } else {
      _saveLocal(agenda);
    }
  }

  /// Mock mode: in-memory store, synchronous.
  void _saveLocal(Agenda agenda) {
    try {
      store.saveAgenda(agenda);
      Navigator.of(context).pop(agenda.id);
    } on StateError {
      setState(() => _error = _parentMissing);
    } on ArgumentError catch (e) {
      setState(
        () => _error = 'Agenda tidak dapat disimpan. ${e.message ?? ''}'.trim(),
      );
    }
  }

  /// Backend mode: `saveAgendaRemote` with an explicit create, then the
  /// receipt. The same immutable [agenda] is resent while the outcome of an
  /// earlier attempt is unknown, so the server can replay it idempotently.
  Future<void> _saveRemote(Agenda agenda) async {
    if (_pending != null) {
      // Resend only with proof of absence from a fresh snapshot.
      if (_mustReload) return;
      if (store.agendaById(agenda.id) != null) {
        _finishSaved(agenda.id);
        return;
      }
    }
    if (store.applicationById(agenda.applicationId) == null) {
      // The parent left the snapshot, so a committed agenda was cascaded too.
      _discardIntent(_parentMissing);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var reloadConfirmed = false;
    try {
      final result = await store.saveAgendaRemote(agenda, SaveMode.create);
      if (!mounted) return;
      _pending = null;
      _needsReload = false;
      if (result.snapshotCurrent) {
        _finishSaved(result.receipt.id);
      } else {
        // Committed on the server: never resend it, only read again.
        _confirmedId = result.receipt.id;
        _error = _confirmedStale;
        reloadConfirmed = true;
      }
    } on RepositoryFailure catch (failure) {
      if (!mounted) return;
      _handleFailure(agenda, failure);
    } catch (_) {
      if (!mounted) return;
      _handleFailure(
        agenda,
        const RepositoryFailure(
          RepositoryIssue.unexpected,
          writeOutcomeUnknown: true,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    // One automatic read for a confirmed write; later reads are user-driven.
    if (reloadConfirmed && mounted) await _reload();
  }

  /// "Muat ulang": a read-only recovery. It refreshes the snapshot and never
  /// writes; the result decides whether the intent is saved or resendable.
  Future<void> _reload() async {
    if (_saving || _reloading) return;
    setState(() => _reloading = true);
    try {
      await store.refresh();
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
    if (mounted) _reconcileIntent();
  }

  void _reconcileIntent() {
    final id = _confirmedId ?? _pending?.id;
    if (id == null) return;
    if (store.phase == StorePhase.error || !store.hasSnapshot) {
      setState(() {
        _needsReload = _pending != null;
        _error = _confirmedId != null
            ? _confirmedStale
            : store.failure?.issue.message ?? _reloadNeeded;
      });
      return;
    }
    if (store.agendaById(id) != null) {
      _finishSaved(id);
    } else if (_confirmedId != null) {
      setState(() {
        _confirmedGone = true;
        _error = _confirmedMissing;
      });
    } else {
      // Proven absent by a fresh read: resending the same intent is safe.
      setState(() {
        _needsReload = false;
        _error = _outcomeUnknown;
      });
    }
  }

  void _handleFailure(Agenda agenda, RepositoryFailure failure) {
    // The store reconciled before rethrowing an ambiguous write; a committed
    // create is visible in the snapshot by its client ID.
    if (failure.writeOutcomeUnknown && store.agendaById(agenda.id) != null) {
      _finishSaved(agenda.id);
      return;
    }
    switch (failure.issue) {
      case RepositoryIssue.busy:
        // Nothing was sent; keep the current intent as it is.
        setState(() => _error = failure.issue.message);
      case _
          when failure.writeOutcomeUnknown ||
              failure.issue == RepositoryIssue.network:
        // Retrying a create with the original ID and payload is safe, but
        // only after a successful read proved the ID absent.
        final failedRead =
            failure.writeOutcomeUnknown &&
            (store.phase == StorePhase.error || !store.hasSnapshot);
        setState(() {
          _pending = agenda;
          _needsReload = failedRead;
          _error = failedRead ? _reloadNeeded : _outcomeUnknown;
        });
      case RepositoryIssue.unavailable:
        _discardIntent(_parentMissing);
      case RepositoryIssue.createConflict:
        _discardIntent(_createConflict);
      default:
        _discardIntent(failure.issue.message);
    }
  }

  /// A definitive rejection: nothing was stored under this intent, so the
  /// user may edit and the next submit becomes a new intent with a new ID.
  void _discardIntent(String message) => setState(() {
    _pending = null;
    _needsReload = false;
    _agendaId = null;
    _error = message;
  });

  /// The agenda is on the server. The sheet only closes while it is the
  /// current route; otherwise closing it later returns the same ID. Saved
  /// feedback belongs to the schedule screen, which checks its own ownership.
  void _finishSaved(String id) {
    setState(() {
      _pending = null;
      _needsReload = false;
      _confirmedId = id;
      _error = null;
    });
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handlePop(didPop),
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: Column(
          key: const ValueKey('add-agenda-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Decorative handle (Figma); drag is disabled, see above.
            ExcludeSemantics(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: _header(),
            ),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('add-agenda-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _submitted
                      ? AutovalidateMode.always
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _applicationField(),
                      const SizedBox(height: 14),
                      _typeField(),
                      const SizedBox(height: 14),
                      _dateTimeRow(),
                      const SizedBox(height: 14),
                      _labelled(
                        'Tautan meeting / lokasi',
                        required: true,
                        TextFormField(
                          key: const ValueKey('agenda-location'),
                          controller: _location,
                          readOnly: _locked,
                          textInputAction: TextInputAction.next,
                          style: _text(14),
                          decoration: _decoration(
                            hint: 'Google Meet / alamat kantor',
                            prefix: Icons.link,
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Tautan atau lokasi wajib diisi'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _labelled(
                        'Catatan',
                        TextFormField(
                          key: const ValueKey('agenda-notes'),
                          controller: _notes,
                          readOnly: _locked,
                          minLines: 2,
                          maxLines: 4,
                          style: _text(14),
                          decoration: _decoration(
                            hint: 'Opsional, mis. bawa portofolio',
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _errorBanner(_error!),
                      ],
                      // Rebuilds on the store: a failed read shows recovery.
                      ListenableBuilder(
                        listenable: store,
                        builder: (context, _) => _showReload
                            ? Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: _reloadButton(),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _actions(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Tambah Agenda Seleksi',
                style: _text(
                  18,
                  weight: FontWeight.w700,
                  family: AppTypography.headingFamily,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Setiap agenda wajib terhubung ke satu lamaran.',
              style: _text(12, color: AppColors.gray),
            ),
          ],
        ),
      ),
      IconButton(
        key: const ValueKey('agenda-close'),
        tooltip: 'Tutup',
        onPressed: _saving ? null : () => Navigator.maybePop(context),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.background,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.close, size: 20, color: AppColors.navy),
      ),
    ],
  );

  InputDecoration _decoration({
    String? hint,
    IconData? prefix,
    IconData? suffix,
    String? errorText,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: _text(14, color: AppColors.gray),
    errorText: errorText,
    errorMaxLines: 3,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    prefixIcon: prefix == null
        ? null
        : Icon(prefix, size: 18, color: AppColors.gray),
    suffixIcon: suffix == null
        ? null
        : Icon(suffix, size: 18, color: AppColors.navy),
    // Tighter than the default 48 px so picker values have room (393 px).
    suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  );

  /// Visible label above the field; merged into the field's semantics node so
  /// screen readers announce "Tanggal, wajib" with the control.
  Widget _labelled(String label, Widget field, {bool required = false}) =>
      MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: required ? '$label, wajib' : label,
              excludeSemantics: true,
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    if (required)
                      TextSpan(
                        text: ' *',
                        style: TextStyle(
                          color: RecruitmentStatus.rejected.foreground,
                        ),
                      ),
                  ],
                ),
                style: _text(12, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            field,
          ],
        ),
      );

  Widget _applicationField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _labelled(
        'Lamaran terkait',
        required: true,
        DropdownButtonFormField<String>(
          key: const ValueKey('agenda-application'),
          initialValue: _appId,
          isExpanded: true,
          style: _text(14),
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.navy),
          decoration: _decoration(
            hint: 'Pilih lamaran',
            prefix: Icons.work_outline,
          ),
          items: [
            for (final app in _eligible)
              DropdownMenuItem(
                value: app.id,
                child: Text(
                  '${app.company} — ${app.position}',
                  overflow: TextOverflow.ellipsis,
                  style: _text(14),
                ),
              ),
          ],
          onChanged: _eligible.isEmpty || _locked ? null : _setApp,
          validator: (value) => value == null ? 'Pilih lamaran terkait' : null,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        _eligible.isEmpty
            ? 'Belum ada lamaran berstatus Screening, Test/Psikotes, atau '
                  'Interview. Ubah status lamaran terlebih dahulu.'
            : 'Hanya lamaran berstatus Screening, Test/Psikotes, atau '
                  'Interview yang dapat dipilih.',
        key: const ValueKey('agenda-application-helper'),
        style: _text(11, color: AppColors.gray),
      ),
    ],
  );

  Widget _typeField() => FormField<void>(
    validator: (_) => _type == null ? 'Pilih jenis agenda' : null,
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Jenis agenda, wajib',
          excludeSemantics: true,
          child: Text.rich(
            TextSpan(
              text: 'Jenis agenda',
              children: [
                TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: RecruitmentStatus.rejected.foreground,
                  ),
                ),
              ],
            ),
            style: _text(12, weight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (i, type) in AgendaType.values.indexed) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(child: _typeOption(type)),
            ],
          ],
        ),
        if (field.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 14),
            child: Text(
              field.errorText!,
              style: _text(12, color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );

  Widget _typeOption(AgendaType type) {
    final selected = _type == type;
    final foreground = ScheduleAgendaCard.typeForeground(type);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: 'Jenis agenda ${type.label}',
      excludeSemantics: true,
      child: Material(
        color: selected
            ? ScheduleAgendaCard.typeBackground(type)
            : AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          side: BorderSide(
            color: selected ? foreground : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('agenda-type-${type.name}'),
          onTap: _locked
              ? null
              : () {
                  setState(() {
                    _type = type;
                    _error = null;
                  });
                  _revalidate();
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    Icon(Icons.circle, size: 6, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      type.label,
                      textAlign: TextAlign.center,
                      style: _text(
                        14,
                        color: selected ? foreground : AppColors.gray,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickerField({
    required Key key,
    GlobalKey<FormFieldState<void>>? fieldKey,
    required String label,
    required String? value,
    String? semanticValue,
    required String placeholder,
    required IconData icon,
    required VoidCallback onTap,
    required FormFieldValidator<void> validator,
  }) => FormField<void>(
    key: fieldKey,
    validator: validator,
    builder: (field) => _labelled(
      label,
      required: true,
      Semantics(
        button: true,
        value: semanticValue ?? value ?? 'belum dipilih',
        child: InkWell(
          key: key,
          onTap: _locked ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: InputDecorator(
            isEmpty: value == null,
            decoration: _decoration(
              hint: placeholder,
              suffix: icon,
              errorText: field.errorText,
            ),
            child: value == null
                ? null
                : Text(
                    value,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: _text(14),
                  ),
          ),
        ),
      ),
    ),
  );

  Widget _dateTimeRow() {
    final time = _time;
    final dateField = _pickerField(
      key: const ValueKey('agenda-date'),
      fieldKey: _dateFieldKey,
      label: 'Tanggal',
      value: _date == null
          ? null
          : ScheduleFormat.fieldDate(_date!, store.referenceDate),
      semanticValue: _date == null ? null : ScheduleFormat.longDate(_date!),
      placeholder: 'Pilih tanggal',
      icon: Icons.calendar_today_outlined,
      onTap: _pickDate,
      validator: (_) => _validateDate(),
    );
    final timeField = _pickerField(
      key: const ValueKey('agenda-time'),
      label: 'Jam mulai',
      value: time == null
          ? null
          : '${time.hour.toString().padLeft(2, '0')}.'
                '${time.minute.toString().padLeft(2, '0')} WIB',
      placeholder: 'Pilih jam',
      icon: Icons.schedule,
      onTap: _pickTime,
      validator: (_) => _time == null ? 'Jam mulai wajib diisi' : null,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final stacked = constraints.maxWidth < 330 || scale > 1.4;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [dateField, const SizedBox(height: 14), timeField],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: dateField),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: timeField),
          ],
        );
      },
    );
  }

  /// Read-only recovery is offered while a pending intent lacks proof of
  /// absence, or a confirmed write is not yet visible in the snapshot.
  bool get _showReload {
    final confirmed = _confirmedId;
    if (confirmed != null) {
      return !_confirmedGone && store.agendaById(confirmed) == null;
    }
    return _mustReload;
  }

  Widget _reloadButton() => OutlinedButton.icon(
    key: const ValueKey('agenda-reload'),
    onPressed: _saving || _reloading || store.isRefreshing ? null : _reload,
    icon: _reloading
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.refresh, size: 18),
    label: Text(
      _reloading ? 'Memuat ulang…' : 'Muat ulang',
      style: _text(14, color: AppColors.primaryDark, weight: FontWeight.w700),
    ),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(44, 44),
      foregroundColor: AppColors.primaryDark,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
    ),
  );

  Widget _errorBanner(String message) {
    // A confirmed write is good news that is only waiting for a read.
    final info = _confirmedId != null && !_confirmedGone;
    final foreground = info
        ? AppColors.primaryDark
        : RecruitmentStatus.rejected.foreground;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: ValueKey(info ? 'agenda-saved-stale' : 'agenda-error'),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: info
              ? AppColors.primaryLight
              : RecruitmentStatus.rejected.background,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              info ? Icons.cloud_done_outlined : Icons.error_outline,
              size: 18,
              color: foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: _text(12, color: foreground, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One-line label; scaleDown only kicks in as a last-resort guard (very
  /// narrow width or large text scale), never at 320+ px with scale 1.
  Widget _actionLabel(String text, Color color) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      text,
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.center,
      style: _text(15, color: color, weight: FontWeight.w700),
    ),
  );

  Widget _actions() {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );
    const padding = EdgeInsets.symmetric(horizontal: 12);
    return Row(
      children: [
        // Simpan gets the larger share (2:3) so its longer label fits.
        Expanded(
          flex: 2,
          child: OutlinedButton(
            key: const ValueKey('agenda-cancel'),
            onPressed: _saving ? null : () => Navigator.maybePop(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 48),
              padding: padding,
              foregroundColor: AppColors.navy,
              side: const BorderSide(color: AppColors.border),
              shape: shape,
            ),
            child: _actionLabel(
              _confirmedId != null ? 'Tutup' : 'Batal',
              AppColors.navy,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 3,
          // Rebuilds on store.isMutating so another write blocks a submit.
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) => FilledButton(
              key: const ValueKey('agenda-save'),
              onPressed:
                  _eligible.isEmpty ||
                      _saving ||
                      _reloading ||
                      _confirmedId != null ||
                      _mustReload ||
                      store.isMutating
                  ? null
                  : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 48),
                padding: padding,
                backgroundColor: AppColors.primary,
                shape: shape,
              ),
              child: _saving
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.gray,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: _actionLabel('Menyimpan…', AppColors.gray),
                        ),
                      ],
                    )
                  : _actionLabel(
                      _confirmedId != null
                          ? 'Tersimpan'
                          : _pending != null
                          ? 'Kirim ulang'
                          : 'Simpan Agenda',
                      AppColors.white,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
