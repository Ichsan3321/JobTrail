import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/constants/app_dates.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/models/agenda.dart';
import 'package:jobtrail/models/application.dart';
import 'package:jobtrail/models/recruitment_status.dart';
import 'package:jobtrail/widgets/app_shell.dart';

void main() {
  testWidgets('clock boundary is consistent across screens at WIB midnight', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 16, 17, 30); // 17 Nov 00:30 WIB.
    final store = JobTrailStore.empty(
      referenceDate: DateTime.utc(2026, 11, 17),
      clock: () => now,
    );
    addTearDown(store.dispose);
    final ids = <String>[];
    for (var i = 0; i < 4; i++) {
      ids.add(
        store.addApplication(
          ApplicationDraft(
            company: 'Clock $i',
            position: 'Intern',
            source: 'Demo',
            appliedAt: DateTime.utc(2026, 11, 15),
            status: RecruitmentStatus.interview,
            location: 'Demo',
            workType: WorkType.remote,
          ),
        ),
      );
      store.saveAgenda(
        Agenda(
          id: 'clock-$i',
          applicationId: ids.last,
          type: i == 1 ? AgendaType.test : AgendaType.interview,
          scheduledAt: now.add(
            i == 3 ? const Duration(minutes: -15) : Duration(hours: i - 1),
          ),
          locationOrLink: 'Clock location $i',
        ),
      );
    }
    expect(
      AppDates.formatWib(now.subtract(const Duration(hours: 1))),
      '16/11/2026 23:30 WIB',
    );
    expect(AppDates.formatWib(now), '17/11/2026 00:30 WIB');
    expect(
      AppDates.formatWib(now.add(const Duration(hours: 1))),
      '17/11/2026 01:30 WIB',
    );
    tester.view.physicalSize = const Size(393, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      JobTrailApp(showAuthentication: false, store: store),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Clock location 0'), findsNothing);
    expect(find.textContaining('Clock location 3'), findsNothing);
    expect(find.textContaining('Clock location 1'), findsOneWidget);
    expect(find.textContaining('Clock location 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-board')));
    await tester.pumpAndSettle();
    final navigation = tester
        .widget<AppShell>(find.byType(AppShell))
        .navigation;
    for (var i = 0; i < 4; i++) {
      final card = find.byKey(ValueKey('application-${ids[i]}'));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(
        find.text(i == 0 || i == 3 ? 'Agenda terakhir' : 'Agenda berikutnya'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('board-preview-detail')));
      await tester.pumpAndSettle();
      expect(
        find.text(i == 0 || i == 3 ? 'Agenda Terkait' : 'Agenda berikutnya'),
        findsOneWidget,
      );
      expect(find.textContaining('Clock location $i'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(navigation.selectedTab.name, 'board');
    await tester.tap(find.byKey(const ValueKey('nav-schedule')));
    await tester.pumpAndSettle();
    expect(find.text('SEN, 16 NOV'), findsOneWidget);
    expect(find.text('SEL, 17 NOV'), findsOneWidget);
    expect(find.byKey(const ValueKey('agenda-past-clock-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('agenda-past-clock-3')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-past-badge-2026-11-17')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('agenda-past-clock-1')), findsNothing);
    expect(find.byKey(const ValueKey('agenda-past-clock-2')), findsNothing);
    expect(find.byKey(const ValueKey('agenda-clock-1')), findsOneWidget);
  });
}
