import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'locker.dart';

/// Shown when the locker isn't connected yet (Android).
class LockerConnectCard extends StatelessWidget {
  const LockerConnectCard({super.key, required this.locker});

  final AssetLocker locker;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_shared_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                'Connect the Asset Locker',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Android keeps each app\'s files apart, so each app asks once. '
                'In the next screen, open Documents and tap "Use this folder". '
                'Everything goes in an "Asset Locker" folder there.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('Connect'),
                onPressed: locker.connect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable grid of locker assets.
class LockerBrowser extends StatefulWidget {
  const LockerBrowser({
    super.key,
    required this.locker,
    this.types,
    this.onTap,
    this.allowDelete = true,
  });

  final AssetLocker locker;

  /// Limit to these types (null = all).
  final List<AssetType>? types;
  final void Function(AssetInfo info)? onTap;
  final bool allowDelete;

  @override
  State<LockerBrowser> createState() => _LockerBrowserState();
}

class _LockerBrowserState extends State<LockerBrowser> {
  List<AssetInfo>? _all;
  AssetType? _type;
  String _query = '';
  String? _tag;
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.locker.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.locker.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    if (!widget.locker.ready) {
      setState(() => _all = null);
      return;
    }
    try {
      final all = await widget.locker.list();
      if (!mounted) return;
      setState(() {
        _all = all;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locker = widget.locker;
    if (!locker.ready) return LockerConnectCard(locker: locker);
    if (_error != null) {
      return Center(child: Text('Could not read the locker:\n$_error'));
    }
    final all = _all;
    if (all == null) return const Center(child: CircularProgressIndicator());
    final allowed = widget.types;
    final base = [
      for (final a in all)
        if (allowed == null || allowed.contains(a.type)) a,
    ];
    final tags = {for (final a in base) ...a.tags}.toList()..sort();
    final q = _query.toLowerCase();
    final shown = [
      for (final a in base)
        if ((_type == null || a.type == _type) &&
            (_tag == null || a.tags.contains(_tag)) &&
            (q.isEmpty ||
                a.name.toLowerCase().contains(q) ||
                a.app.contains(q) ||
                a.tags.any((t) => t.toLowerCase().contains(q))))
          a,
    ];
    final types = allowed ?? AssetType.values;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search names, tags, apps',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (types.length > 1)
                for (final t in types)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: FilterChip(
                      label: Text(t.folder),
                      selected: _type == t,
                      onSelected: (on) => setState(() => _type = on ? t : null),
                    ),
                  ),
              for (final t in tags)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: FilterChip(
                    avatar: const Icon(Icons.sell_outlined, size: 16),
                    label: Text(t),
                    selected: _tag == t,
                    onSelected: (on) => setState(() => _tag = on ? t : null),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    base.isEmpty ? 'Nothing saved yet.' : 'No matches.',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: 0.8,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => _AssetTile(
                      locker: locker,
                      info: shown[i],
                      onTap: widget.onTap,
                      allowDelete: widget.allowDelete,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

IconData assetIcon(AssetType t) => switch (t) {
  AssetType.sample => Icons.graphic_eq,
  AssetType.recording => Icons.mic_none,
  AssetType.preset => Icons.tune,
  AssetType.sprite => Icons.grid_on,
  AssetType.palette => Icons.palette_outlined,
  AssetType.map => Icons.map_outlined,
  AssetType.picture => Icons.photo_outlined,
  AssetType.video => Icons.movie_outlined,
  AssetType.other => Icons.insert_drive_file_outlined,
};

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.locker,
    required this.info,
    required this.onTap,
    required this.allowDelete,
  });

  final AssetLocker locker;
  final AssetInfo info;
  final void Function(AssetInfo info)? onTap;
  final bool allowDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(info),
        onLongPress: allowDelete ? () => _menu(context) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: scheme.surfaceContainerHighest,
                child: info.hasThumbnail
                    ? FutureBuilder<Uint8List?>(
                        future: locker.thumbnail(info),
                        builder: (context, snap) => snap.data == null
                            ? Icon(assetIcon(info.type), size: 40)
                            : Image.memory(
                                snap.data!,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.none,
                              ),
                      )
                    : Icon(assetIcon(info.type), size: 40),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${info.type.label} · ${info.app}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (allowDelete)
                    IconButton(
                      tooltip: 'More',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.more_vert, size: 18),
                      onPressed: () => _menu(context),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename / tags'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete "${info.name}"?'),
          content: const Text('It is removed for every app.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok == true) await locker.delete(info);
    } else if (action == 'edit') {
      final result = await _nameAndTags(context, info.name, info.tags);
      if (result != null) {
        await locker.update(info.copyWith(name: result.$1, tags: result.$2));
      }
    }
  }
}

List<String> _parseTags(String s) => {
  for (final t in s.split(','))
    if (t.trim().isNotEmpty) t.trim().toLowerCase(),
}.toList();

Future<(String, List<String>)?> _nameAndTags(
  BuildContext context,
  String name,
  List<String> tags, {
  String title = 'Rename',
}) async {
  final nameCtl = TextEditingController(text: name);
  final tagCtl = TextEditingController(text: tags.join(', '));
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: tagCtl,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText: 'drums, dark, loop',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  final result = ok == true
      ? (nameCtl.text.trim(), _parseTags(tagCtl.text))
      : null;
  nameCtl.dispose();
  tagCtl.dispose();
  return result;
}

/// Opens a picker over the locker; returns the chosen asset.
Future<AssetInfo?> pickFromLocker(
  BuildContext context,
  AssetLocker locker, {
  List<AssetType>? types,
}) {
  return Navigator.of(context).push<AssetInfo>(
    MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Pick from Asset Locker')),
        body: ListenableBuilder(
          listenable: locker,
          builder: (context, _) => LockerBrowser(
            locker: locker,
            types: types,
            allowDelete: false,
            onTap: (info) => Navigator.pop(context, info),
          ),
        ),
      ),
    ),
  );
}

/// Asks for a name and tags, then saves to the locker.
Future<AssetInfo?> saveToLocker(
  BuildContext context,
  AssetLocker locker, {
  required AssetType type,
  required List<int> bytes,
  required String extension,
  String suggestedName = '',
  List<String> tags = const [],
  Uint8List? thumbnail,
}) async {
  if (!locker.ready && !await locker.connect()) return null;
  if (!context.mounted) return null;
  final result = await _nameAndTags(
    context,
    suggestedName,
    tags,
    title: 'Save to Asset Locker',
  );
  if (result == null) return null;
  return locker.save(
    type: type,
    name: result.$1,
    tags: result.$2,
    bytes: bytes,
    extension: extension,
    thumbnail: thumbnail,
  );
}
