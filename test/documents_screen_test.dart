import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/theme/app_theme.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/app_document.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
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

  testWidgets('unlinked document is deleted only after confirmation', (
    tester,
  ) async {
    final store = JobTrailStore.empty();
    addTearDown(store.dispose);
    store.saveDocument(_testDocument());
    await _pumpDocuments(tester, store);
    final menu = find.byKey(const ValueKey('document-menu-doc-review'));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus dokumen'));
    await tester.pumpAndSettle();
    expect(store.documentById('doc-review'), isNotNull);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(store.documentById('doc-review'), isNotNull);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus dokumen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tester.pumpAndSettle();
    expect(store.documents, isEmpty);
    expect(find.text('CV Review'), findsNothing);
    expect(find.text('Metadata dokumen dihapus.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid metadata stays in form and never mutates store', (
    tester,
  ) async {
    final store = JobTrailStore.empty();
    addTearDown(store.dispose);
    await _pumpDocuments(tester, store);
    await tester.tap(find.byKey(const ValueKey('documents-add')));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '  ');
    await tester.enterText(fields.at(1), 'cv_review.pdf');
    await tester.enterText(fields.at(2), '  ');
    await tester.enterText(fields.at(3), 'Catatan tetap ada');
    final save = find.byKey(const ValueKey('document-form-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.documents, isEmpty);
    expect(find.text('Tambah Dokumen'), findsOneWidget);
    expect(find.text('Bagian ini wajib diisi.'), findsNWidgets(2));
    expect(
      tester.widget<TextFormField>(fields.at(1)).controller!.text,
      'cv_review.pdf',
    );
    expect(
      tester.widget<TextFormField>(fields.at(3)).controller!.text,
      'Catatan tetap ada',
    );
    await tester.enterText(fields.at(0), 'CV Review');
    await tester.enterText(fields.at(1), '  ');
    await tester.enterText(fields.at(2), '1.0');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.documents, isEmpty);
    expect(find.text('Bagian ini wajib diisi.'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(fields.at(0)).controller!.text,
      'CV Review',
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(393, 852), const Size(320, 640)]) {
    testWidgets('long metadata preview scrolls at $size and text scale 2', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);
      final notes = List.filled(
        25,
        'Catatan panjang untuk uji preview.',
      ).join(' ');
      store.saveDocument(_testDocument(notes: notes));
      for (var i = 1; i <= 9; i++) {
        store.addApplication(
          ApplicationDraft(
            company: 'Perusahaan $i',
            position: 'Posisi pengujian',
            source: 'Situs perusahaan',
            appliedAt: store.referenceDate,
            status: RecruitmentStatus.applied,
            location: 'Surabaya',
            workType: WorkType.hybrid,
            documentIds: const ['doc-review'],
          ),
        );
      }
      await _pumpDocuments(tester, store);
      final card = find.byKey(const ValueKey('document-card-doc-review'));
      final mainScroll = find.descendant(
        of: find.byKey(const ValueKey('S06')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.scrollUntilVisible(card, 180, scrollable: mainScroll);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('document-preview-sheet'));
      expect(sheet, findsOneWidget);
      expect(find.text(notes), findsOneWidget);
      expect(tester.takeException(), isNull);
      final scroll = find.descendant(
        of: find.byKey(const ValueKey('document-preview-scroll')),
        matching: find.byType(Scrollable),
      );
      final state = tester.state<ScrollableState>(scroll);
      expect(state.position.maxScrollExtent, greaterThan(0));
      final lastApplication = find.text('• Perusahaan 9 — Posisi pengujian');
      await tester.ensureVisible(lastApplication);
      await tester.pumpAndSettle();
      expect(lastApplication.hitTestable(), findsOneWidget);
      expect(state.position.pixels, greaterThan(0));
      final footer = find.descendant(
        of: sheet,
        matching: find.text(
          'Ini hanya pratinjau metadata. File PDF/DOCX belum diunggah '
          'dan belum dapat dibuka.',
        ),
      );
      await tester.ensureVisible(footer);
      await tester.pumpAndSettle();
      expect(footer.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      final close = find.byTooltip('Tutup');
      await tester.ensureVisible(close);
      await tester.pumpAndSettle();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('add button and all category targets are at least 44 x 48', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = JobTrailStore.empty();
    addTearDown(store.dispose);
    await _pumpDocuments(tester, store);
    void expectTarget(Finder finder) {
      expect(finder, findsOneWidget);
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expectTarget(find.byKey(const ValueKey('documents-add')));
    for (final category in [
      'all',
      ...DocumentCategory.values.map((category) => category.name),
    ]) {
      final chip = find.byKey(ValueKey('documents-filter-$category'));
      expectTarget(find.descendant(of: chip, matching: find.byType(InkWell)));
    }
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDocuments(WidgetTester tester, JobTrailStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: DocumentsScreen(store: store)),
    ),
  );
  await tester.pumpAndSettle();
}

AppDocument _testDocument({String notes = ''}) => AppDocument(
  id: 'doc-review',
  title: 'CV Review',
  category: DocumentCategory.cvResume,
  fileName: 'cv_review.pdf',
  version: '1.0',
  updatedAt: DateTime.utc(2026, 11, 17),
  notes: notes,
);
