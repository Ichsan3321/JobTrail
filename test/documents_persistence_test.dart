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
final _serverTimestamp = DateTime.utc(2026, 11, 25, 3);
const _saveKey = ValueKey('document-form-save');

class _DocumentRepository extends FakeJobTrailRepository {
  _DocumentRepository() : super(() => throw StateError('Set read first'));

  late FutureOr<DocumentReceipt> Function(AppDocument, SaveMode) write;
  final calls = <(AppDocument, SaveMode)>[];

  @override
  Future<DocumentReceipt> saveDocument(
    AppDocument document,
    SaveMode mode,
  ) async {
    calls.add((document, mode));
    return write(document, mode);
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

AppDocument _serverDocument(AppDocument input) => AppDocument(
  id: input.id,
  title: input.title,
  category: input.category,
  fileName: input.fileName,
  version: input.version,
  notes: input.notes,
  updatedAt: _serverTimestamp,
);

DocumentReceipt _receipt(AppDocument item, {bool replayed = false}) =>
    (id: item.id, updatedAt: _serverTimestamp, replayed: replayed);

Future<JobTrailStore> _pumpDocuments(
  WidgetTester tester,
  _DocumentRepository repo,
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

Future<void> _openCreate(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('documents-add')));
  await tester.pumpAndSettle();
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'CV Persistence');
  await tester.enterText(fields.at(1), 'cv_persistence.pdf');
  await tester.enterText(fields.at(3), 'Catatan');
}

Future<void> _save(WidgetTester tester) async {
  final button = find.byKey(_saveKey);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('remote create replays the same immutable intent after timeout', (
    tester,
  ) async {
    final repo = _DocumentRepository();
    final documents = <AppDocument>[];
    repo.read = () => _snapshot(documents);
    repo.write = (item, mode) {
      if (repo.calls.length == 1) {
        documents.add(_serverDocument(item));
        throw const RepositoryFailure(
          RepositoryIssue.network,
          writeOutcomeUnknown: true,
        );
      }
      return _receipt(item, replayed: true);
    };
    final store = await _pumpDocuments(tester, repo);
    await _openCreate(tester);
    await _save(tester);
    expect(repo.calls, hasLength(1));
    expect(
      find.textContaining('Hasil simpan belum terkonfirmasi'),
      findsOneWidget,
    );
    expect(find.text('Coba Simpan Lagi'), findsOneWidget);
    await _save(tester);
    expect(repo.calls, hasLength(2));
    expect(identical(repo.calls[0].$1, repo.calls[1].$1), isTrue);
    expect(repo.calls.map((call) => call.$2), everyElement(SaveMode.create));
    expect(store.documents, hasLength(1));
    expect(store.documents.single.updatedAt, _serverTimestamp);
    expect(find.text('CV Persistence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote edit keeps ID and uses the reconciled server timestamp', (
    tester,
  ) async {
    final repo = _DocumentRepository();
    final documents = [
      AppDocument(
        id: 'document-edit',
        title: 'CV Lama',
        category: DocumentCategory.cvResume,
        fileName: 'cv.pdf',
        version: '1.0',
        updatedAt: _instant,
      ),
    ];
    repo.read = () => _snapshot(documents);
    repo.write = (item, mode) {
      documents[0] = _serverDocument(item);
      return _receipt(item);
    };
    final store = await _pumpDocuments(tester, repo);
    await tester.tap(find.byKey(const ValueKey('document-menu-document-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit metadata'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'CV Baru');
    await _save(tester);
    expect(repo.calls.single.$2, SaveMode.update);
    expect(repo.calls.single.$1.id, 'document-edit');
    expect(store.documents.single.title, 'CV Baru');
    expect(store.documents.single.updatedAt, _serverTimestamp);
    expect(tester.takeException(), isNull);
  });

  testWidgets('committed write with failed refresh only retries reading', (
    tester,
  ) async {
    final repo = _DocumentRepository();
    final documents = <AppDocument>[];
    var failRead = false;
    repo.read = () {
      if (failRead) throw const RepositoryFailure(RepositoryIssue.network);
      return _snapshot(documents);
    };
    repo.write = (item, mode) {
      documents.add(_serverDocument(item));
      failRead = true;
      return _receipt(item);
    };
    final store = await _pumpDocuments(tester, repo);
    await _openCreate(tester);
    await _save(tester);
    expect(repo.calls, hasLength(1));
    expect(store.phase, StorePhase.error);
    expect(
      find.textContaining('Metadata sudah disimpan di server'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed, isNull);
    failRead = false;
    final refresh = find.byKey(const ValueKey('document-form-refresh'));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(repo.calls, hasLength(1));
    expect(store.documents, hasLength(1));
    expect(find.text('CV Persistence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in-flight create disables a second submit', (tester) async {
    final repo = _DocumentRepository();
    final documents = <AppDocument>[];
    final response = Completer<DocumentReceipt>();
    repo.read = () => _snapshot(documents);
    repo.write = (item, mode) => response.future;
    final store = await _pumpDocuments(tester, repo);
    await _openCreate(tester);
    final button = find.byKey(_saveKey);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(repo.calls, hasLength(1));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(button);
    await tester.pump();
    expect(repo.calls, hasLength(1));
    final item = repo.calls.single.$1;
    documents.add(_serverDocument(item));
    response.complete(_receipt(item));
    await tester.pumpAndSettle();
    expect(store.documents, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
