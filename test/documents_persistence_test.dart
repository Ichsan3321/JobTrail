import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/core/theme/app_theme.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/app_document.dart';
import 'package:jobtrail/screens/documents/documents_screen.dart';
import 'package:jobtrail/widgets/app_shell.dart';

import 'support/fake_jobtrail_repository.dart';

final _instant = DateTime.utc(2026, 11, 25, 2);
final _serverTimestamp = DateTime.utc(2026, 11, 25, 3);
const _saveKey = ValueKey('document-form-save');

class _DocumentRepository extends FakeJobTrailRepository {
  _DocumentRepository() : super(() => throw StateError('Set read first'));

  late FutureOr<DocumentReceipt> Function(AppDocument, SaveMode, int?) write;
  final calls = <(AppDocument, SaveMode, int?)>[];

  @override
  Future<DocumentReceipt> saveDocument(
    AppDocument document,
    SaveMode mode, {
    int? expectedRevision,
  }) async {
    calls.add((document, mode, expectedRevision));
    return write(document, mode, expectedRevision);
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

AppDocument _serverDocument(AppDocument input, {int revision = 1}) =>
    AppDocument(
      id: input.id,
      title: input.title,
      category: input.category,
      fileName: input.fileName,
      version: input.version,
      notes: input.notes,
      updatedAt: _serverTimestamp,
      revision: revision,
    );

DocumentReceipt _receipt(
  AppDocument item, {
  bool replayed = false,
  int? revision = 1,
}) => (
  id: item.id,
  updatedAt: _serverTimestamp,
  replayed: replayed,
  revision: revision,
);

Future<JobTrailStore> _pumpDocuments(
  WidgetTester tester,
  _DocumentRepository repo, {
  bool exerciseDeferredMutations = false,
}) async {
  final store = JobTrailStore.connected(repo);
  addTearDown(store.dispose);
  await store.refresh();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: exerciseDeferredMutations
            ? DocumentsScreen.deferredMutationsForTesting(store: store)
            : DocumentsScreen(store: store),
      ),
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
    repo.write = (item, mode, revision) {
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
    expect(repo.calls.map((call) => call.$3), everyElement(isNull));
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
        revision: 4,
        title: 'CV Lama',
        category: DocumentCategory.cvResume,
        fileName: 'cv.pdf',
        version: '1.0',
        updatedAt: _instant,
      ),
    ];
    repo.read = () => _snapshot(documents);
    repo.write = (item, mode, revision) {
      expect(revision, 4);
      documents[0] = _serverDocument(item, revision: 5);
      return _receipt(item, revision: 5);
    };
    final store = await _pumpDocuments(
      tester,
      repo,
      exerciseDeferredMutations: true,
    );
    await tester.tap(find.byKey(const ValueKey('document-menu-document-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit metadata'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'CV Baru');
    await _save(tester);
    expect(repo.calls.single.$2, SaveMode.update);
    expect(repo.calls.single.$1.id, 'document-edit');
    expect(repo.calls.single.$3, 4);
    expect(store.documentRevision('document-edit'), 5);
    expect(store.documents.single.title, 'CV Baru');
    expect(store.documents.single.updatedAt, _serverTimestamp);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connected screen exposes read, preview and create only', (
    tester,
  ) async {
    final repo = _DocumentRepository();
    final item = AppDocument(
      id: 'document-gated',
      revision: 4,
      title: 'CV Connected',
      category: DocumentCategory.cvResume,
      fileName: 'cv.pdf',
      version: '1.0',
      updatedAt: _instant,
    );
    repo.read = () => _snapshot([item]);
    final store = await _pumpDocuments(tester, repo);
    expect(find.text(item.title), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('documents-add')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('document-menu-document-gated')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit metadata'), findsNothing);
    expect(find.text('Hapus dokumen'), findsNothing);
    await tester.tap(find.text('Lihat metadata'));
    await tester.pumpAndSettle();
    expect(find.text('Pratinjau Metadata'), findsOneWidget);
    expect(repo.calls, isEmpty);
    expect(store.documents.single, same(item));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy null revision keeps edit and delete gated even in test seam',
    (tester) async {
      final repo = _DocumentRepository();
      final item = AppDocument(
        id: 'document-legacy',
        title: 'CV Legacy',
        category: DocumentCategory.cvResume,
        fileName: 'legacy.pdf',
        version: '1.0',
        updatedAt: _instant,
      );
      repo.read = () => _snapshot([item]);
      final store = await _pumpDocuments(
        tester,
        repo,
        exerciseDeferredMutations: true,
      );
      expect(store.documentRevision(item.id), isNull);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('documents-add')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('document-menu-document-legacy')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit metadata'), findsNothing);
      expect(find.text('Hapus dokumen'), findsNothing);
      expect(find.text('Lihat metadata'), findsOneWidget);
      expect(repo.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final refreshBeforeSave in [false, true]) {
    testWidgets(
      'stale edit retains draft and reviews winner (refreshed=$refreshBeforeSave)',
      (tester) async {
        final repo = _DocumentRepository();
        final original = AppDocument(
          id: 'document-conflict',
          revision: 4,
          title: 'Portofolio Awal',
          category: DocumentCategory.portfolio,
          fileName: 'portfolio.pdf',
          version: '1.0',
          updatedAt: _instant,
        );
        // Identical payload/timestamp, different revision: a full save of the
        // same metadata still increments the server revision.
        final winner = AppDocument(
          id: original.id,
          revision: 5,
          title: refreshBeforeSave ? original.title : 'Portofolio Sesi Lain',
          category: original.category,
          fileName: original.fileName,
          version: original.version,
          updatedAt: original.updatedAt,
        );
        final documents = [original];
        repo.read = () => _snapshot(documents);
        repo.write = (item, mode, revision) {
          expect(mode, SaveMode.update);
          expect(revision, 4);
          expect(item.id, original.id);
          throw const RepositoryFailure(RepositoryIssue.revisionConflict);
        };
        final store = await _pumpDocuments(
          tester,
          repo,
          exerciseDeferredMutations: true,
        );
        await tester.tap(
          find.byKey(const ValueKey('document-menu-document-conflict')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit metadata'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'Draft Portofolio');
        await tester.enterText(fields.at(3), 'Catatan draft konflik');
        documents[0] = winner;
        if (refreshBeforeSave) {
          await store.refresh();
          await tester.pumpAndSettle();
        }
        final reads = repo.reads;
        await _save(tester);
        expect(repo.calls, hasLength(refreshBeforeSave ? 0 : 1));
        expect(repo.reads, reads + (refreshBeforeSave ? 0 : 1));
        expect(store.documentRevision(original.id), 5);
        expect(store.documentById(original.id), same(winner));
        expect(
          find.text(RepositoryIssue.revisionConflict.message),
          findsOneWidget,
        );
        final review = find.byKey(const ValueKey('document-server-review'));
        expect(tester.widget<Text>(review).data, contains(winner.title));
        expect(tester.widget<Text>(review).data, contains('Revisi server: 5'));
        expect(
          tester.widget<TextFormField>(fields.at(0)).controller!.text,
          'Draft Portofolio',
        );
        expect(
          tester.widget<TextFormField>(fields.at(3)).controller!.text,
          'Catatan draft konflik',
        );
        expect(
          tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed,
          isNull,
        );
        final refresh = find.byKey(const ValueKey('document-form-refresh'));
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(repo.calls, hasLength(refreshBeforeSave ? 0 : 1));
        expect(store.documentRevision(original.id), 5);
        expect(
          tester.widget<TextFormField>(fields.at(0)).controller!.text,
          'Draft Portofolio',
        );
        expect(
          tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // Exercise the retained (not production-enabled) update path. A successful
  // read is not an atomic revision precondition, so never retry the old intent.
  for (final failInitialRead in [false, true]) {
    testWidgets(
      'ambiguous update preserves draft and reconciles (read fails=$failInitialRead)',
      (tester) async {
        final repo = _DocumentRepository();
        final original = AppDocument(
          id: 'document-ambiguous-edit',
          revision: 4,
          title: 'CV Lama',
          category: DocumentCategory.cvResume,
          fileName: 'cv.pdf',
          version: '1.0',
          updatedAt: _instant,
        );
        final documents = [original];
        var failRead = false;
        repo.read = () {
          if (failRead) throw const RepositoryFailure(RepositoryIssue.network);
          return _snapshot(documents);
        };
        repo.write = (item, mode, revision) {
          expect(revision, 4);
          documents[0] = _serverDocument(item, revision: 5);
          failRead = failInitialRead;
          throw const RepositoryFailure(
            RepositoryIssue.network,
            writeOutcomeUnknown: true,
          );
        };
        final store = await _pumpDocuments(
          tester,
          repo,
          exerciseDeferredMutations: true,
        );
        await tester.tap(
          find.byKey(const ValueKey('document-menu-document-ambiguous-edit')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit metadata'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), ' CV Revisi ');
        await tester.enterText(fields.at(1), 'cv_revisi.pdf');
        await tester.enterText(fields.at(2), '2.0');
        await tester.enterText(fields.at(3), 'Catatan draft');
        final readsBeforeWrite = repo.reads;
        await _save(tester);
        expect(repo.calls.single.$2, SaveMode.update);
        expect(repo.calls.single.$1.id, original.id);
        expect(repo.calls.single.$3, 4);
        expect(repo.reads, readsBeforeWrite + 1);
        expect(
          find.textContaining('Hasil perubahan belum terkonfirmasi'),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed,
          isNull,
        );
        expect(
          store.documentById(original.id)!.title,
          failInitialRead ? 'CV Lama' : 'CV Revisi',
        );
        void expectDraft() {
          final values = [
            ' CV Revisi ',
            'cv_revisi.pdf',
            '2.0',
            'Catatan draft',
          ];
          for (var i = 0; i < values.length; i++) {
            expect(
              tester.widget<TextFormField>(fields.at(i)).controller!.text,
              values[i],
            );
          }
        }

        expectDraft();
        failRead = false;
        final refresh = find.byKey(const ValueKey('document-form-refresh'));
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(repo.reads, readsBeforeWrite + 2);
        expect(store.documentById(original.id)!.title, 'CV Revisi');
        expect(store.documentById(original.id)!.updatedAt, _serverTimestamp);
        expect(store.documentRevision(original.id), 5);
        expect(
          find.textContaining('Data terbaru telah dimuat'),
          findsOneWidget,
        );
        expectDraft();
        expect(
          tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed,
          isNull,
        );
        expect(repo.calls, hasLength(1));
        final cancel = find.text('Batal');
        await tester.ensureVisible(cancel);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lanjut mengedit'));
        await tester.pumpAndSettle();
        expectDraft();
        expect(repo.calls, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    repo.write = (item, mode, revision) {
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

  for (final succeeds in [true, false]) {
    testWidgets('late create feedback after tab switch (success=$succeeds)', (
      tester,
    ) async {
      final repo = _DocumentRepository();
      final documents = <AppDocument>[];
      final response = Completer<DocumentReceipt>();
      repo.read = () => _snapshot(documents);
      repo.write = (_, _, _) => response.future;
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
      await _openCreate(tester);
      final button = find.byKey(_saveKey);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(repo.calls, hasLength(1));
      expect(store.isMutating, isTrue);

      // The real navigation can close a modal while a request is pending.
      navigation.showTab(AppTab.home);
      await tester.pumpAndSettle();
      expect(find.text('Tambah Dokumen'), findsNothing);
      expect(navigation.selectedTab, AppTab.home);
      if (succeeds) {
        final item = repo.calls.single.$1;
        documents.add(_serverDocument(item));
        response.complete(_receipt(item));
      } else {
        response.completeError(
          const RepositoryFailure(RepositoryIssue.network),
        );
      }
      await tester.pumpAndSettle();
      expect(navigation.selectedTab, AppTab.home);
      expect(navigation.navigatorKey.currentState!.canPop(), isFalse);
      expect(repo.calls, hasLength(1));
      expect(store.documents, hasLength(succeeds ? 1 : 0));
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            succeeds
                ? 'Metadata dokumen ditambahkan.'
                : RepositoryIssue.network.message,
          ),
        ),
        findsNothing,
      );
      navigation.showTab(AppTab.documents);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S06')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.text('CV Persistence'),
        succeeds ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('in-flight create disables a second submit', (tester) async {
    final repo = _DocumentRepository();
    final documents = <AppDocument>[];
    final response = Completer<DocumentReceipt>();
    repo.read = () => _snapshot(documents);
    repo.write = (item, mode, revision) => response.future;
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
    expect(find.text('Metadata dokumen ditambahkan.'), findsOneWidget);
    expect(repo.calls.single.$3, isNull);
    expect(tester.takeException(), isNull);
  });
}
