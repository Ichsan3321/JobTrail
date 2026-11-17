import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';

void main() {
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
