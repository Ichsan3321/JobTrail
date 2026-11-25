import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/core/theme/app_theme.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/screens/application_form/application_form_screen.dart';

import 'support/fake_jobtrail_repository.dart';

// W13-022: offline route/draft QA for S04.
// Directly opens the form because AppNavigation.openAdd/openEdit remain gated
// in connected mode until the shared-route owner approves their activation.
final _referenceDate = DateTime.utc(2026, 11, 17);
const _editId = '11111111-1111-4111-8111-111111111111';

Application _existingApplication() => Application(
  id: _editId,
  company: 'Lentera Tech',
  position: 'Frontend Developer Intern',
  source: 'Situs perusahaan',
  appliedAt: _referenceDate,
  status: RecruitmentStatus.applied,
  location: 'Bandung',
  workType: WorkType.hybrid,
  salary: null,
);

JobTrailSnapshot _snapshot({List<Application> applications = const []}) =>
    JobTrailSnapshot(
      referenceDate: _referenceDate,
      referenceInstantUtc: DateTime.utc(2026, 11, 17, 2),
      applications: applications,
      agendas: const [],
      documents: const [],
      history: const [],
      applicationRevisions: {
        for (final application in applications) application.id: 1,
      },
    );

Future<JobTrailStore> _connectedStore(FakeJobTrailRepository repository) async {
  final store = JobTrailStore.connected(repository);
  await store.refresh();
  return store;
}

Future<AppNavigation> _mountAndOpen(
  WidgetTester tester,
  JobTrailStore store, {
  String? editId,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final navigation = AppNavigation(store);
  addTearDown(navigation.dispose);
  addTearDown(store.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      navigatorKey: navigation.navigatorKey,
      home: Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () {
              navigation.navigatorKey.currentState!.push<String>(
                MaterialPageRoute<String>(
                  builder: (_) => ApplicationFormScreen(
                    store: store,
                    navigation: navigation,
                    applicationId: editId,
                  ),
                ),
              );
            },
            child: const Text('Buka S04'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Buka S04'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('S04')), findsOneWidget);
  return navigation;
}

Future<void> _changeCompany(WidgetTester tester, String name) async {
  final company = find.byType(TextFormField).first;
  await tester.ensureVisible(company);
  await tester.enterText(company, name);
  await tester.pump();
}

Future<void> _completeAddForm(WidgetTester tester) async {
  await _changeCompany(tester, 'Lentera Tech');
  final position = find.byType(TextFormField).at(1);
  await tester.ensureVisible(position);
  await tester.enterText(position, 'Frontend Developer Intern');
  final location = find.byType(TextFormField).at(2);
  await tester.ensureVisible(location);
  await tester.enterText(location, 'Bandung');
  final source = find.text('LinkedIn');
  await tester.ensureVisible(source);
  await tester.tap(source);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'W13-022: dirty add cancel retains draft until discard confirmed',
    (tester) async {
      final repository = FakeJobTrailRepository(() => _snapshot());
      var writes = 0;
      repository.create = (id, draft) {
        writes++;
        return (id: id, revision: 1, replayed: false);
      };
      final store = await _connectedStore(repository);
      await _mountAndOpen(tester, store);

      await _changeCompany(tester, 'Draft belum disimpan');
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.text('Batalkan perubahan?'), findsOneWidget);

      await tester.tap(find.text('Lanjut mengisi'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S04')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Draft belum disimpan',
      );
      expect(writes, 0);

      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buang perubahan'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S04')), findsNothing);
      expect(find.text('Buka S04'), findsOneWidget);
      expect(writes, 0);
    },
  );

  testWidgets('W13-022: back navigation on dirty edit requires confirmation', (
    tester,
  ) async {
    final repository = FakeJobTrailRepository(
      () => _snapshot(applications: [_existingApplication()]),
    );
    final store = await _connectedStore(repository);
    final navigation = await _mountAndOpen(tester, store, editId: _editId);

    await _changeCompany(tester, 'Draft edit pribadi');
    await navigation.navigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Batalkan perubahan?'), findsOneWidget);

    await tester.tap(find.text('Lanjut mengisi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S04')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'Draft edit pribadi',
    );
    expect(store.applicationById(_editId)!.company, 'Lentera Tech');

    await navigation.navigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buang perubahan'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S04')), findsNothing);
    expect(store.applicationById(_editId)!.company, 'Lentera Tech');
  });

  testWidgets(
    'W13-022: pending remote create cannot cancel or mutate after route teardown',
    (tester) async {
      final repository = FakeJobTrailRepository(() => _snapshot());
      final pending = Completer<ApplicationCreateReceipt>();
      var writes = 0;
      String? requestedId;
      repository.create = (id, draft) {
        writes++;
        requestedId = id;
        return pending.future;
      };
      final store = await _connectedStore(repository);
      await _mountAndOpen(tester, store);
      await _completeAddForm(tester);

      await tester.tap(find.text('Simpan Lamaran'));
      await tester.pump();
      expect(writes, 1);
      expect(find.text('Menyimpan...'), findsOneWidget);
      final cancel = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Batal'),
      );
      expect(cancel.onPressed, isNull);

      // Simulate the authenticated navigator being torn down by a session change.
      // A late receipt must not use the dead form's BuildContext or navigate.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Sesi telah berakhir'))),
      );
      pending.complete((id: requestedId!, revision: 1, replayed: false));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sesi telah berakhir'), findsOneWidget);
      expect(find.byKey(const ValueKey('S04')), findsNothing);
      expect(writes, 1);
    },
  );
}
