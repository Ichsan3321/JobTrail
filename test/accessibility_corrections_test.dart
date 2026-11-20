import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/constants/app_tokens.dart';

import 'widget_test.dart' show selectTab, tapApplication;

void main() {
  for (final edit in [false, true]) {
    testWidgets(
      'editable field semantics persist in ${edit ? 'Edit' : 'Add'} mode',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(const JobTrailApp());
        if (edit) {
          await selectTab(tester, 'board');
          await tapApplication(tester, 'app-nusa');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Edit Lamaran'));
        } else {
          await tester.tap(find.byKey(const ValueKey('home-add')));
        }
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        final names = [
          'Nama Perusahaan',
          'Posisi',
          'Kota / Lokasi',
          'Gaji per bulan (Rp, opsional)',
          'Catatan (opsional)',
        ];
        for (var i = 0; i < names.length; i++) {
          await tester.ensureVisible(fields.at(i));
          await tester.pumpAndSettle();
          final label = tester.getSemantics(fields.at(i)).label;
          expect(names[i].allMatches(label).length, 1, reason: label);
          expect(label.contains('wajib diisi'), i < 3, reason: label);
        }
        handle.dispose();
      },
    );
  }

  testWidgets('notification filters respond to Enter and Space', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const JobTrailApp());
    await tester.tap(find.byTooltip('Notifikasi'));
    await tester.pumpAndSettle();
    Finder ink(String text) => find
        .ancestor(
          of: find.textContaining(text).first,
          matching: find.byType(InkWell),
        )
        .first;
    bool focused(Finder target) =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<InkWell>() ==
        tester.widget<InkWell>(target);
    Future<void> focus(Finder target) async {
      for (var i = 0; i < 30 && !focused(target); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focused(target), isTrue);
    }

    bool selected(Finder target) =>
        tester
            .widget<Semantics>(
              find.ancestor(of: target, matching: find.byType(Semantics)).first,
            )
            .properties
            .selected ==
        true;
    final unread = ink('Belum dibaca');
    final all = ink('Semua (');
    expect(selected(all), isTrue);
    await focus(unread);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected(unread), isTrue);
    expect(selected(all), isFalse);
    await focus(all);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(selected(all), isTrue);
    expect(selected(unread), isFalse);
    handle.dispose();
  });
  testWidgets('form fields have names and back has a 48px target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const JobTrailApp());
    await tester.tap(find.byKey(const ValueKey('home-add')));
    await tester.pumpAndSettle();
    final back = find.byTooltip('Kembali');
    expect(tester.getSize(back).shortestSide, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(find.byType(TextFormField).first).label,
      contains('Nama Perusahaan'),
    );
    expect(
      tester.getSemantics(find.byType(TextFormField).first).label,
      contains('wajib diisi'),
    );
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('S01')), findsOneWidget);
    semantics.dispose();
  });
  testWidgets('notification filters expose selection and 48px targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const JobTrailApp());
    await tester.tap(find.byTooltip('Notifikasi'));
    await tester.pumpAndSettle();
    final unread = find.textContaining('Belum dibaca').first;
    final control = find
        .ancestor(of: unread, matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(control).shortestSide, greaterThanOrEqualTo(48));
    await tester.tap(control);
    await tester.pumpAndSettle();
    final selection = find
        .ancestor(of: control, matching: find.byType(Semantics))
        .first;
    expect(tester.widget<Semantics>(selection).properties.selected, isTrue);
    semantics.dispose();
  });
  test('secondary text token meets normal text contrast on white', () {
    final a = AppColors.gray.computeLuminance();
    final b = Colors.white.computeLuminance();
    expect((b + .05) / (a + .05), greaterThanOrEqualTo(4.5));
  });
}
