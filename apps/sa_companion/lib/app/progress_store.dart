import 'package:shared_preferences/shared_preferences.dart';

/// Where progress is saved on the phone.
abstract class ProgressStore {
  Future<String?> load();
  Future<void> save(String json);
}

class PrefsProgressStore implements ProgressStore {
  /// Same key the web version used for localStorage.
  static const key = 'sa-ps2-companion-v1';

  @override
  Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> save(String json) async =>
      (await SharedPreferences.getInstance()).setString(key, json);
}

class MemoryProgressStore implements ProgressStore {
  MemoryProgressStore([this.saved]);
  String? saved;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> save(String json) async => saved = json;
}
