import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/constants/app_dates.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/models/agenda.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/screens/detail/application_detail_screen.dart';
import 'package:jobtrail/screens/statistics/statistics_screen.dart';
import 'package:jobtrail/widgets/app_shell.dart';

import 'jobtrail_persistence_test.dart' show TestSession, mount;
import 'support/fake_jobtrail_repository.dart';

final mondayMidnightWib = DateTime.utc(2026, 11, 22, 17);

Application application(int id, int day, RecruitmentStatus status) =>
    Application(
      id: 'fixture-$id',
      company: 'Perusahaan Uji $id',
      position: 'Posisi Uji $id',
      source: 'LinkedIn',
      appliedAt: DateTime.utc(2026, 11, day),
      status: status,
      location: 'Jakarta',
      workType: WorkType.hybrid,
    );

JobTrailSnapshot snapshotAt(
  DateTime instant,
  List<Application> applications, {
  List<Agenda> agendas = const [],
}) => JobTrailSnapshot(
  referenceDate: AppDates.wibDate(instant),
  referenceInstantUtc: instant,
  applications: applications,
  agendas: agendas,
  documents: [],
  history: [],
  applicationRevisions: {for (final app in applications) app.id: 1},
);

Finder key(String name) => find.byKey(ValueKey(name));

void main() {
  testWidgets('Home and Statistics reconcile across Monday midnight WIB', (
    tester,
  ) async {
    final sunday = application(1, 22, RecruitmentStatus.interview);
    final monday = application(2, 23, RecruitmentStatus.offering);
    final sundaySnapshot = snapshotAt(
      mondayMidnightWib.subtract(const Duration(microseconds: 1)),
      [sunday],
    );
    final repo = FakeJobTrailRepository(() => sundaySnapshot);
    await mount(tester, TestSession(), (_) => repo);
    await tester.pumpAndSettle();
    expect(find.text('1 dari 8 lamaran'), findsOneWidget);
    expect(find.text('12,5%'), findsOneWidget);

    final before = Completer<JobTrailSnapshot>();
    repo.read = () => before.future;
    await tester.tap(find.byTooltip('Buka menu akun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muat ulang data'));
    await tester.pump();
    expect(tester.widget<Text>(key('home-total')).data, '1');
    before.complete(snapshotAt(mondayMidnightWib, [sunday, monday]));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Muat ulang data'))).pop();
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(key('home-total')).data, '2');
    expect(find.text('+1 mgg ini'), findsOneWidget);
    expect(find.text('1 dari 8 lamaran'), findsOneWidget);
    await tester.tap(key('home-weekly-goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sen\n1'));
    await tester.pumpAndSettle();
    expect(find.text(monday.company).hitTestable(), findsOneWidget);
    expect(find.text(sunday.company).hitTestable(), findsNothing);
    Navigator.of(tester.element(find.text('Target Mingguan'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(key('nav-statistics'));
    await tester.pumpAndSettle();
    for (final entry in {
      'total': '2',
      'interview': '1',
      'offering': '1',
    }.entries) {
      expect(
        find.descendant(
          of: key('statistics-summary-${entry.key}'),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
      );
    }
    await tester.scrollUntilVisible(
      find.text('1 dari 8'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(StatisticsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('1 dari 8').hitTestable(), findsOneWidget);
  });

  testWidgets('Week count can exceed eight while progress stays at 100%', (
    tester,
  ) async {
    final apps = List.generate(
      9,
      (index) => application(index, 23, RecruitmentStatus.applied),
    );
    final repo = FakeJobTrailRepository(
      () => snapshotAt(mondayMidnightWib, apps),
    );
    await mount(tester, TestSession(), (_) => repo);
    await tester.pumpAndSettle();
    expect(find.text('9 dari 8 lamaran'), findsOneWidget);
    expect(find.text('100,0%'), findsOneWidget);
    expect(find.text('+9 mgg ini'), findsOneWidget);
    final add = tester.widget<FloatingActionButton>(key('home-add'));
    expect(add.onPressed, isNull);
    await tester.tap(key('home-add'));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    expect(repo.reads, 1);
  });

  testWidgets(
    'Agenda cutoff, ordering, notification, and Detail use snapshot IDs',
    (tester) async {
      final first = application(1, 22, RecruitmentStatus.offering);
      final second = application(2, 23, RecruitmentStatus.interview);
      final third = application(3, 20, RecruitmentStatus.applied);
      Agenda agenda(String id, Application app, int minutes, AgendaType type) =>
          Agenda(
            id: id,
            applicationId: app.id,
            type: type,
            scheduledAt: mondayMidnightWib.add(Duration(minutes: minutes)),
            locationOrLink: id,
          );
      final repo = FakeJobTrailRepository(
        () => snapshotAt(
          mondayMidnightWib,
          [third, first, second],
          agendas: [
            agenda('Agenda Batas', first, 0, AgendaType.interview),
            agenda('Agenda Berikut', second, 15, AgendaType.test),
            // Keep the past notification on a valid application/date.
            agenda('Agenda Lewat', third, -1, AgendaType.interview),
            agenda('Agenda Ketiga', third, 30, AgendaType.interview),
          ],
        ),
      );
      await mount(tester, TestSession(), (_) => repo);
      await tester.pumpAndSettle();
      expect(find.text('2 mendatang'), findsOneWidget);
      final boundary = find.textContaining('Agenda Batas');
      final next = find.textContaining('Agenda Berikut');
      await tester.ensureVisible(boundary);
      expect(
        tester.getTopLeft(boundary).dy,
        lessThan(tester.getTopLeft(next).dy),
      );
      expect(find.textContaining('Agenda Lewat'), findsNothing);
      expect(find.textContaining('Agenda Ketiga'), findsNothing);
      await tester.tap(boundary);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ApplicationDetailScreen>(
              find.byType(ApplicationDetailScreen),
            )
            .applicationId,
        first.id,
      );
      Navigator.of(tester.element(find.byType(ApplicationDetailScreen))).pop();
      await tester.pumpAndSettle();

      // The same snapshot also drives newest-first applications, independently
      // of the order of the agenda cards and the repository's input list.
      final recent = find.text('Lamaran Terbaru');
      await tester.ensureVisible(recent);
      final positions = [
        second,
        first,
        third,
      ].map((item) => tester.getTopLeft(find.text(item.position)).dy).toList();
      expect(positions[0], lessThan(positions[1]));
      expect(positions[1], lessThan(positions[2]));

      final schedule = find.textContaining('Lihat semua');
      await tester.ensureVisible(schedule);
      await tester.tap(schedule);
      await tester.pumpAndSettle();
      expect(key('S05'), findsOneWidget);
      await tester.tap(key('nav-home'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Notifikasi'));
      await tester.pumpAndSettle();
      final past = find.textContaining('Agenda Lewat');
      await tester.ensureVisible(past);
      expect(find.text('Jadwal interview lalu'), findsOneWidget);
      await tester.tap(past);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ApplicationDetailScreen>(
              find.byType(ApplicationDetailScreen),
            )
            .applicationId,
        third.id,
      );
    },
  );

  testWidgets('Weekly calendar day targets fit 393px and narrow scaled text', (
    tester,
  ) async {
    final repo = FakeJobTrailRepository(
      () => snapshotAt(mondayMidnightWib, []),
    );
    await mount(tester, TestSession(), (_) => repo);
    await tester.pumpAndSettle();
    for (final width in [393.0, 320.0]) {
      tester.view.physicalSize = Size(width, 852);
      tester.platformDispatcher.textScaleFactorTestValue = width == 320 ? 2 : 1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('home-weekly-goal'));
      await tester.pumpAndSettle();
      await tester.tap(key('home-weekly-goal'));
      await tester.pumpAndSettle();
      final mondayLabel = find.text('Sen\n0');
      await tester.scrollUntilVisible(
        mondayLabel,
        100,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      final monday = find
          .ancestor(of: mondayLabel, matching: find.byType(InkWell))
          .first;
      expect(tester.getSize(monday).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(monday).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.text('Target Mingguan'))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Logout while refreshing discards the previous snapshot result', (
    tester,
  ) async {
    final session = TestSession();
    final initial = snapshotAt(mondayMidnightWib, [
      application(1, 23, RecruitmentStatus.applied),
    ]);
    final fresh = snapshotAt(mondayMidnightWib, []);
    final pending = Completer<JobTrailSnapshot>();
    final oldRepo = FakeJobTrailRepository(() => initial);
    final newRepo = FakeJobTrailRepository(() => fresh);
    await mount(tester, session, (id) => id == 'owner-a' ? oldRepo : newRepo);
    await tester.pumpAndSettle();
    oldRepo.read = () => pending.future;
    await tester.tap(find.byTooltip('Buka menu akun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muat ulang data'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    await tester.tap(find.text('Keluar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Ya, keluar'));
    await tester.pumpAndSettle();
    expect(oldRepo.disposed, isTrue);
    session.changes.add(session.signedIn('owner-b'));
    await tester.pumpAndSettle();
    pending.complete(initial);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(key('home-total')).data, '0');
    expect(find.text('Belum ada lamaran.'), findsOneWidget);
  });
}
