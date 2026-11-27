import 'package:crt_tv/src/bindings.dart';
import 'package:crt_tv/src/ui/osd_menu.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late OsdMenuCore menu;
  late List<String> log;
  late OsdPage sub;
  late OsdPage root;

  setUp(() {
    menu = OsdMenuCore();
    log = [];
    sub = OsdPage('SUB', () => [OsdLink('DO IT', () => log.add('did'))]);
    root = OsdPage('ROOT', () => [
          const OsdInfo('JUST TEXT'),
          OsdChoice('CHOICE', 'A', (d) => log.add('choice $d')),
          OsdMeter('METER', 0.5, (d) => log.add('meter $d')),
          OsdLink('SUB', () => menu.push(sub), value: '►'),
        ]);
  });

  test('the cursor skips plain text and wraps around', () {
    menu.open(root);
    expect(menu.rows.map((r) => r.label), ['JUST TEXT', 'CHOICE', 'METER', 'SUB', 'CLOSE MENU']);
    expect(menu.cursor, 1);
    menu.move(-1);
    expect(menu.cursor, 4, reason: 'up from the first line goes to the last line, not the text');
    menu.move(1);
    expect(menu.cursor, 1);
  });

  test('left and right change a setting, select steps a choice forward', () {
    menu.open(root);
    menu.change(-1);
    menu.select();
    menu.move(1);
    menu.change(1);
    menu.select();
    expect(log, ['choice -1', 'choice 1', 'meter 1']);
  });

  test('sub-menus open, go back, and the last line leaves', () {
    menu.open(root);
    menu.move(1);
    menu.move(1);
    menu.select();
    expect(menu.title, 'SUB');
    expect(menu.rows.last.label, 'BACK');
    menu.select();
    expect(log, ['did']);
    menu.back();
    expect(menu.title, 'ROOT');
    expect(menu.cursor, 3, reason: 'comes back to the line it left from');
    menu.move(1);
    menu.select();
    expect(menu.isOpen, isFalse);
  });

  test('clicking a line selects it; text lines ignore clicks', () {
    menu.open(root);
    menu.tap(0);
    expect(log, isEmpty);
    menu.tap(1);
    expect(log, ['choice 1']);
  });

  testWidgets('every kind of line fits its panel at TV sizes', (tester) async {
    final long = OsdPage('A VERY LONG TITLE THAT WILL NOT FIT ON ONE LINE OF THE MENU', () => [
          const OsdInfo('SOME EXPLANATION THAT RUNS ON FAR LONGER THAN THE PANEL IS WIDE, SO IT MUST CUT OFF'),
          OsdChoice('VIDEO ONLY (NO CABINET) AND THEN SOME', 'A LONG VALUE NAME', (_) {}),
          OsdMeter('VOLUME', 0.7, (_) {}),
          for (var i = 0; i < 30; i++) OsdLink('07 SATURDAY MORNING CARTOONS $i', () {}, value: 'A SHOW WITH A LONG NAME S01E0$i'),
        ]);
    for (final size in const [Size(1440, 1080), Size(640, 480), Size(320, 240)]) {
      await tester.pumpWidget(MaterialApp(
        home: Center(child: SizedBox.fromSize(size: size, child: OsdMenuView(menu: menu))),
      ));
      menu.open(long);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'list at $size');
      menu.move(-1);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'scrolled list at $size');
      menu.startCapture(TvAction.videoOnly, pad: true);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'capture prompt at $size');
      menu.cancelCapture();
      menu.flash('SOMETHING NOW HAS NO KEY, WHICH IS A FAIRLY LONG THING TO SAY IN A SMALL BOX');
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'notice at $size');
      menu.close();
      await tester.pump(const Duration(seconds: 5));
    }
  });
}
