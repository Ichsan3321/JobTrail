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

// PR #23 review: all tests are offline. No hosted Supabase writes.
final _date = DateTime.utc(2026, 11, 17);
const _id = '11111111-1111-4111-8111-111111111111';

Application _application({String company = 'Lentera Tech'}) => Application(
  id: _id,
  company: company,
  position: 'Frontend Developer Intern',
  source: 'LinkedIn',
  appliedAt: _date,
  status: RecruitmentStatus.applied,
  location: 'Bandung',
  workType: WorkType.onSite,
  salary: null,
);

JobTrailSnapshot _snapshot({Application? app, int revision = 1}) =>
    JobTrailSnapshot(
      referenceDate: _date,
      referenceInstantUtc: DateTime.utc(2026, 11, 17, 2),
      applications: app == null ? const [] : [app],
      agendas: const [],
      documents: const [],
      history: const [],
      applicationRevisions: app == null ? const {} : {_id: revision},
    );

class _EditingRepository extends FakeJobTrailRepository {
  _EditingRepository(super.read);

  FutureOr<ApplicationReceipt> Function(String, int, ApplicationDraft)? edit;

  @override
  Future<ApplicationReceipt> updateApplication(
    String id,
    int revision,
    ApplicationDraft draft,
  ) async {
    final handler = edit;
    if (handler == null) {
      throw const RepositoryFailure(RepositoryIssue.forbidden);
    }
    return await handler(id, revision, draft);
  }
}

class _FlakyNavigation extends AppNavigation {
  _FlakyNavigation(super.store);

  int finishCalls = 0;

  @override
  void finishForm(String savedId) {
    finishCalls++;
    if (finishCalls == 1) throw StateError('Simulated route failure');
    super.finishForm(savedId);
  }
}

Future<AppNavigation> _open(
  WidgetTester tester,
  JobTrailStore store, {
  bool edit = false,
  AppNavigation? navigation,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final nav = navigation ?? AppNavigation(store);
  addTearDown(nav.dispose);
  addTearDown(store.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      navigatorKey: nav.navigatorKey,
      home: Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => nav.navigatorKey.currentState!.push<String>(
              MaterialPageRoute<String>(
                builder: (_) => ApplicationFormScreen(
                  store: store,
                  navigation: nav,
                  applicationId: edit ? _id : null,
                ),
              ),
            ),
            child: const Text('Open form'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open form'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('S04')), findsOneWidget);
  return nav;
}

Future<void> _fillCreate(WidgetTester tester) async {
  final inputs = find.byType(TextFormField);
  for (final (index, value) in [
    (0, 'Lentera Tech'),
    (1, 'Frontend Developer Intern'),
    (2, 'Bandung'),
  ]) {
    final input = inputs.at(index);
    await tester.ensureVisible(input);
    await tester.enterText(input, value);
    await tester.pump();
  }
  await tester.ensureVisible(find.text('LinkedIn'));
  await tester.tap(find.text('LinkedIn'));
  await tester.pumpAndSettle();
}

Future<void> _changeCompany(WidgetTester tester) async {
  final input = find.byType(TextFormField).first;
  await tester.ensureVisible(input);
  await tester.enterText(input, 'Edit oleh form');
  await tester.pump();
}

Future<void> _safeExit(WidgetTester tester) async {
  await tester.tap(find.text('Batal'));
  await tester.pumpAndSettle();
  expect(find.text('Kembali tanpa konfirmasi'), findsOneWidget);
  await tester.tap(find.text('Kembali tanpa konfirmasi'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('S04')), findsNothing);
  expect(find.text('Open form'), findsOneWidget);
}

void main() {
  testWidgets(
    'PR23: confirmed create receipt but saved ID absent allows safe exit',
    (tester) async {
      final repository = FakeJobTrailRepository(() => _snapshot());
      var writes = 0;
      repository.create = (id, draft) {
        writes++;
        // Receipt confirmed, but a successful snapshot does not contain this ID.
        return (id: id, revision: 1, replayed: false);
      };
      final store = JobTrailStore.connected(repository);
      await store.refresh();
      await _open(tester, store);
      await _fillCreate(tester);
      await tester.tap(find.text('Simpan Lamaran'));
      await tester.pumpAndSettle();

      expect(writes, 1);
      expect(find.text('Muat ulang'), findsOneWidget);
      expect(find.byKey(const ValueKey('S04')), findsOneWidget);
      await _safeExit(tester);
      expect(writes, 1);
    },
  );

  testWidgets(
    'PR23: confirmed edit receipt but saved ID absent allows safe exit',
    (tester) async {
      Application? server = _application();
      final repository = _EditingRepository(() => _snapshot(app: server));
      var writes = 0;
      repository.edit = (id, revision, draft) {
        writes++;
        server = null;
        return (id: id, revision: revision + 1);
      };
      final store = JobTrailStore.connected(repository);
      await store.refresh();
      await _open(tester, store, edit: true);
      await _changeCompany(tester);
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      expect(writes, 1);
      expect(find.text('Muat ulang'), findsOneWidget);
      expect(find.byKey(const ValueKey('S04')), findsOneWidget);
      await _safeExit(tester);
      expect(writes, 1);
    },
  );

  for (final issue in [
    RepositoryIssue.revisionConflict,
    RepositoryIssue.network,
  ]) {
    testWidgets('PR23: identical payload after $issue never implies receipt', (
      tester,
    ) async {
      var server = _application();
      var revision = 1;
      final repository = _EditingRepository(
        () => _snapshot(app: server, revision: revision),
      );
      var writes = 0;
      repository.edit = (id, expected, draft) {
        writes++;
        server = Application.fromDraft(id, draft);
        revision++;
        throw RepositoryFailure(
          issue,
          writeOutcomeUnknown: issue == RepositoryIssue.network,
        );
      };
      final store = JobTrailStore.connected(repository);
      await store.refresh();
      await _open(tester, store, edit: true);
      await _changeCompany(tester);
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();
      expect(find.text('Periksa server'), findsOneWidget);
      await tester.tap(find.text('Periksa server'));
      await tester.pumpAndSettle();

      expect(writes, 1);
      expect(find.byKey(const ValueKey('S04')), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);
      await _safeExit(tester);
      expect(writes, 1);
    });
  }

  testWidgets('PR23: retry callback cannot finish a different top route', (
    tester,
  ) async {
    Application? server;
    final repository = FakeJobTrailRepository(() => _snapshot(app: server));
    var writes = 0;
    repository.create = (id, draft) {
      writes++;
      server = Application.fromDraft(id, draft);
      return (id: id, revision: 1, replayed: false);
    };
    final store = JobTrailStore.connected(repository);
    await store.refresh();
    final navigation = _FlakyNavigation(store);
    await _open(tester, store, navigation: navigation);
    await _fillCreate(tester);
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();

    expect(navigation.finishCalls, 1);
    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    final retry = action.onPressed;
    navigation.navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Foreign route')),
      ),
    );
    await tester.pumpAndSettle();
    retry();
    await tester.pumpAndSettle();

    expect(navigation.finishCalls, 1);
    expect(find.text('Foreign route'), findsOneWidget);
    expect(writes, 1);
  });

  testWidgets('PR23: deferred cancel cannot pop an unrelated route', (
    tester,
  ) async {
    final repository = FakeJobTrailRepository(
      () => _snapshot(app: _application()),
    );
    final store = JobTrailStore.connected(repository);
    await store.refresh();
    final navigation = await _open(tester, store, edit: true);
    await _changeCompany(tester);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Batalkan perubahan?'), findsOneWidget);

    // Resolve dialog, then immediately cover form before its deferred pop.
    await tester.tap(find.text('Buang perubahan'));
    navigation.navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Foreign route')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Foreign route'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('S04'), skipOffstage: false),
      findsOneWidget,
    );
  });
}
