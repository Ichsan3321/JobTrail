import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/constants/app_dates.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/models/status_history.dart';
import 'package:jobtrail/screens/statistics/statistics_screen.dart';

import 'jobtrail_persistence_test.dart' show TestSession, emptySnapshot, mount;
import 'support/fake_jobtrail_repository.dart';

Application _app(
  String id, {
  required String company,
  required DateTime appliedAt,
  required RecruitmentStatus status,
}) => Application(
  id: id,
  company: company,
  position: 'Posisi $id',
  source: 'LinkedIn',
  appliedAt: appliedAt,
  status: status,
  location: 'Jakarta',
  workType: WorkType.hybrid,
);

JobTrailSnapshot _snapshotAt(
  DateTime instantUtc,
  List<Application> applications, {
  List<StatusHistory> history = const [],
}) => JobTrailSnapshot(
  referenceDate: AppDates.wibDate(instantUtc),
  referenceInstantUtc: instantUtc,
  applications: applications,
  agendas: const [],
  documents: const [],
  history: history,
  applicationRevisions: {for (final app in applications) app.id: 1},
);

Future<void> _openStatistics(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-statistics')));
  await tester.pumpAndSettle();
}

Future<void> _triggerAccountRefresh(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-home')));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Buka menu akun'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Muat ulang data'));
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.text('Muat ulang data'))).pop();
  await tester.pumpAndSettle();
  await _openStatistics(tester);
}

String _summaryValue(WidgetTester tester, String id) => tester
    .widget<Text>(
      find
          .descendant(
            of: find.byKey(ValueKey('statistics-summary-$id')),
            matching: find.byType(Text),
          )
          .first,
    )
    .data!;

void main() {
  testWidgets('empty connected snapshot shows empty state with no demo data', (
    tester,
  ) async {
    final repo = FakeJobTrailRepository(emptySnapshot);
    await mount(tester, TestSession(), (_) => repo);
    await tester.pumpAndSettle();

    await _openStatistics(tester);

    expect(find.text('Total: 0'), findsOneWidget);
    expect(
      find.textContaining('Belum ada lamaran pada periode ini'),
      findsOneWidget,
    );
    expect(find.textContaining('Lentera Tech'), findsNothing);
    expect(find.textContaining('Nusa Digital'), findsNothing);
    expect(find.textContaining('Arunika Finance'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WIB boundary shifts 1-month period across UTC 17:00 refresh', (
    tester,
  ) async {
    // 2026-11-17 16:59:59 UTC == 2026-11-17 23:59:59 WIB (referenceDate 17 Nov)
    final beforeMidnightWib = DateTime.utc(2026, 11, 17, 16, 59, 59);
    // 2026-11-17 17:00:00 UTC == 2026-11-18 00:00:00 WIB (referenceDate 18 Nov)
    final atMidnightWib = DateTime.utc(2026, 11, 17, 17);

    final apps = [
      _app(
        'app-boundary',
        company: 'Batas Oktober',
        appliedAt: DateTime.utc(2026, 10, 17),
        status: RecruitmentStatus.applied,
      ),
      _app(
        'app-older',
        company: 'Lebih Lama',
        appliedAt: DateTime.utc(2026, 10, 16),
        status: RecruitmentStatus.screening,
      ),
      _app(
        'app-nov',
        company: 'November Baru',
        appliedAt: DateTime.utc(2026, 11, 15),
        status: RecruitmentStatus.interview,
      ),
    ];

    var current = _snapshotAt(beforeMidnightWib, apps);
    final repo = FakeJobTrailRepository(() => current);
    await mount(tester, TestSession(), (_) => repo);
    await tester.pumpAndSettle();

    await _openStatistics(tester);
    expect(find.text('Total: 3'), findsOneWidget);

    // 17 Nov - 1 month = 17 Oct (inclusive): includes app-boundary & app-nov.
    await tester.tap(find.text('1 Bulan Terakhir'));
    await tester.pumpAndSettle();
    expect(find.text('Total: 2'), findsOneWidget);

    // Advance across midnight WIB (17:00 UTC) and refresh.
    current = _snapshotAt(atMidnightWib, apps);
    await _triggerAccountRefresh(tester);

    // 18 Nov - 1 month = 18 Oct: app-boundary (17 Oct) is now excluded.
    expect(find.text('Total: 1'), findsOneWidget);
    expect(_summaryValue(tester, 'interview'), '1');
  });

  testWidgets(
    'distinguishes current status from history events without double-counting',
    (tester) async {
      final apps = [
        _app(
          'app-1',
          company: 'PT Satu',
          appliedAt: DateTime.utc(2026, 11, 10),
          status: RecruitmentStatus.offering,
        ),
        _app(
          'app-2',
          company: 'PT Dua',
          appliedAt: DateTime.utc(2026, 11, 12),
          status: RecruitmentStatus.rejected,
        ),
        _app(
          'app-3',
          company: 'PT Tiga',
          appliedAt: DateTime.utc(2026, 11, 14),
          status: RecruitmentStatus.offering,
        ),
      ];
      final history = [
        // app-1: Applied -> Interview -> Offering
        StatusHistory(
          id: 'h-1',
          applicationId: 'app-1',
          status: RecruitmentStatus.applied,
          changedAt: DateTime.utc(2026, 11, 10, 2),
        ),
        StatusHistory(
          id: 'h-2',
          applicationId: 'app-1',
          status: RecruitmentStatus.interview,
          changedAt: DateTime.utc(2026, 11, 11, 2),
        ),
        StatusHistory(
          id: 'h-3',
          applicationId: 'app-1',
          status: RecruitmentStatus.offering,
          changedAt: DateTime.utc(2026, 11, 15, 2),
        ),
        // app-2: Applied -> Interview (x2) -> Rejected (must count once!)
        StatusHistory(
          id: 'h-4',
          applicationId: 'app-2',
          status: RecruitmentStatus.applied,
          changedAt: DateTime.utc(2026, 11, 12, 2),
        ),
        StatusHistory(
          id: 'h-5',
          applicationId: 'app-2',
          status: RecruitmentStatus.interview,
          changedAt: DateTime.utc(2026, 11, 13, 2),
        ),
        StatusHistory(
          id: 'h-6',
          applicationId: 'app-2',
          status: RecruitmentStatus.interview,
          changedAt: DateTime.utc(2026, 11, 14, 2),
        ),
        StatusHistory(
          id: 'h-7',
          applicationId: 'app-2',
          status: RecruitmentStatus.rejected,
          changedAt: DateTime.utc(2026, 11, 16, 2),
        ),
        // app-3: Applied -> Offering (skipped Interview)
        StatusHistory(
          id: 'h-8',
          applicationId: 'app-3',
          status: RecruitmentStatus.applied,
          changedAt: DateTime.utc(2026, 11, 14, 2),
        ),
        StatusHistory(
          id: 'h-9',
          applicationId: 'app-3',
          status: RecruitmentStatus.offering,
          changedAt: DateTime.utc(2026, 11, 17, 2),
        ),
      ];

      final repo = FakeJobTrailRepository(
        () => _snapshotAt(
          DateTime.utc(2026, 11, 18, 5),
          apps,
          history: history,
        ),
      );
      await mount(tester, TestSession(), (_) => repo);
      await tester.pumpAndSettle();

      await _openStatistics(tester);

      // Summary uses current status: Total 3, Interview saat ini 0, Offering 2.
      expect(_summaryValue(tester, 'total'), '3');
      expect(_summaryValue(tester, 'interview'), '0');
      expect(_summaryValue(tester, 'offering'), '2');

      // Interview Conversion uses recorded Interview events: 2 of 3 = 67%.
      await tester.scrollUntilVisible(
        find.text('Interview Conversion (tercatat)'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(StatisticsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('67%'), findsWidgets);
      expect(
        find.text('2 dari 3 lamaran memiliki riwayat interview tercatat'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'refresh updates Statistics and matches Home and Board from single snapshot',
    (tester) async {
      final mondayUtc = DateTime.utc(2026, 11, 23, 5); // Mon 23 Nov 2026 WIB
      final firstApps = [
        _app(
          'app-a',
          company: 'Alpha Corp',
          appliedAt: DateTime.utc(2026, 11, 23),
          status: RecruitmentStatus.interview,
        ),
        _app(
          'app-b',
          company: 'Beta Corp',
          appliedAt: DateTime.utc(2026, 11, 20),
          status: RecruitmentStatus.applied,
        ),
      ];
      final secondApps = [
        _app(
          'app-a',
          company: 'Alpha Corp',
          appliedAt: DateTime.utc(2026, 11, 23),
          status: RecruitmentStatus.offering,
        ),
        _app(
          'app-b',
          company: 'Beta Corp',
          appliedAt: DateTime.utc(2026, 11, 20),
          status: RecruitmentStatus.applied,
        ),
        _app(
          'app-c',
          company: 'Gamma Corp',
          appliedAt: DateTime.utc(2026, 11, 23),
          status: RecruitmentStatus.screening,
        ),
      ];

      var current = _snapshotAt(mondayUtc, firstApps);
      final repo = FakeJobTrailRepository(() => current);
      await mount(tester, TestSession(), (_) => repo);
      await tester.pumpAndSettle();

      // Home baseline: total 2, interview 1, offering 0, weekly 1 dari 8.
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('home-total'))).data,
        '2',
      );
      expect(find.text('1 dari 8 lamaran'), findsOneWidget);

      // Update snapshot & refresh from Statistics tab.
      await _openStatistics(tester);
      expect(_summaryValue(tester, 'total'), '2');
      expect(_summaryValue(tester, 'interview'), '1');
      expect(_summaryValue(tester, 'offering'), '0');

      current = _snapshotAt(mondayUtc, secondApps);
      await _triggerAccountRefresh(tester);

      expect(_summaryValue(tester, 'total'), '3');
      expect(_summaryValue(tester, 'interview'), '0');
      expect(_summaryValue(tester, 'offering'), '1');
      await tester.scrollUntilVisible(
        find.text('2 dari 8'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(StatisticsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('2 dari 8'), findsOneWidget);

      // Verify Home and Board reflect the exact same refreshed snapshot.
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('home-total'))).data,
        '3',
      );
      expect(find.text('2 dari 8 lamaran'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav-board')));
      await tester.pumpAndSettle();
      expect(find.text('Alpha Corp'), findsOneWidget);
      expect(find.text('Gamma Corp'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Beta Corp'),
        150,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
      expect(find.text('Beta Corp'), findsOneWidget);
    },
  );

  testWidgets('failed refresh preserves last snapshot and shows retry banner', (
    tester,
  ) async {
    final initial = _snapshotAt(DateTime.utc(2026, 11, 23, 5), [
      _app(
        'app-keep',
        company: 'Stabil Corp',
        appliedAt: DateTime.utc(2026, 11, 22),
        status: RecruitmentStatus.interview,
      ),
    ]);
    var failRead = false;
    final repo = FakeJobTrailRepository(() {
      if (failRead) {
        throw const RepositoryFailure(RepositoryIssue.network);
      }
      return initial;
    });

    await mount(tester, TestSession(), (_) => repo);
    await tester.pumpAndSettle();
    await _openStatistics(tester);
    expect(_summaryValue(tester, 'total'), '1');

    failRead = true;
    await _triggerAccountRefresh(tester);

    expect(find.text('Coba lagi'), findsOneWidget);
    expect(_summaryValue(tester, 'total'), '1');
    expect(tester.takeException(), isNull);
  });
}
