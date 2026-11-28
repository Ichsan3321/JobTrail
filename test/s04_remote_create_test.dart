import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/core/theme/app_theme.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/screens/application_form/application_form_screen.dart';

import 'support/fake_jobtrail_repository.dart';

// W13-019: These are offline UI + store/repository integration tests.
// No Supabase credentials, hosted writes, or changes to shared architecture.
final _referenceDate = DateTime.utc(2026, 11, 17);

JobTrailSnapshot _snapshot(Iterable<Application> applications) {
  final values = applications.toList();
  return JobTrailSnapshot(
    referenceDate: _referenceDate,
    referenceInstantUtc: DateTime.utc(2026, 11, 17, 2),
    applications: values,
    agendas: const [],
    documents: const [],
    history: const [],
    applicationRevisions: {for (final application in values) application.id: 1},
  );
}

Future<JobTrailStore> _storeFor(FakeJobTrailRepository repository) async {
  final store = JobTrailStore.connected(repository);
  await store.refresh();
  expect(store.phase, StorePhase.empty);
  return store;
}

Future<void> _openForm(WidgetTester tester, JobTrailStore store) async {
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
            onPressed: () => navigation.navigatorKey.currentState!.push<String>(
              MaterialPageRoute<String>(
                builder: (_) =>
                    ApplicationFormScreen(store: store, navigation: navigation),
              ),
            ),
            child: const Text('Buka form remote'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Buka form remote'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('S04')), findsOneWidget);
}

Future<void> _enterField(WidgetTester tester, int index, String value) async {
  final target = find.byType(TextFormField).at(index);
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pump();
}

Future<void> _fillValidForm(WidgetTester tester) async {
  await _enterField(tester, 0, 'Lentera Tech');
  await _enterField(tester, 1, 'Frontend Developer Intern');
  await _enterField(tester, 2, 'Bandung');
  final linkedIn = find.text('LinkedIn');
  await tester.ensureVisible(linkedIn);
  await tester.tap(linkedIn);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Simpan Lamaran'));
  await tester.pump();
}

void main() {
  testWidgets('W13-019: pending create blocks rapid double submit', (
    tester,
  ) async {
    final serverApplications = <Application>[];
    final repository = FakeJobTrailRepository(
      () => _snapshot(serverApplications),
    );
    final pending = Completer<ApplicationCreateReceipt>();
    String? requestedId;
    ApplicationDraft? requestedDraft;
    var callCount = 0;
    repository.create = (id, draft) {
      callCount++;
      requestedId = id;
      requestedDraft = draft;
      return pending.future;
    };

    final store = await _storeFor(repository);
    await _openForm(tester, store);
    await _fillValidForm(tester);
    await _submit(tester);

    expect(callCount, 1);
    expect(find.text('Menyimpan...'), findsOneWidget);
    expect(find.byKey(const ValueKey('S04')), findsOneWidget);

    // Even a second tap against the disabled button must not send another RPC.
    await tester.tap(find.text('Menyimpan...'));
    await tester.pump();
    expect(callCount, 1);

    serverApplications.add(
      Application.fromDraft(requestedId!, requestedDraft!),
    );
    pending.complete((id: requestedId!, revision: 1, replayed: false));
    await tester.pumpAndSettle();

    expect(callCount, 1);
    expect(store.applicationById(requestedId!), isNotNull);
    expect(find.byKey(const ValueKey('S04')), findsNothing);
    expect(find.text('Buka form remote'), findsOneWidget);
  });

  testWidgets('W13-019: ambiguous timeout retries identical ID and draft', (
    tester,
  ) async {
    final serverApplications = <Application>[];
    final repository = FakeJobTrailRepository(
      () => _snapshot(serverApplications),
    );
    final attempts = <({String id, ApplicationDraft draft})>[];
    repository.create = (id, draft) {
      attempts.add((id: id, draft: draft));
      if (attempts.length == 1) {
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      }
      serverApplications.add(Application.fromDraft(id, draft));
      return (id: id, revision: 1, replayed: true);
    };

    final store = await _storeFor(repository);
    await _openForm(tester, store);
    await _fillValidForm(tester);
    await _submit(tester);
    await tester.pumpAndSettle();

    expect(attempts, hasLength(1));
    expect(find.text('Coba lagi'), findsOneWidget);
    expect(find.byKey(const ValueKey('S04')), findsOneWidget);

    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(attempts, hasLength(2));
    expect(attempts[1].id, attempts[0].id);
    expect(identical(attempts[1].draft, attempts[0].draft), isTrue);
    expect(store.applicationById(attempts[0].id), isNotNull);
    expect(store.applications, hasLength(1));
    expect(find.byKey(const ValueKey('S04')), findsNothing);
  });

  testWidgets('W13-019: committed receipt with stale snapshot only refreshes', (
    tester,
  ) async {
    final serverApplications = <Application>[];
    var failRead = false;
    final repository = FakeJobTrailRepository(() {
      if (failRead) {
        throw const RepositoryFailure(RepositoryIssue.network);
      }
      return _snapshot(serverApplications);
    });
    var callCount = 0;
    String? receiptId;
    repository.create = (id, draft) {
      callCount++;
      receiptId = id;
      serverApplications.add(Application.fromDraft(id, draft));
      failRead = true;
      return (id: id, revision: 1, replayed: false);
    };

    final store = await _storeFor(repository);
    await _openForm(tester, store);
    await _fillValidForm(tester);
    await _submit(tester);
    await tester.pumpAndSettle();

    expect(callCount, 1);
    expect(find.text('Muat ulang'), findsOneWidget);
    expect(find.byKey(const ValueKey('S04')), findsOneWidget);
    expect(store.applicationById(receiptId!), isNull);

    // A receipt is already committed: NEVER call createApplicationRemote again.
    failRead = false;
    await tester.tap(find.text('Muat ulang'));
    await tester.pumpAndSettle();

    expect(callCount, 1);
    expect(store.applicationById(receiptId!), isNotNull);
    expect(find.byKey(const ValueKey('S04')), findsNothing);
  });

  testWidgets('W13-019: definite validation rejection permits a new intent', (
    tester,
  ) async {
    final serverApplications = <Application>[];
    final repository = FakeJobTrailRepository(
      () => _snapshot(serverApplications),
    );
    final ids = <String>[];
    repository.create = (id, draft) {
      ids.add(id);
      if (ids.length == 1) {
        throw const RepositoryFailure(RepositoryIssue.validation);
      }
      serverApplications.add(Application.fromDraft(id, draft));
      return (id: id, revision: 1, replayed: false);
    };

    final store = await _storeFor(repository);
    await _openForm(tester, store);
    await _fillValidForm(tester);
    await _submit(tester);
    await tester.pumpAndSettle();

    expect(ids, hasLength(1));
    expect(find.text('Simpan Lamaran'), findsOneWidget);
    expect(find.byKey(const ValueKey('S04')), findsOneWidget);

    await _submit(tester);
    await tester.pumpAndSettle();

    expect(ids, hasLength(2));
    expect(ids[1], isNot(ids[0]));
    expect(store.applications, hasLength(1));
    expect(find.byKey(const ValueKey('S04')), findsNothing);
  });

  testWidgets('W13-019: salary above Web-safe limit is rejected', (
    tester,
  ) async {
    final repository = FakeJobTrailRepository(
      () => _snapshot(const <Application>[]),
    );

    var writes = 0;
    repository.create = (id, draft) {
      writes++;
      return (id: id, revision: 1, replayed: false);
    };

    final store = await _storeFor(repository);
    await _openForm(tester, store);
    await _fillValidForm(tester);

    await _enterField(tester, 3, '9007199254740992');
    await _submit(tester);
    await tester.pumpAndSettle();

    expect(writes, 0);
    expect(
      find.text('Nominal maksimal Rp9.007.199.254.740.991.'),
      findsOneWidget,
    );
  });
}
