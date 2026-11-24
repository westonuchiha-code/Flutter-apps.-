import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_capture/light_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('light_capture');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'listCameras':
              return [
                {'id': 'cam0', 'name': 'Webcam'},
              ];
            case 'start':
              if ((call.arguments as Map)['id'] == 'bad') {
                throw PlatformException(code: 'camera_error', message: 'busy');
              }
              return {'width': 160, 'height': 120};
            case 'setAutoExposure':
              return true;
          }
          return null;
        });
  });

  test('listCameras decodes entries', () async {
    expect(await LightCapture.listCameras(), [
      const LightCaptureCamera(id: 'cam0', name: 'Webcam'),
    ]);
  });

  test('start passes the id and maps errors', () async {
    await LightCapture.start(const LightCaptureCamera(id: 'cam0', name: 'x'));
    expect(calls.last.arguments, {'id': 'cam0', 'color': false, 'width': 160});
    await LightCapture.start(
      const LightCaptureCamera(id: 'cam0', name: 'x'),
      color: true,
      width: 320,
    );
    expect(calls.last.arguments, {'id': 'cam0', 'color': true, 'width': 320});
    await expectLater(
      LightCapture.start(const LightCaptureCamera(id: 'bad', name: 'x')),
      throwsA(
        isA<LightCaptureException>().having(
          (e) => e.message,
          'message',
          'busy',
        ),
      ),
    );
  });

  test('setAutoExposure', () async {
    expect(await LightCapture.setAutoExposure(false), isTrue);
    expect(calls.last.arguments, {'enabled': false});
  });
}
