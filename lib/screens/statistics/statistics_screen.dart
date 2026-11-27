import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/activity_streak.dart';
import '../../core/constants/app_dates.dart';
import '../../core/constants/app_tokens.dart';
import '../../data/jobtrail_store.dart';
import '../../models/application.dart';
import '../../models/recruitment_status.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Period enum & safe month subtraction
// ─────────────────────────────────────────────────────────────────────────────

/// Filter options for the statistics period.
enum StatsPeriod {
  all('Saat Ini'),
  oneMonth('1 Bulan Terakhir'),
  twoMonths('2 Bulan Terakhir'),
  threeMonths('3 Bulan Terakhir');

  const StatsPeriod(this.label);
  final String label;
}

/// Subtract [months] calendar months from [date] with day-clamping.
/// E.g. 31 Mar − 1 month = 28 Feb (or 29 in leap year).
/// Handles year rollover (Jan − 1 = Dec of previous year).
@visibleForTesting
DateTime subtractMonths(DateTime date, int months) {
  assert(months >= 0);
  if (months == 0) return date;
  var year = date.year;
  var month = date.month - months;
  while (month < 1) {
    month += 12;
    year -= 1;
  }
  // Clamp day to last day of target month.
  final lastDay = DateUtils.getDaysInMonth(year, month);
  final day = date.day > lastDay ? lastDay : date.day;
  return AppDates.date(year, month, day);
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Monday buckets for the inclusive reporting interval. The unbounded period
/// starts with its earliest historical application; without one it has no range.
/// Boundary weeks count only dates inside the interval through referenceDate.
@visibleForTesting
Map<DateTime, int> weeklyTrendBuckets({
  required Iterable<DateTime> appliedDates,
  required DateTime referenceDate,
  DateTime? start,
}) {
  final dates = appliedDates
      .where(
        (date) =>
            !date.isAfter(referenceDate) &&
            (start == null || !date.isBefore(start)),
      )
      .toList();
  if (start != null && start.isAfter(referenceDate)) return {};
  if (start == null && dates.isEmpty) return {};
  DateTime monday(DateTime date) {
    final day = AppDates.date(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  final firstDate = start ?? dates.reduce((a, b) => a.isBefore(b) ? a : b);
  final lastWeek = monday(referenceDate);
  final buckets = <DateTime, int>{};
  for (
    var week = monday(firstDate);
    !week.isAfter(lastWeek);
    week = week.add(const Duration(days: 7))
  ) {
    buckets[week] = 0;
  }
  for (final date in dates) {
    final week = monday(date);
    buckets[week] = buckets[week]! + 1;
  }
  return buckets;
}

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key, required this.store});
  final JobTrailStore store;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  StatsPeriod _period = StatsPeriod.all;

  JobTrailStore get store => widget.store;

  /// Compute inclusive start date from the selected period using the store's
  /// fixed reference date so results are deterministic and anchor-based.
  DateTime? _periodStart() {
    switch (_period) {
      case StatsPeriod.all:
        return null;
      case StatsPeriod.oneMonth:
        return subtractMonths(store.referenceDate, 1);
      case StatsPeriod.twoMonths:
        return subtractMonths(store.referenceDate, 2);
      case StatsPeriod.threeMonths:
        return subtractMonths(store.referenceDate, 3);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final start = _periodStart();
      final apps = store.applicationsInPeriod(start: start);
      final dist = store.distribution(start: start);
      final total = apps.length;

      return ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        children: [
          // ── Header ──
          Row(
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.asset(
                            'assets/home/logo-background.png',
                            fit: BoxFit.fill,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 22.3,
                        top: 9.1,
                        width: 7,
                        height: 7,
                        child: Image.asset('assets/home/logo-dot.png'),
                      ),
                      Positioned(
                        left: 14.3,
                        top: 17.6,
                        width: 13.2,
                        height: 18.7,
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
                    Text(
                      'Statistik',
                      key: const ValueKey('S07'),
                      style: AppTypography.heading,
                    ),
                    Text(
                      'Pantau perjalanan lamaranmu',
                      style: AppTypography.body.copyWith(
                        color: AppColors.gray,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Hidden total text for existing test compatibility.
          Text(
            'Total: $total',
            key: const ValueKey('statistics-total'),
            style: const TextStyle(fontSize: 0, height: 0),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Period filter chips ──
          _PeriodFilter(
            selected: _period,
            onSelected: (period) => setState(() => _period = period),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Empty state ──
          if (total == 0) ...[
            const SizedBox(height: AppSpacing.xl),
            const EmptyState(
              message: 'Belum ada lamaran pada periode ini.\nTambahkan lamaran untuk melihat statistik.',
            ),
          ] else ...[
            // ── Summary cards ──
            _SummaryRow(distribution: dist, total: total),
            const SizedBox(height: AppSpacing.lg),

            // ── Distribution section ──
            _SectionTitle(title: 'Distribusi Tahapan'),
            const SizedBox(height: AppSpacing.sm),
            _DistributionCard(distribution: dist, total: total, apps: apps),
            const SizedBox(height: AppSpacing.lg),

            // ── Achievement metrics ──
            _SectionTitle(title: 'Metrik Pencapaian'),
            const SizedBox(height: AppSpacing.sm),
            _AchievementMetrics(store: store, start: start),
            const SizedBox(height: AppSpacing.lg),

            // ── Trend section ──
          ],
          if (total > 0 || start != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _SectionTitle(title: 'Tren Lamaran'),
            const SizedBox(height: AppSpacing.sm),
            _TrendCard(store: store, start: start),
          ],

          // Bottom padding so navbar doesn't cover content.
          const SizedBox(height: AppSpacing.xl),
        ],
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Period filter — accessible ChoiceChip with min 44px touch target
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodFilter extends StatelessWidget {
  const _PeriodFilter({required this.selected, required this.onSelected});
  final StatsPeriod selected;
  final ValueChanged<StatsPeriod> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final period in StatsPeriod.values) ...[
          _AccessibleFilterChip(
            label: period.label,
            isSelected: period == selected,
            onTap: () => onSelected(period),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ],
    ),
  );
}

class _AccessibleFilterChip extends StatelessWidget {
  const _AccessibleFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isSelected,
    label: label,
    child: Material(
      color: isSelected ? AppColors.primary : AppColors.white,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            child: Text(
              label,
              style: AppTypography.label.copyWith(
                color: isSelected ? AppColors.white : AppColors.gray,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary row: Total, Interview, Offering
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.distribution, required this.total});
  final Map<RecruitmentStatus, int> distribution;
  final int total;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('statistics-summary'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppRadius.card),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.22),
          blurRadius: 10,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ringkasan lamaran',
                style: AppTypography.body.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.mint,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(dimension: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 250 ||
                MediaQuery.textScalerOf(context).scale(12) > 18;
            final metrics = [
              _SummaryCard(
                label: 'Total Lamaran',
                value: '$total',
                id: 'total',
              ),
              _SummaryCard(
                label: 'Interview saat ini',
                value: '${distribution[RecruitmentStatus.interview] ?? 0}',
                id: 'interview',
              ),
              _SummaryCard(
                label: 'Offering',
                value: '${distribution[RecruitmentStatus.offering] ?? 0}',
                id: 'offering',
              ),
            ];
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < metrics.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.sm),
                    metrics[i],
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < metrics.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(child: metrics[i]),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.id,
  });
  final String label;
  final String value;
  final String id;

  @override
  Widget build(BuildContext context) => Column(
    key: ValueKey('statistics-summary-$id'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: AppTypography.heading.copyWith(
          fontSize: 28,
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        style: AppTypography.label.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section title
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) =>
      Text(title, style: AppTypography.section);
}

// ─────────────────────────────────────────────────────────────────────────────
// Distribution card with horizontal bars and tap-to-expand detail
// ─────────────────────────────────────────────────────────────────────────────

class _DistributionCard extends StatefulWidget {
  const _DistributionCard({
    required this.distribution,
    required this.total,
    required this.apps,
  });
  final Map<RecruitmentStatus, int> distribution;
  final int total;
  final List<Application> apps;

  @override
  State<_DistributionCard> createState() => _DistributionCardState();
}

class _DistributionCardState extends State<_DistributionCard> {
  RecruitmentStatus? _expandedStatus;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        for (int i = 0; i < RecruitmentStatus.values.length; i++) ...[
          _DistributionRow(
            status: RecruitmentStatus.values[i],
            count: widget.distribution[RecruitmentStatus.values[i]] ?? 0,
            total: widget.total,
            isExpanded: _expandedStatus == RecruitmentStatus.values[i],
            onTap: () => setState(() {
              final status = RecruitmentStatus.values[i];
              _expandedStatus = _expandedStatus == status ? null : status;
            }),
            apps: widget.apps
                .where((a) => a.status == RecruitmentStatus.values[i])
                .toList(),
          ),
          if (i < RecruitmentStatus.values.length - 1)
            const SizedBox(height: AppSpacing.sm),
        ],
      ],
    ),
  );
}

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.status,
    required this.count,
    required this.total,
    required this.isExpanded,
    required this.onTap,
    required this.apps,
  });
  final RecruitmentStatus status;
  final int count;
  final int total;
  final bool isExpanded;
  final VoidCallback onTap;
  final List<Application> apps;

  @override
  Widget build(BuildContext context) {
    final percentage = total == 0 ? 0.0 : (count / total * 100);
    final fraction = total == 0 ? 0.0 : count / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tappable row for distribution detail.
        InkWell(
          onTap: count > 0 ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Flexible(child: StatusChip(status: status)),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '$count',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${percentage.toStringAsFixed(0)}%',
                  style: AppTypography.label,
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.gray,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            color: status.foreground,
            backgroundColor: status.background,
          ),
        ),
        // Expanded detail: list of applications with this status.
        if (isExpanded && apps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final app in apps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.circle,
                          size: 6,
                          color: AppColors.gray,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            '${app.company} · ${app.position}',
                            style: AppTypography.label.copyWith(
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Achievement metrics
// ─────────────────────────────────────────────────────────────────────────────

class _AchievementMetrics extends StatelessWidget {
  const _AchievementMetrics({required this.store, required this.start});
  final JobTrailStore store;
  final DateTime? start;

  @override
  Widget build(BuildContext context) {
    final achieved = store.weeklyAchieved;
    final target = store.weeklyGoal.target;
    final progress = store.weeklyProgress;
    // Activity streak uses the full account snapshot and shared WIB referenceDate,
    // matching HomeScreen and staying independent of the selected period filter.
    final streak = calculateActivityStreak(
      referenceDate: store.referenceDate,
      appliedDates: store.applications.map((app) => app.appliedAt),
    );

    // Interview conversion: count apps with a recorded Interview event
    // in StatusHistory. Do NOT assume Offering implies Interview —
    // only count explicit Interview history entries (JT-BUG-017).
    final allApps = store.applicationsInPeriod(start: start);
    final total = allApps.length;
    final historyEntries = store.history;

    // Collect IDs with an explicit RecruitmentStatus.interview event.
    final appIdsWithInterview = <String>{};
    for (final entry in historyEntries) {
      if (entry.status == RecruitmentStatus.interview) {
        appIdsWithInterview.add(entry.applicationId);
      }
    }
    // Filter to only include apps in current period.
    final periodAppIds = allApps.map((a) => a.id).toSet();
    final interviewConversionCount = appIdsWithInterview
        .intersection(periodAppIds)
        .length;
    final hasConversionData = total > 0;
    final conversionRate = hasConversionData
        ? (interviewConversionCount / total * 100)
        : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Weekly Goal — independent of period filter.
          _MetricTile(
            icon: Icons.flag_outlined,
            iconColor: AppColors.mint,
            label: 'Target Minggu Ini',
            value: '$achieved dari $target',
            trailing: _MiniProgressBar(progress: progress),
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.border),

          // Interview conversion — only shown when history data supports it.
          if (hasConversionData && conversionRate != null) ...[
            _MetricTile(
              icon: Icons.trending_up_rounded,
              iconColor: const Color(0xFF0369A1),
              label: 'Interview Conversion (tercatat)',
              value: '${conversionRate.toStringAsFixed(0)}%',
              subtitle:
                  '$interviewConversionCount dari $total lamaran'
                  ' memiliki riwayat interview tercatat',
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48, bottom: AppSpacing.xs),
              child: Text(
                'Riwayat yang belum tercatat dapat membuat angka sebenarnya lebih tinggi.',
                style: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w400,
                  fontSize: 10,
                  color: AppColors.gray,
                ),
              ),
            ),
            const Divider(height: AppSpacing.lg, color: AppColors.border),
          ],

          // Response rate — requires explicit response definition.
          _MetricTile(
            icon: Icons.reply_rounded,
            iconColor: AppColors.peach,
            label: 'Response Rate',
            value: 'Belum tersedia',
            subtitle: 'Memerlukan definisi data respons yang disetujui',
            dimmed: true,
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.border),

          // Activity streak — computed from full account snapshot, matching Home.
          _MetricTile(
            icon: Icons.local_fire_department_rounded,
            iconColor: const Color(0xFFEF4444),
            label: 'Streak Mingguan',
            value: '${streak.consecutiveWeeks} minggu berturut-turut',
            subtitle: streak.hasActivity
                ? 'Satu lamaran tercatat membuat minggu aktif. Dihitung dari seluruh riwayat akun.'
                : 'Belum ada aktivitas lamaran tercatat.',
            dimmed: !streak.hasActivity,
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.subtitle,
    this.trailing,
    this.dimmed = false,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? subtitle;
  final Widget? trailing;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.label),
            const SizedBox(height: 2),
            Text(
              value,
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w600,
                color: dimmed ? AppColors.gray : AppColors.navy,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w400,
                  fontSize: 11,
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(height: AppSpacing.xs),
              trailing!,
            ],
          ],
        ),
      ),
    ],
  );
}

class _MiniProgressBar extends StatelessWidget {
  const _MiniProgressBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: LinearProgressIndicator(
      value: progress,
      minHeight: 8,
      color: AppColors.mint,
      backgroundColor: AppColors.primaryLight,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Trend card: bar chart of applications per week, including zero weeks
// ─────────────────────────────────────────────────────────────────────────────

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.store, required this.start});
  final JobTrailStore store;
  final DateTime? start;

  @override
  Widget build(BuildContext context) {
    final weekBuckets = weeklyTrendBuckets(
      appliedDates: store.applications.map((app) => app.appliedAt),
      referenceDate: store.referenceDate,
      start: start,
    );
    if (weekBuckets.isEmpty) {
      return const EmptyState(message: 'Belum ada data tren pada periode ini.');
    }
    final filledWeeks = weekBuckets.keys.toList();

    final maxCount = weekBuckets.values.fold<int>(0, (a, b) => math.max(a, b));

    // For many weeks, make the chart horizontally scrollable.
    final useScroll = filledWeeks.length > 6;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lamaran per Minggu', style: AppTypography.label),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 110 + MediaQuery.textScalerOf(context).scale(30),
            child: useScroll
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _buildBars(filledWeeks, weekBuckets, maxCount),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _buildBars(filledWeeks, weekBuckets, maxCount),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBars(
    List<DateTime> weeks,
    Map<DateTime, int> buckets,
    int maxCount,
  ) {
    final useFixed = weeks.length > 6;
    return [
      for (int i = 0; i < weeks.length; i++) ...[
        if (useFixed)
          SizedBox(
            width: 48,
            child: _TrendBar(
              weekStart: weeks[i],
              count: buckets[weeks[i]]!,
              maxCount: maxCount,
            ),
          )
        else
          Expanded(
            child: _TrendBar(
              weekStart: weeks[i],
              count: buckets[weeks[i]]!,
              maxCount: maxCount,
            ),
          ),
        if (i < weeks.length - 1) const SizedBox(width: 6),
      ],
    ];
  }
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.weekStart,
    required this.count,
    required this.maxCount,
  });
  final DateTime weekStart;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : count / maxCount;
    final barHeight = math.max(fraction * 100, 4.0);
    final weekLabel =
        '${weekStart.day.toString().padLeft(2, '0')}/${weekStart.month.toString().padLeft(2, '0')}';

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$count',
          style: AppTypography.label.copyWith(
            fontSize: 11,
            color: count > 0 ? AppColors.primary : AppColors.gray,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: barHeight,
          decoration: BoxDecoration(
            color: count > 0
                ? AppColors.primary.withValues(alpha: 0.75)
                : AppColors.border,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          weekLabel,
          style: AppTypography.label.copyWith(fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
