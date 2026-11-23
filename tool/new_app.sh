#!/usr/bin/env bash
# Creates a new app in apps/ already wired to packages/app_shell.
# Usage: tool/new_app.sh <app_name> ["Display Name"] [--android-only]
set -euo pipefail

name=""; title=""; platforms="windows,android,linux"
for arg in "$@"; do
  case "$arg" in
    --android-only) platforms="android" ;;
    *) if [[ -z "$name" ]]; then name="$arg"; else title="$arg"; fi ;;
  esac
done
if [[ ! "$name" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "Usage: tool/new_app.sh <app_name> [\"Display Name\"] [--android-only]" >&2
  echo "app_name: lower case letters, digits and underscores." >&2
  exit 1
fi
[[ -n "$title" ]] || title="$(echo "$name" | sed -E 's/_/ /g; s/\b(.)/\u\1/g')"

root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/apps/$name"
[[ ! -e "$dir" ]] || { echo "apps/$name already exists" >&2; exit 1; }

cd "$root/apps"
flutter create --platforms="$platforms" --org com.westonuchiha \
  --description "$title" "$name" >/dev/null
cd "$dir"
flutter pub add material_ui "app_shell:{\"path\":\"../../packages/app_shell\"}" >/dev/null

cat > lib/main.dart <<DART
import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

const appConfig = AppShellConfig(
  id: '$name',
  name: '$title',
  version: '0.1.0',
  // Add this app's own settings here; the settings screen is generated.
  settings: [],
);

void main() => runShellApp(appConfig, (_) => const HomePage());

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appConfig.name), actions: shellActions(context)),
      body: const Center(child: Text('Hello')),
    );
  }
}
DART

cat > test/widget_test.dart <<DART
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$name/main.dart';

void main() {
  testWidgets('home page loads', (tester) async {
    final dir = Directory.systemTemp.createTempSync('${name}_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    await tester.pumpWidget(
      ShellApp(services: services, home: (_) => const HomePage()),
    );
    expect(find.text('Hello'), findsOneWidget);
  });
}
DART

dart format lib test >/dev/null
echo "Created apps/$name ($platforms). CI picks it up on the next push."
