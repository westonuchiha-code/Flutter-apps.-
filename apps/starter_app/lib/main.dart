import 'package:app_shell/app_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

void main() => runShellApp(starterConfig, (_) => const HomePage());

/// Human-readable name of the platform the app is running on.
String platformName(TargetPlatform platform) => switch (platform) {
  TargetPlatform.windows => 'Windows',
  TargetPlatform.android => 'Android',
  TargetPlatform.linux => 'Linux',
  TargetPlatform.macOS => 'macOS',
  TargetPlatform.iOS => 'iOS',
  TargetPlatform.fuchsia => 'Fuchsia',
};

/// Shell settings for this app (name, version, theme colour).
const starterConfig = AppShellConfig(
  id: 'starter_app',
  name: 'Starter App',
  version: '1.0.0',
  description: 'Smoke test for the Windows, Android and Linux builds.',
  accent: Colors.indigo,
);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final platform = platformName(defaultTargetPlatform);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Starter App'),
        actions: shellActions(context),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Running on $platform', style: textTheme.headlineSmall),
              const SizedBox(height: 24),
              const Text('You have pressed the button this many times:'),
              Text('$_counter', style: textTheme.displayMedium),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _counter++),
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
