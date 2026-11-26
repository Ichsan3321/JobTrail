import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/recruitment_status.dart';

import 'home_persistence_test.dart' show application, snapshotAt;
import 'jobtrail_persistence_test.dart' show TestSession, mount;
import 'support/fake_jobtrail_repository.dart';

const goalKey = ValueKey('home-weekly-goal');
const fabKey = ValueKey('home-add');
const contentKey = ValueKey('home-content');
final instant = DateTime.utc(2026, 11, 26, 2);

Future<void> openStreakCard(WidgetTester tester) async {
  final goal = find.byKey(goalKey);
  await tester.ensureVisible(goal);
  await tester.pumpAndSettle();
  await tester.tap(goal);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Konsistensi mingguan'),
    120,
    scrollable: find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> expectSeparateActionLane(WidgetTester tester) async {
  final scroll = find.descendant(
    of: find.byKey(contentKey),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.text('Lamaran Terbaru'),
    160,
    scrollable: scroll,
  );
  await tester.pumpAndSettle();
  final viewport = tester.getRect(find.byKey(contentKey));
  final fab = tester.getRect(find.byKey(fabKey));
  final count = find.textContaining('Terdaftar');
  await tester.ensureVisible(count);
  expect(viewport.overlaps(fab), isFalse);
  expect(tester.getRect(count).overlaps(fab), isFalse);
  expect(count.hitTestable(), findsOneWidget);
  expect(
    tester.getRect(find.byKey(const ValueKey('nav-home'))).top,
    greaterThan(fab.bottom),
  );
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('empty streak is meaningful and keeps weekly goal at eight', (
    tester,
  ) async {
    final repo = FakeJobTrailRepository(() => snapshotAt(instant, []));
    await mount(tester, TestSession(), (_) => repo);
    expect(find.text('Streak · 0 minggu'), findsOneWidget);
    expect(find.text('0 dari 8 lamaran'), findsOneWidget);
    await openStreakCard(tester);
    expect(find.text('Belum ada aktivitas lamaran tercatat.'), findsOneWidget);
    expect(find.text('0 minggu berturut-turut'), findsOneWidget);
    expect(find.text('23/11 · Menunggu'), findsOneWidget);
  });

  testWidgets('streak refresh and account switching use their own snapshot', (
    tester,
  ) async {
    final session = TestSession();
    final first = application(1, 10, RecruitmentStatus.applied);
    final last = application(2, 17, RecruitmentStatus.applied);
    final repoA = FakeJobTrailRepository(
      () => snapshotAt(instant, [first, last]),
    );
    final repoB = FakeJobTrailRepository(() => snapshotAt(instant, []));
    await mount(tester, session, (id) => id == 'owner-a' ? repoA : repoB);
    expect(find.text('Streak · 2 minggu'), findsOneWidget);
    final semantics = tester.ensureSemantics();

    await openStreakCard(tester);
    expect(
      find.bySemanticsLabel('Minggu 02/11/2026 sampai 08/11/2026, Tidak aktif'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Minggu 09/11/2026 sampai 15/11/2026, Aktif'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Minggu 16/11/2026 sampai 22/11/2026, Aktif'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Minggu 23/11/2026 sampai 29/11/2026, Menunggu'),
      findsOneWidget,
    );
    semantics.dispose();
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    repoA.read = () => snapshotAt(instant, [last]);
    final homeScroll = find.descendant(
      of: find.byKey(contentKey),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(homeScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Buka menu akun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muat ulang data'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Muat ulang data'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Streak · 1 minggu'), findsOneWidget);
    session.changes.add(session.signedIn('owner-b'));
    await tester.pumpAndSettle();
    expect(find.text('Streak · 0 minggu'), findsOneWidget);
    expect(find.text('Streak · 1 minggu'), findsNothing);
    expect(repoA.disposed, isTrue);
  });

  testWidgets(
    '320px backend, large text and disabled FAB keep count scrollable',
    (tester) async {
      final repo = FakeJobTrailRepository(
        () => snapshotAt(instant, [
          application(1, 26, RecruitmentStatus.applied),
        ]),
      );
      await mount(tester, TestSession(), (_) => repo);
      tester.view.physicalSize = const Size(320, 852);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FloatingActionButton>(find.byKey(fabKey)).onPressed,
        isNull,
      );
      await openStreakCard(tester);
      expect(find.text('23/11 · Aktif'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();
      await expectSeparateActionLane(tester);
    },
  );

  for (final size in [
    const Size(320, 852),
    const Size(393, 852),
    const Size(1280, 900),
  ]) {
    testWidgets('enabled mock FAB leaves the recent count clear at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = JobTrailStore.demo();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        JobTrailApp(showAuthentication: false, store: store),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FloatingActionButton>(find.byKey(fabKey)).onPressed,
        isNotNull,
      );
      await expectSeparateActionLane(tester);
    });
  }
}
