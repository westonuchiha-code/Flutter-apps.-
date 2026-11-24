import 'dart:isolate';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';

int _sum((List<int>, int) a) => a.$1.fold(a.$2, (x, y) => x + y);

/// Like a widget State: holds a port, which can't be sent to an isolate.
class _Holder {
  final port = ReceivePort();
  var busy = false;

  Future<int> work(List<int> data) async {
    // A closure that uses `this` puts the object into the method's context;
    // Isolate.run(() => ...) here would try to send the port and fail.
    void mark() => busy = true;
    mark();
    final r = await runInBackground(_sum, (data, 1));
    port.close();
    return r;
  }
}

void main() {
  test('runInBackground sends only the function and its argument', () async {
    expect(await _Holder().work([1, 2, 3]), 7);
  });
}
