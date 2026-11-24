import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Experimental offline reader, independent of task repositories.
class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  static const _channel = MethodChannel('kedis/knowledge');
  final _query = TextEditingController();
  Map<Object?, Object?>? _archive;
  List<Map<Object?, Object?>> _results = [];
  bool _busy = false;
  bool _searched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? error.code);
    } on MissingPluginException {
      if (mounted) {
        setState(() => _error = 'Offline knowledge is unavailable here.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(() async {
    setState(() {
      _archive = null;
      _results = [];
      _searched = false;
    });
    final archive = await _channel.invokeMapMethod<Object?, Object?>('status');
    if (!mounted) return;
    setState(() => _archive = archive);
  });

  Future<void> _import() => _run(() async {
    final archive = await _channel.invokeMapMethod<Object?, Object?>(
      'importArchive',
    );
    if (!mounted || archive == null) return;
    setState(() {
      _archive = archive;
      _results = [];
      _searched = false;
    });
  });

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove local archive?'),
        content: const Text(
          'Only the copy inside Kedis will be removed. '
          'Your original file will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _channel.invokeMethod<void>('remove');
      if (!mounted) return;
      setState(() {
        _archive = null;
        _results = [];
        _searched = false;
      });
    });
  }

  Future<void> _search() => _run(() async {
    final text = _query.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _results = [];
      _searched = false;
    });
    final results = await _channel.invokeListMethod<Object?>('search', {
      'query': text,
    });
    if (!mounted) return;
    setState(() {
      _results = (results ?? []).cast<Map<Object?, Object?>>();
      _searched = true;
    });
  });

  Future<void> _read(Map<Object?, Object?> result) => _run(() async {
    final article = await _channel.invokeMapMethod<Object?, Object?>('read', {
      'path': result['path'],
      'uuid': result['uuid'],
    });
    if (!mounted || article == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => _ArticleScreen(article: article),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final archive = _archive;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline knowledge')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (archive == null)
              const Text('No archive installed. Import a searchable ZIM file.')
            else ...[
              Text(
                '${archive['title']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${archive['date']} · '
                '${((archive['bytes'] as num) / 1048576).toStringAsFixed(1)} MiB',
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Kedis keeps its own local copy (up to 2 GiB). '
              'The original file is never changed.',
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _busy ? null : _import,
                  child: const Text('Import ZIM'),
                ),
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Check archive'),
                ),
                TextButton(
                  onPressed: _busy ? null : _remove,
                  child: const Text('Remove archive'),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (archive != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _query,
                enabled: !_busy,
                maxLength: 200,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  labelText: 'Search articles',
                  border: OutlineInputBorder(),
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : _search,
                child: const Text('Search'),
              ),
              if (_searched && _results.isEmpty)
                const Text('No matching articles. Try different search terms.'),
              for (final result in _results)
                ListTile(
                  title: Text('${result['title']}'),
                  subtitle: Text('${result['path']}'),
                  onTap: _busy ? null : () => _read(result),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArticleScreen extends StatelessWidget {
  const _ArticleScreen({required this.article});

  final Map<Object?, Object?> article;

  @override
  Widget build(BuildContext context) {
    final archive = article['archive'] as Map<Object?, Object?>;
    return Scaffold(
      appBar: AppBar(title: Text('${article['title']}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${archive['title']} · ${archive['date']}'),
            SelectableText('Archive UUID: ${archive['uuid']}'),
            SelectableText('Article path: ${article['resolvedPath']}'),
            for (final field in ['creator', 'publisher', 'source', 'license'])
              if ('${archive[field] ?? ''}'.isNotEmpty)
                SelectableText('$field: ${archive[field]}'),
            const Text(
              'Local excerpt. Wikipedia text is generally CC BY-SA; '
              'consult the original archive for applicable terms and credits.',
            ),
            const Divider(),
            if (article['truncated'] == true)
              const Text('Excerpt truncated for this preview.'),
            SelectableText('${article['text']}'),
          ],
        ),
      ),
    );
  }
}
