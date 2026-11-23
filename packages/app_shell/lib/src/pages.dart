import 'package:material_ui/material_ui.dart';

import 'crash_log.dart';
import 'settings.dart';
import 'shell.dart';

/// Settings screen generated from the app's [Setting] declarations.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = Shell.of(context);
    final store = shell.settings;
    final sections = <String, List<Setting<Object?>>>{};
    for (final s in store.settings) {
      sections.putIfAbsent(s.section, () => []).add(s);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          children: [
            for (final entry in sections.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(
                  entry.key,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              for (final s in entry.value)
                _SettingTile(store: store, setting: s),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.store, required this.setting});

  final SettingsStore store;
  final Setting<Object?> setting;

  @override
  Widget build(BuildContext context) {
    final s = setting;
    final subtitle = s.subtitle == null ? null : Text(s.subtitle!);
    switch (s) {
      case BoolSetting():
        return SwitchListTile(
          title: Text(s.title),
          subtitle: subtitle,
          value: store.get(s),
          onChanged: (v) => store.set(s, v),
        );
      case ChoiceSetting():
        final value = store.get(s);
        return ListTile(
          title: Text(s.title),
          subtitle: subtitle ?? Text(s.choices[value] ?? value),
          trailing: DropdownButton<String>(
            value: value,
            underline: const SizedBox.shrink(),
            items: [
              for (final e in s.choices.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              if (v != null) store.set(s, v);
            },
          ),
        );
      case SliderSetting():
        final value = store.get(s);
        return ListTile(
          title: Row(
            children: [
              Expanded(child: Text(s.title)),
              Text(s.format?.call(value) ?? value.toStringAsFixed(2)),
            ],
          ),
          subtitle: Slider(
            value: value,
            min: s.min,
            max: s.max,
            divisions: s.divisions,
            onChanged: (v) => store.set(s, v),
          ),
        );
      case TextSetting():
        return ListTile(
          title: Text(s.title),
          subtitle: Text(
            store.get(s).isEmpty ? (s.subtitle ?? 'Not set') : store.get(s),
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final controller = TextEditingController(text: store.get(s));
            final v = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(s.title),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
            controller.dispose();
            if (v != null) store.set(s, v);
          },
        );
    }
  }
}

/// About page: name, version, description, licences and the error log.
class AboutShellPage extends StatelessWidget {
  const AboutShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = Shell.of(context);
    final c = shell.config;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(c.name, style: text.headlineSmall),
          Text('Version ${c.version}', style: text.bodyMedium),
          if (c.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(c.description),
            ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Error log'),
            subtitle: const Text('Problems the app has recorded'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CrashLogPage()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Licences'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: c.name,
              applicationVersion: c.version,
            ),
          ),
        ],
      ),
    );
  }
}

class CrashLogPage extends StatefulWidget {
  const CrashLogPage({super.key});

  @override
  State<CrashLogPage> createState() => _CrashLogPageState();
}

class _CrashLogPageState extends State<CrashLogPage> {
  late Future<List<CrashEntry>> _entries;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entries = Shell.of(context).crashLog.entries();
  }

  @override
  Widget build(BuildContext context) {
    final shell = Shell.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Error log'),
        actions: [
          IconButton(
            tooltip: 'Share report',
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              final report = await shell.crashLog.report(
                shell.config.name,
                shell.config.version,
              );
              await shell.exporter.exportText(
                '${shell.config.id}-errors.txt',
                report,
              );
            },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await shell.crashLog.clear();
              setState(() => _entries = shell.crashLog.entries());
            },
          ),
        ],
      ),
      body: FutureBuilder(
        future: _entries,
        builder: (context, snap) {
          final list = (snap.data ?? const <CrashEntry>[]).reversed.toList();
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (list.isEmpty) {
            return const Center(child: Text('No errors recorded.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => ExpansionTile(
              title: Text(
                list[i].error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${list[i].time.toLocal()}${list[i].fatal ? ' · fatal' : ''}',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    list[i].stack,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
