import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/core/theme/app_theme.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/app_document.dart';
import 'package:jobtrail/screens/documents/documents_screen.dart';

import 'support/fake_jobtrail_repository.dart';

Future<void> _pump(WidgetTester tester, JobTrailStore store) async {
  addTearDown(store.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: DocumentsScreen(store: store)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('documents-add')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dirty Back confirms discard and cancel preserves draft', (
    tester,
  ) async {
    final store = JobTrailStore.empty();
    await _pump(tester, store);
    await _open(tester);
    final field = find.byType(TextFormField).first;
    await tester.enterText(field, 'CV belum disimpan');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Buang perubahan?'), findsOneWidget);
    await _tap(tester, 'Lanjut mengedit');
    expect(
      tester.widget<TextFormField>(field).controller!.text,
      'CV belum disimpan',
    );
    expect(store.documents, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _tap(tester, 'Buang perubahan');
    expect(find.text('Tambah Dokumen'), findsNothing);
    expect(store.documents, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clean form can cancel without discard confirmation', (
    tester,
  ) async {
    final store = JobTrailStore.empty();
    await _pump(tester, store);
    await _open(tester);
    await _tap(tester, 'Batal');
    expect(find.text('Tambah Dokumen'), findsNothing);
    expect(find.text('Buang perubahan?'), findsNothing);
    expect(store.documents, isEmpty);
  });

  testWidgets('category-only edit is dirty and cancel does not change store', (
    tester,
  ) async {
    final store = JobTrailStore.empty();
    store.saveDocument(
      AppDocument(
        id: 'draft-test',
        title: 'CV asli',
        category: DocumentCategory.cvResume,
        fileName: 'cv.pdf',
        version: '1.0',
        updatedAt: store.referenceInstantUtc,
      ),
    );
    await _pump(tester, store);
    await tester.tap(find.byKey(const ValueKey('document-menu-draft-test')));
    await tester.pumpAndSettle();
    await _tap(tester, 'Edit metadata');
    final category = find.byKey(const ValueKey('document-form-category'));
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portofolio').last);
    await tester.pumpAndSettle();
    await _tap(tester, 'Batal');
    expect(find.text('Buang perubahan?'), findsOneWidget);
    await _tap(tester, 'Lanjut mengedit');
    expect(
      tester.state<FormFieldState<DocumentCategory>>(category).value,
      DocumentCategory.portfolio,
    );
    await _tap(tester, 'Batal');
    await _tap(tester, 'Buang perubahan');
    expect(
      store.documentById('draft-test')!.category,
      DocumentCategory.cvResume,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dirty modal is not dismissed by tapping outside or dragging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = JobTrailStore.empty();
    await _pump(tester, store);
    await _open(tester);
    final field = find.byType(TextFormField).first;
    await tester.enterText(field, 'Draft modal');
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Tambah Dokumen'), findsOneWidget);
    await tester.drag(find.text('Tambah Dokumen'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('Tambah Dokumen'), findsOneWidget);
    expect(tester.widget<TextFormField>(field).controller!.text, 'Draft modal');
    expect(store.documents, isEmpty);
  });

  testWidgets('snapshot refresh keeps an open dirty draft without writing', (
    tester,
  ) async {
    final repo = FakeJobTrailRepository(
      () => JobTrailSnapshot(
        referenceDate: DateTime.utc(2026, 11, 25),
        referenceInstantUtc: DateTime.utc(2026, 11, 25, 3),
        applications: const [],
        agendas: const [],
        documents: const [],
        history: const [],
        applicationRevisions: const {},
      ),
    );
    final store = JobTrailStore.connected(repo);
    await store.refresh();
    await _pump(tester, store);
    await _open(tester);
    final field = find.byType(TextFormField).first;
    await tester.enterText(field, 'Draft saat refresh');
    await tester.pump();
    final reads = repo.reads;
    await store.refresh();
    await tester.pumpAndSettle();
    expect(repo.reads, reads + 1);
    expect(
      tester.widget<TextFormField>(field).controller!.text,
      'Draft saat refresh',
    );
    expect(store.documents, isEmpty);
    await _tap(tester, 'Batal');
    expect(find.text('Buang perubahan?'), findsOneWidget);
    await _tap(tester, 'Buang perubahan');
    expect(tester.takeException(), isNull);
  });
}
