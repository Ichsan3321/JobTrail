import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/agenda.dart';

// DEFERRED (bukan test palsu): batas jam pada hari yang sama — mis. menolak
// agenda 08.00 pada referenceDate bila "sekarang" sudah 09.00 WIB — menunggu
// `store.now` dari Ichsan (keputusan PR #4). Saat ini sheet hanya memvalidasi
// tanggal >= appliedAt lamaran, sesuai kontrak store.saveAgenda.

const _phone = Size(393, 852);

Future<JobTrailStore> _open(
  WidgetTester tester, {
  Size size = _phone,
  JobTrailStore? store,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final s = store ?? JobTrailStore.demo();
  addTearDown(s.dispose);
  await tester.pumpWidget(JobTrailApp(store: s));
  await tester.tap(find.byKey(const ValueKey('nav-schedule')));
  await tester.pumpAndSettle();
  return s;
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tapInSheet(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(_key('schedule-add'));
  await tester.pumpAndSettle();
  expect(_key('add-agenda-sheet'), findsOneWidget);
}

Future<void> _openSheetFromEmptyState(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _key('schedule-empty-add'),
    150,
    scrollable: find.descendant(
      of: _key('S05'),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(_key('schedule-empty-add'));
  await tester.pumpAndSettle();
  expect(_key('add-agenda-sheet'), findsOneWidget);
}

Future<void> _selectApplication(WidgetTester tester, String label) async {
  await _tapInSheet(tester, 'agenda-application');
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _pickDay(WidgetTester tester, int day) async {
  await _tapInSheet(tester, 'agenda-date');
  await tester.tap(find.text('$day').last);
  await tester.tap(find.text('Pilih'));
  await tester.pumpAndSettle();
}

Future<void> _pickTime(WidgetTester tester, String hour, String minute) async {
  await _tapInSheet(tester, 'agenda-time');
  final inputs = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(inputs.at(0), hour);
  await tester.enterText(inputs.at(1), minute);
  await tester.tap(find.text('Pilih'));
  await tester.pumpAndSettle();
}

/// Fills every required field except the date (already prefilled or picked).
Future<void> _fillRest(
  WidgetTester tester, {
  String app = 'Nusa Digital — UI/UX Designer Intern',
  String type = 'interview',
  String location = 'Kantor Nusa',
}) async {
  await _selectApplication(tester, app);
  await _tapInSheet(tester, 'agenda-type-$type');
  await _pickTime(tester, '10', '00');
  await tester.ensureVisible(_key('agenda-location'));
  await tester.enterText(_key('agenda-location'), location);
  await tester.pumpAndSettle();
}

Future<void> _shiftWeek(WidgetTester tester, int delta) async {
  final key = delta > 0 ? 'schedule-week-next' : 'schedule-week-prev';
  // Week buttons sit at the top of the list; scroll back up first.
  await tester.drag(_key('S05'), const Offset(0, 3000));
  await tester.pumpAndSettle();
  for (var i = 0; i < delta.abs(); i++) {
    await tester.tap(_key(key));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('saves via pickers and shows the agenda on its WIB date', (
    tester,
  ) async {
    final store = await _open(tester);
    final before = store.agendas.length;
    await _openSheet(tester);
    await _pickDay(tester, 18);
    await _fillRest(tester);
    await tester.enterText(_key('agenda-notes'), '  Bawa portofolio  ');
    await _tapInSheet(tester, 'agenda-save');

    expect(_key('add-agenda-sheet'), findsNothing);
    expect(store.agendas.length, before + 1);
    final saved = store.agendas.last;
    expect(saved.applicationId, 'app-nusa');
    expect(saved.type, AgendaType.interview);
    // 18 Nov 10.00 WIB == 03.00 UTC.
    expect(saved.scheduledAt, DateTime.utc(2026, 11, 18, 3));
    expect(saved.locationOrLink, 'Kantor Nusa');
    expect(saved.notes, 'Bawa portofolio');

    expect(find.text('Agenda tersimpan: Rab, 18 Nov, 10.00 WIB'), findsOne);
    expect(find.text('RAB, 18 NOV', skipOffstage: false), findsOneWidget);
    expect(_key('agenda-${saved.id}'), findsOneWidget);
    // Only the new date is listed (date selected after save).
    expect(_key('agenda-agenda-arunika'), findsNothing);
  });

  testWidgets('empty required fields block saving with inline messages', (
    tester,
  ) async {
    final store = await _open(tester);
    final before = store.agendas.length;
    await _openSheet(tester);
    await _tapInSheet(tester, 'agenda-save');
    expect(_key('add-agenda-sheet'), findsOneWidget);
    expect(find.text('Pilih lamaran terkait'), findsOneWidget);
    expect(find.text('Pilih jenis agenda'), findsOneWidget);
    expect(find.text('Tanggal wajib diisi'), findsOneWidget);
    expect(find.text('Jam mulai wajib diisi'), findsOneWidget);
    expect(find.text('Tautan atau lokasi wajib diisi'), findsOneWidget);
    expect(store.agendas.length, before);

    // Whitespace-only location is still empty.
    await tester.enterText(_key('agenda-location'), '   ');
    await tester.pumpAndSettle();
    expect(find.text('Tautan atau lokasi wajib diisi'), findsOneWidget);
  });

  testWidgets('date before appliedAt is rejected inline and not saved', (
    tester,
  ) async {
    final store = await _open(tester);
    final before = store.agendas.length;
    await _shiftWeek(tester, -2); // 1–7 Nov
    await tester.tap(_key('schedule-day-2026-11-01'));
    await tester.pumpAndSettle();
    await _openSheetFromEmptyState(tester);
    expect(find.text('Min, 1 Nov 2026'), findsOneWidget); // prefilled
    // Arunika applied on 5 Nov 2026.
    await _fillRest(tester, app: 'Arunika Finance — Business Analyst Intern');
    expect(
      find.text('Tanggal tidak boleh sebelum tanggal lamaran (5 Nov 2026)'),
      findsOneWidget,
    );
    await _tapInSheet(tester, 'agenda-save');
    expect(_key('add-agenda-sheet'), findsOneWidget);
    expect(store.agendas.length, before);
  });

  testWidgets('store errors are caught and shown in Indonesian', (
    tester,
  ) async {
    final store = await _open(tester);
    await _openSheet(tester);
    await _pickDay(tester, 18);
    await _fillRest(tester);
    store.deleteApplication('app-nusa'); // removed while the sheet is open
    await tester.pumpAndSettle();
    await _tapInSheet(tester, 'agenda-save');
    expect(_key('add-agenda-sheet'), findsOneWidget);
    expect(_key('agenda-error'), findsOneWidget);
    expect(
      find.text('Lamaran terkait sudah tidak tersedia. Pilih lamaran lain.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel: dirty asks confirmation, clean closes directly', (
    tester,
  ) async {
    final store = await _open(tester);
    final before = store.agendas.length;

    await _openSheet(tester);
    await _tapInSheet(tester, 'agenda-cancel');
    expect(_key('agenda-discard-dialog'), findsNothing);
    expect(_key('add-agenda-sheet'), findsNothing);

    await _openSheet(tester);
    await _tapInSheet(tester, 'agenda-type-test');
    await _tapInSheet(tester, 'agenda-cancel');
    expect(_key('agenda-discard-dialog'), findsOneWidget);
    await tester.tap(_key('agenda-discard-keep'));
    await tester.pumpAndSettle();
    expect(_key('add-agenda-sheet'), findsOneWidget);

    // X button and barrier go through the same guard.
    await tester.tap(_key('agenda-close'));
    await tester.pumpAndSettle();
    expect(_key('agenda-discard-dialog'), findsOneWidget);
    await tester.tap(_key('agenda-discard-confirm'));
    await tester.pumpAndSettle();
    expect(_key('add-agenda-sheet'), findsNothing);
    expect(store.agendas.length, before);
  });

  testWidgets('prefilled date alone is not dirty', (tester) async {
    await _open(tester);
    await tester.tap(_key('schedule-day-2026-11-21'));
    await tester.pumpAndSettle();
    await _openSheetFromEmptyState(tester);
    expect(find.text('Sab, 21 Nov 2026'), findsOneWidget);
    await _tapInSheet(tester, 'agenda-cancel');
    expect(_key('agenda-discard-dialog'), findsNothing);
    expect(_key('add-agenda-sheet'), findsNothing);
  });

  testWidgets('Agenda Terkait prefills its application', (tester) async {
    final store = await _open(tester);
    await tester.tap(_key('nav-board'));
    await tester.pumpAndSettle();
    await tester.tap(_key('application-app-arunika'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda Terkait'));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    expect(
      find.text('Arunika Finance — Business Analyst Intern'),
      findsOneWidget,
    );
    await _pickDay(tester, 20);
    await _tapInSheet(tester, 'agenda-type-test');
    await _pickTime(tester, '08', '30');
    await tester.enterText(_key('agenda-location'), 'Zoom');
    await _tapInSheet(tester, 'agenda-save');
    expect(store.agendasFor('app-arunika').length, 2);
    expect(find.text('Agenda untuk Arunika Finance'), findsOneWidget);
  });

  testWidgets('weeks across month and year boundaries; save lands there', (
    tester,
  ) async {
    final store = await _open(tester);
    await _shiftWeek(tester, 2);
    for (final d in ['2026-11-29', '2026-11-30', '2026-12-01', '2026-12-05']) {
      expect(_key('schedule-day-$d'), findsOneWidget);
    }
    expect(find.text('Desember 2026'), findsOneWidget);
    await tester.tap(_key('schedule-day-2026-12-03'));
    await tester.pumpAndSettle();
    await _openSheetFromEmptyState(tester);
    await _fillRest(tester);
    await _tapInSheet(tester, 'agenda-save');
    expect(store.agendas.last.scheduledAt, DateTime.utc(2026, 12, 3, 3));
    expect(find.text('KAM, 3 DES', skipOffstage: false), findsOneWidget);

    await _shiftWeek(tester, 4); // 27 Des 2026 – 2 Jan 2027
    for (final d in ['2026-12-27', '2026-12-31', '2027-01-01', '2027-01-02']) {
      expect(_key('schedule-day-$d'), findsOneWidget);
    }
    await tester.tap(_key('schedule-day-2027-01-01'));
    await tester.pumpAndSettle();
    await _openSheetFromEmptyState(tester);
    expect(find.text('Jum, 1 Jan 2027'), findsOneWidget);
    await _fillRest(tester, location: 'Online');
    await _tapInSheet(tester, 'agenda-save');
    // 1 Jan 2027 10.00 WIB == 1 Jan 03.00 UTC.
    expect(store.agendas.last.scheduledAt, DateTime.utc(2027, 1, 1, 3));
    expect(find.text('JUM, 1 JAN', skipOffstage: false), findsOneWidget);
    expect(_key('schedule-day-2027-01-01'), findsOneWidget);
  });

  testWidgets('a 00.30 WIB agenda belongs to its WIB date, not UTC date', (
    tester,
  ) async {
    final store = await _open(tester);
    await _openSheet(tester);
    await _pickDay(tester, 19);
    await _selectApplication(tester, 'Nusa Digital — UI/UX Designer Intern');
    await _tapInSheet(tester, 'agenda-type-interview');
    await _pickTime(tester, '00', '30');
    await tester.enterText(_key('agenda-location'), 'Zoom');
    await _tapInSheet(tester, 'agenda-save');
    // 19 Nov 00.30 WIB == 18 Nov 17.30 UTC, shown on 19 Nov.
    expect(store.agendas.last.scheduledAt, DateTime.utc(2026, 11, 18, 17, 30));
    expect(find.text('KAM, 19 NOV', skipOffstage: false), findsOneWidget);
  });

  testWidgets('saved agenda syncs to Home Jadwal Terdekat via store', (
    tester,
  ) async {
    final store = await _open(tester);
    await tester.tap(_key('nav-home'));
    await tester.pumpAndSettle();
    expect(
      find.text('18/11/2026 10:00 WIB · Kantor Nusa', skipOffstage: false),
      findsNothing,
    );
    await tester.tap(_key('nav-schedule'));
    await tester.pumpAndSettle();

    await _openSheet(tester);
    await _pickDay(tester, 18);
    await _fillRest(tester);
    await _tapInSheet(tester, 'agenda-save');
    final saved = store.agendas.last;

    await tester.tap(_key('nav-home'));
    await tester.pumpAndSettle();
    // Home renders the store's company + WIB time + location for the agenda.
    expect(
      find.text('18/11/2026 10:00 WIB · Kantor Nusa', skipOffstage: false),
      findsOneWidget,
    );
    expect(store.applicationById(saved.applicationId)!.company, 'Nusa Digital');
    expect(find.text('Nusa Digital', skipOffstage: false), findsWidgets);
  });

  for (final width in [320.0, 360.0, 393.0]) {
    testWidgets('week strip cells are >= 44x44 and fully tappable at $width', (
      tester,
    ) async {
      await _open(tester, size: Size(width, 852));
      for (var day = 15; day <= 21; day++) {
        final cell = _key('schedule-day-2026-11-$day');
        final size = tester.getSize(cell);
        expect(size.width, greaterThanOrEqualTo(44), reason: '$day w');
        expect(size.height, greaterThanOrEqualTo(44), reason: '$day h');
      }
      // Tapping the very edge of a cell still selects that date.
      final rect = tester.getRect(_key('schedule-day-2026-11-21'));
      await tester.tapAt(rect.topLeft + const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(
        find.text('Belum ada agenda di tanggal ini', skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('day cells expose a descriptive semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester);
    expect(
      find.bySemanticsLabel('Selasa 17 November, hari ini, 1 agenda'),
      findsOneWidget,
    );
    await tester.tap(_key('schedule-day-2026-11-17'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Selasa 17 November, hari ini, 1 agenda, terpilih'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Sabtu 21 November, 0 agenda'),
      findsOneWidget,
    );
    expect(find.byTooltip('Tambah agenda'), findsOneWidget);
    expect(find.byTooltip('Minggu sebelumnya'), findsOneWidget);
    expect(find.byTooltip('Minggu berikutnya'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('sheet stays usable with keyboard open at 393x852', (
    tester,
  ) async {
    await _open(tester);
    await _openSheet(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(_key('agenda-location'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('agenda-notes'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('agenda-save'));
    await tester.pumpAndSettle();
    final save = tester.getRect(_key('agenda-save'));
    expect(save.bottom, lessThanOrEqualTo(852 - 336));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet does not overflow at 320x640 with text scale 2', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _open(tester, size: const Size(320, 640));
    await _openSheet(tester);
    await _tapInSheet(tester, 'agenda-save'); // show all errors too
    await tester.drag(_key('add-agenda-scroll'), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('no eligible application disables save and explains why', (
    tester,
  ) async {
    final store = JobTrailStore.empty();
    await _open(tester, store: store);
    await _openSheetFromEmptyState(tester);
    expect(
      find.textContaining('Belum ada lamaran berstatus Screening'),
      findsOneWidget,
    );
    final save = tester.widget<FilledButton>(_key('agenda-save'));
    expect(save.onPressed, isNull);
  });
}
