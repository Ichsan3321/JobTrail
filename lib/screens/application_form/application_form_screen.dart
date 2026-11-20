import 'package:flutter/material.dart';

import '../../core/constants/app_dates.dart';
import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_store.dart';
import '../../models/application.dart';
import '../../models/recruitment_status.dart';
import '../../widgets/app_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/input_field.dart';
import '../../widgets/status_chip.dart';

/// S04 Add/Edit Application. Uses the shared JobTrailStore and navigation.
/// The form owns only transient UI state; it does not create another store.
class ApplicationFormScreen extends StatefulWidget {
  const ApplicationFormScreen({
    super.key,
    required this.store,
    required this.navigation,
    this.applicationId,
  });

  final JobTrailStore store;
  final AppNavigation navigation;
  final String? applicationId;

  @override
  State<ApplicationFormScreen> createState() => _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends State<ApplicationFormScreen> {
  // The palette follows JobTrail's shared GSM. Move these to AppTokens only
  // after coordinating with the owner of the shared theme.
  static const _navy = Color(0xFF1E2A4A);
  static const _gray = Color(0xFF5A6380);
  static const _primary = Color(0xFF5B5BF0);
  static const _primaryDark = Color(0xFF4343C9);
  static const _primaryLight = Color(0xFFEEEEFF);
  static const _background = Color(0xFFF7F7FC);
  static const _border = Color(0xFFE4E4F0);

  static const _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  String _dateLabel(DateTime date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';

  static const _sources = <String>[
    'LinkedIn',
    'Glints',
    'Kalibrr',
    'Jobstreet',
    'Website perusahaan',
    'Referral',
    'Job fair kampus',
    'Lainnya',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _company;
  late final TextEditingController _position;
  late final TextEditingController _location;
  late final TextEditingController _salary;
  late final TextEditingController _notes;

  late DateTime _appliedAt;
  late RecruitmentStatus _status;
  late WorkType _workType;
  late String _source;
  late List<String> _documentIds;

  bool _dirty = false;
  bool _allowPop = false;
  bool _saving = false;
  bool _submissionCommitted = false;
  bool _sourceInvalid = false;

  bool get _isEditing => widget.applicationId != null;

  @override
  void initState() {
    super.initState();
    final app = _isEditing
        ? widget.store.applicationById(widget.applicationId!)
        : null;
    _company = TextEditingController(text: app?.company ?? '');
    _position = TextEditingController(text: app?.position ?? '');
    _location = TextEditingController(text: app?.location ?? '');
    _salary = TextEditingController(text: app?.salary?.toString() ?? '');
    _notes = TextEditingController(text: app?.notes ?? '');
    _source = app?.source ?? '';
    _appliedAt = app?.appliedAt ?? widget.store.referenceDate;
    _status = app?.status ?? RecruitmentStatus.applied;
    _workType = app?.workType ?? WorkType.onSite;
    _documentIds = List.of(app?.documentIds ?? const <String>[]);

    for (final controller in [
      _company,
      _position,
      _location,
      _salary,
      _notes,
    ]) {
      controller.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _company,
      _position,
      _location,
      _salary,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Batalkan perubahan?'),
            content: const Text(
              'Data yang belum disimpan akan hilang. Yakin ingin keluar?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Lanjut mengisi'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Buang perubahan'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // A PopScope guard also catches the phone's system-back gesture/button.
  Future<void> _cancel() async {
    if (_allowPop || _saving || _submissionCommitted) return;
    final approved = await _confirmDiscard();
    if (!approved || !mounted || _saving || _submissionCommitted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.navigation.back();
    });
  }

  Future<void> _pickDate() async {
    if (_saving || _submissionCommitted) return;
    final reference = widget.store.referenceDate;
    final lastDate = DateTime(reference.year, reference.month, reference.day);
    final current = DateTime(_appliedAt.year, _appliedAt.month, _appliedAt.day);
    // Existing records may predate the default year 2000 lower bound.
    // A previously stored date beyond the demo anchor must not crash the picker.
    var firstYear = 2000;
    if (current.year < firstYear) firstYear = current.year;
    if (lastDate.year < firstYear) firstYear = lastDate.year;
    final firstDate = DateTime(firstYear);
    final initialDate = current.isAfter(lastDate) ? lastDate : current;
    final selected = await showDatePicker(
      context: context,
      helpText: 'Tanggal Melamar',
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: initialDate,
    );
    if (selected == null || !mounted || _saving || _submissionCommitted) return;
    setState(() {
      _appliedAt = AppDates.date(selected.year, selected.month, selected.day);
      _dirty = true;
    });
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Wajib diisi.' : null;

  String? _validateSalary(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (!RegExp(r'^\d+$').hasMatch(text) || int.tryParse(text) == null) {
      return 'Masukkan nominal rupiah tanpa tanda baca.';
    }
    return null;
  }

  // A successful store write must be treated as committed even while the next
  // Navigator frame is pending. Otherwise a second rapid tap can add twice.
  Future<void> _save() async {
    if (_saving || _submissionCommitted || _allowPop) return;
    final formValid = _formKey.currentState?.validate() ?? false;
    setState(() => _sourceInvalid = _source.trim().isEmpty);
    if (!formValid || _sourceInvalid) return;

    final salaryText = _salary.text.trim();
    final draft = ApplicationDraft(
      company: _company.text.trim(),
      position: _position.text.trim(),
      source: _source.trim(),
      appliedAt: _appliedAt,
      status: _status,
      location: _location.text.trim(),
      workType: _workType,
      salary: salaryText.isEmpty ? null : int.parse(salaryText),
      notes: _notes.text.trim(),
      documentIds: _documentIds,
    );

    setState(() => _saving = true);
    try {
      final String id;
      if (_isEditing) {
        id = widget.applicationId!;
        widget.store.updateApplication(id, draft);
      } else {
        id = widget.store.addApplication(draft);
      }
      if (!mounted) return;
      setState(() {
        _submissionCommitted = true;
        _allowPop = true;
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _finishNavigation(id),
      );
    } on ArgumentError catch (error) {
      if (mounted) _showError(error.message?.toString() ?? error.toString());
    } on StateError catch (error) {
      if (mounted) _showError(error.message);
    } catch (error) {
      if (mounted) _showError('Gagal menyimpan lamaran: $error');
    } finally {
      // Only a failed store write may unlock the Save button. A successful
      // write remains locked until the form route has finished popping.
      if (mounted && !_submissionCommitted) setState(() => _saving = false);
    }
  }

  void _finishNavigation(String id) {
    if (!mounted) return;
    try {
      widget.navigation.finishForm(id);
    } catch (error) {
      // A commit already happened; allowing Save again would create a duplicate.
      // Offer navigation retry without writing to the store a second time.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Lamaran tersimpan, tetapi gagal kembali.'),
          action: SnackBarAction(
            label: 'Coba lagi',
            onPressed: () => _finishNavigation(id),
          ),
        ),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _inputDecoration(IconData icon, String hint) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _gray, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: _gray),
        prefixIconConstraints: const BoxConstraints(minWidth: 43),
        filled: true,
        fillColor: _background,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 13,
          horizontal: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _border),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _primary, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.red),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
      );

  Widget _fieldLabel(
    String label, {
    bool isRequired = false,
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Wrap(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _navy,
          ),
        ),
        if (isRequired)
          const Text(
            ' *',
            style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
          ),
        if (optional)
          const Text(
            ' (Opsional)',
            style: TextStyle(fontSize: 12, color: _gray),
          ),
      ],
    ),
  );

  Widget _textField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool isRequired = false,
    bool optional = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: _fieldLabel(label, isRequired: isRequired, optional: optional),
      ),
      Semantics(
        label: isRequired ? '$label, wajib diisi' : label,
        child: TextFormField(
          controller: controller,
          style: const TextStyle(
            color: _navy,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          textInputAction: TextInputAction.next,
          validator: isRequired ? _required : null,
          decoration: _inputDecoration(icon, hint),
        ),
      ),
    ],
  );

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: _primaryDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: _gray),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );

  Widget _informationCard() => _card(
    icon: Icons.description_outlined,
    title: 'Informasi Lamaran',
    subtitle: 'Perusahaan, posisi, dan tahap seleksi',
    children: [
      _textField(
        label: 'Nama Perusahaan',
        controller: _company,
        icon: Icons.business_outlined,
        hint: 'Contoh: Lentera Tech',
        isRequired: true,
      ),
      const SizedBox(height: 14),
      _textField(
        label: 'Posisi',
        controller: _position,
        icon: Icons.work_outline,
        hint: 'Contoh: Frontend Developer Intern',
        isRequired: true,
      ),
      const SizedBox(height: 14),
      _fieldLabel('Sumber Lowongan', isRequired: true),
      Wrap(
        spacing: 7,
        runSpacing: 8,
        children: [
          for (final source in {..._sources, if (_source.isNotEmpty) _source})
            ChoiceChip(
              label: Text(source),
              selected: _source == source,
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 12,
                color: _source == source ? _primaryDark : _gray,
                fontWeight: _source == source
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
              backgroundColor: Colors.white,
              selectedColor: _primaryLight,
              side: BorderSide(color: _source == source ? _primary : _border),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              onSelected: (_) => setState(() {
                _source = source;
                _sourceInvalid = false;
                _dirty = true;
              }),
            ),
        ],
      ),
      if (_sourceInvalid)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Pilih sumber lowongan.',
            style: TextStyle(fontSize: 12, color: Colors.red),
          ),
        ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fieldLabel('Tanggal Melamar', isRequired: true),
                InkWell(
                  key: const ValueKey('form-date-picker'),
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _background,
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 17,
                          color: _gray,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _dateLabel(_appliedAt),
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fieldLabel('Status', isRequired: true),
                PopupMenuButton<RecruitmentStatus>(
                  key: const ValueKey('form-status-picker'),
                  initialValue: _status,
                  onSelected: (value) => setState(() {
                    _status = value;
                    _dirty = true;
                  }),
                  itemBuilder: (_) => [
                    for (final value in RecruitmentStatus.values)
                      PopupMenuItem(
                        value: value,
                        child: StatusChip(status: value),
                      ),
                  ],
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _background,
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: StatusChip(status: _status),
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: _gray,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );

  void _selectWorkType(WorkType type) {
    if (_saving || _submissionCommitted) return;
    setState(() {
      _workType = type;
      _dirty = true;
    });
  }

  Widget _workLocationCard() => _card(
    icon: Icons.location_on_outlined,
    title: 'Lokasi & Tipe Kerja',
    subtitle: 'Tempat kerja yang dilamar',
    children: [
      _textField(
        label: 'Kota / Lokasi',
        controller: _location,
        icon: Icons.place_outlined,
        hint: 'Contoh: Bandung',
        // Shared store requires location until the central contract changes.
        isRequired: true,
      ),
      const SizedBox(height: 14),
      _fieldLabel('Tipe Kerja', isRequired: true),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _background,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            for (final type in WorkType.values)
              Expanded(
                child: Semantics(
                  key: ValueKey('work-type-${type.name}'),
                  container: true,
                  button: true,
                  selected: _workType == type,
                  label: 'Tipe kerja ${type.label}',
                  onTap: _saving ? null : () => _selectWorkType(type),
                  child: InkWell(
                    excludeFromSemantics: true,
                    onTap: _saving ? null : () => _selectWorkType(type),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _workType == type
                            ? Colors.white
                            : Colors.transparent,
                        border: _workType == type
                            ? Border.all(color: _border)
                            : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        type.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _workType == type ? _primaryDark : _gray,
                          fontSize: 13,
                          fontWeight: _workType == type
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _additionalCard() => _card(
    icon: Icons.notes_outlined,
    title: 'Informasi Tambahan',
    subtitle: 'Lengkapi informasi jika tersedia',
    children: [
      InputField(
        label: 'Gaji per bulan (Rp, opsional)',
        controller: _salary,
        keyboardType: TextInputType.number,
        validator: _validateSalary,
      ),
      const SizedBox(height: 12),
      InputField(label: 'Catatan (opsional)', controller: _notes, maxLines: 4),
      if (widget.store.documents.isNotEmpty) ...[
        const SizedBox(height: 14),
        _fieldLabel('Dokumen pendukung', optional: true),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final doc in widget.store.documents)
              FilterChip(
                label: Text(doc.title),
                selected: _documentIds.contains(doc.id),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _documentIds.add(doc.id);
                  } else {
                    _documentIds.remove(doc.id);
                  }
                  _dirty = true;
                }),
              ),
          ],
        ),
      ],
    ],
  );

  Widget _footer() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: _border)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            SizedBox(
              width: 112,
              height: 48,
              child: OutlinedButton(
                onPressed: _saving ? null : _cancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navy,
                  side: const BorderSide(color: _border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButtonTheme(
                  data: FilledButtonThemeData(
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  child: AppButton(
                    label: _saving
                        ? 'Menyimpan...'
                        : (_isEditing ? 'Simpan Perubahan' : 'Simpan Lamaran'),
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // The screen can outlive its entity if another route deletes it.
    if (_isEditing &&
        widget.store.applicationById(widget.applicationId!) == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Lamaran')),
        body: const SafeArea(
          child: EmptyState(
            message: 'Lamaran tidak ditemukan. Silakan kembali.',
          ),
        ),
      );
    }

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _cancel();
      },
      child: Scaffold(
        key: const ValueKey('S04'),
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _background,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 60,
          automaticallyImplyLeading: false,
          titleSpacing: 20,
          title: Row(
            children: [
              Tooltip(
                message: 'Kembali',
                child: OutlinedButton(
                  onPressed: _saving ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    maximumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: _border),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Icon(Icons.arrow_back, color: _navy, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isEditing ? 'Edit Lamaran' : 'Tambah Lamaran',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    Text(
                      _isEditing
                          ? 'Perbarui informasi lamaran'
                          : 'Catat lamaran kerja atau magang baru',
                      style: const TextStyle(fontSize: 12, color: _gray),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: AbsorbPointer(
            absorbing: _saving,
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 12),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '*',
                              style: TextStyle(color: Color(0xFFB91C1C)),
                            ),
                            TextSpan(
                              text: ' wajib diisi',
                              style: TextStyle(color: _gray),
                            ),
                          ],
                        ),
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    _informationCard(),
                    const SizedBox(height: 12),
                    _workLocationCard(),
                    const SizedBox(height: 12),
                    _additionalCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: _footer(),
      ),
    );
  }
}
