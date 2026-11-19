import 'package:flutter/material.dart';

import '../../core/constants/app_dates.dart';
import '../../core/constants/app_tokens.dart';
import '../../data/jobtrail_store.dart';
import '../../models/agenda.dart';
import '../../models/application.dart';
import '../../models/recruitment_status.dart';
import '../../widgets/status_chip.dart';
import 'schedule_agenda_card.dart';
import 'schedule_format.dart';

/// Opens the S05 "Tambah Agenda Seleksi" sheet (Figma `334:4369`).
/// Returns the saved agenda ID, or null when cancelled.
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

  JobTrailStore get store => widget.store;

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
    if (didPop) return;
    final navigator = Navigator.of(context);
    if (!_dirty || await _confirmDiscard()) navigator.pop();
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
          'Data yang sudah diisi belum disimpan dan akan hilang.',
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

  void _save() {
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_formKey.currentState!.validate()) return;
    final time = _time!;
    try {
      final id = store.nextAgendaId();
      store.saveAgenda(
        Agenda(
          id: id,
          applicationId: _appId!,
          type: _type!,
          scheduledAt: ScheduleFormat.parseWib(_date!, time.hour, time.minute),
          locationOrLink: _location.text.trim(),
          notes: _notes.text.trim(),
        ),
      );
      Navigator.of(context).pop(id);
    } on StateError {
      setState(
        () => _error =
            'Lamaran terkait sudah tidak tersedia. Pilih lamaran lain.',
      );
    } on ArgumentError catch (e) {
      setState(
        () => _error = 'Agenda tidak dapat disimpan. ${e.message ?? ''}'.trim(),
      );
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
        onPressed: () => Navigator.maybePop(context),
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
          onChanged: _eligible.isEmpty ? null : _setApp,
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
          onTap: () {
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
          onTap: onTap,
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

  Widget _errorBanner(String message) => Semantics(
    liveRegion: true,
    child: Container(
      key: const ValueKey('agenda-error'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: RecruitmentStatus.rejected.background,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: RecruitmentStatus.rejected.foreground,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: _text(
                12,
                color: RecruitmentStatus.rejected.foreground,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );

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
            onPressed: () => Navigator.maybePop(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 48),
              padding: padding,
              foregroundColor: AppColors.navy,
              side: const BorderSide(color: AppColors.border),
              shape: shape,
            ),
            child: _actionLabel('Batal', AppColors.navy),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 3,
          child: FilledButton(
            key: const ValueKey('agenda-save'),
            onPressed: _eligible.isEmpty ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 48),
              padding: padding,
              backgroundColor: AppColors.primary,
              shape: shape,
            ),
            child: _actionLabel('Simpan Agenda', AppColors.white),
          ),
        ),
      ],
    );
  }
}
