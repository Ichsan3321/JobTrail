import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/theme/app_theme.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/app_document.dart';
import 'package:jobtrail/screens/documents/documents_screen.dart';

import 'support/fake_jobtrail_repository.dart';

final _instant = DateTime.utc(2026, 11, 25, 2);
final _document = AppDocument(
  id: 'document-delete',
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

  late FutureOr<String> Function(String) remove;
  final calls = <String>[];

  @override
  Future<String> deleteDocument(String id) async {
    calls.add(id);
    return remove(id);
  }
}

JobTrailSnapshot _snapshot(List<AppDocument> documents) => JobTrailSnapshot(
  referenceDate: DateTime.utc(2026, 11, 25),
  referenceInstantUtc: _instant,
  applications: const [],
  agendas: const [],
  documents: documents,
  history: const [],
  applicationRevisions: const {},
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
      // Retained remote delete is exercised only in this fake test harness.
      home: Scaffold(
        body: DocumentsScreen.deferredMutationsForTesting(store: store),
      ),
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
    repo.remove = (id) {
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
    expect(repo.calls, [_document.id]);
    expect(store.documents, isEmpty);
    expect(find.text('Metadata dokumen dihapus.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server rejects a linked document even if snapshot is stale', (
    tester,
  ) async {
    final repo = _DeleteRepository();
    repo.read = () => _snapshot([_document]);
    repo.remove = (_) =>
        throw const RepositoryFailure(RepositoryIssue.documentInUse);
    final store = await _pumpDocuments(tester, repo);
    await _openDelete(tester);
    await _confirm(tester);
    expect(repo.calls, [_document.id]);
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
    repo.remove = (id) {
      documents.clear();
      failRead = true;
      return id;
    };
    final store = await _pumpDocuments(tester, repo);
    await _openDelete(tester);
    await _confirm(tester);
    expect(repo.calls, [_document.id]);
    expect(store.phase, StorePhase.error);
    expect(store.documentById(_document.id), isNotNull);
    expect(find.byKey(_refresh), findsOneWidget);
    expect(find.text('Metadata dokumen dihapus.'), findsNothing);
    failRead = false;
    await tester.tap(find.byKey(_refresh));
    await tester.pumpAndSettle();
    expect(repo.calls, [_document.id]);
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
    repo.remove = (id) {
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
    expect(repo.calls, [_document.id]);
    expect(find.byKey(_refresh), findsOneWidget);
    expect(find.text('Metadata dokumen dihapus.'), findsNothing);
    final reads = repo.reads;
    await tester.tap(find.byKey(_refresh));
    await tester.pumpAndSettle();
    expect(repo.reads, greaterThan(reads));
    expect(repo.calls, [_document.id]);
    expect(store.documents, hasLength(1));
    await _openDelete(tester);
    expect(repo.calls, [_document.id]);
    await _confirm(tester);
    expect(repo.calls, [_document.id, _document.id]);
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
    repo.remove = (_) => response.future;
    final store = await _pumpDocuments(tester, repo);
    await _openDelete(tester);
    await _confirm(tester);
    expect(repo.calls, [_document.id]);
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
    expect(repo.calls, [_document.id]);
    expect(store.documents, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
