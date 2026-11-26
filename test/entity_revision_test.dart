import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/data/jobtrail_wire.dart';
import 'package:jobtrail/data/supabase_jobtrail_repository.dart';
import 'package:jobtrail/widgets/app_shell.dart';

import 'jobtrail_persistence_test.dart' show TestSession, failsWith, mount;
import 'jobtrail_repository_test.dart' show agendaId, appId, documentId, wire;
import 'support/fake_jobtrail_repository.dart';

WireObject revisionWire({int agenda = 3, int document = 4}) {
  final root = wire()..['entity_revision_version'] = 1;
  root['agendas'] = [
    <String, Object?>{
      ...JobTrailWire.rows(root, 'agendas').single,
      'revision': agenda,
    },
  ];
  root['documents'] = [
    <String, Object?>{
      ...JobTrailWire.rows(root, 'documents').single,
      'revision': document,
    },
  ];
  return root;
}

void main() {
  test(
    'versioned snapshots require positive child revisions; legacy reads do not',
    () {
      final legacy = JobTrailWire.snapshot(wire());
      expect(legacy.agendas.single.revision, isNull);
      expect(legacy.documents.single.revision, isNull);
      final current = JobTrailWire.snapshot(revisionWire());
      expect(current.agendas.single.revision, 3);
      expect(current.documents.single.revision, 4);
      expect(current.applicationRevisions[appId], 7);
      expect(() => current.agendas.clear(), throwsUnsupportedError);
      expect(() => current.documents.clear(), throwsUnsupportedError);
      expect(
        () => JobTrailWire.snapshot(revisionWire(document: 0)),
        throwsFormatException,
      );
      expect(
        () => JobTrailWire.snapshot(wire()..['entity_revision_version'] = 1),
        throwsFormatException,
      );
      expect(
        () => JobTrailWire.snapshot(
          revisionWire()..['entity_revision_version'] = 2,
        ),
        throwsFormatException,
      );
    },
  );

  test('agenda update forwards the captured revision and requires a receipt revision', () async {
    final agenda = JobTrailWire.snapshot(revisionWire(agenda: 8))
        .agendas
        .single;
    final calls = <WireObject>[];
    final repo = SupabaseJobTrailRepository((name, args) async {
      expect(name, 'jobtrail_save_agenda');
      calls.add(args);
      return {
        'id': agendaId,
        'replayed': false,
        if (calls.length == 1) 'revision': 4,
      };
    }, isActive: () => true);
    final receipt = await repo.saveAgenda(
      agenda,
      SaveMode.update,
      expectedRevision: 3,
    );
    expect(receipt, (id: agendaId, revision: 4, replayed: false));
    expect(calls.single['p_create'], isFalse);
    expect(calls.single['p_expected_revision'], 3);
    await expectLater(
      repo.saveAgenda(agenda, SaveMode.update, expectedRevision: 3),
      throwsA(
        isA<RepositoryFailure>().having(
          (error) => error.writeOutcomeUnknown,
          'unknown',
          true,
        ),
      ),
    );
  });

  test('save without a required revision fails locally and legacy create still works', () async {
    final document = JobTrailWire.snapshot(wire()).documents.single;
    final calls = <WireObject>[];
    final repo = SupabaseJobTrailRepository((name, args) async {
      expect(name, 'jobtrail_save_document');
      calls.add(args);
      return {
        'id': documentId,
        'updated_at': '2026-11-24T02:00:00Z',
        'replayed': false,
      };
    }, isActive: () => true);

    await expectLater(
      repo.saveDocument(document, SaveMode.update),
      failsWith(RepositoryIssue.validation),
    );
    await expectLater(
      repo.saveDocument(document, SaveMode.create, expectedRevision: 1),
      failsWith(RepositoryIssue.validation),
    );
    await expectLater(
      repo.deleteDocument(documentId, 0),
      failsWith(RepositoryIssue.validation),
    );
    expect(calls, isEmpty);

    final receipt = await repo.saveDocument(document, SaveMode.create);
    expect(receipt.revision, isNull);
    expect(calls.single['p_create'], isTrue);
    expect(calls.single.containsKey('p_expected_revision'), isFalse);
  });

  test(
    'document conflict reloads the account without replacing the draft intent',
    () async {
      final repo = FakeJobTrailRepository(
        () => JobTrailWire.snapshot(revisionWire()),
      );
      final store = JobTrailStore.connected(repo);
      addTearDown(store.dispose);
      await store.refresh();
      final draft = store.documentById(documentId)!;
      final captured = store.documentRevision(documentId);
      repo.read = () => JobTrailWire.snapshot(revisionWire(document: 5));
      await store.refresh();
      var writes = 0;
      repo.documentSave = (value, mode, revision) {
        writes++;
        expect(identical(draft, value), isTrue);
        expect(mode, SaveMode.update);
        expect(revision, 4);
        throw const RepositoryFailure(RepositoryIssue.revisionConflict);
      };
      await expectLater(
        store.saveDocumentRemote(
          draft,
          SaveMode.update,
          expectedRevision: captured,
        ),
        failsWith(RepositoryIssue.revisionConflict),
      );
      expect(writes, 1);
      expect(store.documentRevision(documentId), 5);
      expect(draft.revision, 4);
    },
  );

  test(
    'confirmed agenda update survives a failed read and recovery is read-only',
    () async {
      final repo = FakeJobTrailRepository(
        () => JobTrailWire.snapshot(revisionWire()),
      );
      final store = JobTrailStore.connected(repo);
      addTearDown(store.dispose);
      await store.refresh();
      var writes = 0;
      repo.agendaSave = (value, mode, revision) {
        writes++;
        expect(value.id, agendaId);
        expect(mode, SaveMode.update);
        expect(revision, 3);
        return (id: agendaId, revision: 4, replayed: false);
      };
      repo.read = () => throw const RepositoryFailure(RepositoryIssue.network);
      final result = await store.saveAgendaRemote(
        store.agendaById(agendaId)!,
        SaveMode.update,
        expectedRevision: store.agendaRevision(agendaId),
      );
      expect(result.receipt.revision, 4);
      expect(result.snapshotCurrent, isFalse);
      expect(store.agendaRevision(agendaId), 3);
      expect(store.phase, StorePhase.error);
      await expectLater(
        store.deleteAgendaRemote(agendaId, 3),
        failsWith(RepositoryIssue.busy),
      );
      repo.read = () => JobTrailWire.snapshot(revisionWire(agenda: 4));
      await store.refresh();
      expect(store.agendaRevision(agendaId), 4);
      expect(writes, 1);
    },
  );

  test(
    'ambiguous delete reconciles without issuing a second delete or a receipt',
    () async {
      final repo = FakeJobTrailRepository(
        () => JobTrailWire.snapshot(revisionWire()),
      );
      final store = JobTrailStore.connected(repo);
      addTearDown(store.dispose);
      await store.refresh();
      var writes = 0;
      repo.agendaDelete = (id, revision) {
        writes++;
        expect(id, agendaId);
        expect(revision, 3);
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      };
      repo.read = () => JobTrailWire.snapshot(revisionWire()..['agendas'] = []);
      await expectLater(
        store.deleteAgendaRemote(agendaId, 3),
        throwsA(
          isA<RepositoryFailure>().having(
            (error) => error.writeOutcomeUnknown,
            'unknown',
            true,
          ),
        ),
      );
      expect(store.agendaRevision(agendaId), isNull);
      expect(store.agendaById(agendaId), isNull);
      expect(store.applicationRevision(appId), 7);
      expect(writes, 1);
    },
  );

  testWidgets('account switch discards an old document receipt and revisions', (
    tester,
  ) async {
    final session = TestSession();
    final first = FakeJobTrailRepository(
      () => JobTrailWire.snapshot(revisionWire()),
    );
    final second = FakeJobTrailRepository(
      () => JobTrailWire.snapshot(revisionWire(document: 2)),
    );
    await mount(tester, session, (id) => id == 'owner-a' ? first : second);
    JobTrailStore visibleStore() =>
        tester.widget<AppShell>(find.byType(AppShell)).store;
    final oldStore = visibleStore();
    final pending = Completer<DocumentReceipt>();
    first.documentSave = (_, _, _) => pending.future;
    final discarded = expectLater(
      oldStore.saveDocumentRemote(
        oldStore.documentById(documentId)!,
        SaveMode.update,
        expectedRevision: 4,
      ),
      failsWith(RepositoryIssue.authentication),
    );
    session.changes.add(session.signedIn('owner-b'));
    await tester.pumpAndSettle();
    pending.complete((
      id: documentId,
      revision: 5,
      replayed: false,
      updatedAt: DateTime.utc(2026, 11, 24),
    ));
    await discarded;
    expect(first.disposed, isTrue);
    expect(oldStore.documentRevision(documentId), isNull);
    expect(visibleStore().documentRevision(documentId), 2);
  });
}
