// Local check against the real Cross-Save repo, read-only: an empty folder
// takes the PC's RetroArch saves (nothing is ever sent from here).
// Needs network access to api.github.com (uses the environment's proxy).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xmb_frontend/src/sync/cross_save.dart';
import 'package:xmb_frontend/src/sync/github.dart';

void main() {
  test('reads the real repo and takes its saves', () async {
    final ctx = SecurityContext(withTrustedRoots: true);
    const bundle = '/root/.ccr/ca-bundle.crt';
    if (File(bundle).existsSync()) ctx.setTrustedCertificates(bundle);
    final http = HttpClient(context: ctx)
      ..findProxy = HttpClient.findProxyFromEnvironment;
    final repo = GitHubRepo(token: '', client: http);
    expect(await repo.check(), 'westonuchiha-code/Cross-Save');
    final dir = Directory.systemTemp.createTempSync('xs_real');
    final r = await crossSync(
      repo: _ReadOnly(repo),
      maps: [
        SyncMap(
          'saves/retroarch',
          p.join(dir.path, 'RetroArch'),
          exts: const ['srm', 'rtc'],
        ),
        SyncMap(
          'pokeville',
          p.join(dir.path, 'Pokeville'),
          skipDirs: const ['sent'],
        ),
      ],
      state: {},
      device: 'test',
      backups: p.join(dir.path, 'bk'),
    );
    // ignore: avoid_print
    print('took ${r.took.length}: ${r.took.take(10).join(' | ')}');
    expect(r.ok, isTrue, reason: r.error);
    expect(r.sent, isEmpty);
    expect(
      r.took,
      contains('Gambatte/Pokemon - Crystal Version (USA, Europe).srm'),
    );
    final crystal = File(
      p.join(
        dir.path,
        'RetroArch',
        'Gambatte',
        'Pokemon - Crystal Version (USA, Europe).srm',
      ),
    );
    expect(crystal.lengthSync(), greaterThanOrEqualTo(32768));
    expect(
      File(p.join(dir.path, 'Pokeville', 'box.json')).existsSync(),
      isTrue,
    );
    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Refuses every write (this check must never change the repo).
class _ReadOnly implements SaveRepo {
  _ReadOnly(this.r);
  final SaveRepo r;
  @override
  Future<({String commit, String tree})> head() => r.head();
  @override
  Future<Map<String, String>> files(String tree) => r.files(tree);
  @override
  Future<Uint8List> blob(String sha) => r.blob(sha);
  @override
  Future<String> putBlob(Uint8List bytes) => throw 'read-only';
  @override
  Future<String> putTree(String base, Map<String, String> files) =>
      throw 'read-only';
  @override
  Future<String> commit(String message, String tree, String parent) =>
      throw 'read-only';
  @override
  Future<bool> moveBranch(String commit) => throw 'read-only';
}
