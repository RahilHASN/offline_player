import 'package:flutter/material.dart';

import '../services/trash_service.dart';
import '../utils/format.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  void _snack(BuildContext context, String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _empty(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty trash?'),
        content: const Text('All videos in Trash are deleted for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty'),
          ),
        ],
      ),
    );
    if (yes == true) await TrashService.instance.empty();
  }

  @override
  Widget build(BuildContext context) {
    final t = TrashService.instance;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final list = t.entries.reversed.toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Trash'),
            actions: [
              TextButton(
                onPressed: list.isEmpty ? null : () => _empty(context),
                child: const Text('Empty'),
              ),
            ],
          ),
          body: list.isEmpty
              ? const Center(
                  child: Text('Trash is empty.',
                      style: TextStyle(color: Colors.white54)),
                )
              : ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Videos are removed for good after 30 days.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    for (final e in list)
                      ListTile(
                        leading: const Icon(Icons.movie_outlined),
                        title: Text(e.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${formatSize(e.size)} · deleted '
                          '${DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(e.deletedMs)).inDays} days ago',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Restore',
                              icon: const Icon(Icons.restore),
                              onPressed: () async {
                                try {
                                  await t.restore(e);
                                  if (context.mounted) {
                                    _snack(context, 'Restored.');
                                  }
                                } catch (err) {
                                  if (context.mounted) {
                                    _snack(context, 'Could not restore: $err');
                                  }
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Delete for good',
                              icon: const Icon(Icons.delete_forever),
                              onPressed: () => t.deleteForever(e),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
