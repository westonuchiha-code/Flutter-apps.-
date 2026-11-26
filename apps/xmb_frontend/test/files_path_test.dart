import 'package:flutter_test/flutter_test.dart';
import 'package:xmb_frontend/src/files_path.dart';

void main() {
  test('folders read as the phone\'s file manager shows them', () {
    expect(
      filesPath('/storage/emulated/0/XMB Frontend/ROMs'),
      'Internal storage › XMB Frontend › ROMs',
    );
    expect(filesPath('/storage/emulated/0'), 'Internal storage');
    expect(filesPath('/storage/1A2B-3C4D/Games'), 'SD card › Games');
    expect(filesPath('/sdcard/Comics'), 'Internal storage › Comics');
    expect(filesPath('/data/user/0/x'), '/data/user/0/x');
  });
}
