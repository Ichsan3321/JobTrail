import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/core/theme/app_theme.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/app_document.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/screens/documents/documents_screen.dart';
import 'package:jobtrail/widgets/app_shell.dart';

import 'support/fake_jobtrail_repository.dart';

final _instant = DateTime.utc(2026, 11, 25, 2);
final _document = AppDocument(
  id: 'document-delete',
  revision: 4,
  title: 'CV Delete QA',
  category: DocumentCategory.cvResume,
  fileName: 'cv_delete.pdf',
  version: '1.0',
  updatedAt: _instant,
);
const _menu = ValueKey('document-menu-document-delete');
const _refresh = ValueKey('documents-delete-refresh');

class _DeleteRepository extends FakeJobTrailRepository {
  _DeleteRepository() : super(() => throw StateError('Set read first'));

  late FutureOr<String> Function(String, int) remove;
  final calls = <(String, int)>[];

  @override
  Future<String> deleteDocument(String id, int expectedRevision) async {
    calls.add((id, expectedRevision));
    return remove(id, expectedRevision);
  }
}

JobTrailSnapshot _snapshot(
  List<AppDocument> documents, {
  List<Application> applications = const [],
}) => JobTrailSnapshot(
  referenceDate: DateTime.utc(2026, 11, 25),
  referenceInstantUtc: _instant,
  applications: applications,
  agendas: const [],
  documents: documents,
  history: const [],
  applicationRevisions: {for (final app in applications) app.id: 1},
);

Future<JobTrailStore> _pumpDocuments(
  WidgetTester tester,
  _DeleteRepository repo,
) async {
  final store = JobTrailStore.connected(repo);
  addTearDown(store.dispose);
  await store.refresh();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: DocumentsScreen(store: store)),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> _openDelete(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_menu));
  await tester.tap(find.byKey(_menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Hapus dokumen'));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('remote delete only writes after explicit confirmation', (
    tester,
  ) async {
    final repo = _DeleteRepository();
    final documents = [_document];
    repo.read = () => _snapshot(documents);
    repo.remove = (id, revision) {
      documents.removeWhere((item) => item.id == id);
      return id;
    };
    final store = await _pumpDocuments(tester, repo);
    await _openDelete(tester);
    expect(repo.calls, isEmpty);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    expect(store.documents, hasLength(1));
    await _openDelete(tester);
    await _confirm(tester);
    expect(repo.calls, [(_document.id, 4)]);
    expect(store.documents, isEmpty);
    expect(find.text('Metadata dokumen dihapus.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'delete captures revision before confirmation and never retries JT002',
    (tester) async {
      final repo = _DeleteRepository();
      final documents = [_document];
      final winner = AppDocument(
        id: _document.id,
        revision: 5,
        title: 'CV Sesi Lain',
        category: _document.category,
        fileName: _document.fileName,
        version: _document.version,
        updatedAt: _instant,
      );
      repo.read = () => _snapshot(documents);
      repo.remove = (id, revision) {
        if (revision != documents.single.revision) {
          throw const RepositoryFailure(RepositoryIssue.revisionConflict);
        }
        documents.clear();
        return id;
      };
      final store = await _pumpDocuments(tester, repo);
      await _openDelete(tester);
      documents[0] = winner;
      await store.refresh();
      await tester.pumpAndSettle();
      expect(store.documentRevision(_document.id), 5);
      expect(repo.calls, isEmpty);
      await _confirm(tester);
      expect(repo.calls, [(_document.id, 4)]);
      expect(store.documentById(_document.id), same(winner));
      expect(
        find.text(RepositoryIssue.revisionConflict.message),
        findsOneWidget,
      );
      // Only a new explicit confirmation may capture revision 5.
      await _openDelete(tester);
      expect(repo.calls, [(_document.id, 4)]);
      await _confirm(tester);
      expect(repo.calls, [(_document.id, 4), (_document.id, 5)]);
      expect(store.documents, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('connected linked document is blocked before any delete RPC', (
    tester,
  ) async {
    final repo = _DeleteRepository();
    final application = Application(
      id: 'application-linked',
      company: 'QA Company',
      position: 'Developer',
      source: 'Website perusahaan',
      appliedAt: DateTime.utc(2026, 11, 25),
      status: RecruitmentStatus.applied,
      location: 'Surabaya',
      workType: WorkType.remote,
      documentIds: [_document.id],
    );
    repo.read = () => _snapshot([_document], applications: [application]);
    final store = await _pumpDocuments(tester, repo);
    await _openDelete(tester);
    expect(find.text('Dokumen masih digunakan'), findsOneWidget);
    expect(find.textContaining('QA Company'), findsOneWidget);
    expect(find.text('Hapus dokumen?'), findsNothing);
    expect(repo.calls, isEmpty);
    await tester.tap(find.text('Mengerti'));
    await tester.pumpAndSettle();
    expect(store.documentById(_document.id), same(_document));
    expect(repo.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final succeeds in [true, false]) {
    testWidgets('late delete feedback after tab switch (success=$succeeds)', (
      tester,
    ) async {
      final repo = _DeleteRepository();
      final documents = [_document];
      final response = Completer<String>();
      repo.read = () => _snapshot(documents);
      repo.remove = (_, _) => response.future;
      final store = JobTrailStore.connected(repo);
      final navigation = AppNavigation(store);
      addTearDown(store.dispose);
      addTearDown(navigation.dispose);
      await store.refresh();
      navigation.showTab(AppTab.documents);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          navigatorKey: navigation.navigatorKey,
          home: AppShell(store: store, navigation: navigation),
        ),
      );
      await tester.pumpAndSettle();
      await _openDelete(tester);
      await _confirm(tester);
      expect(repo.calls, [(_document.id, 4)]);
      expect(store.isMutating, isTrue);
      navigation.showTab(AppTab.home);
      await tester.pumpAndSettle();
      if (succeeds) {
        documents.clear();
        response.complete(_document.id);
      } else {
        response.completeError(
          const RepositoryFailure(RepositoryIssue.network),
        );
      }
      await tester.pumpAndSettle();
      expect(navigation.selectedTab, AppTab.home);
      expect(navigation.navigatorKey.currentState!.canPop(), isFalse);
      expect(find.byType(SnackBar), findsNothing);
      expect(repo.calls, [(_document.id, 4)]);
      expect(store.documents, hasLength(succeeds ? 0 : 1));
      navigation.showTab(AppTab.documents);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.text(_document.title),
        succeeds ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('server rejects a linked document even if snapshot is stale', (
    tester,
  ) async {
    final repo = _DeleteRepository();
    repo.read = () => _snapshot([_document]);
    repo.remove = (_, _) =>
        throw const RepositoryFailure(RepositoryIssue.documentInUse);
    final store = await _pumpDocuments(tester, repo);
    await _openDelete(tester);
    await _confirm(tester);
    expect(repo.calls, [(_document.id, 4)]);
    expect(store.documentById(_document.id), same(_document));
    expect(find.text(RepositoryIssue.documentInUse.message), findsOneWidget);
    expect(find.text('Metadata dokumen dihapus.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('committed delete with failed read only retries snapshot', (
    tester,
  ) async {
    final repo = _DeleteRepository();
    final documents = [_document];
    var failRead = false;
    repo.read = () {
      if (failRead) throw const RepositoryFailure(RepositoryIssue.network);
      return _snapshot(documents);
    };
    repo.remove = (id, revision) {
      documents.clear();
      failRead = true;
      return id;
    };
    final store = await _pumpDocuments(tester, repo);
    await _openDelete(tester);
    await _confirm(tester);
    expect(repo.calls, [(_document.id, 4)]);
    expect(store.phase, StorePhase.error);
    expect(store.documentById(_document.id), isNotNull);
    expect(find.byKey(_refresh), findsOneWidget);
    expect(find.text('Metadata dokumen dihapus.'), findsNothing);
    failRead = false;
    await tester.tap(find.byKey(_refresh));
    await tester.pumpAndSettle();
    expect(repo.calls, [(_document.id, 4)]);
    expect(store.documents, isEmpty);
    expect(find.byKey(_refresh), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambiguous delete requires read before a new delete intent', (
    tester,
  ) async {
    final repo = _DeleteRepository();
    final documents = [_document];
    repo.read = () => _snapshot(documents);
    repo.remove = (id, revision) {
      if (repo.calls.length == 1) {
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      }
      documents.clear();
      return id;
    };
    final store = await _pumpDocuments(tester, repo);
    await _openDelete(tester);
    await _confirm(tester);
    expect(repo.calls, [(_document.id, 4)]);
    expect(find.byKey(_refresh), findsOneWidget);
    expect(find.text('Metadata dokumen dihapus.'), findsNothing);
    final reads = repo.reads;
    await tester.tap(find.byKey(_refresh));
    await tester.pumpAndSettle();
    expect(repo.reads, greaterThan(reads));
    expect(repo.calls, [(_document.id, 4)]);
    expect(store.documents, hasLength(1));
    await _openDelete(tester);
    expect(repo.calls, [(_document.id, 4)]);
    await _confirm(tester);
    expect(repo.calls, [(_document.id, 4), (_document.id, 4)]);
    expect(store.documents, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in-flight remote delete prevents a second delete', (
    tester,
  ) async {
    final repo = _DeleteRepository();
    final documents = [_document];
    final response = Completer<String>();
    repo.read = () => _snapshot(documents);
    repo.remove = (_, _) => response.future;
    final store = await _pumpDocuments(tester, repo);
    await _openDelete(tester);
    await _confirm(tester);
    expect(repo.calls, [(_document.id, 4)]);
    expect(store.isMutating, isTrue);
    await tester.tap(find.byKey(_menu));
    await tester.pumpAndSettle();
    expect(find.text('Hapus dokumen'), findsNothing);
    expect(find.text('Lihat metadata'), findsOneWidget);
    // Close the menu before completing the request.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    documents.clear();
    response.complete(_document.id);
    await tester.pumpAndSettle();
    expect(repo.calls, [(_document.id, 4)]);
    expect(store.documents, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
