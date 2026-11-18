import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';

/// Mobile width, tall enough that every fixture card is built by the ListView.
Future<void> openBoard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const JobTrailApp());
  await tester.tap(find.byKey(const ValueKey('nav-board')));
  await tester.pumpAndSettle();
}

Finder card(String id) => find.byKey(ValueKey('application-$id'));

Future<void> tapPill(WidgetTester tester, String name) async {
  final pill = find.byKey(ValueKey('board-pill-$name'));
  await tester.ensureVisible(pill);
  await tester.pumpAndSettle();
  await tester.tap(pill);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('summary and pills count from shared store', (tester) async {
    await openBoard(tester);
    expect(find.text('3 lamaran tercatat'), findsOneWidget);
    expect(find.text('2 sedang diproses · 1 menunggu respons'), findsOneWidget);
    expect(card('app-lentera'), findsOneWidget);
    expect(card('app-nusa'), findsOneWidget);
    expect(card('app-arunika'), findsOneWidget);
  });

  testWidgets('status pill filters and Semua resets', (tester) async {
    await openBoard(tester);
    await tapPill(tester, 'interview');
    expect(card('app-nusa'), findsOneWidget);
    expect(card('app-lentera'), findsNothing);
    expect(card('app-arunika'), findsNothing);

    await tapPill(tester, 'offering');
    expect(find.byKey(const ValueKey('board-no-match')), findsOneWidget);

    await tapPill(tester, 'all');
    expect(card('app-lentera'), findsOneWidget);
  });

  testWidgets('search matches company or position', (tester) async {
    await openBoard(tester);
    await tester.enterText(
      find.byKey(const ValueKey('board-search')),
      'analyst',
    );
    await tester.pumpAndSettle();
    expect(card('app-arunika'), findsOneWidget);
    expect(card('app-nusa'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('board-search')),
      'lentera',
    );
    await tester.pumpAndSettle();
    expect(card('app-lentera'), findsOneWidget);
    expect(card('app-arunika'), findsNothing);
    expect(find.text('1 hasil untuk "lentera"'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('board-search')), 'bank');
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada lamaran yang cocok'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-reset-search')));
    await tester.pumpAndSettle();
    expect(card('app-nusa'), findsOneWidget);
    expect(find.byKey(const ValueKey('board-result-count')), findsNothing);
  });

  testWidgets('sort toggles newest and oldest by appliedAt', (tester) async {
    await openBoard(tester);
    double top(String id) => tester.getTopLeft(card(id)).dy;
    expect(top('app-lentera'), lessThan(top('app-nusa')));

    await tester.tap(find.byKey(const ValueKey('board-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terlama').last);
    await tester.pumpAndSettle();
    expect(top('app-nusa'), lessThan(top('app-lentera')));
  });

  testWidgets('agenda row and add button route to S04', (tester) async {
    await openBoard(tester);
    expect(
      find.text('Interview · 16 Nov, 10.00 WIB · Google Meet (demo)'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('board-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S04')), findsOneWidget);
  });

  testWidgets('filter sheet applies sort and source, Reset restores', (
    tester,
  ) async {
    await openBoard(tester);
    double top(String id) => tester.getTopLeft(card(id)).dy;

    await tester.tap(find.byKey(const ValueKey('board-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Filter & Urutkan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-sheet-sort-company')));
    await tester.tap(find.byKey(const ValueKey('board-sheet-apply')));
    await tester.pumpAndSettle();
    expect(top('app-arunika'), lessThan(top('app-lentera')));
    expect(top('app-lentera'), lessThan(top('app-nusa')));

    // Close discards unapplied changes.
    await tester.tap(find.byKey(const ValueKey('board-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-sheet-sort-oldest')));
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(top('app-arunika'), lessThan(top('app-lentera')));

    await tester.tap(find.byKey(const ValueKey('board-filter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('board-sheet-source-Situs perusahaan')),
    );
    await tester.tap(find.byKey(const ValueKey('board-sheet-reset')));
    await tester.tap(find.byKey(const ValueKey('board-sheet-apply')));
    await tester.pumpAndSettle();
    expect(top('app-lentera'), lessThan(top('app-arunika')));
  });

  testWidgets('card opens preview; Buka Detail opens same ID', (tester) async {
    await openBoard(tester);
    await tester.tap(card('app-nusa'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('board-preview-company')))
          .data,
      'Nusa Digital',
    );
    expect(find.text('CV Demo, Portofolio Demo'), findsOneWidget);
    expect(find.text('Agenda terakhir'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-preview-detail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
  });

  testWidgets('preview Ubah Status updates shared store', (tester) async {
    await openBoard(tester);
    await tester.tap(card('app-lentera'));
    await tester.pumpAndSettle();
    expect(find.text('Agenda berikutnya'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('board-preview-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-status-screening')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('1 sedang diproses · 0 menunggu respons'), findsNothing);
    expect(find.text('3 sedang diproses · 0 menunggu respons'), findsOneWidget);
  });
}
