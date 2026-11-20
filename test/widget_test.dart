import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/widgets/app_shell.dart';
import 'package:jobtrail/widgets/bottom_navbar.dart';

import 'jobtrail_store_test.dart' show draft;

Future<void> selectTab(WidgetTester tester, String tab) async {
  await tester.tap(find.byKey(ValueKey('nav-$tab')));
  await tester.pumpAndSettle();
}

/// Board cards follow Figma height; scroll S02 until the card is visible,
/// then open its preview and tap Buka Detail.
Future<void> tapApplication(WidgetTester tester, String id) async {
  final target = find.byKey(ValueKey('application-$id'));
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('S02')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  // S02 card opens the preview sheet first; Buka Detail pushes S03.
  await tester.tap(find.byKey(const ValueKey('board-preview-detail')));
}

void main() {
  testWidgets(
    'tab headers are owned by screens and Board state survives switching',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const JobTrailApp());
      for (final entry in {
        'home': 'S01',
        'board': 'S02',
        'schedule': 'S05',
        'documents': 'S06',
        'statistics': 'S07',
      }.entries) {
        await selectTab(tester, entry.key);
        expect(find.byKey(ValueKey(entry.value)), findsOneWidget);
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(BottomNavbar), findsOneWidget);
        final nav = find.byKey(ValueKey('nav-${entry.key}'));
        final semantics = tester.widget<Semantics>(
          find.ancestor(of: nav, matching: find.byType(Semantics)).first,
        );
        expect(semantics.properties.button, isTrue);
        expect(semantics.properties.selected, isTrue);
      }
      await selectTab(tester, 'board');
      await tester.enterText(
        find.byKey(const ValueKey('board-search')),
        'Nusa',
      );
      await tester.pumpAndSettle();
      await selectTab(tester, 'home');
      await selectTab(tester, 'board');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('board-search')))
            .controller!
            .text,
        'Nusa',
      );
      expect(
        find.byKey(const ValueKey('application-app-lentera')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('application-app-nusa')),
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('S02')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.byKey(const ValueKey('application-app-nusa')),
        findsOneWidget,
      );
    },
  );
  testWidgets('primary action maintains a 48px touch target on desktop', (
    tester,
  ) async {
    await tester.pumpWidget(const JobTrailApp());
    expect(
      tester.getSize(find.byKey(const ValueKey('home-add'))).height,
      greaterThanOrEqualTo(48),
    );
  });
  testWidgets(
    'five destinations share one navbar and preserve selected tab on Back',
    (tester) async {
      await tester.pumpWidget(const JobTrailApp());
      expect(find.byKey(const ValueKey('S01')), findsOneWidget);
      for (final entry in {
        'board': 'S02',
        'schedule': 'S05',
        'documents': 'S06',
        'statistics': 'S07',
        'home': 'S01',
      }.entries) {
        await selectTab(tester, entry.key);
        expect(find.byKey(ValueKey(entry.value)), findsOneWidget);
        expect(find.byType(BottomNavbar), findsOneWidget);
      }
      await selectTab(tester, 'board');
      await tapApplication(tester, 'app-nusa');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S03')), findsOneWidget);
      expect(find.text('Nusa Digital'), findsOneWidget);
      expect(find.byType(BottomNavbar), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S02')), findsOneWidget);
      await tapApplication(tester, 'app-lentera');
      await tester.pumpAndSettle();
      expect(find.text('Lentera Tech'), findsOneWidget);
    },
  );

  testWidgets(
    'edit uses same ID and cancel restores detail; add cancel restores origin',
    (tester) async {
      await tester.pumpWidget(const JobTrailApp());
      await tester.tap(find.byKey(const ValueKey('home-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S04')), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S01')), findsOneWidget);
      await selectTab(tester, 'board');
      await tapApplication(tester, 'app-nusa');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Lamaran'));
      await tester.pumpAndSettle();
      expect(find.text('Nusa Digital'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    },
  );

  testWidgets('save contracts return add to Board and edit to live Detail', (
    tester,
  ) async {
    final store = JobTrailStore.demo();
    addTearDown(store.dispose);
    await tester.pumpWidget(JobTrailApp(store: store));
    final navigation = tester
        .widget<AppShell>(find.byType(AppShell))
        .navigation;
    await tester.tap(find.byKey(const ValueKey('home-add')));
    await tester.pumpAndSettle();
    final id = store.addApplication(draft());
    navigation.finishForm(id); // Contract test; placeholder has no save UI.
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S02')), findsOneWidget);
    navigation.openDetail(id);
    await tester.pumpAndSettle();
    navigation.openEdit(id);
    await tester.pumpAndSettle();
    store.updateApplication(id, draft(company: 'Nama Diubah'));
    navigation.finishForm(id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S03')), findsOneWidget);
    expect(find.text('Nama Diubah'), findsOneWidget);
    store.changeStatus(id, RecruitmentStatus.offering);
    await tester.pumpAndSettle();
    expect(find.text('Offering'), findsOneWidget);
    store.deleteApplication(id);
    navigation.showTab(AppTab.board);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S02')), findsOneWidget);
    expect(find.text('Nama Diubah'), findsNothing);
  });

  testWidgets('related schedule and its detail resolve application IDs', (
    tester,
  ) async {
    await tester.pumpWidget(const JobTrailApp());
    await selectTab(tester, 'board');
    await tapApplication(tester, 'app-nusa');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda Terkait'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S05')), findsOneWidget);
    expect(find.byKey(const ValueKey('agenda-agenda-arunika')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agenda-agenda-nusa')));
    await tester.pumpAndSettle();
    expect(find.text('Nusa Digital'), findsOneWidget);
  });

  testWidgets('missing detail/edit IDs fail safely', (tester) async {
    await tester.pumpWidget(const JobTrailApp());
    final navigation = tester
        .widget<AppShell>(find.byType(AppShell))
        .navigation;
    navigation.openDetail('missing');
    await tester.pumpAndSettle();
    expect(
      find.text('Lamaran tidak ditemukan. Silakan kembali.'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    navigation.openEdit('missing');
    await tester.pumpAndSettle();
    expect(
      find.text('Lamaran tidak ditemukan. Silakan kembali.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state and shared mutation propagate across tabs', (
    tester,
  ) async {
    final store = JobTrailStore.empty();
    addTearDown(store.dispose);
    await tester.pumpWidget(JobTrailApp(store: store));
    await selectTab(tester, 'board');
    expect(find.text('Belum ada lamaran.'), findsOneWidget);
    store.addApplication(draft());
    await tester.pumpAndSettle();
    expect(find.text('Demo Baru'), findsOneWidget);
    await selectTab(tester, 'home');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('home-total'))).data,
      '1',
    );
    await selectTab(tester, 'statistics');
    expect(find.text('Total: 1'), findsOneWidget);
  });

  for (final size in [
    const Size(393, 852),
    const Size(320, 640),
    const Size(1280, 800),
  ]) {
    testWidgets('shell scrolls without overflow at $size and text scale 2', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const JobTrailApp());
      for (final tab in [
        'home',
        'board',
        'schedule',
        'documents',
        'statistics',
      ]) {
        await selectTab(tester, tab);
        await tester.drag(
          find.byType(ListView).hitTestable().first,
          const Offset(0, -1200),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
