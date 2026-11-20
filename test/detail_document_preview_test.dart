import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/app_document.dart';
import 'package:jobtrail/models/application.dart';

void main() {
  testWidgets(
    'Detail previews each linked document and follows store updates safely',
    (tester) async {
      final store = JobTrailStore.demo();
      addTearDown(store.dispose);
      await tester.pumpWidget(JobTrailApp(store: store));
      await tester.tap(find.byKey(const ValueKey('nav-board')));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('application-app-nusa'));
      await tester.scrollUntilVisible(
        card,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('S02')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('board-preview-detail')));
      await tester.pumpAndSettle();
      final app = store.applicationById('app-nusa')!;
      final cv = store.documentById('doc-cv')!;
      var changes = 0;
      void onChange() => changes++;
      store.addListener(onChange);
      addTearDown(() => store.removeListener(onChange));
      final cvButton = find.byKey(const ValueKey('detail-document-doc-cv'));
      await tester.ensureVisible(cvButton);
      await tester.tap(cvButton);
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('document-preview-sheet'));
      expect(
        find.descendant(of: sheet, matching: find.text('CV Demo')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('CV/Resume')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('v1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('cv_demo.pdf')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('Nusa Digital'), findsOneWidget);
      expect(identical(store.applicationById('app-nusa'), app), isTrue);
      expect(identical(store.documentById('doc-cv'), cv), isTrue);
      expect(changes, 0);
      final portfolioButton = find.byKey(
        const ValueKey('detail-document-doc-portfolio'),
      );
      await tester.ensureVisible(portfolioButton);
      await tester.tap(portfolioButton);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: sheet, matching: find.text('Portofolio Demo')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Portofolio')),
        findsOneWidget,
      );
      final portfolio = store.documentById('doc-portfolio')!;
      store.saveDocument(
        AppDocument(
          id: portfolio.id,
          title: 'Portfolio updated',
          category: portfolio.category,
          fileName: portfolio.fileName,
          version: '2',
          updatedAt: portfolio.updatedAt,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: sheet, matching: find.text('Portfolio updated')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('v2')),
        findsOneWidget,
      );
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('Portfolio updated · 2'), findsOneWidget);
    await tester.tap(portfolioButton);
    await tester.pumpAndSettle();
      store.updateApplication(
        app.id,
        ApplicationDraft(
          company: app.company,
          position: app.position,
          source: app.source,
          appliedAt: app.appliedAt,
          status: app.status,
          location: app.location,
          workType: app.workType,
          salary: app.salary,
          notes: app.notes,
          documentIds: ['doc-cv'],
        ),
      );
      store.deleteDocument('doc-portfolio');
      await tester.pumpAndSettle();
      expect(find.text('Dokumen tidak tersedia.'), findsOneWidget);
      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('Nusa Digital'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('detail-document-doc-portfolio')),
        findsNothing,
      );
      expect(store.applicationById('app-nusa')!.documentIds, ['doc-cv']);
    },
  );
}
