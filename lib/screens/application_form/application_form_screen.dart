import 'package:flutter/material.dart';

import '../../core/constants/app_dates.dart';
import '../../core/constants/app_tokens.dart';
import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_repository.dart';
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

  ColorScheme get _colors => Theme.of(context).colorScheme;

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
    'Situs perusahaan',
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

  // Captured when edit opens. Never silently replace with a newer revision.
  int? _editExpectedRevision;
  bool _hadEditingRecord = false;
  bool _editNeedsReview = false;
  bool _editOutcomeUnknown = false;
  ApplicationDraft? _submittedEditDraft;
  String? _committedEditId;
  int? _committedEditRevision;

  // Backend create: one immutable ID+draft per intent, even after timeout.
  ApplicationCreation? _createIntent;
  bool _createOutcomeUnknown = false;
  String? _committedCreateId;
  // A completed write can wait for this form to own its route again.
  String? _pendingNavigationId;

  // A confirmed receipt is not a guarantee that its record still exists.
  // These states only permit an explicit exit without saved-ID completion.
  bool _confirmedRecordMissing = false;
  bool _matchingServerStateUnconfirmed = false;
  bool get _safeExitAvailable =>
      _confirmedRecordMissing || _matchingServerStateUnconfirmed;

  bool get _isEditing => widget.applicationId != null;
  bool get _routeCurrent {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    final owner = Navigator.maybeOf(context);
    return route != null &&
        route.isCurrent &&
        owner != null &&
        identical(widget.navigation.navigatorKey.currentState, owner);
  }

  bool get _formLocked =>
      _saving ||
      _submissionCommitted ||
      (widget.store.isConnected && _createIntent != null) ||
      _editNeedsReview;

  @override
  void initState() {
    super.initState();
    final app = _isEditing
        ? widget.store.applicationById(widget.applicationId!)
        : null;
    _hadEditingRecord = app != null;
    _editExpectedRevision = _isEditing && widget.store.isConnected
        ? widget.store.applicationRevision(widget.applicationId!)
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
    if (!_dirty && !_safeExitAvailable) return true;
    final missing = _confirmedRecordMissing;
    final matchOnly = _matchingServerStateUnconfirmed;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              missing
                  ? 'Lamaran tidak ada di snapshot terbaru'
                  : matchOnly
                  ? 'Edit belum terkonfirmasi'
                  : 'Batalkan perubahan?',
            ),
            content: Text(
              missing
                  ? 'Server telah menerima permintaan simpan, tetapi ID '
                        'lamaran tidak ditemukan setelah pembaruan data. '
                        'Kembali tanpa membuka Board/Detail dan tanpa kirim ulang?'
                  : matchOnly
                  ? 'Data server sama dengan draft, tetapi form tidak menerima '
                        'confirmed receipt. Kembali tanpa menganggap edit berhasil?'
                  : _createOutcomeUnknown || _editOutcomeUnknown
                  ? 'Hasil kirim ke server belum pasti. Keluar tidak '
                        'membatalkan permintaan yang mungkin sudah diterima. '
                        'Yakin ingin meninggalkan draft?'
                  : 'Data yang belum disimpan akan hilang. Yakin ingin keluar?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Lanjut mengisi'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  _safeExitAvailable
                      ? 'Kembali tanpa konfirmasi'
                      : 'Buang perubahan',
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  // A PopScope guard also catches the phone's system-back gesture/button.
  Future<void> _cancel() async {
    if (!_routeCurrent ||
        _allowPop ||
        _saving ||
        (_submissionCommitted && !_safeExitAvailable)) {
      return;
    }
    final approved = await _confirmDiscard();
    if (!approved ||
        !_routeCurrent ||
        _saving ||
        (_submissionCommitted && !_safeExitAvailable)) {
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_routeCurrent) {
        // Use the owning Navigator, never a different top route.
        Navigator.of(context).pop<String>();
      } else if (mounted) {
        // PopScope permission is one-shot: do not leave the dirty form armed.
        setState(() => _allowPop = false);
      }
    });
  }

  Future<void> _pickDate() async {
    if (_formLocked) return;
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
    if (selected == null || !mounted || _formLocked) return;
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

    if (!RegExp(r'^\d+$').hasMatch(text)) {
      return 'Masukkan nominal rupiah tanpa tanda baca.';
    }

    final amount = BigInt.tryParse(text);

    if (amount == null || amount > BigInt.parse('9007199254740991')) {
      return 'Nominal maksimal Rp9.007.199.254.740.991.';
    }

    return null;
  }

  // W13-019/020: remote writes must use receipts and snapshot reconciliation.
  Future<void> _save() async {
    if (_saving || _submissionCommitted || _allowPop || _editNeedsReview) {
      return;
    }
    if (_isEditing &&
        widget.store.isConnected &&
        _editExpectedRevision == null) {
      _showError(
        'Revisi lamaran belum tersedia. Muat ulang data sebelum edit.',
      );
      return;
    }

    final ApplicationDraft draft;
    if (widget.store.isConnected && !_isEditing && _createIntent != null) {
      // Retry the identical payload after an ambiguous create failure.
      draft = _createIntent!.draft;
    } else {
      final formValid = _formKey.currentState?.validate() ?? false;
      setState(() => _sourceInvalid = _source.trim().isEmpty);
      if (!formValid || _sourceInvalid) return;
      final salaryText = _salary.text.trim();
      draft = ApplicationDraft(
        company: _company.text.trim(),
        position: _position.text.trim(),
        source: _source.trim(),
        appliedAt: _appliedAt,
        status: _status,
        location: _location.text.trim(),
        workType: _workType,
        salary: salaryText.isEmpty ? null : int.parse(salaryText),
        notes: _notes.text.trim(),
        documentIds: List.of(_documentIds),
      );
    }

    setState(() => _saving = true);
    try {
      final String id;
      if (widget.store.isConnected) {
        if (_isEditing) {
          id = widget.applicationId!;
          _submittedEditDraft = draft;
          final result = await widget.store.updateApplicationRemote(
            id,
            _editExpectedRevision!,
            draft,
          );
          // Route coverage only blocks UI/navigation, not receipt capture.
          if (!mounted) return;
          if (result.receipt.id != id) {
            throw const RepositoryFailure(
              RepositoryIssue.unexpected,
              writeOutcomeUnknown: true,
            );
          }
          setState(() {
            _committedEditId = id;
            _committedEditRevision = result.receipt.revision;
            _submissionCommitted = true;
          });
          if (!result.snapshotCurrent || !_editReceiptVisible(id)) {
            if (result.snapshotCurrent &&
                widget.store.applicationById(id) == null) {
              setState(() => _confirmedRecordMissing = true);
              if (_routeCurrent) {
                _showError(
                  'Edit diterima server, tetapi ID hilang dari snapshot. '
                  'Pilih Batal untuk kembali tanpa konfirmasi.',
                );
              }
            } else {
              if (_routeCurrent) {
                _showError(
                  'Perubahan sudah diterima server, tetapi snapshot belum '
                  'memuat revisi terbaru. Tekan Muat ulang; jangan kirim ulang.',
                );
              }
            }
            return;
          }
        } else {
          final intent = _createIntent ??= ApplicationCreation(draft);
          // AbsorbPointer does not prevent key events in an already-focused field.
          FocusManager.instance.primaryFocus?.unfocus();
          if (widget.store.phase == StorePhase.error) {
            await widget.store.refresh();
            if (!_routeCurrent) return;
          }
          final result = await widget.store.createApplicationRemote(intent);
          // Preserve confirmed receipts while a temporary route covers S04.
          if (!mounted) return;
          if (result.receipt.id != intent.id) {
            throw const RepositoryFailure(
              RepositoryIssue.unexpected,
              writeOutcomeUnknown: true,
            );
          }
          id = result.receipt.id;
          setState(() {
            _committedCreateId = id;
            _submissionCommitted = true;
            _createOutcomeUnknown = false;
          });
          if (!result.snapshotCurrent ||
              widget.store.applicationById(id) == null) {
            if (result.snapshotCurrent &&
                widget.store.applicationById(id) == null) {
              setState(() => _confirmedRecordMissing = true);
              if (_routeCurrent) {
                _showError(
                  'Tambah diterima server, tetapi ID hilang dari snapshot. '
                  'Pilih Batal untuk kembali tanpa konfirmasi.',
                );
              }
            } else {
              if (_routeCurrent) {
                _showError(
                  'Lamaran sudah diterima server, tetapi data terbaru belum '
                  'tersedia. Tekan Muat ulang; jangan kirim ulang lamaran.',
                );
              }
            }
            return;
          }
        }
      } else if (_isEditing) {
        id = widget.applicationId!;
        widget.store.updateApplication(id, draft);
      } else {
        id = widget.store.addApplication(draft);
      }

      if (!mounted) return;
      if (!_routeCurrent) {
        // Keep completion available without issuing the mutation again.
        setState(() => _pendingNavigationId = id);
        return;
      }
      _completeNavigation(id);
    } on RepositoryFailure catch (error) {
      if (!_routeCurrent) return;
      if (widget.store.isConnected && _isEditing) {
        if (error.writeOutcomeUnknown ||
            error.issue == RepositoryIssue.revisionConflict ||
            error.issue == RepositoryIssue.unavailable ||
            error.issue == RepositoryIssue.documentUnavailable) {
          setState(() {
            _editNeedsReview = true;
            _editOutcomeUnknown = error.writeOutcomeUnknown;
          });
        }
        _showError(
          error.writeOutcomeUnknown
              ? 'Hasil edit belum pasti. Draft tetap aman. '
                    'Tekan Periksa server sebelum mencoba lagi.'
              : error.issue.message,
        );
      } else {
        if (widget.store.isConnected) {
          if (error.writeOutcomeUnknown) {
            _createOutcomeUnknown = true;
          } else if (!_createOutcomeUnknown) {
            _createIntent = null;
          }
        }
        _showError(
          error.writeOutcomeUnknown
              ? 'Hasil simpan belum pasti. Draft dan ID dipertahankan. '
                    'Tekan Coba lagi saat koneksi pulih.'
              : error.issue.message,
        );
      }
    } on ArgumentError catch (error) {
      if (_routeCurrent) {
        _showError(error.message?.toString() ?? error.toString());
      }
    } on StateError catch (error) {
      if (_routeCurrent) {
        _showError(error.message);
      }
    } catch (_) {
      if (!_routeCurrent) return;
      if (widget.store.isConnected && _isEditing) {
        setState(() {
          _editNeedsReview = true;
          _editOutcomeUnknown = true;
        });
        _showError(
          'Hasil edit belum pasti. Periksa server sebelum mencoba lagi.',
        );
      } else if (widget.store.isConnected) {
        _createOutcomeUnknown = true;
        _showError(
          'Status penyimpanan belum pasti. Coba lagi dengan ID yang sama.',
        );
      } else {
        _showError('Gagal menyimpan lamaran. Silakan coba lagi.');
      }
    } finally {
      if (mounted && !_allowPop) setState(() => _saving = false);
    }
  }

  bool _editReceiptVisible(String id) {
    final revision = widget.store.applicationRevision(id);
    return widget.store.applicationById(id) != null &&
        revision != null &&
        _committedEditRevision != null &&
        revision >= _committedEditRevision!;
  }

  Future<void> _reloadCommittedWrite() async {
    final id = _committedCreateId ?? _committedEditId;
    if (id == null || _saving || _allowPop) return;
    setState(() => _saving = true);
    try {
      await widget.store.refresh();
      if (!_routeCurrent) return;
      if (widget.store.phase != StorePhase.error &&
          widget.store.applicationById(id) == null) {
        setState(() => _confirmedRecordMissing = true);
        _showError(
          'ID lamaran tidak ditemukan setelah refresh. '
          'Pilih Batal untuk kembali tanpa konfirmasi; jangan kirim ulang.',
        );
        return;
      }
      final isReady =
          widget.store.phase != StorePhase.error &&
          (_committedEditId != null
              ? _editReceiptVisible(id)
              : widget.store.applicationById(id) != null);
      if (isReady) {
        _completeNavigation(id);
      } else {
        _showError(
          widget.store.failure?.issue.message ?? 'Data server belum terbarui. Tekan Muat ulang untuk mencoba lagi.',
        );
      }
    } catch (_) {
      if (_routeCurrent) {
        _showError('Belum bisa memuat data terbaru. Coba lagi.');
      }
    } finally {
      if (mounted && !_allowPop) setState(() => _saving = false);
    }
  }

  // On ambiguous edit / revision conflict, reconcile before ever retrying.
  Future<void> _reviewEditServer() async {
    if (!_isEditing || !_editNeedsReview || _saving) return;
    final id = widget.applicationId!;
    setState(() => _saving = true);
    try {
      await widget.store.refresh();
      if (!_routeCurrent) return;
      final server = widget.store.applicationById(id);
      final revision = widget.store.applicationRevision(id);
      if (widget.store.phase == StorePhase.error ||
          server == null ||
          revision == null) {
        _showError(
          widget.store.failure?.issue.message ??
              'Versi server tidak tersedia. Draft tetap disimpan di form.',
        );
        return;
      }
      if (revision == _editExpectedRevision) {
        // No revision change in a refreshed snapshot: user may explicitly retry.
        setState(() {
          _editNeedsReview = false;
          _editOutcomeUnknown = false;
        });
        _showError(
          'Revisi server belum berubah. Tinjau draft lalu simpan ulang.',
        );
        return;
      }
      if (_submittedEditDraft != null &&
          _sameApplicationDraft(server, _submittedEditDraft!)) {
        // Identical payload is evidence of state, NOT a confirmed receipt.
        // It could be another actor's edit (including JT002 conflicts).
        setState(() => _matchingServerStateUnconfirmed = true);
        _showError(
          'Snapshot sama dengan draft, tetapi receipt edit tidak terkonfirmasi. '
          'Pilih Batal untuk kembali tanpa konfirmasi.',
        );
        return;
      }

      if (!mounted) {
        return;
      }
      final decision = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Versi server telah berubah'),
          content: Text(
            'Draft Anda tetap ada. Revisi saat form dibuka: '
            '${_editExpectedRevision ?? '-'}, revisi server: $revision.\n\n'
            'Versi server: ${server.company} — ${server.position} '
            '(${server.source}).\n\n'
            'Memilih Simpan draft saya akan memakai revisi baru saat '
            'Anda menekan Simpan lagi, dan dapat menimpa perubahan server.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Pertahankan draft'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'server'),
              child: const Text('Muat versi server'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'draft'),
              child: const Text('Simpan draft saya'),
            ),
          ],
        ),
      );
      if (!_routeCurrent) return;
      if (decision == 'server') {
        _company.text = server.company;
        _position.text = server.position;
        _location.text = server.location;
        _salary.text = server.salary?.toString() ?? '';
        _notes.text = server.notes;
        setState(() {
          _source = server.source;
          _appliedAt = server.appliedAt;
          _status = server.status;
          _workType = server.workType;
          _documentIds = List.of(server.documentIds);
          _editExpectedRevision = revision;
          _submittedEditDraft = null;
          _editNeedsReview = false;
          _editOutcomeUnknown = false;
          _matchingServerStateUnconfirmed = false;
          _dirty = false;
        });
      } else if (decision == 'draft') {
        // Explicit opt-in only; never silently swap the captured revision.
        setState(() {
          _editExpectedRevision = revision;
          _editNeedsReview = false;
          _editOutcomeUnknown = false;
          _matchingServerStateUnconfirmed = false;
        });
        _showError('Draft dipertahankan. Tekan Simpan Perubahan untuk lanjut.');
      }
    } catch (_) {
      if (_routeCurrent) {
        _showError('Gagal memeriksa server. Draft tetap ada.');
      }
    } finally {
      if (mounted && !_allowPop) setState(() => _saving = false);
    }
  }

  bool _sameApplicationDraft(Application app, ApplicationDraft draft) {
    final remoteIds = app.documentIds.toSet();
    final draftIds = draft.documentIds.toSet();
    return app.company == draft.company &&
        app.position == draft.position &&
        app.source == draft.source &&
        app.appliedAt.year == draft.appliedAt.year &&
        app.appliedAt.month == draft.appliedAt.month &&
        app.appliedAt.day == draft.appliedAt.day &&
        app.status == draft.status &&
        app.location == draft.location &&
        app.workType == draft.workType &&
        app.salary == draft.salary &&
        app.notes == draft.notes &&
        remoteIds.length == draftIds.length &&
        remoteIds.containsAll(draftIds);
  }

  void _completeNavigation(String id) {
    if (!_routeCurrent) return;
    setState(() {
      _submissionCommitted = true;
      _pendingNavigationId = id;
      _allowPop = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_routeCurrent) {
        _finishNavigation(id);
      } else if (mounted) {
        // No foreign pop, no armed PopScope, no permanently busy footer.
        setState(() {
          _allowPop = false;
          _saving = false;
        });
      }
    });
  }

  void _finishNavigation(String id) {
    if (!_routeCurrent || !_submissionCommitted) return;
    if (widget.store.isConnected && widget.store.applicationById(id) == null) {
      setState(() {
        _allowPop = false;
        _pendingNavigationId = null;
        _confirmedRecordMissing = true;
      });
      _showError(
        'ID lamaran tidak ditemukan. Kembali tanpa konfirmasi '
        'atau tekan Muat ulang.',
      );
      return;
    }
    try {
      widget.navigation.finishForm(id);
    } catch (_) {
      if (!_routeCurrent) return;
      setState(() {
        _allowPop = false;
        _saving = false;
      });
      // Retry must not pop a newer route after the form loses ownership.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Lamaran tersimpan, tetapi gagal kembali.'),
          action: SnackBarAction(
            label: 'Coba lagi',
            onPressed: () {
              if (_routeCurrent) _completeNavigation(id);
            },
          ),
        ),
      );
    }
  }

  void _showError(String message) {
    final colors = _colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: colors.errorContainer,
        content: Text(
          message,
          style: TextStyle(color: colors.onErrorContainer),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(IconData icon, String hint) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _gray, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: _gray),
        prefixIconConstraints: const BoxConstraints(minWidth: 43),
        filled: true,
        fillColor: _colors.surfaceContainer,
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
          borderSide: BorderSide(color: _colors.error),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _colors.error, width: 1.5),
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
          Text(' *', style: TextStyle(fontSize: 12, color: _colors.error)),
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
          readOnly: _formLocked,
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
      color: _colors.surfaceContainerLowest,
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
                color: _colors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: _colors.onPrimaryContainer),
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
              onSelected: _formLocked
                  ? null
                  : (_) => setState(() {
                      _source = source;
                      _sourceInvalid = false;
                      _dirty = true;
                    }),
            ),
        ],
      ),
      if (_sourceInvalid)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Pilih sumber lowongan.',
            style: TextStyle(fontSize: 12, color: _colors.error),
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
                  onSelected: _formLocked
                      ? null
                      : (value) => setState(() {
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
    if (_formLocked) return;
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
                  onTap: _formLocked ? null : () => _selectWorkType(type),
                  child: InkWell(
                    excludeFromSemantics: true,
                    onTap: _formLocked ? null : () => _selectWorkType(type),
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
                onSelected: _formLocked
                    ? null
                    : (selected) => setState(() {
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
                onPressed:
                    (_saving || (_submissionCommitted && !_safeExitAvailable))
                    ? null
                    : _cancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navy,
                  side: const BorderSide(color: _border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
                        : _pendingNavigationId != null
                        ? 'Lanjut'
                        : (_committedCreateId != null ||
                              _committedEditId != null)
                        ? 'Muat ulang'
                        : _editNeedsReview
                        ? 'Periksa server'
                        : _createOutcomeUnknown
                        ? 'Coba lagi'
                        : (_isEditing ? 'Simpan Perubahan' : 'Simpan Lamaran'),
                    onPressed: _saving || _allowPop
                        ? null
                        : _pendingNavigationId != null
                        ? () => _completeNavigation(_pendingNavigationId!)
                        : (_committedCreateId != null ||
                              _committedEditId != null)
                        ? _reloadCommittedWrite
                        : _editNeedsReview
                        ? _reviewEditServer
                        : _save,
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
    // After a remote conflict/deletion, keep the already-open draft visible.
    if (_isEditing &&
        !_hadEditingRecord &&
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
                  onPressed:
                      (_saving || (_submissionCommitted && !_safeExitAvailable))
                      ? null
                      : _cancel,
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
          child: ExcludeFocus(
            excluding: _formLocked,
            child: AbsorbPointer(
              absorbing: _formLocked,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 12),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '*',
                                style: TextStyle(color: _colors.error),
                              ),
                              const TextSpan(
                                text: ' wajib diisi',
                                style: TextStyle(color: _gray),
                              ),
                            ],
                          ),
                          style: const TextStyle(fontSize: 11),
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
        ),
        bottomNavigationBar: _footer(),
      ),
    );
  }
}
