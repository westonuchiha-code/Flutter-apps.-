import 'package:flutter/foundation.dart';
import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

/// Shared to-do list, saved in the Asset Locker.
class TodoPage extends StatefulWidget {
  const TodoPage({super.key, required this.apps});

  /// App ids offered as tags.
  final ValueListenable<List<String>> apps;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  List<TodoItem>? _items;
  AssetLocker? _locker;
  String? _filter;
  String _newTag = '';
  final _text = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locker = Shell.of(context).locker;
    if (locker != _locker) {
      _locker?.removeListener(_load);
      _locker = locker..addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    _locker?.removeListener(_load);
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final locker = _locker!;
    if (!locker.ready) return;
    final items = await locker.readTodos();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _save(List<TodoItem> items) async {
    setState(() => _items = items);
    await _locker!.writeTodos(items);
  }

  void _add() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    Shell.of(context).tick();
    _text.clear();
    final now = DateTime.now();
    _save([
      TodoItem(
        id: now.microsecondsSinceEpoch.toRadixString(36),
        text: t,
        tag: _newTag,
        created: now,
      ),
      ...?_items,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final locker = Shell.of(context).locker;
    if (!locker.ready) return LockerConnectCard(locker: locker);
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    return ValueListenableBuilder(
      valueListenable: widget.apps,
      builder: (context, apps, _) {
        final tags = {...apps, for (final i in items) i.tag}..remove('');
        final sortedTags = tags.toList()..sort();
        final shown = [
          for (final i in items)
            if (_filter == null || i.tag == _filter) i,
        ]..sort((a, b) => a.done == b.done ? 0 : (a.done ? 1 : -1));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _text,
                      decoration: const InputDecoration(
                        hintText: 'Add a to-do',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 2,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: sortedTags.contains(_newTag) ? _newTag : '',
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('General'),
                        ),
                        for (final t in sortedTags)
                          DropdownMenuItem(
                            value: t,
                            child: Text(t, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _newTag = v ?? ''),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Add',
                    icon: const Icon(Icons.add),
                    onPressed: _add,
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  for (final t in ['', ...sortedTags])
                    if (t.isEmpty || items.any((i) => i.tag == t))
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: FilterChip(
                          label: Text(t.isEmpty ? 'General' : t),
                          selected: _filter == t,
                          onSelected: (on) =>
                              setState(() => _filter = on ? t : null),
                        ),
                      ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('Nothing to do.'))
                  : ListView(
                      children: [
                        for (final i in shown)
                          Dismissible(
                            key: ValueKey(i.id),
                            background: Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .errorContainer,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              child: const Icon(Icons.delete_outline),
                            ),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) => _save([
                              for (final x in items)
                                if (x.id != i.id) x,
                            ]),
                            child: CheckboxListTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              value: i.done,
                              title: Text(
                                i.text,
                                style: i.done
                                    ? const TextStyle(
                                        decoration: TextDecoration.lineThrough,
                                      )
                                    : null,
                              ),
                              subtitle: Text(i.tag.isEmpty ? 'General' : i.tag),
                              onChanged: (v) => _save([
                                for (final x in items)
                                  x.id == i.id ? x.copyWith(done: v) : x,
                              ]),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
