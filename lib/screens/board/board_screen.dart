import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_tokens.dart';
import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_repository.dart';
import '../../data/jobtrail_store.dart';
import '../../models/agenda.dart';
import '../../models/application.dart';
import '../../models/recruitment_status.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';

part 'board_sheets.dart';

/// S02 Application Board (Figma node 173:1792, PIC Hanif).
/// Reads the shared store only; filter/search/sort are view state, not data.
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.store,
    required this.navigation,
    this.savedApplicationId,
  });
  final JobTrailStore store;
  final AppNavigation navigation;
  final String? savedApplicationId;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

enum BoardSort {
  newest('Terbaru', 'Terbaru dilamar'),
  oldest('Terlama', 'Terlama dilamar'),
  company('A–Z', 'Nama perusahaan A–Z');

  const BoardSort(this.label, this.sheetLabel);
  final String label;
  final String sheetLabel;
}

class _BoardScreenState extends State<BoardScreen> {
  final _searchController = TextEditingController();
  RecruitmentStatus? _statusFilter;
  BoardSort _sort = BoardSort.newest;
  Set<String> _sources = const {};

  @override
  void didUpdateWidget(covariant BoardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final savedId = widget.savedApplicationId;
    if (savedId == null || savedId == oldWidget.savedApplicationId) return;
    final saved = widget.store.applicationById(savedId);
    if (saved == null) return;

    if (!_matchesSearch(saved, _query.toLowerCase())) _searchController.clear();
    if (!_matchesStatus(saved)) _statusFilter = null;
    if (!_matchesSource(saved)) _sources = {..._sources, saved.source};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim();

  bool _matchesSearch(Application app, String query) =>
      query.isEmpty ||
      app.company.toLowerCase().contains(query) ||
      app.position.toLowerCase().contains(query);

  bool _matchesStatus(Application app) =>
      _statusFilter == null || app.status == _statusFilter;

  bool _matchesSource(Application app) =>
      _sources.isEmpty || _sources.contains(app.source);

  List<Application> _visible(List<Application> all) {
    final query = _query.toLowerCase();
    final items = all
        .where(
          (app) =>
              _matchesStatus(app) &&
              _matchesSource(app) &&
              _matchesSearch(app, query),
        )
        .toList();
    int byCompany(Application a, Application b) =>
        a.company.toLowerCase().compareTo(b.company.toLowerCase());
    items.sort((a, b) {
      final order = switch (_sort) {
        BoardSort.newest => b.appliedAt.compareTo(a.appliedAt),
        BoardSort.oldest => a.appliedAt.compareTo(b.appliedAt),
        BoardSort.company => byCompany(a, b),
      };
      return order != 0 ? order : byCompany(a, b);
    });
    return items;
  }

  /// Distinct sources from shared data, so every chip can match something.
  List<String> get _availableSources => {
    for (final app in widget.store.applications) app.source,
    ..._sources,
  }.toList()..sort();

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_BoardFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        initial: _BoardFilter(sort: _sort, sources: _sources),
        sources: _availableSources,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _sort = result.sort;
      _sources = result.sources;
    });
  }

  Future<void> _openPreview(String applicationId) async {
    final openDetail = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _PreviewSheet(store: widget.store, applicationId: applicationId),
    );
    if (openDetail == true && mounted) {
      await widget.navigation.openDetail(applicationId);
    }
  }

  void _resetSearch() {
    _searchController.clear();
    setState(() {
      _statusFilter = null;
      _sources = const {};
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final all = widget.store.applications;
      final counts = widget.store.distribution();
      final visible = _visible(all);
      return ListView(
        key: const ValueKey('S02'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, AppSpacing.xl),
        children: [
          _Header(
            onAdd: widget.store.allowsLocalWrites
                ? widget.navigation.openAdd
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          _SearchRow(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            onClear: () => setState(_searchController.clear),
            onFilter: _openFilterSheet,
            filterActive: _sources.isNotEmpty || _sort != BoardSort.newest,
          ),
          const SizedBox(height: 6),
          _StatusPills(
            selected: _statusFilter,
            total: all.length,
            counts: counts,
            onSelected: (status) => setState(() => _statusFilter = status),
          ),
          const SizedBox(height: 8),
          _SummaryCard(
            total: all.length,
            counts: counts,
            sort: _sort,
            onSort: (sort) => setState(() => _sort = sort),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_query.isNotEmpty) ...[
            Text(
              '${visible.length} hasil untuk "$_query"',
              key: const ValueKey('board-result-count'),
              style: _jakarta(12, FontWeight.w400, AppColors.gray),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (all.isEmpty)
            const EmptyState(message: 'Belum ada lamaran.')
          else if (visible.isEmpty)
            _NoMatch(onReset: _resetSearch)
          else
            for (final app in visible) ...[
              _BoardApplicationCard(
                key: ValueKey('application-${app.id}'),
                application: app,
                agenda: _highlightAgenda(
                  widget.store.agendasFor(app.id),
                  widget.store.referenceInstantUtc,
                ),
                onTap: () => _openPreview(app.id),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      );
    },
  );
}

/// Whether [agenda] is at or after the reference instant (same day counts
/// only when its time has not passed yet).
bool _isUpcoming(Agenda agenda, DateTime now) =>
    !agenda.scheduledAt.isBefore(now);

/// Next agenda at/after [now]; otherwise the most recent past one.
/// [agendas] must be sorted ascending (JobTrailStore.agendasFor does this).
Agenda? _highlightAgenda(List<Agenda> agendas, DateTime now) {
  if (agendas.isEmpty) return null;
  for (final agenda in agendas) {
    if (_isUpcoming(agenda, now)) return agenda;
  }
  return agendas.last;
}

/// Keeps the Figma visual size while guaranteeing a 48x48 hit area, matching
/// the project's button theme minimum (JT-BUG-003).
class _HitArea extends StatelessWidget {
  const _HitArea({super.key, required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: kMinInteractiveDimension,
        minHeight: kMinInteractiveDimension,
      ),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    ),
  );
}

DateTime _wib(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 7));

const _months = [
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

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} ${_months[date.month - 1]} ${date.year}';

String _formatAgenda(Agenda agenda) {
  final civil = _wib(agenda.scheduledAt);
  final time =
      '${civil.hour.toString().padLeft(2, '0')}.${civil.minute.toString().padLeft(2, '0')}';
  return '${agenda.type.label} · ${civil.day} ${_months[civil.month - 1]}, '
      '$time WIB · ${agenda.locationOrLink}';
}

TextStyle _jakarta(double size, FontWeight weight, Color color) => TextStyle(
  fontFamily: AppTypography.bodyFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
);

/// Placeholder text color from Figma search field (not a GSM token).
const _placeholderColor = Color(0xFF7A8199);

/// Distribution bar/legend colors per Figma 173:1869. Test/Psikotes uses a
/// distinct orange in the bar only, so it is distinguishable from Screening.
Color _barColor(RecruitmentStatus status) => status == RecruitmentStatus.test
    ? const Color(0xFFC2410C)
    : status.foreground;

class _Header extends StatelessWidget {
  const _Header({required this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const _Logo(),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Board Lamaran',
              style: _jakarta(20, FontWeight.w800, AppColors.navy),
            ),
            const SizedBox(height: 2),
            Text(
              'Pantau status setiap lamaranmu',
              style: _jakarta(12, FontWeight.w400, AppColors.gray),
            ),
          ],
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Tooltip(
        message: 'Tambah Lamaran',
        child: Material(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: InkWell(
            key: const ValueKey('board-add'),
            borderRadius: BorderRadius.circular(AppRadius.button),
            onTap: onAdd,
            child: const SizedBox(
              width: kMinInteractiveDimension,
              height: kMinInteractiveDimension,
              child: Icon(Icons.add, color: AppColors.white, size: 22),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Same official logo assets and composition as S01 Home.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'JobTrail',
    image: true,
    child: SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/home/logo-background.png'),
          ),
          Positioned(
            left: 20.3,
            top: 8.3,
            width: 6.4,
            height: 6.4,
            child: Image.asset('assets/home/logo-dot.png'),
          ),
          Positioned(
            left: 13,
            top: 16,
            width: 12,
            height: 17,
            child: Image.asset('assets/home/logo-letter.png'),
          ),
        ],
      ),
    ),
  );
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onFilter,
    required this.filterActive,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilter;
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('board-search'),
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: _jakarta(13, FontWeight.w400, AppColors.navy),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.white,
              hintText: 'Cari perusahaan atau posisi...',
              hintStyle: _jakarta(13, FontWeight.w400, _placeholderColor),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: AppColors.gray,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 39,
                minHeight: 44,
              ),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('board-search-clear'),
                      tooltip: 'Hapus pencarian',
                      onPressed: onClear,
                      icon: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: AppColors.border,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Tooltip(
          message: 'Filter & Urutkan',
          child: Material(
            color: filterActive ? AppColors.primaryLight : AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
              side: BorderSide(
                color: filterActive ? AppColors.primary : AppColors.border,
              ),
            ),
            child: InkWell(
              key: const ValueKey('board-filter'),
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: onFilter,
              child: const SizedBox(
                width: kMinInteractiveDimension,
                height: kMinInteractiveDimension,
                child: Icon(Icons.tune, size: 20, color: AppColors.navy),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPills extends StatelessWidget {
  const _StatusPills({
    required this.selected,
    required this.total,
    required this.counts,
    required this.onSelected,
  });
  final RecruitmentStatus? selected;
  final int total;
  final Map<RecruitmentStatus, int> counts;
  final ValueChanged<RecruitmentStatus?> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _HitArea(
          key: const ValueKey('board-pill-all'),
          onTap: () => onSelected(null),
          child: _Pill(
            label: 'Semua',
            count: total,
            active: selected == null,
            onTap: () => onSelected(null),
          ),
        ),
        for (final status in RecruitmentStatus.values) ...[
          const SizedBox(width: AppSpacing.xs),
          _HitArea(
            key: ValueKey('board-pill-${status.name}'),
            onTap: () => onSelected(status),
            child: _Pill(
              label: status.label,
              count: counts[status] ?? 0,
              active: selected == status,
              onTap: () => onSelected(status),
            ),
          ),
        ],
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? AppColors.white : AppColors.navy;
    return Semantics(
      selected: active,
      button: true,
      child: Material(
        color: active ? AppColors.primary : AppColors.white,
        shape: StadiumBorder(
          side: BorderSide(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: _jakarta(13, FontWeight.w700, foreground)),
                  const SizedBox(width: 6),
                  Opacity(
                    opacity: 0.8,
                    child: Text(
                      '$count',
                      style: _jakarta(13, FontWeight.w600, foreground),
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
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.counts,
    required this.sort,
    required this.onSort,
  });
  final int total;
  final Map<RecruitmentStatus, int> counts;
  final BoardSort sort;
  final ValueChanged<BoardSort> onSort;

  int _count(RecruitmentStatus status) => counts[status] ?? 0;

  @override
  Widget build(BuildContext context) {
    // Definisi sementara (perlu konfirmasi Ziyaad): menunggu respons = Applied;
    // sedang diproses = Screening + Test/Psikotes + Interview.
    final inProcess =
        _count(RecruitmentStatus.screening) +
        _count(RecruitmentStatus.test) +
        _count(RecruitmentStatus.interview);
    final waiting = _count(RecruitmentStatus.applied);
    return Container(
      key: const ValueKey('board-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.work_outline,
                  size: 20,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$total lamaran tercatat',
                      key: const ValueKey('board-total'),
                      style: _jakarta(15, FontWeight.w800, AppColors.navy),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$inProcess sedang diproses · $waiting menunggu respons',
                      style: _jakarta(12, FontWeight.w400, AppColors.gray),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              PopupMenuButton<BoardSort>(
                key: const ValueKey('board-sort'),
                tooltip: 'Urutkan',
                initialValue: sort,
                onSelected: onSort,
                itemBuilder: (_) => [
                  for (final option in BoardSort.values)
                    PopupMenuItem(value: option, child: Text(option.label)),
                ],
                child: SizedBox(
                  height: kMinInteractiveDimension,
                  child: Center(
                    widthFactor: 1,
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 36,
                        maxWidth: 120,
                      ),
                      padding: const EdgeInsets.only(left: 12, right: 10),
                      decoration: const ShapeDecoration(
                        color: AppColors.white,
                        shape: StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              sort.label,
                              overflow: TextOverflow.ellipsis,
                              style: _jakarta(
                                12,
                                FontWeight.w700,
                                AppColors.primaryDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            size: 14,
                            color: AppColors.primaryDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _DistributionBar(counts: counts, total: total),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 4,
            children: [
              for (final status in RecruitmentStatus.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _barColor(status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${status.label} ${_count(status)}',
                        style: _jakarta(11, FontWeight.w600, AppColors.navy),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({required this.counts, required this.total});
  final Map<RecruitmentStatus, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final segments = [
      for (final status in RecruitmentStatus.values)
        if ((counts[status] ?? 0) > 0) status,
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Container(
        height: 10,
        color: AppColors.white,
        child: total == 0
            ? null
            : Row(
                children: [
                  for (var i = 0; i < segments.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: counts[segments[i]]!,
                      child: ColoredBox(
                        color: _barColor(segments[i]),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _BoardApplicationCard extends StatelessWidget {
  const _BoardApplicationCard({
    super.key,
    required this.application,
    required this.agenda,
    required this.onTap,
  });
  final Application application;
  final Agenda? agenda;
  final VoidCallback onTap;

  String get _initials {
    final words = application.company
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2);
    return words.map((word) => word[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      side: const BorderSide(color: AppColors.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AdaptiveCardRow(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _initials,
                    style: _jakarta(13, FontWeight.w800, AppColors.primaryDark),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        application.company,
                        style: _jakarta(15, FontWeight.w700, AppColors.navy),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${application.location} · ${application.workType.label}',
                        style: _jakarta(12, FontWeight.w400, AppColors.gray),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _CardStatusChip(status: application.status),
              ],
            ),
            if (agenda != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        _formatAgenda(agenda!),
                        style: _jakarta(12, FontWeight.w600, AppColors.navy),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            const SizedBox(height: AppSpacing.sm),
            _AdaptiveCardRow(
              children: [
                Expanded(
                  child: Text(
                    application.position,
                    style: _jakarta(13, FontWeight.w700, AppColors.navy),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  _formatDate(application.appliedAt),
                  style: _jakarta(12, FontWeight.w400, AppColors.gray),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Card-sized chip per Figma StatusChip (172:1810); colors from shared GSM
/// extension. Propose upstreaming this variant to the shared StatusChip.
class _CardStatusChip extends StatelessWidget {
  const _CardStatusChip({required this.status});
  final RecruitmentStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: ShapeDecoration(
      color: status.background,
      shape: const StadiumBorder(),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: status.foreground,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            status.label,
            style: _jakarta(11, FontWeight.w700, status.foreground),
          ),
        ),
      ],
    ),
  );
}

// Preserve compact cards at normal text sizes; stack constrained content.
class _AdaptiveCardRow extends StatelessWidget {
  const _AdaptiveCardRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (MediaQuery.textScalerOf(context).scale(12) <= 16) {
        return Row(children: children);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final child in children) child is Expanded ? child.child : child,
        ],
      );
    },
  );
}
