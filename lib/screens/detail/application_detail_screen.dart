import 'package:flutter/material.dart';

import '../../core/constants/app_dates.dart';
import '../../core/constants/app_tokens.dart';
import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_repository.dart';
import '../../data/jobtrail_store.dart';
import '../../models/agenda.dart';
import '../../models/application.dart';
import '../../models/recruitment_status.dart';
import '../../models/status_history.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';
import '../schedule/add_agenda_sheet.dart';
import '../documents/document_preview_sheet.dart';

class ApplicationDetailScreen extends StatefulWidget {
  const ApplicationDetailScreen({
    super.key,
    required this.store,
    required this.navigation,
    required this.applicationId,
  });

  final JobTrailStore store;
  final AppNavigation navigation;
  final String applicationId;

  @override
  State<ApplicationDetailScreen> createState() =>
      _ApplicationDetailScreenState();
}

class _ApplicationDetailScreenState extends State<ApplicationDetailScreen> {
  JobTrailStore get store => widget.store;
  String get applicationId => widget.applicationId;

  ModalRoute<dynamic>? _route;
  bool _actionInProgress = false;
  String? _confirmedDeletionId;
  ApplicationReceipt? _statusReceiptAwaitingSnapshot;
  RecruitmentStatus? _statusDraft;
  String? _deferredMessage;

  bool get _canMutate =>
      !store.isMutating &&
      !store.isRefreshing &&
      (store.phase == StorePhase.ready || store.phase == StorePhase.empty);

  // The protected navigator and store are replaced together on account change.
  bool _ownsSession(JobTrailStore actionStore) =>
      mounted && identical(store, actionStore);

  bool _ownsRoute(JobTrailStore actionStore, String id) =>
      _ownsSession(actionStore) &&
      applicationId == id &&
      _route?.isActive == true;

  bool get _isVisible => _route?.isCurrent == true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (!_isVisible ||
        (_deferredMessage == null && _confirmedDeletionId == null)) {
      return;
    }
    final actionStore = store;
    final id = applicationId;
    // Route changes are reported during build. Defer UI effects until the frame
    // ends and check ownership again in case the route changed meanwhile.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_ownsRoute(actionStore, id) || !_isVisible) return;
      if (_deferredMessage case final message?) _showMessage(message);
      _finishDeletion();
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionInProgress || !_canMutate) return;
    setState(() => _actionInProgress = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final application = store.applicationById(applicationId);
      return Scaffold(
        key: const ValueKey('S03'),
        body: SafeArea(
          child: Column(
            children: [
              _DetailHeader(
                onEdit: application == null || !store.allowsLocalWrites
                    ? null
                    : () => widget.navigation.openEdit(applicationId),
              ),
              if (store.phase == StorePhase.error)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          store.failure?.issue.message ??
                              RepositoryIssue.unexpected.message,
                        ),
                      ),
                      TextButton(
                        onPressed: store.isRefreshing || _actionInProgress
                            ? null
                            : _refreshSnapshot,
                        child: const Text('Muat ulang'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: application == null
                    ? const EmptyState(
                        message: 'Lamaran tidak ditemukan. Silakan kembali.',
                      )
                    : _buildDetails(context, application),
              ),
            ],
          ),
        ),
        bottomNavigationBar: application == null
            ? null
            : _DetailActions(
                onChangeStatus: _actionInProgress || !_canMutate
                    ? null
                    : () => _runAction(() => _changeStatus(application)),
                onDelete: _actionInProgress || !_canMutate
                    ? null
                    : () => _runAction(() => _deleteApplication(application)),
              ),
      );
    },
  );

  Future<void> _changeStatus(Application application) async {
    final actionStore = store;
    final id = application.id;
    final revision = actionStore.applicationRevision(id);
    final status = await showModalBottomSheet<RecruitmentStatus>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.white,
      barrierColor: AppColors.navy.withValues(alpha: .65),
      builder: (_) => _StatusSheet(
        application: application,
        initialStatus: _statusDraft ?? application.status,
      ),
    );
    if (!_ownsRoute(actionStore, id) || !_isVisible) return;
    _statusDraft = null;
    if (status == null) return;

    const failureMessage = 'Status gagal diubah.';
    if (!_canSubmit(actionStore, id, revision, failureMessage)) return;
    try {
      if (revision == null) {
        actionStore.changeStatus(id, status);
        return;
      }
      final result = await actionStore.changeStatusRemote(id, revision, status);
      if (!_ownsRoute(actionStore, result.receipt.id)) return;
      if (!result.snapshotCurrent) {
        _statusReceiptAwaitingSnapshot = result.receipt;
        await _refreshSnapshot();
      }
    } on RepositoryFailure catch (failure) {
      await _handleRemoteFailure(
        actionStore,
        id,
        failure,
        failureMessage,
        attemptedStatus: status,
      );
    } on ArgumentError {
      if (_ownsRoute(actionStore, id)) {
        _showMessage('$failureMessage ${RepositoryIssue.validation.message}');
      }
    } on StateError catch (error) {
      if (_ownsRoute(actionStore, id)) {
        _showMessage('$failureMessage ${error.message}');
      }
    }
  }

  Future<void> _deleteApplication(Application application) async {
    final actionStore = store;
    final id = application.id;
    final revision = actionStore.applicationRevision(id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        scrollable: true,
        title: const Text('Hapus lamaran?'),
        content: Text(
          'Lamaran ${application.company}, agenda, dan riwayat statusnya '
          'akan dihapus dari Board. Dokumen bersama tetap tersedia.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ModalRoute.of(dialogContext)?.isCurrent == true) {
                Navigator.pop(dialogContext, false);
              }
            },
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: RecruitmentStatus.rejected.foreground,
            ),
            onPressed: () {
              if (ModalRoute.of(dialogContext)?.isCurrent == true) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Hapus Lamaran'),
          ),
        ],
      ),
    );
    if (!_ownsRoute(actionStore, id) || !_isVisible || confirmed != true) {
      return;
    }

    const failureMessage = 'Lamaran gagal dihapus.';
    if (!_canSubmit(actionStore, id, revision, failureMessage)) return;
    try {
      if (revision == null) {
        actionStore.deleteApplication(id);
        widget.navigation.showTab(AppTab.board);
        return;
      }
      final result = await actionStore.deleteApplicationRemote(id, revision);
      if (!_ownsRoute(actionStore, result.receipt)) return;
      _confirmedDeletionId = result.receipt;
      if (result.snapshotCurrent) {
        _finishDeletion();
      } else {
        await _refreshSnapshot();
      }
    } on RepositoryFailure catch (failure) {
      await _handleRemoteFailure(actionStore, id, failure, failureMessage);
    } on StateError catch (error) {
      if (_ownsRoute(actionStore, id)) {
        _showMessage('$failureMessage ${error.message}');
      }
    }
  }

  bool _canSubmit(
    JobTrailStore actionStore,
    String id,
    int? revision,
    String failureMessage,
  ) {
    if (actionStore.applicationById(id) == null ||
        (actionStore.isConnected && revision == null)) {
      _showMessage('$failureMessage ${RepositoryIssue.unavailable.message}');
      return false;
    }
    return true;
  }

  Future<void> _handleRemoteFailure(
    JobTrailStore actionStore,
    String id,
    RepositoryFailure failure,
    String failureMessage, {
    RecruitmentStatus? attemptedStatus,
  }) async {
    if (!_ownsRoute(actionStore, id) ||
        failure.issue == RepositoryIssue.authentication) {
      return;
    }
    if (failure.writeOutcomeUnknown) {
      _showMessage(
        'Hasil perubahan belum dapat dipastikan. Periksa data terbaru.',
      );
      // The store already attempted reconciliation before returning this failure.
      if (actionStore.phase == StorePhase.error) await _refreshSnapshot();
    } else if (failure.issue == RepositoryIssue.revisionConflict) {
      if (attemptedStatus != null) _statusDraft = attemptedStatus;
      final action = attemptedStatus == null
          ? 'menghapus lamaran'
          : 'memilih status ${attemptedStatus.label}';
      _showMessage(
        'Data lamaran telah berubah. Tinjau data terbaru sebelum $action.',
      );
    } else {
      _showMessage('$failureMessage ${failure.issue.message}');
    }
  }

  Future<void> _refreshSnapshot() async {
    final actionStore = store;
    final id = applicationId;
    if (!_ownsRoute(actionStore, id)) return;
    await actionStore.refresh();
    if (!_ownsRoute(actionStore, id)) return;
    if (actionStore.phase == StorePhase.error) {
      if (_statusReceiptAwaitingSnapshot?.id == id) {
        _showMessage(
          'Perubahan status diterima server. Data terbaru belum tersedia.',
        );
      } else if (_confirmedDeletionId == id) {
        _showMessage(
          'Penghapusan diterima server. Data terbaru belum tersedia.',
        );
      }
      return;
    }
    if (_statusReceiptAwaitingSnapshot?.id == id) {
      _statusReceiptAwaitingSnapshot = null;
      _showMessage(
        'Perubahan status diterima server. Data telah dimuat ulang.',
      );
    }
    _finishDeletion();
  }

  void _finishDeletion() {
    if (!_isVisible || _confirmedDeletionId != applicationId || !_canMutate) {
      return;
    }
    _confirmedDeletionId = null;
    if (store.applicationById(applicationId) == null) {
      widget.navigation.showTab(AppTab.board);
    }
  }

  void _showMessage(String message) {
    if (!_isVisible) {
      _deferredMessage = message;
      return;
    }
    _deferredMessage = null;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildDetails(BuildContext context, Application application) {
    final agendas = store.agendasFor(applicationId);
    final upcomingAgenda = agendas
        .where(
          (agenda) => !agenda.scheduledAt.isBefore(store.referenceInstantUtc),
        )
        .firstOrNull;
    return ListView(
      key: const ValueKey('detail-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, AppSpacing.lg),
      children: [
        _ApplicationSummary(application: application, store: store),
        const SizedBox(height: AppSpacing.sm),
        _RelatedAgenda(
          agenda: upcomingAgenda ?? agendas.lastOrNull,
          upcoming: upcomingAgenda != null,
          onAdd:
              store.allowsLocalWrites &&
                  agendaEligibleStatuses.contains(application.status)
              ? () => showAddAgendaSheet(
                  context,
                  store: store,
                  initialApplicationId: applicationId,
                )
              : null,
          onOpen: () => widget.navigation.showTab(
            AppTab.schedule,
            applicationId: applicationId,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _StatusTimeline(
          // The wire decoder orders server events by event_no. historyFor
          // preserves that order for equal timestamps.
          history: store.historyFor(applicationId),
          currentStatus: application.status,
        ),
        const SizedBox(height: AppSpacing.sm),
        _DetailCard(
          minHeight: 90,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(icon: Icons.notes_rounded, title: 'Catatan'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                application.notes.trim().isEmpty
                    ? 'Belum ada catatan.'
                    : application.notes,
                style: AppTypography.body.copyWith(color: AppColors.gray),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.onEdit});

  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.xs, 20, AppSpacing.sm),
      child: Row(
        children: [
          BackButton(style: _iconStyle),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text('Detail Lamaran', style: AppTypography.section),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: AppSpacing.xs),
            if (constraints.maxWidth >= 540 &&
                MediaQuery.textScalerOf(context).scale(14) <= 18)
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
                label: const Text('Edit Lamaran'),
              )
            else
              IconButton.outlined(
                tooltip: 'Edit Lamaran',
                style: _iconStyle.copyWith(
                  foregroundColor: const WidgetStatePropertyAll(
                    AppColors.primary,
                  ),
                ),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
          ],
        ],
      ),
    ),
  );

  static final _iconStyle = IconButton.styleFrom(
    minimumSize: const Size(44, 44),
    iconSize: 20,
    backgroundColor: AppColors.white,
    foregroundColor: AppColors.navy,
    side: const BorderSide(color: AppColors.border),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

class _ApplicationSummary extends StatelessWidget {
  const _ApplicationSummary({required this.application, required this.store});

  final Application application;
  final JobTrailStore store;

  @override
  Widget build(BuildContext context) {
    final initials = application.company
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first)
        .join()
        .toUpperCase();
    final status = _DottedStatusChip(
      chipKey: const ValueKey('detail-current-status'),
      status: application.status,
    );
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: const EdgeInsets.all(AppSpacing.xs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              initials,
              style: AppTypography.label.copyWith(color: AppColors.primaryDark),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                application.company,
                key: const ValueKey('detail-company'),
                style: AppTypography.section,
              ),
              Text(
                application.position,
                style: AppTypography.label.copyWith(
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 285 ||
                  MediaQuery.textScalerOf(context).scale(14) > 18) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: AppSpacing.xs),
                    status,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: AppSpacing.xs),
                  status,
                ],
              );
            },
          ),
          const Divider(height: 20, color: AppColors.border),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackFields =
                  constraints.maxWidth < 260 ||
                  MediaQuery.textScalerOf(context).scale(14) > 18;
              final fieldWidth = stackFields
                  ? constraints.maxWidth
                  : (constraints.maxWidth - AppSpacing.sm) / 2;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  _Metadata(
                    width: fieldWidth,
                    label: 'Tanggal melamar',
                    value: _formatAppliedDate(application.appliedAt),
                  ),
                  _Metadata(
                    width: fieldWidth,
                    label: 'Sumber',
                    value: application.source,
                  ),
                  _Metadata(
                    width: fieldWidth,
                    label: 'Lokasi & tipe kerja',
                    value:
                        '${application.location} · ${application.workType.label}',
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dokumen dipakai',
                          style: AppTypography.label.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        if (application.documentIds.isEmpty)
                          Text(
                            'Belum dicatat',
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        for (final id in application.documentIds)
                          if (store.documentById(id) case final document?)
                            TextButton(
                              key: ValueKey('detail-document-$id'),
                              onPressed: () => showDocumentPreview(
                                context,
                                store: store,
                                documentId: id,
                              ),
                              child: Text(
                                '${document.title} · ${document.version}',
                              ),
                            )
                          else
                            const Text('Dokumen tidak tersedia'),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Gaji: ${_formatSalary(application.salary)}',
            style: AppTypography.label.copyWith(fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }

  String _formatAppliedDate(DateTime date) {
    const months = [
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
    final day = date.day.toString().padLeft(2, '0');
    return '$day ${months[date.month - 1]} ${date.year}';
  }

  String _formatSalary(int? salary) {
    if (salary == null) return 'Belum dicatat';
    final digits = salary.toString();
    final amount = digits.replaceAllMapped(
      RegExp(r'(\d)(?=(?:\d{3})+$)'),
      (match) => '${match[1]}.',
    );
    return 'Rp$amount / bulan';
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.label.copyWith(fontWeight: FontWeight.w400),
        ),
        Text(
          value,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _RelatedAgenda extends StatelessWidget {
  const _RelatedAgenda({
    required this.agenda,
    required this.upcoming,
    required this.onOpen,
    this.onAdd,
  });

  final Agenda? agenda;
  final bool upcoming;
  final VoidCallback onOpen;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final item = agenda;
    final foreground = item == null
        ? AppColors.gray
        : item.type == AgendaType.interview
        ? RecruitmentStatus.interview.foreground
        : RecruitmentStatus.test.foreground;
    final background = item == null
        ? RecruitmentStatus.applied.background
        : item.type == AgendaType.interview
        ? RecruitmentStatus.interview.background
        : AppColors.peachTint;

    return _DetailCard(
      color: background,
      onTap: item == null ? null : onOpen,
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item == null || upcoming
                      ? 'Agenda berikutnya'
                      : 'Agenda Terkait',
                  style: AppTypography.label.copyWith(color: foreground),
                ),
                if (item == null && onAdd != null)
                  TextButton(
                    onPressed: onAdd,
                    child: const Text('Tambah Agenda'),
                  ),
                Text(
                  item?.type.label ?? 'Belum ada agenda',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  item == null
                      ? 'Agenda tes atau wawancara akan tampil di sini.'
                      : '${AppDates.formatWib(item.scheduledAt)} · ${item.locationOrLink}',
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (item != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right_rounded, color: foreground),
          ],
        ],
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.history, required this.currentStatus});

  final List<StatusHistory> history;
  final RecruitmentStatus currentStatus;

  @override
  Widget build(BuildContext context) => _DetailCard(
    minHeight: 176,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.history_rounded,
          title: 'Riwayat Status',
        ),
        const SizedBox(height: AppSpacing.xs),
        if (history.isEmpty)
          const Text('Belum ada riwayat status.', style: AppTypography.label),
        for (final (index, entry) in history.indexed)
          _TimelineEntry(
            entry: entry,
            first: index == 0,
            last: index == history.length - 1,
            current:
                index == history.length - 1 && entry.status == currentStatus,
          ),
      ],
    ),
  );
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.entry,
    required this.first,
    required this.last,
    required this.current,
  });

  final StatusHistory entry;
  final bool first;
  final bool last;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final foreground = current ? entry.status.foreground : AppColors.gray;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: first ? 13 : 0,
                  bottom: last ? null : 0,
                  height: last ? (first ? 0 : 13) : null,
                  width: 1,
                  child: const ColoredBox(color: AppColors.border),
                ),
                Positioned(
                  top: 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: foreground,
                      border: Border.all(color: AppColors.white),
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 10),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Text.rich(
                    TextSpan(
                      text: '${entry.status.label}\n',
                      style: AppTypography.label.copyWith(
                        color: current ? foreground : AppColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                      children: [
                        TextSpan(
                          text: AppDates.formatWib(entry.changedAt),
                          style: AppTypography.label.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (current)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: entry.status.background,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: Text(
                          'Saat ini',
                          style: AppTypography.label.copyWith(
                            color: foreground,
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
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: AppColors.primary),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          title,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.child,
    this.color = AppColors.white,
    this.onTap,
    this.minHeight = 0,
  });

  final Widget child;
  final Color color;
  final VoidCallback? onTap;
  final double minHeight;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: minHeight),
    child: Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: child,
        ),
      ),
    ),
  );
}

class _DottedStatusChip extends StatelessWidget {
  const _DottedStatusChip({required this.status, this.chipKey});

  final RecruitmentStatus status;
  final Key? chipKey;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: status.background,
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Stack(
      alignment: Alignment.centerLeft,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 7),
          child: StatusChip(key: chipKey, status: status),
        ),
        Positioned(
          left: 9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: status.foreground,
              shape: BoxShape.circle,
            ),
            child: const SizedBox.square(dimension: 5),
          ),
        ),
      ],
    ),
  );
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({required this.onChangeStatus, required this.onDelete});

  final VoidCallback? onChangeStatus;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.white,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          20,
          AppSpacing.sm,
          20,
          AppSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: onChangeStatus,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: const Text('Ubah Status'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: RecruitmentStatus.rejected.foreground,
              ),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Hapus Lamaran'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusSheet extends StatefulWidget {
  const _StatusSheet({required this.application, required this.initialStatus});

  final Application application;
  final RecruitmentStatus initialStatus;

  @override
  State<_StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<_StatusSheet> {
  late RecruitmentStatus _selected = widget.initialStatus;

  static const _descriptions = {
    RecruitmentStatus.applied: 'Sudah dikirim, belum ada respons',
    RecruitmentStatus.screening: 'Berkas ditinjau recruiter',
    RecruitmentStatus.test: 'Tes psikotes atau tes teknis',
    RecruitmentStatus.interview: 'Wawancara HR atau user',
    RecruitmentStatus.offering: 'Menerima penawaran kerja',
    RecruitmentStatus.rejected: 'Tidak lolos di tahap mana pun',
  };

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(20, AppSpacing.xs, 20, AppSpacing.md),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: const SizedBox(width: 32, height: 4),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ubah Status Lamaran',
                    style: AppTypography.section,
                  ),
                  Text(widget.application.company, style: AppTypography.label),
                ],
              ),
            ),
            IconButton.outlined(
              tooltip: 'Tutup',
              onPressed: () {
                if (ModalRoute.of(context)?.isCurrent == true) {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Flexible(
          child: RadioGroup<RecruitmentStatus>(
            groupValue: _selected,
            onChanged: (status) {
              if (status != null) setState(() => _selected = status);
            },
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final status in RecruitmentStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Material(
                      clipBehavior: Clip.antiAlias,
                      color: status == _selected
                          ? AppColors.primaryLight
                          : AppColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                        side: BorderSide(
                          color: status == _selected
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                      child: RadioListTile<RecruitmentStatus>(
                        key: ValueKey('status-option-${status.name}'),
                        value: status,
                        minTileHeight: 48,
                        minVerticalPadding: 6,
                        horizontalTitleGap: AppSpacing.xs,
                        controlAffinity: ListTileControlAffinity.trailing,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        title: LayoutBuilder(
                          builder: (context, constraints) {
                            final badge = _DottedStatusChip(status: status);
                            final description = Text(
                              _descriptions[status]!,
                              style: AppTypography.label.copyWith(
                                fontWeight: FontWeight.w400,
                              ),
                            );
                            if (constraints.maxWidth < 175 ||
                                MediaQuery.textScalerOf(context).scale(12) >
                                    16) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [badge, description],
                              );
                            }
                            return Row(
                              children: [
                                badge,
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(child: description),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                const Text(
                  'Rejected bisa dipilih dari tahap mana pun. '
                  'Offering menandai tawaran kerja.',
                  style: AppTypography.label,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: () {
            if (ModalRoute.of(context)?.isCurrent == true) {
              Navigator.pop(context, _selected);
            }
          },
          child: const Text('Simpan Status'),
        ),
      ],
    ),
  );
}
