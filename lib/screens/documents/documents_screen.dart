import 'package:flutter/material.dart';

import '../../core/constants/app_tokens.dart';
import '../../data/jobtrail_store.dart';
import '../../models/app_document.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/input_field.dart';
import 'document_preview_sheet.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, required this.store});

  final JobTrailStore store;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  DocumentCategory? _selectedCategory;

  JobTrailStore get store => widget.store;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppDocument> _visibleDocuments() {
    final query = _query.trim().toLowerCase();
    final documents = store.documents.where((document) {
      final matchesCategory =
          _selectedCategory == null || document.category == _selectedCategory;
      final searchable = [
        document.title,
        document.fileName,
        document.version,
        document.category.label,
        document.notes,
      ].join(' ').toLowerCase();
      return matchesCategory && (query.isEmpty || searchable.contains(query));
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return documents;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final documents = _visibleDocuments();
      final total = store.documents.length;
      return ListView(
        key: const ValueKey('S06'),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _buildHeader(total),
          const SizedBox(height: 18),
          _buildSearchField(),
          const SizedBox(height: 12),
          _buildCategoryFilters(),
          const SizedBox(height: 20),
          _buildStorageSummary(total),
          const SizedBox(height: 12),
          if (documents.isEmpty)
            _buildEmptyState(total)
          else
            for (final document in documents) ...[
              _DocumentCard(
                key: ValueKey('document-card-${document.id}'),
                document: document,
                allowWrites: store.allowsLocalWrites,
                onTap: () => _showPreview(document),
                onAction: (action) => _handleAction(action, document),
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 12),
          Center(
            child: Text(
              store.isConnected
                  ? 'Metadata akun dari server.'
                  : 'Metadata disimpan lokal. File PDF/DOCX belum diunggah.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.gray),
            ),
          ),
        ],
      );
    },
  );

  Widget _buildHeader(int total) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dokumen Saya',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: AppTypography.headingFamily,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$total berkas tersimpan untuk lamaran',
              style: const TextStyle(fontSize: 11, color: AppColors.gray),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Tooltip(
        message: 'Tambah dokumen',
        child: SizedBox(
          width: 48,
          height: 48,
          child: FilledButton(
            key: const ValueKey('documents-add'),
            onPressed: store.allowsLocalWrites
                ? () => _openDocumentForm()
                : null,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 48),
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Icon(Icons.add, size: 24),
          ),
        ),
      ),
    ],
  );

  Widget _buildSearchField() => SizedBox(
    height: 48,
    child: TextField(
      key: const ValueKey('documents-search'),
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 12, color: AppColors.navy),
      decoration: InputDecoration(
        hintText: 'Cari CV, portofolio, versi...',
        hintStyle: const TextStyle(fontSize: 12, color: AppColors.gray),
        prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.gray),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Hapus pencarian',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close, size: 17),
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    ),
  );

  Widget _buildCategoryFilters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _FilterChip(
          key: const ValueKey('documents-filter-all'),
          label: 'Semua',
          selected: _selectedCategory == null,
          onTap: () => setState(() => _selectedCategory = null),
        ),
        const SizedBox(width: 6),
        for (final category in DocumentCategory.values) ...[
          _FilterChip(
            key: ValueKey('documents-filter-${category.name}'),
            label: category.label,
            selected: _selectedCategory == category,
            onTap: () => setState(() => _selectedCategory = category),
          ),
          const SizedBox(width: 6),
        ],
      ],
    ),
  );

  Widget _buildStorageSummary(int total) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.folder_open_outlined,
            size: 17,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Penyimpanan Berkas',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                store.isConnected
                    ? '$total metadata dokumen akun'
                    : '$total metadata dokumen tersimpan lokal',
                style: const TextStyle(fontSize: 11, color: AppColors.gray),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: const Text(
            'PDF/DOCX',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildEmptyState(int total) {
    final hasFilter = _query.trim().isNotEmpty || _selectedCategory != null;
    return Padding(
      padding: const EdgeInsets.only(top: 34),
      child: EmptyState(
        message: hasFilter
            ? 'Tidak ada dokumen yang cocok dengan pencarian atau filter.'
            : total == 0
            ? 'Belum ada dokumen. Tambahkan metadata CV atau portofolio.'
            : 'Belum ada dokumen pada kategori ini.',
      ),
    );
  }

  void _handleAction(_DocumentAction action, AppDocument document) {
    switch (action) {
      case _DocumentAction.preview:
        _showPreview(document);
        break;
      case _DocumentAction.edit:
        _openDocumentForm(document);
        break;
      case _DocumentAction.delete:
        _confirmDelete(document);
        break;
    }
  }

  Future<void> _showPreview(AppDocument document) async {
    await showDocumentPreview(context, store: store, documentId: document.id);
  }

  Future<void> _openDocumentForm([AppDocument? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _DocumentFormSheet(
        document: existing,
        onSave: (value) {
          store.saveDocument(
            AppDocument(
              id: existing?.id ?? store.nextDocumentId(),
              title: value.title,
              category: value.category,
              fileName: value.fileName,
              version: value.version,
              updatedAt: store.referenceInstantUtc,
              notes: value.notes,
            ),
          );
        },
      ),
    );
    if (!mounted || saved != true) return;
    _showMessage(
      existing == null
          ? 'Metadata dokumen ditambahkan.'
          : 'Metadata dokumen diperbarui.',
    );
  }

  Future<void> _confirmDelete(AppDocument document) async {
    final linkedApplications = store.applications
        .where((application) => application.documentIds.contains(document.id))
        .toList();
    if (linkedApplications.isNotEmpty) {
      final names = linkedApplications.map((item) => item.company).join(', ');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Dokumen masih digunakan'),
          content: Text(
            'Dokumen ini masih terhubung dengan: $names. '
            'Lepaskan referensinya melalui pengelolaan lamaran sebelum '
            'menghapus dokumen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus dokumen?'),
        content: Text('Metadata "${document.title}" akan dihapus dari daftar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      store.deleteDocument(document.id);
      _showMessage('Metadata dokumen dihapus.');
    } on StateError catch (error) {
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Ink(
              decoration: ShapeDecoration(
                color: selected ? AppColors.primary : AppColors.white,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 6,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.white : AppColors.gray,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    super.key,
    required this.document,
    required this.onTap,
    required this.onAction,
    required this.allowWrites,
  });

  final AppDocument document;
  final VoidCallback onTap;
  final ValueChanged<_DocumentAction> onAction;
  final bool allowWrites;

  Color get _iconBackground => switch (document.category) {
    DocumentCategory.cvResume => AppColors.primaryLight,
    DocumentCategory.portfolio => AppColors.peachTint,
  };

  Color get _iconColor => switch (document.category) {
    DocumentCategory.cvResume => AppColors.primary,
    DocumentCategory.portfolio => const Color(0xFFFF9A55),
  };

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppColors.border),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _iconBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: _iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          document.title,
                          key: ValueKey('document-title-${document.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 5),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              'v${document.version}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.gray,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          document.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.gray,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<_DocumentAction>(
                  key: ValueKey('document-menu-${document.id}'),
                  tooltip: 'Aksi dokumen',
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.more_vert,
                    size: 20,
                    color: AppColors.gray,
                  ),
                  onSelected: onAction,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _DocumentAction.preview,
                      child: Text('Lihat metadata'),
                    ),
                    if (allowWrites)
                      const PopupMenuItem(
                        value: _DocumentAction.edit,
                        child: Text('Edit metadata'),
                      ),
                    if (allowWrites)
                      const PopupMenuItem(
                        value: _DocumentAction.delete,
                        child: Text('Hapus dokumen'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              spacing: 12,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    document.category.label,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                Text(
                  formatDocumentDate(document.updatedAt),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 10, color: AppColors.gray),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

enum _DocumentAction { preview, edit, delete }

class _DocumentFormValue {
  const _DocumentFormValue({
    required this.title,
    required this.category,
    required this.fileName,
    required this.version,
    required this.notes,
  });

  final String title;
  final DocumentCategory category;
  final String fileName;
  final String version;
  final String notes;
}

class _DocumentFormSheet extends StatefulWidget {
  const _DocumentFormSheet({this.document, required this.onSave});

  final AppDocument? document;
  final ValueChanged<_DocumentFormValue> onSave;

  @override
  State<_DocumentFormSheet> createState() => _DocumentFormSheetState();
}

class _DocumentFormSheetState extends State<_DocumentFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _fileNameController;
  late final TextEditingController _versionController;
  late final TextEditingController _notesController;
  late DocumentCategory _category;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final document = widget.document;
    _titleController = TextEditingController(text: document?.title ?? '');
    _fileNameController = TextEditingController(text: document?.fileName ?? '');
    _versionController = TextEditingController(
      text: document?.version ?? '1.0',
    );
    _notesController = TextEditingController(text: document?.notes ?? '');
    _category = document?.category ?? DocumentCategory.cvResume;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _fileNameController.dispose();
    _versionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
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
              Text(
                widget.document == null ? 'Tambah Dokumen' : 'Edit Metadata',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Isi informasi dokumen. File aslinya belum diunggah.',
                style: TextStyle(fontSize: 12, color: AppColors.gray),
              ),
              const SizedBox(height: 18),
              InputField(
                label: 'Judul dokumen',
                controller: _titleController,
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<DocumentCategory>(
                key: const ValueKey('document-form-category'),
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: [
                  for (final category in DocumentCategory.values)
                    DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              InputField(
                label: 'Nama file',
                controller: _fileNameController,
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              InputField(
                label: 'Versi',
                controller: _versionController,
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              InputField(
                label: 'Catatan (opsional)',
                controller: _notesController,
                maxLines: 3,
              ),
              const SizedBox(height: 18),
              if (_saveError != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _saveError!,
                    key: const ValueKey('document-form-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('document-form-save'),
                  onPressed: _save,
                  child: Text(
                    widget.document == null
                        ? 'Simpan Metadata'
                        : 'Simpan Perubahan',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String? _requiredValidator(String? value) =>
      value == null || value.trim().isEmpty ? 'Bagian ini wajib diisi.' : null;

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saveError = null);
    try {
      widget.onSave(
        _DocumentFormValue(
          title: _titleController.text.trim(),
          category: _category,
          fileName: _fileNameController.text.trim(),
          version: _versionController.text.trim(),
          notes: _notesController.text.trim(),
        ),
      );
    } on ArgumentError catch (error) {
      setState(() => _saveError = error.message.toString());
      return;
    } on StateError catch (error) {
      setState(() => _saveError = error.message);
      return;
    }
    Navigator.pop(context, true);
  }
}
