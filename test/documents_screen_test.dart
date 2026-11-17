import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/screens/documents/documents_screen.dart';

void main() {
  testWidgets('Documents screen renders shared document metadata', (
    tester,
  ) async {
    final store = JobTrailStore.demo();
    addTearDown(store.dispose);

    await tester.pumpWidget(JobTrailApp(store: store));
    await tester.tap(find.byKey(const ValueKey('nav-documents')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('S06')), findsOneWidget);
    expect(find.text('Dokumen Saya'), findsOneWidget);
    expect(find.text('CV Demo'), findsOneWidget);
    expect(find.text('Portofolio Demo'), findsOneWidget);
    final footerNote = find.text(
      'Metadata disimpan lokal. File PDF/DOCX belum diunggah.',
    );
    // ListView lazily builds children. Scroll first so the footer enters
    // the widget tree before asserting that it is rendered.
    for (var attempt = 0; attempt < 5 && footerNote.evaluate().isEmpty; attempt++) {
      await tester.drag(
        find.byKey(const ValueKey('S06')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
    }
    expect(footerNote, findsOneWidget);
    expect(find.byType(DocumentsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search and category filter update the visible documents', (
    tester,
  ) async {
    final store = JobTrailStore.demo();
    addTearDown(store.dispose);

    await tester.pumpWidget(JobTrailApp(store: store));
    await tester.tap(find.byKey(const ValueKey('nav-documents')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('documents-search')),
      'portofolio',
    );
    await tester.pumpAndSettle();
    expect(find.text('Portofolio Demo'), findsOneWidget);
    expect(find.text('CV Demo'), findsNothing);

    await tester.tap(find.byTooltip('Hapus pencarian'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('documents-filter-cvResume')));
    await tester.pumpAndSettle();
    expect(find.text('CV Demo'), findsOneWidget);
    expect(find.text('Portofolio Demo'), findsNothing);
  });

  testWidgets('add document metadata through the form', (tester) async {
    final store = JobTrailStore.empty();
    addTearDown(store.dispose);

    await tester.pumpWidget(JobTrailApp(store: store));
    await tester.tap(find.byKey(const ValueKey('nav-documents')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('documents-add')));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'CV Product Designer');
    await tester.enterText(fields.at(1), 'cv_product_designer.pdf');
    await tester.enterText(fields.at(2), '2.0');
    await tester.enterText(fields.at(3), 'Versi terbaru');
    await tester.tap(find.byKey(const ValueKey('document-form-save')));
    await tester.pumpAndSettle();

    expect(store.documents, hasLength(1));
    expect(store.documents.single.title, 'CV Product Designer');
    expect(store.documents.single.fileName, 'cv_product_designer.pdf');
    expect(store.documents.single.notes, 'Versi terbaru');
    expect(find.text('CV Product Designer'), findsOneWidget);
  });

  testWidgets('metadata preview explains that the source file is unavailable', (
    tester,
  ) async {
    final store = JobTrailStore.demo();
    addTearDown(store.dispose);

    await tester.pumpWidget(JobTrailApp(store: store));
    await tester.tap(find.byKey(const ValueKey('nav-documents')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-card-doc-cv')));
    await tester.pumpAndSettle();

    expect(find.text('Pratinjau Metadata'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('document-preview-sheet')),
        matching: find.text('cv_demo.pdf'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Ini hanya pratinjau metadata. File PDF/DOCX belum diunggah '
        'dan belum dapat dibuka.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('edit metadata keeps its document ID', (tester) async {
    final store = JobTrailStore.demo();
    addTearDown(store.dispose);
    final originalId = store.documents.first.id;

    await tester.pumpWidget(JobTrailApp(store: store));
    await tester.tap(find.byKey(const ValueKey('nav-documents')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-menu-doc-cv')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit metadata'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'CV Farhad Final');
    await tester.tap(find.byKey(const ValueKey('document-form-save')));
    await tester.pumpAndSettle();

    expect(store.documents, hasLength(2));
    expect(store.documentById(originalId)?.title, 'CV Farhad Final');
  });

  testWidgets('document referenced by an application cannot be deleted', (
    tester,
  ) async {
    final store = JobTrailStore.demo();
    addTearDown(store.dispose);

    await tester.pumpWidget(JobTrailApp(store: store));
    await tester.tap(find.byKey(const ValueKey('nav-documents')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-menu-doc-cv')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus dokumen'));
    await tester.pumpAndSettle();

    expect(find.text('Dokumen masih digunakan'), findsOneWidget);
    expect(store.documentById('doc-cv'), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty store has a clear add-document state', (tester) async {
    final store = JobTrailStore.empty();
    addTearDown(store.dispose);

    await tester.pumpWidget(JobTrailApp(store: store));
    await tester.tap(find.byKey(const ValueKey('nav-documents')));
    await tester.pumpAndSettle();

    expect(
      find.text('Belum ada dokumen. Tambahkan metadata CV atau portofolio.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('documents-add')), findsOneWidget);
  });
}
