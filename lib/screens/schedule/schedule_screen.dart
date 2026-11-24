import 'package:flutter/material.dart';

import '../../core/constants/app_dates.dart';
import '../../core/constants/app_tokens.dart';
import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_store.dart';
import '../../models/agenda.dart';
import 'add_agenda_sheet.dart';
import 'schedule_agenda_card.dart';
import 'schedule_format.dart';

TextStyle _text(
  double size, {
  Color color = AppColors.navy,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: AppTypography.bodyFamily,
  fontSize: size,
  color: color,
  fontWeight: weight,
);

/// S05 Interview Schedule (Figma `270:3817`, states `333:4879`, `333:4578`).
/// Reads agendas from the shared store; "today" is `store.referenceDate`.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.store,
    required this.navigation,
  });
  final JobTrailStore store;
  final AppNavigation navigation;
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  int _weekOffset = 0;
  DateTime? _selectedDate;
  AgendaType? _normalType;
  AgendaType? _relatedType;

  AgendaType? get _type => widget.navigation.scheduleApplicationId == null
      ? _normalType
      : _relatedType;
  set _type(AgendaType? value) {
    if (widget.navigation.scheduleApplicationId == null) {
      _normalType = value;
    } else {
      _relatedType = value;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.navigation.addListener(_onNavigation);
  }

  void _onNavigation() {
    if (widget.navigation.selectedTab == AppTab.schedule &&
        widget.navigation.scheduleApplicationId != null) {
      _relatedType = null;
    }
  }

  @override
  void dispose() {
    widget.navigation.removeListener(_onNavigation);
    super.dispose();
  }

  JobTrailStore get store => widget.store;

  /// Opens the add sheet prefilled with the selected date (week view) or the
  /// related application (Agenda Terkait view), then focuses the new agenda.
  Future<void> _openAddSheet() async {
    final appFilter = widget.navigation.scheduleApplicationId;
    final messenger = ScaffoldMessenger.of(context);
    final id = await showAddAgendaSheet(
      context,
      store: store,
      initialDate: appFilter == null ? _selectedDate : null,
      initialApplicationId: appFilter,
    );
    if (!mounted || id == null) return;
    final agenda = store.agendas.where((a) => a.id == id).firstOrNull;
    if (agenda == null) return;
    final date = _dateOf(agenda);
    final stayRelated = appFilter == agenda.applicationId;
    if (appFilter != null && !stayRelated) {
      widget.navigation.showTab(AppTab.schedule);
    }
    setState(() {
      _weekOffset =
          ScheduleFormat.weekStartSunday(date)
              .difference(ScheduleFormat.weekStartSunday(store.referenceDate))
              .inDays ~/
          7;
      _selectedDate = stayRelated ? null : date;
      _type = null;
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('schedule-saved-snackbar'),
          content: Text(
            'Agenda tersimpan: ${ScheduleFormat.shortDayMonth(date)}, '
            '${ScheduleFormat.timeWib(agenda.scheduledAt)} WIB',
          ),
        ),
      );
  }

  void _shiftWeek(int delta) => setState(() {
    _weekOffset += delta;
    _selectedDate = null;
  });

  void _toggleDate(DateTime date) =>
      setState(() => _selectedDate = _selectedDate == date ? null : date);

  void _selectType(AgendaType? type) => setState(() {
    _type = type;
    // Figma: "ketuk Semua untuk melihat agenda minggu ini".
    if (type == null) _selectedDate = null;
  });

  static DateTime _dateOf(Agenda agenda) =>
      AppDates.wibDate(agenda.scheduledAt);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, widget.navigation]),
    builder: (context, _) {
      final today = store.referenceDate;
      final weekStart = ScheduleFormat.addDays(
        ScheduleFormat.weekStartSunday(today),
        7 * _weekOffset,
      );
      final weekEnd = ScheduleFormat.addDays(weekStart, 7);
      final days = [
        for (var i = 0; i < 7; i++) ScheduleFormat.addDays(weekStart, i),
      ];

      final appFilter = widget.navigation.scheduleApplicationId;
      final filterApp = appFilter == null
          ? null
          : store.applicationById(appFilter);
      final scoped =
          (appFilter == null ? store.agendas : store.agendasFor(appFilter))
              .where((a) => store.applicationById(a.applicationId) != null)
              .toList()
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      final inWeek = scoped.where((a) {
        final date = _dateOf(a);
        return !date.isBefore(weekStart) && date.isBefore(weekEnd);
      }).toList();
      // Related-application view lists every agenda of that application.
      final base = appFilter == null ? inWeek : scoped;
      // Day selection only applies to the week view.
      final selected = appFilter == null ? _selectedDate : null;
      final dayFiltered = selected == null
          ? base
          : base.where((a) => _dateOf(a) == selected).toList();
      final visible = _type == null
          ? dayFiltered
          : dayFiltered.where((a) => a.type == _type).toList();

      return ListView(
        key: const ValueKey('S05'),
        // Horizontal page inset is applied per child so the week strip can
        // bleed into it on narrow screens (44 px cells, JT-BUG-007).
        padding: const EdgeInsets.fromLTRB(0, 8, 0, AppSpacing.xl),
        children: [
          _inset(_titleRow()),
          const SizedBox(height: AppSpacing.md),
          if (appFilter != null)
            // Related-application view (from S03 "Agenda Terkait").
            _inset(_relatedBanner(filterApp?.company ?? 'lamaran ini'))
          else ...[
            _inset(_monthRow(weekStart, weekEnd, today)),
            const SizedBox(height: AppSpacing.md),
            _weekStrip(days, today, base),
            const SizedBox(height: AppSpacing.md),
            _inset(_summary(today, scoped, base, dayFiltered)),
          ],
          const SizedBox(height: AppSpacing.md),
          _inset(_typeFilter(base)),
          const SizedBox(height: AppSpacing.md),
          for (final child
              in visible.isEmpty
                  ? _emptyGroup(selected)
                  : _groups(visible, today))
            _inset(child),
          _inset(_planningNote()),
        ],
      );
    },
  );

  static const _pageInset = 20.0;
  static const _minTarget = 44.0;

  static Widget _inset(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _pageInset),
    child: child,
  );

  Widget _titleRow() => Row(
    children: [
      // Same official logo assets as S01 Home (no shared logo widget yet).
      Semantics(
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
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Jadwal Seleksi', style: _text(20, weight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              'Agenda tes & interview lamaranmu',
              style: _text(12, color: AppColors.gray),
            ),
          ],
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Tooltip(
        message: 'Tambah agenda',
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: 'Tambah agenda',
          child: Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.button),
            child: InkWell(
              key: const ValueKey('schedule-add'),
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: widget.store.allowsLocalWrites ? _openAddSheet : null,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.add, color: AppColors.white, size: 22),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _monthRow(DateTime weekStart, DateTime weekEnd, DateTime today) {
    // JT-BUG-012: stop at the week that contains a supported-range bound.
    final canGoBack = weekStart.isAfter(ScheduleFormat.firstDate);
    // weekEnd is exclusive, so the last visible day is weekEnd - 1.
    final canGoForward = !weekEnd.isAfter(ScheduleFormat.lastDate);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Month of the week's midpoint, so cross-month weeks read well.
                ScheduleFormat.monthYear(ScheduleFormat.addDays(weekStart, 3)),
                style: _text(16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'Hari ini · ${ScheduleFormat.longDate(today)}',
                key: const ValueKey('schedule-today'),
                style: _text(12, color: AppColors.gray),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _weekButton(
          key: const ValueKey('schedule-week-prev'),
          tooltip: 'Minggu sebelumnya',
          icon: Icons.chevron_left,
          onTap: canGoBack ? () => _shiftWeek(-1) : null,
        ),
        _weekButton(
          key: const ValueKey('schedule-week-next'),
          tooltip: 'Minggu berikutnya',
          icon: Icons.chevron_right,
          onTap: canGoForward ? () => _shiftWeek(1) : null,
        ),
      ],
    );
  }

  Widget _weekButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onTap,
  }) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      child: InkResponse(
        key: key,
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                icon,
                size: 18,
                color: onTap == null ? AppColors.border : AppColors.navy,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// Seven equal slots; each whole slot (incl. the 3 px visual gap) is the
  /// tap target. On narrow screens the strip eats into the page inset so a
  /// slot never drops below 44 px (320 → 6 px inset, 393 → 20 px as Figma).
  Widget _weekStrip(List<DateTime> days, DateTime today, List<Agenda> base) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final inset = ((constraints.maxWidth - 7 * _minTarget) / 2).clamp(
            0.0,
            _pageInset - 3,
          );
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final day in days)
                  Expanded(
                    child: _dayChip(
                      day,
                      isToday: day == today,
                      isSelected: day == _selectedDate,
                      enabled: ScheduleFormat.isInRange(day),
                      agendas: base.where((a) => _dateOf(a) == day).toList(),
                    ),
                  ),
              ],
            ),
          );
        },
      );

  Widget _dayChip(
    DateTime day, {
    required bool isToday,
    required bool isSelected,
    required bool enabled,
    required List<Agenda> agendas,
  }) {
    final Color background;
    final Color border;
    final Color labelColor;
    final Color dateColor;
    if (isSelected) {
      background = AppColors.primary;
      border = AppColors.primary;
      labelColor = AppColors.white;
      dateColor = AppColors.white;
    } else if (isToday) {
      background = AppColors.primaryLight;
      border = AppColors.primary;
      labelColor = AppColors.primaryDark;
      dateColor = AppColors.primaryDark;
    } else if (!enabled) {
      // Outside the supported range (JT-BUG-012): visible but inert.
      background = AppColors.background;
      border = AppColors.border;
      labelColor = AppColors.border;
      dateColor = AppColors.border;
    } else {
      background = AppColors.white;
      border = AppColors.border;
      labelColor = AppColors.gray;
      dateColor = AppColors.navy;
    }
    final dots = <Color>[
      for (final a in agendas.take(3))
        isSelected
            ? AppColors.white
            : ScheduleAgendaCard.typeForeground(a.type),
      if (agendas.isEmpty && isToday)
        isSelected ? AppColors.white : AppColors.primary,
    ];
    final label = [
      ScheduleFormat.dayMonthLong(day),
      if (isToday) 'hari ini',
      '${agendas.length} agenda',
      if (isSelected) 'terpilih',
      if (!enabled) 'di luar rentang',
    ].join(', ');
    final onTap = enabled ? () => _toggleDate(day) : null;
    final radius = BorderRadius.circular(AppRadius.button);
    return Semantics(
      selected: isSelected,
      label: label,
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: ValueKey('schedule-day-${day.toIso8601String().substring(0, 10)}'),
        onTap: onTap,
        borderRadius: radius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _minTarget,
            minHeight: _minTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Ink(
              decoration: BoxDecoration(
                color: background,
                borderRadius: radius,
                border: Border.all(color: border, width: isToday ? 1.5 : 1),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        ScheduleFormat.dayShort(day),
                        style: _text(
                          10,
                          color: labelColor,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${day.day}',
                        style: _text(
                          16,
                          color: dateColor,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 6,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final (i, color) in dots.indexed) ...[
                            if (i > 0) const SizedBox(width: 3),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _relatedBanner(String company) => Row(
    children: [
      Expanded(
        child: Text(
          'Agenda untuk $company',
          style: _text(12, color: AppColors.gray, weight: FontWeight.w600),
        ),
      ),
      TextButton(
        onPressed: () => widget.navigation.showTab(AppTab.schedule),
        child: const Text('Tampilkan semua agenda'),
      ),
    ],
  );

  Widget _summary(
    DateTime today,
    List<Agenda> scoped,
    List<Agenda> base,
    List<Agenda> dayFiltered,
  ) {
    final String title;
    final String detail;
    if (_selectedDate != null && dayFiltered.isEmpty) {
      title =
          'Tidak ada agenda pada ${ScheduleFormat.longDayMonth(_selectedDate!)}';
      detail =
          'Pilih tanggal lain atau ketuk "Semua" untuk melihat '
          '${base.length} agenda minggu ini.';
    } else {
      final horizon = ScheduleFormat.addDays(today, 7);
      final upcoming = scoped.where((a) {
        final date = _dateOf(a);
        return !a.scheduledAt.isBefore(store.referenceInstantUtc) &&
            date.isBefore(horizon);
      }).toList();
      final interviews = upcoming
          .where((a) => a.type == AgendaType.interview)
          .length;
      final tests = upcoming.length - interviews;
      title = '${upcoming.length} agenda dalam 7 hari ke depan';
      final parts = ['$interviews interview', '$tests test/psikotes'];
      if (upcoming.isNotEmpty) {
        final next = upcoming.first;
        parts.add(
          'terdekat ${ScheduleFormat.relativeDay(_dateOf(next), today)} '
          '${ScheduleFormat.timeWib(next.scheduledAt)} WIB',
        );
      }
      detail = parts.join(' · ');
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const ValueKey('schedule-summary-title'),
                  style: _text(14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  key: const ValueKey('schedule-summary-detail'),
                  style: _text(12, color: AppColors.gray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeFilter(List<Agenda> base) {
    final interviews = base.where((a) => a.type == AgendaType.interview).length;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        _pill(
          'all',
          'Semua',
          base.length,
          _type == null,
          () => _selectType(null),
        ),
        _pill(
          'interview',
          AgendaType.interview.label,
          interviews,
          _type == AgendaType.interview,
          () => _selectType(AgendaType.interview),
        ),
        _pill(
          'test',
          AgendaType.test.label,
          base.length - interviews,
          _type == AgendaType.test,
          () => _selectType(AgendaType.test),
        ),
      ],
    );
  }

  Widget _pill(
    String id,
    String label,
    int count,
    bool active,
    VoidCallback onTap,
  ) {
    final color = active ? AppColors.white : AppColors.navy;
    return Semantics(
      selected: active,
      child: Material(
        color: active ? AppColors.primary : AppColors.white,
        shape: StadiumBorder(
          side: BorderSide(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('schedule-filter-$id'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: _text(13, color: color, weight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Opacity(
                    opacity: 0.8,
                    child: Text(
                      '$count',
                      style: _text(13, color: color, weight: FontWeight.w600),
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

  Widget _groupHeader(DateTime date, DateTime today) {
    final diff = date.difference(today).inDays;
    final isPast = diff < 0;
    final badge = isPast
        ? 'Lewat'
        : diff == 0
        ? 'Hari ini'
        : diff == 1
        ? 'Besok'
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            ScheduleFormat.groupHeader(date),
            style: _text(12, color: AppColors.gray, weight: FontWeight.w700),
          ),
          if (badge != null)
            Container(
              key: isPast
                  ? ValueKey(
                      'schedule-past-badge-${date.toIso8601String().substring(0, 10)}',
                    )
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isPast ? AppColors.border : AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                badge,
                style: _text(
                  10,
                  color: isPast ? AppColors.gray : AppColors.primaryDark,
                  weight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _groups(List<Agenda> visible, DateTime today) {
    final grouped = <DateTime, List<Agenda>>{};
    for (final agenda in visible) {
      grouped.putIfAbsent(_dateOf(agenda), () => []).add(agenda);
    }
    return [
      for (final entry in grouped.entries) ...[
        _groupHeader(entry.key, today),
        for (final agenda in entry.value) ...[
          ScheduleAgendaCard(
            agenda: agenda,
            application: store.applicationById(agenda.applicationId)!,
            onTap: () => widget.navigation.openDetail(agenda.applicationId),
            isPast: agenda.scheduledAt.isBefore(store.referenceInstantUtc),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
      ],
    ];
  }

  List<Widget> _emptyGroup(DateTime? date) {
    return [
      if (date != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            ScheduleFormat.groupHeader(date),
            style: _text(12, color: AppColors.gray, weight: FontWeight.w700),
          ),
        ),
      Container(
        key: const ValueKey('schedule-empty'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.peachTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_today_outlined,
                size: 28,
                color: AppColors.peach,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              date != null
                  ? 'Belum ada agenda di tanggal ini'
                  : 'Belum ada agenda di minggu ini',
              textAlign: TextAlign.center,
              style: _text(15, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Tambahkan jadwal tes atau interview dari lamaran yang sedang '
              'berjalan agar tidak terlewat.',
              textAlign: TextAlign.center,
              style: _text(12, color: AppColors.gray),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              key: const ValueKey('schedule-empty-add'),
              onPressed: widget.store.allowsLocalWrites ? _openAddSheet : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(180, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              child: Text(
                '+ Tambah Agenda',
                style: _text(
                  14,
                  color: AppColors.white,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
    ];
  }

  Widget _planningNote() => CustomPaint(
    painter: _DashedBorderPainter(),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        'Rancangan Week 11: pengingat ditampilkan sebagai rencana. Notifikasi '
        'push dan sinkronisasi kalender direncanakan pada tahap implementasi.',
        style: _text(11, color: AppColors.gray),
      ),
    ),
  );
}

/// Dashed outline for the Planning Note (Figma `270:4083`).
class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadius.button),
    );
    canvas.drawRRect(rrect, Paint()..color = AppColors.white);
    final stroke = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
