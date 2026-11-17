import 'package:flutter/material.dart';

import '../../data/jobtrail_store.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/placeholder_content.dart';

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key, required this.store});
  final JobTrailStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => PlaceholderContent(
      screenId: 'S06',
      title: 'Dokumen',
      owner: 'Farhad',
      children: [
        const Text('Metadata demo; file belum diunggah.'),
        if (store.documents.isEmpty)
          const EmptyState(message: 'Belum ada dokumen.'),
        for (final document in store.documents)
          ListTile(
            title: Text(document.title),
            subtitle: Text('${document.category.label} · ${document.fileName}'),
          ),
      ],
    ),
  );
}
