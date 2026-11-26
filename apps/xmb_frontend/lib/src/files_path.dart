/// A folder as the phone's file manager shows it (Samsung's My Files,
/// Files by Google): `/storage/emulated/0/XMB Frontend/ROMs` is
/// "Internal storage › XMB Frontend › ROMs"; an SD card's
/// `/storage/1234-ABCD/...` is "SD card › ...". Anything else is left as is.
String filesPath(String dir) {
  final parts = dir
      .replaceAll(r'\', '/')
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  List<String>? rest;
  var where = '';
  if (parts.length >= 3 && parts[0] == 'storage' && parts[1] == 'emulated') {
    where = 'Internal storage';
    rest = parts.sublist(3);
  } else if (parts.length >= 2 &&
      parts[0] == 'storage' &&
      RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$').hasMatch(parts[1])) {
    where = 'SD card';
    rest = parts.sublist(2);
  } else if (parts.length >= 2 && parts[0] == 'sdcard') {
    where = 'Internal storage';
    rest = parts.sublist(1);
  }
  if (rest == null) return dir;
  return [where, ...rest].join(' › ');
}
