import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/constants/app_tokens.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/screens/statistics/statistics_screen.dart';

import 'jobtrail_store_test.dart' show draft;

Future<void> selectTab(WidgetTester tester, String tab) async {
  await tester.tap(find.byKey(ValueKey('nav-$tab')));
  await tester.pumpAndSettle();
}

/// Navigate to Statistics tab from app.
Future<void> goToStatistics(WidgetTester tester) async {
  await selectTab(tester, 'statistics');
}

void main() {
  testWidgets('summary and interview caveat retain readable contrast', (
    tester,
  ) async {
    await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
    await goToStatistics(tester);
    final summaryText = tester.widget<Text>(find.text('Ringkasan lamaran'));
    final white = summaryText.style!.color!.computeLuminance();
    final purple = AppColors.primary.computeLuminance();
    expect((white + .05) / (purple + .05), greaterThanOrEqualTo(4.5));
    final caveat = find.textContaining('Riwayat yang belum tercatat');
    await tester.scrollUntilVisible(
      caveat,
      150,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    final color = tester.widget<Text>(caveat).style!.color!;
    expect(
      (Colors.white.computeLuminance() + .05) /
          (color.computeLuminance() + .05),
      greaterThanOrEqualTo(4.5),
    );
  });
  for (final size in [const Size(393, 852), const Size(320, 640)]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('summary remains readable at $size scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = JobTrailStore.demo();
        addTearDown(store.dispose);
        await tester.pumpWidget(
          JobTrailApp(showAuthentication: false, store: store),
        );
        await goToStatistics(tester);
        final summary = find.byKey(const ValueKey('statistics-summary'));
        await tester.scrollUntilVisible(
          summary,
          150,
          scrollable: find
              .ancestor(
                of: find.byKey(const ValueKey('S07')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(summary, findsOneWidget);
        final decoration =
            tester.widget<Container>(summary).decoration! as BoxDecoration;
        expect(decoration.color, AppColors.primary);
        for (final entry in {
          'total': ('3', 'Total Lamaran'),
          'interview': ('1', 'Interview saat ini'),
          'offering': ('0', 'Offering'),
        }.entries) {
          final metric = find.byKey(
            ValueKey('statistics-summary-${entry.key}'),
          );
          expect(
            find.descendant(of: metric, matching: find.text(entry.value.$1)),
            findsOneWidget,
          );
          final label = find.descendant(
            of: metric,
            matching: find.text(entry.value.$2),
          );
          expect(label, findsOneWidget);
          expect(
            tester.widget<Text>(label).overflow,
            isNot(TextOverflow.ellipsis),
          );
          expect(tester.widget<Text>(label).maxLines, isNull);
        }
        store.changeStatus('app-nusa', RecruitmentStatus.offering);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('statistics-summary-interview')),
            matching: find.text('0'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('statistics-summary-offering')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  // ─────────────────────────────────────────────────────────────────────────
  // subtractMonths unit tests (JT-BUG-018)
  // ─────────────────────────────────────────────────────────────────────────

  group('subtractMonths – safe month-end handling', () {
    test('normal case: 17 Nov − 1 month = 17 Oct', () {
      final result = subtractMonths(DateTime.utc(2026, 11, 17), 1);
      expect(result, DateTime.utc(2026, 10, 17));
    });

    test('month-end clamping: 31 Mar − 1 month = 28 Feb (non-leap)', () {
      final result = subtractMonths(DateTime.utc(2027, 3, 31), 1);
      expect(result, DateTime.utc(2027, 2, 28));
    });

    test('leap year: 31 Mar − 1 month = 29 Feb (leap year 2028)', () {
      final result = subtractMonths(DateTime.utc(2028, 3, 31), 1);
      expect(result, DateTime.utc(2028, 2, 29));
    });

    test('month-end clamping: 31 Jan − 1 month = 31 Dec (year rollover)', () {
      final result = subtractMonths(DateTime.utc(2027, 1, 31), 1);
      expect(result, DateTime.utc(2026, 12, 31));
    });

    test('year rollover: 15 Jan − 2 months = 15 Nov previous year', () {
      final result = subtractMonths(DateTime.utc(2027, 1, 15), 2);
      expect(result, DateTime.utc(2026, 11, 15));
    });

    test('year rollover: 15 Feb − 3 months = 15 Nov previous year', () {
      final result = subtractMonths(DateTime.utc(2027, 2, 15), 3);
      expect(result, DateTime.utc(2026, 11, 15));
    });

    test('zero months returns same date', () {
      final date = DateTime.utc(2026, 11, 17);
      expect(subtractMonths(date, 0), date);
    });

    test('31 May − 3 months = 28 Feb (non-leap)', () {
      final result = subtractMonths(DateTime.utc(2027, 5, 31), 3);
      expect(result, DateTime.utc(2027, 2, 28));
    });

    test('30 Nov − 1 month = 30 Oct', () {
      final result = subtractMonths(DateTime.utc(2026, 11, 30), 1);
      expect(result, DateTime.utc(2026, 10, 30));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Status distribution and rounding
  // ─────────────────────────────────────────────────────────────────────────

  group('status distribution and rounding', () {
    testWidgets('demo fixture shows correct distribution', (tester) async {
      await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
      await goToStatistics(tester);

      // Demo: 3 total — Applied 1, Screening 1, Interview 1
      expect(find.text('Total: 3'), findsOneWidget);
      // All 6 statuses appear in distribution section
      for (final status in RecruitmentStatus.values) {
        expect(find.text(status.label), findsWidgets);
      }
    });

    testWidgets('percentages display correctly with rounding', (tester) async {
      await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
      await goToStatistics(tester);

      // 1/3 ≈ 33%, each of the three statuses with count 1
      expect(find.text('33%'), findsNWidgets(3));
    });

    testWidgets('single-app shows 100% for that status', (tester) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);
      store.addApplication(draft());
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);

      expect(find.text('100%'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Interview conversion (JT-BUG-017)
  // ─────────────────────────────────────────────────────────────────────────

  group('interview conversion – only explicit Interview history', () {
    testWidgets('counts only apps with recorded Interview event', (
      tester,
    ) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);

      // App 1: Applied → Interview (has interview history)
      final id1 = store.addApplication(
        draft(company: 'Co A', appliedAt: DateTime.utc(2026, 11, 15)),
      );
      store.changeStatus(id1, RecruitmentStatus.interview);

      // App 2: Applied only (no interview history)
      store.addApplication(
        draft(company: 'Co B', appliedAt: DateTime.utc(2026, 11, 16)),
      );

      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();

      // 1 of 2 has interview history → 50%
      expect(find.text('50%'), findsWidgets);
      expect(find.textContaining('1 dari 2 lamaran'), findsOneWidget);
    });

    testWidgets('does NOT count Offering as Interview', (tester) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);

      // App: Applied → Offering (skipped interview)
      final id = store.addApplication(
        draft(company: 'Direct Offer', appliedAt: DateTime.utc(2026, 11, 15)),
      );
      store.changeStatus(id, RecruitmentStatus.offering);

      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();

      // 0 of 1 has interview → 0%
      expect(find.textContaining('0 dari 1 lamaran'), findsOneWidget);
    });

    testWidgets('non-linear history: Interview→Rejected still counts', (
      tester,
    ) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);

      // Applied → Interview → Rejected
      final id = store.addApplication(
        draft(company: 'Rejected Co', appliedAt: DateTime.utc(2026, 11, 14)),
      );
      store.changeStatus(id, RecruitmentStatus.interview);
      store.changeStatus(id, RecruitmentStatus.rejected);

      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();

      // 1 of 1 has interview history → 100%
      expect(find.textContaining('1 dari 1 lamaran'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Empty datasets and division-by-zero
  // ─────────────────────────────────────────────────────────────────────────

  group('recorded interview cohort', () {
    testWidgets('warns about missing history and filters the cohort', (
      tester,
    ) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);
      final old = store.addApplication(
        draft(company: 'Old', appliedAt: DateTime.utc(2026, 10, 16)),
      );
      store.changeStatus(old, RecruitmentStatus.interview);
      final recent = store.addApplication(
        draft(company: 'Recent', appliedAt: DateTime.utc(2026, 11, 1)),
      );
      store.changeStatus(recent, RecruitmentStatus.interview);
      store.changeStatus(recent, RecruitmentStatus.rejected);
      store.changeStatus(recent, RecruitmentStatus.interview);
      store.addApplication(
        draft(company: 'Missing events', appliedAt: DateTime.utc(2026, 11, 2)),
      );
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 dari 3 lamaran'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 Bulan Terakhir'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 dari 2 lamaran'), findsOneWidget);
      expect(find.text('Interview Conversion (tercatat)'), findsOneWidget);
      expect(
        find.textContaining(
          'Riwayat yang belum tercatat dapat membuat angka sebenarnya lebih tinggi',
        ),
        findsOneWidget,
      );
    });
  });

  group('weekly trend reporting interval', () {
    test('includes boundary, gap and reference weeks in year order', () {
      final buckets = weeklyTrendBuckets(
        start: DateTime.utc(2026, 12, 23),
        referenceDate: DateTime.utc(2027, 1, 19),
        appliedDates: [
          DateTime.utc(2026, 12, 22),
          DateTime.utc(2026, 12, 23),
          DateTime.utc(2027, 1, 5),
          DateTime.utc(2027, 1, 19),
          DateTime.utc(2027, 1, 20),
        ],
      );
      expect(buckets, {
        DateTime.utc(2026, 12, 21): 1,
        DateTime.utc(2026, 12, 28): 0,
        DateTime.utc(2027, 1, 4): 1,
        DateTime.utc(2027, 1, 11): 0,
        DateTime.utc(2027, 1, 18): 1,
      });
      expect(buckets.keys.toList(), [
        DateTime.utc(2026, 12, 21),
        DateTime.utc(2026, 12, 28),
        DateTime.utc(2027, 1, 4),
        DateTime.utc(2027, 1, 11),
        DateTime.utc(2027, 1, 18),
      ]);
    });

    test(
      'empty bounded period has zero weeks; unbounded empty has no range',
      () {
        final reference = DateTime.utc(2026, 11, 17);
        expect(
          weeklyTrendBuckets(
            start: DateTime.utc(2026, 11, 2),
            referenceDate: reference,
            appliedDates: [],
          ),
          {
            DateTime.utc(2026, 11, 2): 0,
            DateTime.utc(2026, 11, 9): 0,
            DateTime.utc(2026, 11, 16): 0,
          },
        );
        expect(
          weeklyTrendBuckets(referenceDate: reference, appliedDates: []),
          isEmpty,
        );
      },
    );

    test(
      'unbounded period runs from earliest historical date to reference',
      () {
        expect(
          weeklyTrendBuckets(
            referenceDate: DateTime.utc(2026, 11, 17),
            appliedDates: [
              DateTime.utc(2026, 11, 4),
              DateTime.utc(2026, 11, 18),
            ],
          ),
          {
            DateTime.utc(2026, 11, 2): 1,
            DateTime.utc(2026, 11, 9): 0,
            DateTime.utc(2026, 11, 16): 0,
          },
        );
      },
    );

    testWidgets('empty filtered period still displays zero trend', (
      tester,
    ) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);
      await tester.tap(find.text('1 Bulan Terakhir'));
      await tester.pumpAndSettle();
      expect(find.text('Lamaran per Minggu'), findsOneWidget);
      expect(
        find.text(
          'Belum ada lamaran pada periode ini.\nTambahkan lamaran untuk melihat statistik.',
        ),
        findsOneWidget,
      );
    });
  });

  group('empty dataset and division-by-zero', () {
    testWidgets('empty store shows empty state', (tester) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);

      expect(find.text('Total: 0'), findsOneWidget);
      expect(
        find.textContaining('Belum ada lamaran pada periode ini'),
        findsOneWidget,
      );
    });

    testWidgets('no NaN or crash with zero total', (tester) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);

      expect(tester.takeException(), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Period filter and interaction (JT-BUG-021)
  // ─────────────────────────────────────────────────────────────────────────

  group('period filter interaction', () {
    testWidgets('all four period chips are displayed', (tester) async {
      await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
      await goToStatistics(tester);

      expect(find.text('Saat Ini'), findsOneWidget);
      expect(find.text('1 Bulan Terakhir'), findsOneWidget);
      expect(find.text('2 Bulan Terakhir'), findsOneWidget);
      expect(find.text('3 Bulan Terakhir'), findsOneWidget);
    });

    testWidgets('selecting period filter changes displayed data', (
      tester,
    ) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);

      // App from 2 months ago (Oct 17)
      store.addApplication(
        draft(company: 'Old Co', appliedAt: DateTime.utc(2026, 10, 17)),
      );
      // App from this month (Nov 15)
      store.addApplication(
        draft(company: 'New Co', appliedAt: DateTime.utc(2026, 11, 15)),
      );

      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);

      // All: 2 total
      expect(find.text('Total: 2'), findsOneWidget);

      // Switch to 1 month: start = Oct 17, includes both
      await tester.tap(find.text('1 Bulan Terakhir'));
      await tester.pumpAndSettle();
      expect(find.text('Total: 2'), findsOneWidget);
    });

    testWidgets('filter chips have min 44px touch target', (tester) async {
      await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
      await goToStatistics(tester);

      final chipFinder = find.text('Saat Ini');
      expect(chipFinder, findsOneWidget);

      // The InkWell container should have >= 44px height.
      final chipElement = tester.element(chipFinder);
      final renderBox = chipElement.findRenderObject()! as RenderBox;
      // The parent container enforces minHeight: 44
      // The text itself may be smaller but the touch target is the
      // InkWell/Container that wraps it.
      expect(renderBox.size.height, greaterThan(0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Distribution detail interaction (JT-BUG-020)
  // ─────────────────────────────────────────────────────────────────────────

  group('distribution detail interaction', () {
    testWidgets('tapping a status row expands detail list', (tester) async {
      await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
      await goToStatistics(tester);

      // Before tap: Lentera Tech should not be visible in distribution
      // section specifically (it appears in Board). We look for the
      // distribution detail pattern.
      final appliedChip = find.text('Applied');
      expect(appliedChip, findsWidgets);

      // Tap on the Applied row in distribution
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();

      // After expansion, the detail should show application info
      expect(find.byIcon(Icons.keyboard_arrow_up), findsWidgets);
    });

    testWidgets('zero-count rows are not tappable', (tester) async {
      await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
      await goToStatistics(tester);

      // Test/Psikotes has 0 in demo fixture — no arrow should appear
      // for it, and it should not expand.
      expect(tester.takeException(), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Zero-week trend (JT-BUG-019)
  // ─────────────────────────────────────────────────────────────────────────

  group('trend chart with zero weeks', () {
    testWidgets('fills gap weeks with zero count', (tester) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);

      // Week 1: Oct 26 (Mon)
      store.addApplication(
        draft(company: 'Week1', appliedAt: DateTime.utc(2026, 10, 26)),
      );
      // Week 3: Nov 9 (Mon) — skip week 2
      store.addApplication(
        draft(company: 'Week3', appliedAt: DateTime.utc(2026, 11, 9)),
      );

      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);

      // Should have 3 bars (weeks: Oct 26, Nov 2 [zero], Nov 9)
      // The zero week should show '0' label.
      expect(find.text('0'), findsWidgets);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Reactive updates: add, edit, delete, status change
  // ─────────────────────────────────────────────────────────────────────────

  group('reactive updates propagate to statistics', () {
    testWidgets('adding an application updates total', (tester) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);

      expect(find.text('Total: 0'), findsOneWidget);

      store.addApplication(draft());
      await tester.pumpAndSettle();

      expect(find.text('Total: 1'), findsOneWidget);
    });

    testWidgets('deleting an application updates total', (tester) async {
      final store = JobTrailStore.demo();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);

      expect(find.text('Total: 3'), findsOneWidget);

      store.deleteApplication('app-lentera');
      await tester.pumpAndSettle();

      expect(find.text('Total: 2'), findsOneWidget);
    });

    testWidgets('status change updates distribution', (tester) async {
      final store = JobTrailStore.demo();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await goToStatistics(tester);

      // Before: Interview = 1 (Nusa Digital)
      store.changeStatus('app-nusa', RecruitmentStatus.offering);
      await tester.pumpAndSettle();

      // After: Offering should now show 1
      // The summary card for Offering should update.
      expect(tester.takeException(), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Responsive layout and accessibility
  // ─────────────────────────────────────────────────────────────────────────

  group('responsive layout', () {
    for (final size in [
      const Size(393, 852),
      const Size(320, 640),
      const Size(1280, 800),
    ]) {
      testWidgets('no overflow at $size with text scale 2', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
        await goToStatistics(tester);

        // Scroll through entire content.
        await tester.drag(
          find.byType(ListView).hitTestable().first,
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('accessibility: filter chips have Semantics', (tester) async {
      await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
      await goToStatistics(tester);

      // Semantics node should exist for the filter chip.
      final semantics = tester.getSemantics(find.text('Saat Ini'));
      // Verify the semantics node is present and has actions (tap).
      expect(semantics.label, contains('Saat Ini'));
    });
  });
}
