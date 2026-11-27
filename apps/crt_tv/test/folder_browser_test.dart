import 'dart:io';

import 'package:crt_tv/src/folder_browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('going up a level on Windows ends at the list of drives', () {
    expect(parentFolder(r'E:\TV\Channel 3', windows: true), r'E:\TV');
    expect(parentFolder(r'E:\TV', windows: true), r'E:\');
    expect(parentFolder(r'E:\', windows: true), '');
    expect(parentFolder('', windows: true), isNull);
  });

  test('going up a level on Linux ends at the root', () {
    expect(parentFolder('/media/Kodi Media/TV', windows: false), '/media/Kodi Media');
    expect(parentFolder('/media', windows: false), '/');
    expect(parentFolder('/userdata/', windows: false), '/');
    expect(parentFolder('/', windows: false), isNull);
  });

  test('stepping into a folder builds the right path', () {
    expect(childFolder(r'E:\', 'TV', windows: true), r'E:\TV');
    expect(childFolder(r'E:\TV', 'Channel 3', windows: true), r'E:\TV\Channel 3');
    expect(childFolder('/', 'media', windows: false), '/media');
    expect(childFolder('/media', 'Kodi Media', windows: false), '/media/Kodi Media');
  });

  test('channel folders are recognised by name, seasonal ones too', () {
    expect(isChannelFolderName('Channel 3'), isTrue);
    expect(isChannelFolderName('Channel Gojira'), isTrue);
    expect(isChannelFolderName('Channel Halloween [Oct]'), isTrue);
    expect(isChannelFolderName('z Other'), isFalse);
  });

  test('a folder lists its sub-folders in order, without files or hidden ones', () {
    final root = Directory.systemTemp.createTempSync('tv_browse_test');
    addTearDown(() => root.deleteSync(recursive: true));
    for (final name in ['Channel 10', 'Channel 2', '.hidden', 'Movies']) {
      Directory('${root.path}/$name').createSync();
    }
    File('${root.path}/notes.txt').writeAsStringSync('x');
    expect(listFolders(root.path), ['Channel 2', 'Channel 10', 'Movies']);
    expect(listFolders('${root.path}/does not exist'), isNull);
  });
}
