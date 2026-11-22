import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const StarterApp());
}

/// Human-readable name of the platform the app is running on.
String platformName(TargetPlatform platform) => switch (platform) {
  TargetPlatform.windows => 'Windows',
  TargetPlatform.android => 'Android',
  TargetPlatform.linux => 'Linux',
  TargetPlatform.macOS => 'macOS',
  TargetPlatform.iOS => 'iOS',
  TargetPlatform.fuchsia => 'Fuchsia',
};

class StarterApp extends StatelessWidget {
  const StarterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Starter App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

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
      appBar: AppBar(title: const Text('Starter App')),
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
