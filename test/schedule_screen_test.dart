import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/agenda.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/screens/schedule/schedule_agenda_card.dart';
import 'package:jobtrail/widgets/status_chip.dart';

Future<void> openSchedule(
  WidgetTester tester, {
  JobTrailStore? store,
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    store == null ? const JobTrailApp() : JobTrailApp(store: store),
  );
  await tester.tap(find.byKey(const ValueKey('nav-schedule')));
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// Scrolls the S05 list until [finder] is on screen (ListView is lazy).
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('S05')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('today and week strip follow store.referenceDate (MIN start)', (
    tester,
  ) async {
    await openSchedule(tester);
    expect(find.byKey(const ValueKey('S05')), findsOneWidget);
    expect(textOf(tester, 'schedule-today'), 'Hari ini · Selasa, 17 Nov 2026');
    expect(find.text('November 2026'), findsOneWidget);
    for (var day = 15; day <= 21; day++) {
      expect(find.byKey(ValueKey('schedule-day-2026-11-$day')), findsOneWidget);
    }
    expect(find.text('MIN'), findsOneWidget);
  });

  testWidgets('groups fixture agendas by WIB date with relative badge', (
    tester,
  ) async {
    await openSchedule(tester);
    expect(find.text('SEN, 16 NOV', skipOffstage: false), findsOneWidget);
    expect(find.text('SEL, 17 NOV', skipOffstage: false), findsOneWidget);
    // 17 Nov is the reference date; 16 Nov is yesterday, so no "Besok".
    expect(find.text('Hari ini', skipOffstage: false), findsOneWidget);
    expect(find.text('Lewat', skipOffstage: false), findsOneWidget);
    expect(find.text('Besok', skipOffstage: false), findsNothing);
    expect(
      find.byKey(const ValueKey('agenda-agenda-nusa'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agenda-agenda-arunika'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('10.00', skipOffstage: false), findsOneWidget);
    expect(find.text('13.00', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Nusa Digital · UI/UX Designer Intern', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('summary counts the next 7 days from the reference date', (
    tester,
  ) async {
    await openSchedule(tester);
    expect(
      textOf(tester, 'schedule-summary-title'),
      '1 agenda dalam 7 hari ke depan',
    );
    expect(
      textOf(tester, 'schedule-summary-detail'),
      '0 interview · 1 test/psikotes · terdekat hari ini 13.00 WIB',
    );
  });

  testWidgets('type filter narrows the list and keeps week counts', (
    tester,
  ) async {
    await openSchedule(tester);
    await tester.tap(find.byKey(const ValueKey('schedule-filter-interview')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('agenda-agenda-nusa'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agenda-agenda-arunika'), skipOffstage: false),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('schedule-filter-test')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('agenda-agenda-nusa'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agenda-agenda-arunika'), skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('schedule-filter-all')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('agenda-agenda-nusa'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('empty date shows Figma empty state; Semua resets', (
    tester,
  ) async {
    await openSchedule(tester);
    await tester.tap(find.byKey(const ValueKey('schedule-day-2026-11-21')));
    await tester.pumpAndSettle();
    expect(
      textOf(tester, 'schedule-summary-title'),
      'Tidak ada agenda pada Sabtu, 21 Nov',
    );
    expect(
      textOf(tester, 'schedule-summary-detail'),
      'Pilih tanggal lain atau ketuk "Semua" untuk melihat 2 agenda minggu ini.',
    );
    expect(find.text('SAB, 21 NOV', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Belum ada agenda di tanggal ini', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agenda-agenda-nusa'), skipOffstage: false),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('schedule-filter-all')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-empty'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('agenda-agenda-nusa'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('selecting a date with agenda shows only that date', (
    tester,
  ) async {
    await openSchedule(tester);
    await tester.tap(find.byKey(const ValueKey('schedule-day-2026-11-16')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('agenda-agenda-nusa'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agenda-agenda-arunika'), skipOffstage: false),
      findsNothing,
    );
    // Tapping the same date again clears the selection.
    await tester.tap(find.byKey(const ValueKey('schedule-day-2026-11-16')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('agenda-agenda-arunika'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('week navigation shifts exactly 7 days', (tester) async {
    await openSchedule(tester);
    await tester.tap(find.byKey(const ValueKey('schedule-week-next')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-day-2026-11-22')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-day-2026-11-28')),
      findsOneWidget,
    );
    expect(
      find.text('Belum ada agenda di minggu ini', skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('schedule-week-prev')));
    await tester.tap(find.byKey(const ValueKey('schedule-week-prev')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-day-2026-11-08')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-day-2026-11-14')),
      findsOneWidget,
    );
  });

  testWidgets('add button opens the Tambah Agenda sheet without saving', (
    tester,
  ) async {
    final store = JobTrailStore.demo();
    addTearDown(store.dispose);
    await openSchedule(tester, store: store);
    final before = store.agendas.length;
    await tester.tap(find.byKey(const ValueKey('schedule-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-agenda-sheet')), findsOneWidget);
    expect(find.text('Tambah Agenda Seleksi'), findsOneWidget);
    expect(find.text('Tambah agenda segera tersedia'), findsNothing);
    expect(store.agendas.length, before);
  });

  testWidgets('card opens S03 with its own application ID', (tester) async {
    await openSchedule(tester);
    await reveal(tester, find.byKey(const ValueKey('agenda-agenda-arunika')));
    await tester.tap(find.byKey(const ValueKey('agenda-agenda-arunika')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    expect(find.text('Arunika Finance'), findsOneWidget);
  });

  testWidgets('shared store mutations appear without restart', (tester) async {
    final store = JobTrailStore.demo();
    addTearDown(store.dispose);
    await openSchedule(tester, store: store);
    store.saveAgenda(
      Agenda(
        id: store.nextAgendaId(),
        applicationId: 'app-lentera',
        type: AgendaType.interview,
        scheduledAt: DateTime.parse('2026-11-19T10:00:00+07:00').toUtc(),
        locationOrLink: 'Kantor demo',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      textOf(tester, 'schedule-summary-title'),
      '2 agenda dalam 7 hari ke depan',
    );
    await reveal(tester, find.text('KAM, 19 NOV'));
    expect(
      find.text(
        'Lentera Tech · Frontend Developer Intern',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    store.deleteApplication('app-nusa');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('agenda-agenda-nusa'), skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('empty store renders week empty state safely', (tester) async {
    final store = JobTrailStore.empty();
    addTearDown(store.dispose);
    await openSchedule(tester, store: store);
    expect(
      find.text('Belum ada agenda di minggu ini', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      textOf(tester, 'schedule-summary-title'),
      '0 agenda dalam 7 hari ke depan',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at 320x640 with text scale 2 and empty date', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openSchedule(tester, size: const Size(320, 640));
    await reveal(tester, find.byKey(const ValueKey('schedule-day-2026-11-21')));
    await tester.tap(find.byKey(const ValueKey('schedule-day-2026-11-21')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('S05')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('past agendas stay visible, dimmed, with a Lewat badge', (
    tester,
  ) async {
    await openSchedule(tester);
    // Nusa 16 Nov WIB < referenceDate 17 Nov: shown, dimmed, badge on header.
    expect(
      find.byKey(const ValueKey('schedule-past-badge-2026-11-16')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('schedule-past-badge-2026-11-16')),
        matching: find.text('Lewat'),
      ),
      findsOneWidget,
    );
    final dimmed = tester.widget<Opacity>(
      find.byKey(
        const ValueKey('agenda-past-agenda-nusa'),
        skipOffstage: false,
      ),
    );
    expect(dimmed.opacity, lessThan(1));
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('agenda-past-agenda-nusa'),
          skipOffstage: false,
        ),
        matching: find.byKey(
          const ValueKey('agenda-agenda-nusa'),
          skipOffstage: false,
        ),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    // Today's agenda (Arunika 17 Nov) is not marked as past.
    expect(
      find.byKey(
        const ValueKey('agenda-past-agenda-arunika'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('schedule-past-badge-2026-11-17'),
        skipOffstage: false,
      ),
      findsNothing,
    );
  });

  testWidgets('same-day elapsed and boundary agendas remain actionable', (
    tester,
  ) async {
    final store = JobTrailStore.demo(
      clock: () => DateTime.utc(2026, 11, 17, 2),
    );
    addTearDown(store.dispose);
    for (final entry in [
      (1, AgendaType.test),
      (2, AgendaType.interview),
      (3, AgendaType.test),
    ]) {
      store.saveAgenda(
        Agenda(
          id: 'boundary-${entry.$1}',
          applicationId: 'app-nusa',
          type: entry.$2,
          scheduledAt: DateTime.utc(2026, 11, 17, entry.$1),
          locationOrLink: 'Demo',
        ),
      );
    }
    await openSchedule(tester, store: store);
    await reveal(tester, find.byKey(const ValueKey('agenda-boundary-1')));
    expect(
      find.byKey(const ValueKey('agenda-past-boundary-1')),
      findsOneWidget,
    );
    await reveal(tester, find.byKey(const ValueKey('agenda-boundary-2')));
    expect(find.byKey(const ValueKey('agenda-past-boundary-2')), findsNothing);
    await reveal(tester, find.byKey(const ValueKey('agenda-boundary-3')));
    expect(find.byKey(const ValueKey('agenda-past-boundary-3')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agenda-boundary-3')));
    await tester.pumpAndSettle();
    expect(find.text('Nusa Digital'), findsOneWidget);
  });

  testWidgets('past agenda in related view is still tappable to S03', (
    tester,
  ) async {
    await openSchedule(tester);
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
    await tester.tap(find.text('Agenda Terkait'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-past-badge-2026-11-16')),
      findsOneWidget,
    );
    await reveal(tester, find.byKey(const ValueKey('agenda-agenda-nusa')));
    await tester.tap(find.byKey(const ValueKey('agenda-agenda-nusa')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    expect(find.text('Nusa Digital'), findsOneWidget);
  });

  test('agenda type colors reuse GSM status tokens', () {
    expect(
      ScheduleAgendaCard.typeForeground(AgendaType.test),
      RecruitmentStatus.test.foreground,
    );
    expect(
      ScheduleAgendaCard.typeBackground(AgendaType.test),
      RecruitmentStatus.test.background,
    );
    expect(
      ScheduleAgendaCard.typeForeground(AgendaType.interview),
      RecruitmentStatus.interview.foreground,
    );
    expect(
      ScheduleAgendaCard.typeBackground(AgendaType.interview),
      RecruitmentStatus.interview.background,
    );
  });
}
