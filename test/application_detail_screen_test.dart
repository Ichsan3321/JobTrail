import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/constants/app_dates.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/widgets/app_shell.dart';
import 'package:jobtrail/widgets/status_chip.dart';

Future<AppNavigation> mountApp(WidgetTester tester, JobTrailStore store) async {
  addTearDown(store.dispose);
  await tester.pumpWidget(JobTrailApp(store: store));
  return tester.widget<AppShell>(find.byType(AppShell)).navigation;
}

Future<void> openDetail(
  WidgetTester tester,
  AppNavigation navigation,
  String id,
) async {
  // The future completes when the route is popped.
  navigation.openDetail(id);
  await tester.pumpAndSettle();
}

Finder detailScrollable() => find.descendant(
  of: find.byKey(const ValueKey('detail-scroll')),
  matching: find.byType(Scrollable),
);

Finder statusOption(RecruitmentStatus status) =>
    find.byKey(ValueKey('status-option-${status.name}'));

Future<void> openStatusSheet(WidgetTester tester) async {
  await tester.tap(find.text('Ubah Status'));
  await tester.pumpAndSettle();
}

Future<void> openDeleteDialog(WidgetTester tester) async {
  await tester.tap(find.text('Hapus Lamaran'));
  await tester.pumpAndSettle();
}

Finder deleteConfirmation() =>
    find.widgetWithText(FilledButton, 'Hapus Lamaran');

void main() {
  testWidgets('detail resolves the fixture records and only their relations', (
    tester,
  ) async {
    final store = JobTrailStore.demo();
    final navigation = await mountApp(tester, store);
    const appliedDates = {
      'app-lentera': '12 Nov 2026',
      'app-nusa': '01 Nov 2026',
      'app-arunika': '05 Nov 2026',
    };
    for (final application in store.applications) {
      await openDetail(tester, navigation, application.id);
      expect(find.text(application.company), findsOneWidget);
      expect(find.text(application.position), findsOneWidget);
      expect(find.text(appliedDates[application.id]!), findsOneWidget);
      expect(find.text(application.source), findsOneWidget);
      expect(
        tester.widget<StatusChip>(find.byType(StatusChip)).status,
        application.status,
      );
      final agendas = store.agendasFor(application.id);
      if (agendas.isEmpty) {
        expect(find.text('Belum ada agenda'), findsOneWidget);
      } else {
        expect(
          find.textContaining(agendas.single.locationOrLink),
          findsOneWidget,
        );
      }
      for (final id in application.documentIds) {
        expect(
          find.textContaining(store.documentById(id)!.title),
          findsOneWidget,
        );
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('optional values and revisions reflect the same live store', (
    tester,
  ) async {
    final store = JobTrailStore.empty();
    final id = store.addApplication(
      ApplicationDraft(
        company: 'Perusahaan QA',
        position: 'Penguji',
        source: 'Situs perusahaan',
        appliedAt: store.referenceDate,
        status: RecruitmentStatus.applied,
        location: 'Surabaya',
        workType: WorkType.hybrid,
      ),
    );
    final navigation = await mountApp(tester, store);
    await openDetail(tester, navigation, id);

    expect(find.text('Belum dicatat'), findsOneWidget);
    expect(find.text('Gaji: Belum dicatat'), findsOneWidget);
    expect(find.text('Belum ada agenda'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Belum ada catatan.'),
      160,
      scrollable: detailScrollable(),
    );

    store.updateApplication(
      id,
      ApplicationDraft(
        company: 'Perusahaan QA Diperbarui',
        position: 'Penguji',
        source: 'Situs perusahaan',
        appliedAt: store.referenceDate,
        status: RecruitmentStatus.offering,
        location: 'Surabaya',
        workType: WorkType.hybrid,
        salary: 0,
        notes: 'Catatan setelah edit',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Perusahaan QA Diperbarui'), findsOneWidget);
    expect(find.text('Gaji: Rp0 / bulan'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Catatan setelah edit'),
      160,
      scrollable: detailScrollable(),
    );
    final history = store.historyFor(id);
    for (final event in history) {
      expect(
        find.text(
          '${event.status.label}\n${AppDates.formatWib(event.changedAt)}',
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Saat ini'), findsOneWidget);
  });

  for (final size in [const Size(393, 852), const Size(320, 640)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'detail scroll and action area at $size and text scale $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final navigation = await mountApp(tester, JobTrailStore.demo());
          await openDetail(tester, navigation, 'app-nusa');
          expect(find.byTooltip('Edit Lamaran'), findsOneWidget);
          final statusButton = find.widgetWithText(FilledButton, 'Ubah Status');
          final deleteButton = find.widgetWithText(TextButton, 'Hapus Lamaran');
          expect(
            tester.widget<FilledButton>(statusButton).onPressed,
            isNotNull,
          );
          expect(tester.widget<TextButton>(deleteButton).onPressed, isNotNull);

          await tester.scrollUntilVisible(
            find.text('Belum ada catatan.'),
            160,
            scrollable: detailScrollable(),
          );
          await tester.pumpAndSettle();
          expect(find.text('Belum ada catatan.').hitTestable(), findsOneWidget);
          expect(
            tester.getRect(find.text('Belum ada catatan.')).bottom,
            lessThan(tester.getTopLeft(statusButton).dy),
          );
          expect(deleteButton.hitTestable(), findsOneWidget);
          await openStatusSheet(tester);
          expect(find.text('Simpan Status').hitTestable(), findsOneWidget);
          await tester.scrollUntilVisible(
            statusOption(RecruitmentStatus.rejected),
            140,
            scrollable: find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            statusOption(RecruitmentStatus.rejected).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'status selection stays local until Save and updates chip and history',
    (tester) async {
      final store = JobTrailStore.demo();
      const id = 'app-nusa';
      final historyCount = store.historyFor(id).length;
      final navigation = await mountApp(tester, store);
      await openDetail(tester, navigation, id);
      await openStatusSheet(tester);

      expect(find.text('Ubah Status Lamaran'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<RecruitmentStatus>>(
              find.byType(RadioGroup<RecruitmentStatus>),
            )
            .groupValue,
        RecruitmentStatus.interview,
      );
      for (final status in RecruitmentStatus.values) {
        expect(statusOption(status), findsOneWidget);
      }

      await tester.tap(statusOption(RecruitmentStatus.offering));
      await tester.pumpAndSettle();
      expect(store.applicationById(id)!.status, RecruitmentStatus.interview);
      expect(store.historyFor(id), hasLength(historyCount));

      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();
      expect(store.applicationById(id)!.status, RecruitmentStatus.interview);
      expect(store.historyFor(id), hasLength(historyCount));

      await openStatusSheet(tester);
      await tester.tap(statusOption(RecruitmentStatus.offering));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan Status'));
      await tester.pumpAndSettle();

      expect(store.applicationById(id)!.status, RecruitmentStatus.offering);
      final history = store.historyFor(id);
      expect(history, hasLength(historyCount + 1));
      final latestEvent = history.last;
      expect(latestEvent.status, RecruitmentStatus.offering);
      expect(
        tester
            .widget<StatusChip>(
              find.byKey(const ValueKey('detail-current-status')),
            )
            .status,
        RecruitmentStatus.offering,
      );
      final latestRow = find.text(
        '${latestEvent.status.label}\n${AppDates.formatWib(latestEvent.changedAt)}',
      );
      await tester.scrollUntilVisible(
        latestRow,
        160,
        scrollable: detailScrollable(),
      );
      await tester.pumpAndSettle();
      expect(latestRow.hitTestable(), findsOneWidget);
      expect(find.text('Saat ini'), findsOneWidget);

      await openStatusSheet(tester);
      await tester.tap(find.text('Simpan Status'));
      await tester.pumpAndSettle();
      expect(store.historyFor(id), hasLength(historyCount + 1));
    },
  );

  testWidgets(
    'failed status update reports the error and keeps the current state',
    (tester) async {
      final store = JobTrailStore.demo(clock: () => DateTime.utc(2026, 1, 1));
      final navigation = await mountApp(tester, store);
      const id = 'app-nusa';
      final historyCount = store.historyFor(id).length;
      await openDetail(tester, navigation, id);
      await openStatusSheet(tester);
      await tester.tap(statusOption(RecruitmentStatus.rejected));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan Status'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Status gagal diubah.'), findsOneWidget);
      expect(store.applicationById(id)!.status, RecruitmentStatus.interview);
      expect(store.historyFor(id), hasLength(historyCount));
    },
  );

  testWidgets(
    'delete cancel and dismiss preserve the application and relations',
    (tester) async {
      final store = JobTrailStore.demo();
      final navigation = await mountApp(tester, store);
      const id = 'app-nusa';
      final application = store.applicationById(id);
      final agendas = store.agendasFor(id);
      final history = store.historyFor(id);
      await openDetail(tester, navigation, id);

      await openDeleteDialog(tester);
      expect(find.text('Hapus lamaran?'), findsOneWidget);
      expect(find.textContaining('Lamaran Nusa Digital'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(store.applicationById(id), same(application));
      expect(store.agendasFor(id), agendas);
      expect(store.historyFor(id), history);

      await openDeleteDialog(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(store.applicationById(id), same(application));
      expect(store.agendasFor(id), agendas);
      expect(store.historyFor(id), history);
    },
  );

  testWidgets(
    'delete confirmation mutates once, cascades, and returns to Board',
    (tester) async {
      final store = JobTrailStore.demo();
      final navigation = await mountApp(tester, store);
      const id = 'app-nusa';
      final linkedDocuments = store.applicationById(id)!.documentIds;
      var notifications = 0;
      store.addListener(() => notifications++);
      await openDetail(tester, navigation, id);

      final openDialog = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Hapus Lamaran'))
          .onPressed!;
      openDialog();
      openDialog();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final confirm = tester
          .widget<FilledButton>(deleteConfirmation())
          .onPressed!;
      confirm();
      confirm();
      await tester.pumpAndSettle();

      expect(notifications, 1);
      expect(store.applicationById(id), isNull);
      expect(store.agendasFor(id), isEmpty);
      expect(store.historyFor(id), isEmpty);
      for (final docId in linkedDocuments) {
        expect(store.documentById(docId), isNotNull);
      }
      expect(store.applicationById('app-lentera'), isNotNull);
      expect(find.byKey(const ValueKey('S02')), findsOneWidget);
      expect(find.text('Nusa Digital'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('delete failure reports a missing application', (tester) async {
    final store = JobTrailStore.demo();
    final navigation = await mountApp(tester, store);
    const id = 'app-nusa';
    await openDetail(tester, navigation, id);
    await openDeleteDialog(tester);
    store.deleteApplication(id);
    await tester.pumpAndSettle();
    await tester.tap(deleteConfirmation());
    await tester.pumpAndSettle();
    expect(find.textContaining('Lamaran gagal dihapus.'), findsOneWidget);
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    expect(navigation.selectedTab, AppTab.home);
  });

  testWidgets('Back restores Home, Board and the filtered Jadwal origin', (
    tester,
  ) async {
    final navigation = await mountApp(tester, JobTrailStore.demo());
    await tester.scrollUntilVisible(find.text('Lentera Tech'), 160);
    await tester.tap(find.text('Lentera Tech'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S01')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-board')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('application-app-nusa')),
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('S02')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('application-app-nusa')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('application-app-nusa')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-preview-detail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S02')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('application-app-nusa')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-preview-detail')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda Terkait'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S05')), findsOneWidget);
    expect(navigation.scheduleApplicationId, 'app-nusa');
    expect(find.byKey(const ValueKey('agenda-agenda-arunika')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agenda-agenda-nusa')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S05')), findsOneWidget);
    expect(navigation.scheduleApplicationId, 'app-nusa');
  });

  testWidgets('Edit opens the same ID and Detail refreshes after finishForm', (
    tester,
  ) async {
    final store = JobTrailStore.demo();
    final navigation = await mountApp(tester, store);
    const id = 'app-nusa';
    await openDetail(tester, navigation, id);
    await tester.tap(find.text('Edit Lamaran'));
    await tester.pumpAndSettle();
    final company = tester.widget<Text>(
      find.byKey(const ValueKey('form-company')),
    );
    expect(company.data, store.applicationById(id)!.company);
    expect(
      ModalRoute.of(tester.element(find.byKey(const ValueKey('form-company'))))!
          .settings
          .arguments,
      id,
    );

    // S04 currently exposes the route contract, but no Save control.
    final application = store.applicationById(id)!;
    store.updateApplication(
      id,
      ApplicationDraft(
        company: application.company,
        position: 'Posisi setelah edit',
        source: application.source,
        appliedAt: application.appliedAt,
        status: application.status,
        location: application.location,
        workType: application.workType,
        salary: application.salary,
        notes: application.notes,
        documentIds: application.documentIds,
      ),
    );
    navigation.finishForm(id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    expect(find.text('Posisi setelah edit'), findsOneWidget);
  });
}
