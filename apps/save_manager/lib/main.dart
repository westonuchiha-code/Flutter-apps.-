import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

const appConfig = AppShellConfig(
  id: 'save_manager',
  name: 'Save Manager',
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
      appBar: AppBar(
        title: Text(appConfig.name),
        actions: shellActions(context),
      ),
      body: const Center(child: Text('Hello')),
    );
  }
}
