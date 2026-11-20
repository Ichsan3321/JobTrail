import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:jobtrail/app.dart';

void main() {
  testWidgets('weekly goal is a keyboard focusable semantic button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const JobTrailApp());
    final goal = find.byKey(const ValueKey('home-weekly-goal'));
    expect(
      tester.getSemantics(goal),
      matchesSemantics(
        label: 'Detail target mingguan',
        value: '0 dari 8 lamaran, 0,0%',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
    final ink = find.descendant(of: goal, matching: find.byType(InkWell));
    bool goalFocused() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<InkWell>() ==
        tester.widget<InkWell>(ink);
    for (var i = 0; i < 30 && !goalFocused(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(goalFocused(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Target Mingguan'), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 30 && !goalFocused(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(goalFocused(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Target Mingguan'), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S01')), findsOneWidget);
  });
  testWidgets('notifications filter, mark read and dismiss', (tester) async {
    await tester.pumpWidget(const JobTrailApp());
    await tester.tap(find.byTooltip('Notifikasi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tandai dibaca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Belum dibaca 0'));
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada notifikasi belum dibaca.'), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S01')), findsOneWidget);
  });
  testWidgets('weekly activity selection and dismissal', (tester) async {
    await tester.pumpWidget(const JobTrailApp());
    await tester.tap(find.byKey(const ValueKey('home-weekly-goal')));
    await tester.pumpAndSettle();
    expect(find.text('Target Mingguan'), findsOneWidget);
    await tester.tap(find.text('Sen\n0'));
    await tester.pumpAndSettle();
    expect(find.text('16/11/2026: 0 lamaran'), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tambah Lamaran'), findsOneWidget);
  });
}
