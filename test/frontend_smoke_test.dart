import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/data/jobtrail_store.dart';

import 'widget_test.dart' show selectTab, tapApplication;

Future<void> typeField(WidgetTester tester, int index, String text) async {
  final field = find.byType(TextFormField).at(index);
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Board summary survives mounted viewport and text-scale changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
      await selectTab(tester, 'board');
      for (final size in [
        const Size(393, 852),
        const Size(320, 640),
        const Size(393, 852),
      ]) {
        tester.view.physicalSize = size;
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpAndSettle();
          tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byKey(const ValueKey('S02')),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('board-summary')),
            120,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('S02')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('board-summary')), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$size scale $scale');
        }
      }
    },
  );
  testWidgets('shell add edit journey updates Board Home and Statistics', (
    tester,
  ) async {
    final store = JobTrailStore.demo();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      JobTrailApp(showAuthentication: false, store: store),
    );
    expect(find.byKey(const ValueKey('S01')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();
    expect(find.text('Wajib diisi.'), findsWidgets);
    expect(store.applications.length, 3);
    await typeField(tester, 0, 'Smoke Studio');
    await typeField(tester, 1, 'Integration Intern');
    await typeField(tester, 2, 'Surabaya');
    await tester.ensureVisible(find.text('LinkedIn'));
    await tester.tap(find.text('LinkedIn'));
    await tester.tap(find.text('Simpan Lamaran'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S02')), findsOneWidget);
    final id = store.applications
        .singleWhere((app) => app.company == 'Smoke Studio')
        .id;
    expect(store.applications.length, 4);
    await tapApplication(tester, id);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Lamaran'));
    await tester.pumpAndSettle();
    await typeField(tester, 0, 'Smoke Studio Updated');
    await tester.tap(find.text('Simpan Perubahan'));
    await tester.pumpAndSettle();
    expect(find.text('Smoke Studio Updated'), findsOneWidget);
    expect(store.applicationById(id)!.company, 'Smoke Studio Updated');
    expect(store.applications.length, 4);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await selectTab(tester, 'home');
    await tester.scrollUntilVisible(find.text('Smoke Studio Updated'), 160);
    expect(find.text('Smoke Studio Updated'), findsOneWidget);
    await selectTab(tester, 'statistics');
    expect(find.text('Total: 4'), findsOneWidget);
    await tester.tap(find.text('1 Bulan Terakhir'));
    await tester.pumpAndSettle();
    expect(find.text('Total: 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (393.0, 852.0, 1.0),
    (320.0, 640.0, 1.5),
    (320.0, 640.0, 2.0),
  ]) {
    testWidgets('all screen smoke at ${scenario.$1} scale ${scenario.$3}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(scenario.$1, scenario.$2);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
      for (final tab in [
        'home',
        'board',
        'schedule',
        'documents',
        'statistics',
      ]) {
        await selectTab(tester, tab);
        expect(find.byKey(ValueKey('nav-$tab')).hitTestable(), findsOneWidget);
        final list = find.byType(ListView).hitTestable().first;
        await tester.drag(list, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
      await selectTab(tester, 'board');
      final cardTitle = find.descendant(
        of: find.byKey(const ValueKey('application-app-nusa')),
        matching: find.text('Nusa Digital'),
      );
      await tester.scrollUntilVisible(
        cardTitle,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('S02')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(cardTitle);
      await tester.pumpAndSettle();
      await tester.tap(cardTitle);
      await tester.pumpAndSettle();
      final detailAction = find.byKey(const ValueKey('board-preview-detail'));
      await tester.ensureVisible(detailAction);
      await tester.pumpAndSettle();
      await tester.tap(detailAction);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S03')), findsOneWidget);
      await tester.tap(
        find.byTooltip('Edit Lamaran').evaluate().isNotEmpty
            ? find.byTooltip('Edit Lamaran')
            : find.text('Edit Lamaran'),
      );
      await tester.pumpAndSettle();
      await typeField(
        tester,
        4,
        'Long notes for responsive QA and keyboard content reachability.',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final discard = find.text('Buang perubahan');
      await tester.ensureVisible(discard);
      await tester.tap(discard);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S03')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
