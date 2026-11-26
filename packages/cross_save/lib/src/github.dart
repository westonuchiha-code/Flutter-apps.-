import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cross_save.dart';

/// The Cross-Save repo through GitHub's REST API (no git on Android).
class GitHubRepo implements SaveRepo {
  GitHubRepo({
    required this.token,
    this.owner = 'westonuchiha-code',
    this.name = 'Cross-Save',
    this.branch = 'main',
    HttpClient? client,
  }) : _http = client ?? HttpClient();

  /// A fine-grained token for this one repo ("Contents: read and write").
  final String token;
  final String owner, name, branch;
  final HttpClient _http;

  static const _api = 'api.github.com';

  Future<Object?> _call(String method, String path, [Object? body]) async {
    // A query ("?recursive=1") must not be escaped into the path.
    final q = path.indexOf('?');
    final uri = Uri.https(
      _api,
      '/repos/$owner/$name${q < 0 ? path : path.substring(0, q)}',
      q < 0 ? null : Uri.splitQueryString(path.substring(q + 1)),
    );
    final req = await _http
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 15));
    req.headers
      ..set('Accept', 'application/vnd.github+json')
      ..set('X-GitHub-Api-Version', '2022-11-28')
      ..set('User-Agent', 'xmb-frontend-android');
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    final res = await req.close().timeout(const Duration(seconds: 60));
    final text = await utf8.decodeStream(res);
    if (res.statusCode >= 300) {
      throw GitHubError(res.statusCode, _message(text));
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  static String _message(String text) {
    try {
      final j = jsonDecode(text);
      if (j is Map && j['message'] is String) return j['message'] as String;
    } catch (_) {}
    return text.length > 120 ? text.substring(0, 120) : text;
  }

  /// Checks the token can see the repo; returns its name.
  Future<String> check() async {
    final j = await _call('GET', '') as Map;
    return '${j['full_name']}';
  }

  @override
  Future<({String commit, String tree})> head() async {
    final ref = await _call('GET', '/git/ref/heads/$branch') as Map;
    final sha = (ref['object'] as Map)['sha'] as String;
    final c = await _call('GET', '/git/commits/$sha') as Map;
    return (commit: sha, tree: (c['tree'] as Map)['sha'] as String);
  }

  @override
  Future<Map<String, String>> files(String tree) async {
    final j = await _call('GET', '/git/trees/$tree?recursive=1') as Map;
    if (j['truncated'] == true) {
      throw const GitHubError(0, 'the repo is too big to list in one go');
    }
    return {
      for (final e in j['tree'] as List)
        if (e is Map && e['type'] == 'blob') '${e['path']}': '${e['sha']}',
    };
  }

  @override
  Future<Uint8List> blob(String sha) async {
    final j = await _call('GET', '/git/blobs/$sha') as Map;
    final content = '${j['content']}'.replaceAll('\n', '');
    return base64Decode(content);
  }

  @override
  Future<String> putBlob(Uint8List bytes) async {
    final j = await _call('POST', '/git/blobs', {
      'content': base64Encode(bytes),
      'encoding': 'base64',
    }) as Map;
    return '${j['sha']}';
  }

  @override
  Future<String> putTree(String base, Map<String, String> files) async {
    final j = await _call('POST', '/git/trees', {
      'base_tree': base,
      'tree': [
        for (final e in files.entries)
          {'path': e.key, 'mode': '100644', 'type': 'blob', 'sha': e.value},
      ],
    }) as Map;
    return '${j['sha']}';
  }

  @override
  Future<String> commit(String message, String tree, String parent) async {
    final j = await _call('POST', '/git/commits', {
      'message': message,
      'tree': tree,
      'parents': [parent],
    }) as Map;
    return '${j['sha']}';
  }

  @override
  Future<bool> moveBranch(String commit) async {
    try {
      await _call('PATCH', '/git/refs/heads/$branch', {
        'sha': commit,
        'force': false,
      });
      return true;
    } on GitHubError catch (e) {
      // 422: not a fast-forward (someone pushed meanwhile).
      if (e.status == 422) return false;
      rethrow;
    }
  }
}

class GitHubError implements Exception {
  const GitHubError(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => switch (status) {
    401 => 'the GitHub token was refused (check it in Settings > Cross Save)',
    403 ||
    404 => 'the token can\'t open the Cross-Save repo ($status: $message)',
    0 => message,
    _ => 'GitHub said $status: $message',
  };
}
