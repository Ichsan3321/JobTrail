import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/constants/app_dates.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/screens/schedule/add_agenda_sheet.dart';
import 'package:jobtrail/screens/schedule/schedule_format.dart';

// JT-BUG-012: S05 week navigation, week strip and the Tambah Agenda date
// picker are bounded to ScheduleFormat.firstDate..lastDate (1 Jan 2020 –
// 31 Des 2035). Boundary weeks are reached through store.referenceDate
// instead of tapping hundreds of times.

Finder _key(String key) => find.byKey(ValueKey(key));

/// Opens S05 with "today" set to [reference] (UTC civil date).
Future<JobTrailStore> _openAt(WidgetTester tester, DateTime reference) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = JobTrailStore.empty(referenceDate: reference);
  addTearDown(store.dispose);
  await tester.pumpWidget(JobTrailApp(store: store));
  await tester.tap(_key('nav-schedule'));
  await tester.pumpAndSettle();
  return store;
}

void _expectWeekButton(
  WidgetTester tester,
  String label, {
  required bool enabled,
}) {
  expect(
    tester.getSemantics(find.bySemanticsLabel(label)),
    isSemantics(isButton: true, hasEnabledState: true, isEnabled: enabled),
  );
  final key = label == 'Minggu sebelumnya'
      ? 'schedule-week-prev'
      : 'schedule-week-next';
  expect(tester.widget<InkResponse>(_key(key)).onTap != null, enabled);
}

/// Opens the sheet from the title button, then the date picker; both must
/// render without an initialDate assertion.
Future<void> _openSheetAndPicker(WidgetTester tester) async {
  await tester.tap(_key('schedule-add'));
  await tester.pumpAndSettle();
  expect(_key('add-agenda-sheet'), findsOneWidget);
  await tester.ensureVisible(_key('agenda-date'));
  await tester.pumpAndSettle();
  await tester.tap(_key('agenda-date'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.byType(DatePickerDialog), findsOneWidget);
  final picker = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
  final first = ScheduleFormat.firstDate;
  final last = ScheduleFormat.lastDate;
  expect(picker.firstDate, DateTime(first.year, first.month, first.day));
  expect(picker.lastDate, DateTime(last.year, last.month, last.day));
  expect(picker.initialDate!.isBefore(picker.firstDate), isFalse);
  expect(picker.initialDate!.isAfter(picker.lastDate), isFalse);
  await tester.tap(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.text('Batal'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the sheet directly with an arbitrary prefill date.
Future<void> _openSheetWithPrefill(
  WidgetTester tester,
  DateTime prefill,
) async {
  final store = await _openAt(tester, AppDates.date(2026, 11, 15));
  showAddAgendaSheet(
    tester.element(_key('S05')),
    store: store,
    initialDate: prefill,
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(_key('add-agenda-sheet'), findsOneWidget);
}

void main() {
  group('ScheduleFormat range helpers', () {
    test('bounds are 1 Jan 2020 and 31 Des 2035 (UTC civil dates)', () {
      expect(ScheduleFormat.firstDate, AppDates.date(2020, 1, 1));
      expect(ScheduleFormat.lastDate, AppDates.date(2035, 12, 31));
    });

    test('isInRange is inclusive on both bounds', () {
      expect(ScheduleFormat.isInRange(AppDates.date(2019, 12, 31)), isFalse);
      expect(ScheduleFormat.isInRange(AppDates.date(2020, 1, 1)), isTrue);
      expect(ScheduleFormat.isInRange(AppDates.date(2035, 12, 31)), isTrue);
      expect(ScheduleFormat.isInRange(AppDates.date(2036, 1, 1)), isFalse);
    });

    test('clampToRange pins out-of-range dates to the nearest bound', () {
      expect(
        ScheduleFormat.clampToRange(AppDates.date(2019, 12, 31)),
        ScheduleFormat.firstDate,
      );
      expect(
        ScheduleFormat.clampToRange(AppDates.date(2036, 1, 1)),
        ScheduleFormat.lastDate,
      );
      expect(
        ScheduleFormat.clampToRange(AppDates.date(2026, 11, 15)),
        AppDates.date(2026, 11, 15),
      );
    });
  });

  testWidgets('week containing 1 Jan 2020: prev disabled, picker opens', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openAt(tester, AppDates.date(2020, 1, 1));
    expect(_key('schedule-day-2019-12-29'), findsOneWidget);

    _expectWeekButton(tester, 'Minggu sebelumnya', enabled: false);
    _expectWeekButton(tester, 'Minggu berikutnya', enabled: true);
    await tester.tap(_key('schedule-week-prev'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_key('schedule-day-2019-12-29'), findsOneWidget);

    // Days before 1 Jan 2020 are inert and announced as disabled.
    expect(
      tester.widget<InkWell>(_key('schedule-day-2019-12-31')).onTap,
      isNull,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Selasa 31 Desember'))),
      isSemantics(isEnabled: false, isSelected: false),
    );
    await tester.tap(_key('schedule-day-2019-12-31'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tidak ada agenda pada'), findsNothing);
    expect(
      tester.widget<InkWell>(_key('schedule-day-2020-01-01')).onTap,
      isNotNull,
    );

    await _openSheetAndPicker(tester);
    handle.dispose();
  });

  testWidgets('selected 1 Jan 2020 prefills the sheet and the picker', (
    tester,
  ) async {
    await _openAt(tester, AppDates.date(2020, 1, 1));
    await tester.tap(_key('schedule-day-2020-01-01'));
    await tester.pumpAndSettle();
    await _openSheetAndPicker(tester);
    expect(find.text('Rab, 1 Jan'), findsOneWidget); // prefilled value
  });

  testWidgets('navigating back stops at the week containing 1 Jan 2020', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openAt(tester, AppDates.date(2020, 1, 5));
    _expectWeekButton(tester, 'Minggu sebelumnya', enabled: true);
    await tester.tap(_key('schedule-week-prev'));
    await tester.pumpAndSettle();
    expect(_key('schedule-day-2020-01-01'), findsOneWidget);
    _expectWeekButton(tester, 'Minggu sebelumnya', enabled: false);
    handle.dispose();
  });

  testWidgets('week containing 31 Des 2035: next disabled, picker opens', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openAt(tester, AppDates.date(2035, 12, 31));
    expect(_key('schedule-day-2036-01-05'), findsOneWidget);

    _expectWeekButton(tester, 'Minggu berikutnya', enabled: false);
    _expectWeekButton(tester, 'Minggu sebelumnya', enabled: true);
    await tester.tap(_key('schedule-week-next'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_key('schedule-day-2036-01-05'), findsOneWidget);

    expect(
      tester.widget<InkWell>(_key('schedule-day-2036-01-01')).onTap,
      isNull,
    );
    expect(
      tester.widget<InkWell>(_key('schedule-day-2035-12-31')).onTap,
      isNotNull,
    );

    await _openSheetAndPicker(tester);
    handle.dispose();
  });

  testWidgets('navigating forward stops at the week containing 31 Des 2035', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    // Sat 29 Des 2035: its week ends before the bound.
    await _openAt(tester, AppDates.date(2035, 12, 29));
    _expectWeekButton(tester, 'Minggu berikutnya', enabled: true);
    await tester.tap(_key('schedule-week-next'));
    await tester.pumpAndSettle();
    expect(_key('schedule-day-2035-12-31'), findsOneWidget);
    _expectWeekButton(tester, 'Minggu berikutnya', enabled: false);
    handle.dispose();
  });

  testWidgets('reference date outside the range still opens the picker', (
    tester,
  ) async {
    await _openAt(tester, AppDates.date(2036, 1, 3));
    await _openSheetAndPicker(tester);
  });

  for (final prefill in [
    AppDates.date(2019, 12, 31),
    AppDates.date(2036, 1, 1),
  ]) {
    testWidgets('prefill ${AppDates.formatDate(prefill)} is ignored', (
      tester,
    ) async {
      await _openSheetWithPrefill(tester, prefill);
      final shown = ScheduleFormat.fieldDate(
        prefill,
        AppDates.date(2026, 11, 15),
      );
      expect(find.text(shown), findsNothing);
      expect(
        find.descendant(
          of: _key('agenda-date'),
          matching: find.text('Pilih tanggal'),
        ),
        findsOneWidget,
      );

      // Untouched sheet is not dirty: closing needs no discard dialog.
      await tester.tap(_key('agenda-close'));
      await tester.pumpAndSettle();
      expect(_key('agenda-discard-dialog'), findsNothing);
      expect(_key('add-agenda-sheet'), findsNothing);
    });

    testWidgets(
      'prefill ${AppDates.formatDate(prefill)}: picker opens in range',
      (tester) async {
        await _openSheetWithPrefill(tester, prefill);
        await tester.ensureVisible(_key('agenda-date'));
        await tester.pumpAndSettle();
        await tester.tap(_key('agenda-date'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(DatePickerDialog), findsOneWidget);
      },
    );
  }
}
