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

// PR #23 follow-up review: offline connected-store widget regressions only.
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

JobTrailSnapshot _snapshot({Application? application, int revision = 1}) =>
    JobTrailSnapshot(
      referenceDate: _date,
      referenceInstantUtc: DateTime.utc(2026, 11, 17, 2),
      applications: application == null ? const [] : [application],
      agendas: const [],
      documents: const [],
      history: const [],
      applicationRevisions: application == null
          ? const {}
          : {application.id: revision},
    );

class _EditRepo extends FakeJobTrailRepository {
  _EditRepo(super.read);

  FutureOr<ApplicationReceipt> Function(String, int, ApplicationDraft)? edit;

  @override
  Future<ApplicationReceipt> updateApplication(
    String id,
    int revision,
    ApplicationDraft draft,
  ) async => await edit!(id, revision, draft);
}

Future<AppNavigation> _open(
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
  final nav = AppNavigation(store);
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
                  applicationId: editId,
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
  for (final (index, value) in [
    (0, 'Lentera Tech'),
    (1, 'Frontend Developer Intern'),
    (2, 'Bandung'),
  ]) {
    final field = find.byType(TextFormField).at(index);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pump();
  }
  await tester.ensureVisible(find.text('LinkedIn'));
  await tester.tap(find.text('LinkedIn'));
  await tester.pumpAndSettle();
}

void _cover(AppNavigation nav) {
  nav.navigatorKey.currentState!.push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Foreign route')),
    ),
  );
}

void main() {
  testWidgets('PR23 follow-up: confirmed create receipt survives route cover', (
    tester,
  ) async {
    Application? server;
    final pending = Completer<ApplicationCreateReceipt>();
    final repository = FakeJobTrailRepository(
      () => _snapshot(application: server),
    );
    String? savedId;
    ApplicationDraft? savedDraft;
    var writes = 0;
    repository.create = (id, draft) {
      writes++;
      savedId = id;
      savedDraft = draft;
      return pending.future;
    };
    final store = JobTrailStore.connected(repository);
    await store.refresh();
    final nav = await _open(tester, store);
    await _fillCreate(tester);
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pump();
    expect(writes, 1);

    _cover(nav);
    await tester.pumpAndSettle();
    server = Application.fromDraft(savedId!, savedDraft!);
    pending.complete((id: savedId!, revision: 1, replayed: false));
    await tester.pumpAndSettle();
    expect(find.text('Foreign route'), findsOneWidget);

    nav.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Lanjut'), findsOneWidget);
    expect(writes, 1);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S04')), findsNothing);
    expect(writes, 1);
    expect(store.applicationById(savedId!), isNotNull);
  });

  testWidgets('PR23 follow-up: confirmed edit receipt survives route cover', (
    tester,
  ) async {
    var server = _application();
    var revision = 4;
    final pending = Completer<ApplicationReceipt>();
    final repository = _EditRepo(
      () => _snapshot(application: server, revision: revision),
    );
    String? requestedId;
    ApplicationDraft? requestedDraft;
    var writes = 0;
    repository.edit = (id, expected, draft) {
      writes++;
      requestedId = id;
      requestedDraft = draft;
      expect(expected, 4);
      return pending.future;
    };
    final store = JobTrailStore.connected(repository);
    await store.refresh();
    final nav = await _open(tester, store, editId: _id);
    final field = find.byType(TextFormField).first;
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Edited while covered');
    await tester.tap(find.text('Simpan Perubahan'));
    await tester.pump();
    expect(writes, 1);

    _cover(nav);
    await tester.pumpAndSettle();
    server = Application.fromDraft(requestedId!, requestedDraft!);
    revision = 5;
    pending.complete((id: _id, revision: 5));
    await tester.pumpAndSettle();

    nav.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Lanjut'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S04')), findsNothing);
    expect(writes, 1);
    expect(store.applicationRevision(_id), 5);
  });

  testWidgets('PR23 follow-up: deferred save does not stay busy after cover', (
    tester,
  ) async {
    Application? server;
    final repo = FakeJobTrailRepository(() => _snapshot(application: server));
    late AppNavigation nav;
    var writes = 0;
    repo.create = (id, draft) {
      writes++;
      server = Application.fromDraft(id, draft);
      // Queue foreign coverage before S04's deferred completion callback.
      WidgetsBinding.instance.addPostFrameCallback((_) => _cover(nav));
      return (id: id, revision: 1, replayed: false);
    };
    final store = JobTrailStore.connected(repo);
    await store.refresh();
    nav = await _open(tester, store);
    await _fillCreate(tester);
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();
    expect(find.text('Foreign route'), findsOneWidget);
    expect(writes, 1);

    nav.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Menyimpan...'), findsNothing);
    expect(find.text('Lanjut'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S04')), findsNothing);
    expect(writes, 1);
  });

  testWidgets('PR23 follow-up: deferred dirty cancel keeps confirmation', (
    tester,
  ) async {
    final repo = FakeJobTrailRepository(
      () => _snapshot(application: _application()),
    );
    final store = JobTrailStore.connected(repo);
    await store.refresh();
    final nav = await _open(tester, store, editId: _id);
    final field = find.byType(TextFormField).first;
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Unsaved change');
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Batalkan perubahan?'), findsOneWidget);

    await tester.tap(find.text('Buang perubahan'));
    _cover(nav);
    await tester.pumpAndSettle();
    expect(find.text('Foreign route'), findsOneWidget);
    nav.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S04')), findsOneWidget);

    await nav.navigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Batalkan perubahan?'), findsOneWidget);
  });

  testWidgets('PR23 follow-up: frozen create ignores focused text input', (
    tester,
  ) async {
    final serverApps = <Application>[];
    final attempts = <({String id, ApplicationDraft draft})>[];
    final repo = FakeJobTrailRepository(
      () =>
          _snapshot(application: serverApps.isEmpty ? null : serverApps.single),
    );
    repo.create = (id, draft) {
      attempts.add((id: id, draft: draft));
      if (attempts.length == 1) {
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      }
      serverApps.add(Application.fromDraft(id, draft));
      return (id: id, revision: 1, replayed: true);
    };
    final store = JobTrailStore.connected(repo);
    await store.refresh();
    await _open(tester, store);
    await _fillCreate(tester);
    final company = find.byType(TextFormField).first;
    await tester.ensureVisible(company);
    await tester.showKeyboard(company);
    await tester.pump();
    final before = tester.widget<TextFormField>(company).controller!.text;
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();
    expect(find.text('Coba lagi'), findsOneWidget);

    // Input goes through the platform text channel, not controller mutation.
    tester.testTextInput.enterText('Modified while frozen');
    await tester.pump();
    expect(tester.widget<TextFormField>(company).controller!.text, before);

    final companyTextField = find.descendant(
      of: company,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(companyTextField).readOnly, isTrue);

    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(attempts, hasLength(2));
    expect(attempts[1].id, attempts[0].id);
    expect(identical(attempts[1].draft, attempts[0].draft), isTrue);
    expect(find.byKey(const ValueKey('S04')), findsNothing);
  });
}
