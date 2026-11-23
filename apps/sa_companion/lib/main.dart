import 'package:material_ui/material_ui.dart';

import 'app/app_state.dart';
import 'app/progress_store.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(PrefsProgressStore());
  await state.load();
  runApp(SaCompanionApp(state: state));
}

class SaCompanionApp extends StatelessWidget {
  const SaCompanionApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SA Companion',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Shell(state: state),
    );
  }
}
