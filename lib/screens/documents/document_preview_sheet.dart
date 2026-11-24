import 'package:flutter/material.dart';

import '../../core/constants/app_tokens.dart';
import '../../data/jobtrail_store.dart';
import '../../models/app_document.dart';
import '../../models/application.dart';

Future<void> showDocumentPreview(
  BuildContext context, {
  required JobTrailStore store,
  required String documentId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final document = store.documentById(documentId);
      if (document == null) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Dokumen tidak tersedia.'),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup'),
                ),
              ],
            ),
          ),
        );
      }
      final linked = store.applications
          .where((app) => app.documentIds.contains(documentId))
          .toList();
      return _DocumentPreviewSheet(
        document: document,
        linkedApplications: linked,
      );
    },
  ),
);

class _DocumentPreviewSheet extends StatelessWidget {
  const _DocumentPreviewSheet({
    required this.document,
    required this.linkedApplications,
  });

  final AppDocument document;
  final List<Application> linkedApplications;

  @override
  Widget build(BuildContext context) => SafeArea(
    key: const ValueKey('document-preview-sheet'),
    top: false,
    child: SingleChildScrollView(
      key: const ValueKey('document-preview-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pratinjau Metadata',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tutup',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetadataRow(label: 'Judul', value: document.title),
          _MetadataRow(label: 'Kategori', value: document.category.label),
          _MetadataRow(label: 'Nama file', value: document.fileName),
          _MetadataRow(label: 'Versi', value: 'v${document.version}'),
          _MetadataRow(
            label: 'Diperbarui',
            value: formatDocumentDate(document.updatedAt),
          ),
          if (document.notes.trim().isNotEmpty)
            _MetadataRow(label: 'Catatan', value: document.notes),
          if (linkedApplications.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Terhubung dengan lamaran',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 4),
            for (final application in linkedApplications)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '• ${application.company} — ${application.position}',
                  style: AppTypography.caption,
                ),
              ),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Ini hanya pratinjau metadata. File PDF/DOCX belum diunggah '
              'dan belum dapat dibuka.',
              style: TextStyle(fontSize: 11, color: AppColors.primaryDark),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelText = Text(label, style: AppTypography.caption);
        final valueText = Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.navy,
          ),
        );
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(12) > 18) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelText, const SizedBox(height: 4), valueText],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 94, child: labelText),
            const SizedBox(width: 8),
            Expanded(child: valueText),
          ],
        );
      },
    ),
  );
}

String formatDocumentDate(DateTime instant) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  final wib = instant.toUtc().add(const Duration(hours: 7));
  return '${wib.day.toString().padLeft(2, '0')} ${months[wib.month - 1]} ${wib.year}';
}
