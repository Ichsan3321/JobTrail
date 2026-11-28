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

// W13-020 — all scenarios use an in-memory fake, never hosted Supabase writes.
final _reference = DateTime.utc(2026, 11, 17);
const _id = '11111111-1111-4111-8111-111111111111';

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

Application _application({
  String company = 'Lentera Tech',
  String source = 'Situs perusahaan',
}) => Application(
  id: _id,
  company: company,
  position: 'Frontend Developer Intern',
  source: source,
  appliedAt: _reference,
  status: RecruitmentStatus.applied,
  location: 'Bandung',
  workType: WorkType.hybrid,
  salary: 4500000,
  notes: 'Lamaran awal',
  documentIds: const ['cv-1', 'portfolio-1'],
);

JobTrailSnapshot _snapshot(Application app, int revision) => JobTrailSnapshot(
  referenceDate: _reference,
  referenceInstantUtc: DateTime.utc(2026, 11, 17, 2),
  applications: [app],
  agendas: const [],
  documents: const [],
  history: const [],
  applicationRevisions: {_id: revision},
);

Future<void> _openEdit(WidgetTester tester, JobTrailStore store) async {
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
                builder: (_) => ApplicationFormScreen(
                  store: store,
                  navigation: navigation,
                  applicationId: _id,
                ),
              ),
            ),
            child: const Text('Buka edit remote'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Buka edit remote'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('S04')), findsOneWidget);
}

Future<void> _changeCompany(WidgetTester tester, String name) async {
  final field = find.byType(TextFormField).first;
  await tester.ensureVisible(field);
  await tester.enterText(field, name);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Simpan Perubahan'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'W13-020: edit uses captured revision, original ID and nullable salary',
    (tester) async {
      var serverApp = _application();
      var revision = 4;
      final repository = _EditingRepository(
        () => _snapshot(serverApp, revision),
      );
      final attempts = <({String id, int revision, ApplicationDraft draft})>[];
      repository.edit = (id, expected, draft) {
        attempts.add((id: id, revision: expected, draft: draft));
        serverApp = Application.fromDraft(id, draft);
        revision = 5;
        return (id: id, revision: revision);
      };
      final store = JobTrailStore.connected(repository);
      await store.refresh();
      await _openEdit(tester, store);
      await _changeCompany(tester, 'Lentera Tech Baru');
      final salary = find.byType(TextFormField).at(3);
      await tester.ensureVisible(salary);
      await tester.enterText(salary, '');
      await tester.pump();
      await _submit(tester);

      expect(attempts, hasLength(1));
      expect(attempts.single.id, _id);
      expect(attempts.single.revision, 4);
      expect(attempts.single.draft.company, 'Lentera Tech Baru');
      expect(attempts.single.draft.source, 'Situs perusahaan');
      expect(attempts.single.draft.salary, isNull);
      expect(attempts.single.draft.documentIds, ['cv-1', 'portfolio-1']);
      expect(store.applicationRevision(_id), 5);
      expect(find.byKey(const ValueKey('S04')), findsNothing);
    },
  );

  testWidgets(
    'W13-020: revision conflict preserves draft and offers server review',
    (tester) async {
      var serverApp = _application();
      var revision = 1;
      final repository = _EditingRepository(
        () => _snapshot(serverApp, revision),
      );
      var writes = 0;
      repository.edit = (id, expected, draft) {
        writes++;
        expect(expected, 1);
        revision = 2;
        serverApp = _application(company: 'Perubahan rekan');
        throw const RepositoryFailure(RepositoryIssue.revisionConflict);
      };
      final store = JobTrailStore.connected(repository);
      await store.refresh();
      await _openEdit(tester, store);
      await _changeCompany(tester, 'Draft saya');
      await _submit(tester);

      expect(writes, 1);
      expect(find.byKey(const ValueKey('S04')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Draft saya',
      );
      expect(find.text('Periksa server'), findsOneWidget);

      await tester.tap(find.text('Periksa server'));
      await tester.pumpAndSettle();
      expect(find.text('Versi server telah berubah'), findsOneWidget);
      expect(find.textContaining('Perubahan rekan'), findsOneWidget);
      await tester.tap(find.text('Pertahankan draft'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Draft saya',
      );
      expect(writes, 1);

      await tester.tap(find.text('Periksa server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Muat versi server'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Perubahan rekan',
      );
      expect(find.text('Simpan Perubahan'), findsOneWidget);
      expect(writes, 1);
    },
  );

  testWidgets('W13-020: unknown outcome reconciles without duplicate update', (
    tester,
  ) async {
    var serverApp = _application();
    var revision = 1;
    final repository = _EditingRepository(() => _snapshot(serverApp, revision));
    var writes = 0;
    repository.edit = (id, expected, draft) {
      writes++;
      serverApp = Application.fromDraft(id, draft);
      revision = 2;
      throw const RepositoryFailure(
        RepositoryIssue.network,
        writeOutcomeUnknown: true,
      );
    };
    final store = JobTrailStore.connected(repository);
    await store.refresh();
    await _openEdit(tester, store);
    await _changeCompany(tester, 'Edit sudah masuk');
    await _submit(tester);

    expect(writes, 1);
    expect(find.text('Periksa server'), findsOneWidget);
    await tester.tap(find.text('Periksa server'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    // A matching snapshot is not proof this form received a confirmed receipt.
    expect(find.byKey(const ValueKey('S04')), findsOneWidget);
    expect(find.text('Batal'), findsOneWidget);
    expect(store.applicationById(_id)!.company, 'Edit sudah masuk');
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Edit belum terkonfirmasi'), findsOneWidget);
    await tester.tap(find.text('Kembali tanpa konfirmasi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S04')), findsNothing);
    expect(writes, 1);
  });

  testWidgets(
    'W13-020: committed edit with failed refresh never writes twice',
    (tester) async {
      var serverApp = _application();
      var revision = 1;
      var readFails = false;
      final repository = _EditingRepository(() {
        if (readFails) {
          throw const RepositoryFailure(RepositoryIssue.network);
        }
        return _snapshot(serverApp, revision);
      });
      var writes = 0;
      repository.edit = (id, expected, draft) {
        writes++;
        serverApp = Application.fromDraft(id, draft);
        revision = 2;
        readFails = true;
        return (id: id, revision: revision);
      };
      final store = JobTrailStore.connected(repository);
      await store.refresh();
      await _openEdit(tester, store);
      await _changeCompany(tester, 'Sudah disimpan');
      await _submit(tester);

      expect(writes, 1);
      expect(find.text('Muat ulang'), findsOneWidget);
      expect(find.byKey(const ValueKey('S04')), findsOneWidget);
      readFails = false;
      await tester.tap(find.text('Muat ulang'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(store.applicationRevision(_id), 2);
      expect(find.byKey(const ValueKey('S04')), findsNothing);
    },
  );
}
