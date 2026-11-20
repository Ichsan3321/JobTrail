import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';

// S04-only regression tests. This host intentionally uses the production
// JobTrailStore and AppNavigation contracts; it does not create a second store.
// NOTE: Home observer coverage below checks shared-store notifications, not
// the final cross-screen Home UI (that remains central integration QA).
final _reference = DateTime.utc(2026, 11, 17);

JobTrailStore _emptyStore({DateTime Function()? clock}) => JobTrailStore.empty(
  referenceDate: _reference,
  clock: clock ?? () => DateTime.utc(2026, 11, 17, 2),
);

ApplicationDraft _draft({
  String company = 'Lentera Tech',
  DateTime? appliedAt,
}) => ApplicationDraft(
  company: company,
  position: 'Frontend Developer Intern',
  source: 'LinkedIn',
  appliedAt: appliedAt ?? _reference,
  status: RecruitmentStatus.applied,
  location: 'Bandung',
  workType: WorkType.hybrid,
);

Future<AppNavigation> _mount(
  WidgetTester tester,
  JobTrailStore store, {
  Size viewport = const Size(393, 852),
  double textScale = 1,
  String? editId,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final navigation = AppNavigation(store);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigation.navigatorKey,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              ListenableBuilder(
                listenable: store,
                builder: (context, _) =>
                    Text('Home total: ${store.applications.length}'),
              ),
              TextButton(
                onPressed: () => navigation.openAdd(),
                child: const Text('Buka tambah'),
              ),
              if (editId != null)
                TextButton(
                  onPressed: () => navigation.openEdit(editId),
                  child: const Text('Buka edit'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  return navigation;
}

Future<void> _openAdd(WidgetTester tester) async {
  await tester.tap(find.text('Buka tambah'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('S04')), findsOneWidget);
}

Future<void> _openEdit(WidgetTester tester) async {
  await tester.tap(find.text('Buka edit'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('S04')), findsOneWidget);
}

Future<void> _typeAt(WidgetTester tester, int index, String value) async {
  final field = find.byType(TextFormField).at(index);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> _fillRequired(WidgetTester tester) async {
  await _typeAt(tester, 0, 'Lentera Tech');
  await _typeAt(tester, 1, 'Frontend Developer Intern');
  await _typeAt(tester, 2, 'Bandung');
  final source = find.text('LinkedIn');
  await tester.ensureVisible(source);
  await tester.tap(source);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('JT-BUG-016: add updates shared store and Home observer', (
    tester,
  ) async {
    final store = _emptyStore();
    await _mount(tester, store);
    await _openAdd(tester);
    await _fillRequired(tester);

    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();
    expect(store.applications, hasLength(1));
    expect(store.applications.single.company, 'Lentera Tech');
    expect(find.text('Home total: 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('S04')), findsNothing);
  });

  testWidgets('JT-BUG-016: edit preserves existing ID', (tester) async {
    final store = _emptyStore();
    final id = store.addApplication(_draft());
    await _mount(tester, store, editId: id);
    await _openEdit(tester);
    await _typeAt(tester, 0, 'Lentera Tech Updated');

    await tester.tap(find.text('Simpan Perubahan'));
    await tester.pumpAndSettle();
    expect(store.applications, hasLength(1));
    expect(store.applicationById(id)?.company, 'Lentera Tech Updated');
    expect(store.applications.single.id, id);
  });

  testWidgets('JT-BUG-015/016: required location and salary validation', (
    tester,
  ) async {
    final store = _emptyStore();
    await _mount(tester, store);
    await _openAdd(tester);
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();
    expect(find.text('Wajib diisi.'), findsWidgets);
    expect(store.applications, isEmpty);

    await _fillRequired(tester);
    await _typeAt(tester, 2, '');
    await _typeAt(tester, 3, '12,500');
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();
    expect(find.text('Wajib diisi.'), findsWidgets);
    expect(
      find.text('Masukkan nominal rupiah tanpa tanda baca.'),
      findsOneWidget,
    );
    expect(store.applications, isEmpty);
  });

  testWidgets(
    'JT-BUG-013: rapid double submit creates exactly one application',
    (tester) async {
      final store = _emptyStore();
      await _mount(tester, store);
      await _openAdd(tester);
      await _fillRequired(tester);

      // Fire both gestures before the next frame can perform navigation.
      await tester.tap(find.text('Simpan Lamaran'));
      await tester.tap(find.text('Simpan Lamaran'));
      await tester.pumpAndSettle();
      expect(store.applications, hasLength(1));
    },
  );

  testWidgets('JT-BUG-013/016: store failure keeps inputs and unlocks retry', (
    tester,
  ) async {
    var clock = DateTime.utc(2020, 1, 1); // Invalid for demo 2026 date.
    final store = _emptyStore(clock: () => clock);
    await _mount(tester, store);
    await _openAdd(tester);
    await _fillRequired(tester);
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();

    expect(store.applications, isEmpty);
    expect(find.byKey(const ValueKey('S04')), findsOneWidget);
    expect(
      find.byType(TextFormField).first.evaluate().single.widget,
      isA<TextFormField>(),
    );
    final company = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(company.controller?.text, 'Lentera Tech');

    clock = DateTime.utc(2026, 11, 17, 2);
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();
    expect(store.applications, hasLength(1));
  });

  testWidgets('JT-BUG-016: dirty cancel confirms and retains/abandons draft', (
    tester,
  ) async {
    final store = _emptyStore();
    await _mount(tester, store);
    await _openAdd(tester);
    await _typeAt(tester, 0, 'Draft Company');

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Batalkan perubahan?'), findsOneWidget);
    await tester.tap(find.text('Lanjut mengisi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S04')), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buang perubahan'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S04')), findsNothing);
    expect(store.applications, isEmpty);
  });

  testWidgets('JT-BUG-016: old existing date is safe in picker', (
    tester,
  ) async {
    final store = _emptyStore();
    final id = store.addApplication(
      _draft(appliedAt: DateTime.utc(1995, 1, 2)),
    );
    await _mount(tester, store, editId: id);
    await _openEdit(tester);
    final datePicker = find.byKey(const ValueKey('form-date-picker'));
    // Center the field in the scrollable body so the fixed bottom action bar
    // does not intercept the tap at the edge of the test viewport.
    await Scrollable.ensureVisible(tester.element(datePicker), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(datePicker);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('JT-BUG-014: work-type targets are at least 44 px and selected', (
    tester,
  ) async {
    final store = _emptyStore();
    await _mount(tester, store);
    await _openAdd(tester);
    final semanticsHandle = tester.ensureSemantics();
    final hybrid = find.byKey(const ValueKey('work-type-hybrid'));
    await tester.ensureVisible(hybrid);
    await tester.tap(find.text('Hybrid'));
    await tester.pumpAndSettle();
    expect(tester.getSize(hybrid).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(hybrid).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    semanticsHandle.dispose();
  });

  testWidgets('JT-BUG-016: 393 and narrow enlarged-text layout can scroll', (
    tester,
  ) async {
    final store = _emptyStore();
    await _mount(tester, store, viewport: const Size(320, 640), textScale: 1.5);
    await _openAdd(tester);
    final additional = find.text('Informasi Tambahan');
    await tester.ensureVisible(additional);
    await tester.pumpAndSettle();
    expect(find.text('Simpan Lamaran'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('JT-BUG-016: document selection keeps the relationship by ID', (
    tester,
  ) async {
    final store = JobTrailStore.demo();
    // If this fails, coordinate a shared document fixture with Farhad/Ziyaad;
    // never invent a separate fake Document model inside the form.
    expect(
      store.documents,
      isNotEmpty,
      reason: 'Regression requires an approved demo document fixture.',
    );
    final document = store.documents.first;
    await _mount(tester, store);
    await _openAdd(tester);
    await _fillRequired(tester);
    final chip = find.text(document.title);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();
    expect(store.applications.last.documentIds, contains(document.id));
  });
}
