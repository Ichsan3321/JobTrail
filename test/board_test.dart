import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/agenda.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';

/// Mobile width, tall enough that every fixture card is built by the ListView.
Future<void> openBoard(WidgetTester tester, {JobTrailStore? store}) async {
  tester.view.physicalSize = const Size(393, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    store == null
        ? const JobTrailApp(showAuthentication: false)
        : JobTrailApp(showAuthentication: false, store: store),
  );
  await tester.tap(find.byKey(const ValueKey('nav-board')));
  await tester.pumpAndSettle();
}

ApplicationDraft boardDraft(String company, {String source = 'Situs'}) =>
    ApplicationDraft(
      company: company,
      position: 'Intern',
      source: source,
      appliedAt: DateTime.utc(2026, 11, 10),
      status: RecruitmentStatus.interview,
      location: 'Surabaya',
      workType: WorkType.remote,
    );

/// Agenda on the demo reference date (17 Nov 2026) at [hour]:00 WIB.
Agenda sameDayAgenda(String id, String applicationId, int hour) => Agenda(
  id: id,
  applicationId: applicationId,
  type: AgendaType.interview,
  scheduledAt: DateTime.parse(
    '2026-11-17T${hour.toString().padLeft(2, '0')}:00:00+07:00',
  ).toUtc(),
  locationOrLink: 'Ruang $hour',
);

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

  group('review regressions', () {
    testWidgets('JT-BUG-001: tab screens own their headers', (tester) async {
      await openBoard(tester);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Board Lamaran'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-schedule')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const ValueKey('S01')), findsOneWidget);
    });

    testWidgets('JT-BUG-002: same-day agenda before 09:00 WIB is past', (
      tester,
    ) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);
      final id = store.addApplication(boardDraft('Pagi Studio'));
      store.saveAgenda(sameDayAgenda('ag-early', id, 8));
      store.saveAgenda(sameDayAgenda('ag-late', id, 13));
      await openBoard(tester, store: store);

      // 08:00 already passed at the 09:00 WIB reference; 13:00 is next.
      expect(
        find.text('Interview · 17 Nov, 13.00 WIB · Ruang 13'),
        findsOneWidget,
      );
      expect(find.textContaining('08.00 WIB'), findsNothing);
      await tester.tap(card(id));
      await tester.pumpAndSettle();
      expect(find.text('Agenda berikutnya'), findsOneWidget);
      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();

      // Only the past same-day agenda left: shown, labelled as last.
      store.deleteAgenda('ag-late');
      await tester.pumpAndSettle();
      expect(
        find.text('Interview · 17 Nov, 08.00 WIB · Ruang 8'),
        findsOneWidget,
      );
      await tester.tap(card(id));
      await tester.pumpAndSettle();
      expect(find.text('Agenda terakhir'), findsOneWidget);
      expect(find.text('Agenda berikutnya'), findsNothing);
    });

    testWidgets('JT-BUG-002: agenda exactly at the reference time is next', (
      tester,
    ) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);
      final id = store.addApplication(boardDraft('Tepat Waktu'));
      store.saveAgenda(sameDayAgenda('ag-nine', id, 9));
      await openBoard(tester, store: store);
      await tester.tap(card(id));
      await tester.pumpAndSettle();
      expect(find.text('Agenda berikutnya'), findsOneWidget);
    });

    testWidgets('source filter keeps only the selected source', (tester) async {
      final store = JobTrailStore.empty();
      addTearDown(store.dispose);
      final linkedIn = store.addApplication(
        boardDraft('Satu Data', source: 'LinkedIn'),
      );
      final glints = store.addApplication(
        boardDraft('Dua Kreasi', source: 'Glints'),
      );
      await openBoard(tester, store: store);
      expect(card(linkedIn), findsOneWidget);
      expect(card(glints), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('board-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('board-sheet-source-LinkedIn')),
      );
      await tester.tap(find.byKey(const ValueKey('board-sheet-apply')));
      await tester.pumpAndSettle();
      expect(card(linkedIn), findsOneWidget);
      expect(card(glints), findsNothing);

      await tester.tap(find.byKey(const ValueKey('board-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('board-sheet-reset')));
      await tester.tap(find.byKey(const ValueKey('board-sheet-apply')));
      await tester.pumpAndSettle();
      expect(card(glints), findsOneWidget);
    });

    testWidgets('Home reflects a status change made on Board', (tester) async {
      await openBoard(tester);
      await tester.tap(card('app-lentera'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('board-preview-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('board-status-interview')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();
      final interviewCard = find
          .ancestor(
            of: find.textContaining('mendatang'),
            matching: find.byType(Column),
          )
          .first;
      expect(
        find.descendant(of: interviewCard, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('home-total'))).data,
        '3',
      );
    });

    testWidgets('JT-BUG-003: interactive targets are at least 48x48', (
      tester,
    ) async {
      await openBoard(tester);
      void expectTarget(Finder finder) {
        final size = tester.getSize(finder);
        expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
      }

      for (final key in [
        'board-add',
        'board-filter',
        'board-pill-all',
        'board-pill-applied',
        'board-sort',
      ]) {
        expectTarget(find.byKey(ValueKey(key)));
      }
      await tester.tap(find.byKey(const ValueKey('board-filter')));
      await tester.pumpAndSettle();
      expectTarget(
        find.byKey(const ValueKey('board-sheet-source-Situs perusahaan')),
      );
      expectTarget(find.byTooltip('Tutup'));
      expectTarget(find.byKey(const ValueKey('board-sheet-sort-newest')));
      expectTarget(find.byKey(const ValueKey('board-sheet-apply')));
    });
  });
}
