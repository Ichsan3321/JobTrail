import 'package:flutter/material.dart';

import '../../core/constants/app_tokens.dart';
import '../../data/jobtrail_repository.dart';
import '../../data/jobtrail_store.dart';
import '../../models/app_document.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/input_field.dart';
import 'document_preview_sheet.dart';

bool _canSaveDocuments(JobTrailStore store) =>
    store.allowsLocalWrites ||
    (store.isConnected &&
        store.hasSnapshot &&
        !store.isMutating &&
        !store.isRefreshing &&
        (store.phase == StorePhase.ready || store.phase == StorePhase.empty));

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, required this.store, this.isActiveTab});

  final JobTrailStore store;
  // Read live navigation state, not the IndexedStack's shared route state.
  // Standalone screens (e.g. widget tests) own their own route.
  final bool Function()? isActiveTab;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  DocumentCategory? _selectedCategory;
  bool _deleteBusy = false;
  ({String id, bool committed})? _deleteRecovery;

  JobTrailStore get store => widget.store;
  bool get _canWriteDocuments =>
      !_deleteBusy && _deleteRecovery == null && _canSaveDocuments(store);

  bool get _ownsActiveTab => widget.isActiveTab?.call() ?? true;

  // Remote mutations require a positive server revision. Legacy records
  // remain read-only (preview is still available).
  bool _canEditDelete(String id) =>
      _canWriteDocuments &&
      (store.allowsLocalWrites ||
          (store.isConnected && (store.documentRevision(id) ?? 0) > 0));

  @override
  void didUpdateWidget(covariant DocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, store)) {
      _deleteBusy = false;
      _deleteRecovery = null;
    }
  }

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
          if (store.isConnected &&
              store.documents.any((document) => (document.revision ?? 0) <= 0))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Edit dan hapus tidak tersedia untuk dokumen tanpa revisi server.',
                style: TextStyle(fontSize: 11, color: AppColors.gray),
              ),
            ),
          if (_deleteRecovery != null) _buildDeleteRecovery(),
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
                allowWrites: _canEditDelete(document.id),
                allowEdits: _canEditDelete(document.id),
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
            onPressed: _canWriteDocuments ? () => _openDocumentForm() : null,
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
    final activeStore = store;
    if (!_ownsActiveTab ||
        !_canWriteDocuments ||
        (existing != null && !_canEditDelete(existing.id))) {
      return;
    }
    final current = existing == null
        ? null
        : activeStore.documentById(existing.id);
    if (existing != null && current == null) {
      _showMessage(RepositoryIssue.unavailable.message);
      return;
    }
    final revisionAtDraftOpen = current == null
        ? null
        : activeStore.documentRevision(current.id);
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Keep the form route available while a mutation is in flight.
      // Dismiss through Back or Batal, never through a barrier/drag.
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _DocumentFormSheet(
        document: current,
        store: activeStore,
        revisionAtDraftOpen: revisionAtDraftOpen,
        isOwnerActive: () =>
            mounted && identical(store, activeStore) && _ownsActiveTab,
        onLateResult: (message) => _showMutationResult(activeStore, message),
      ),
    );
    if (message != null) _showMutationResult(activeStore, message);
  }

  Future<void> _confirmDelete(AppDocument document) async {
    final activeStore = store;
    if (!_ownsActiveTab || !_canEditDelete(document.id)) return;
    final current = activeStore.documentById(document.id);
    if (current == null) {
      _showMessage(RepositoryIssue.unavailable.message);
      return;
    }
    // Capture before opening the confirmation, never from a later snapshot.
    final revisionBeforeConfirm = activeStore.documentRevision(document.id);
    final linkedApplications = activeStore.applications
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
        content: Text('Metadata "${current.title}" akan dihapus dari daftar.'),
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
    if (!mounted ||
        !identical(store, activeStore) ||
        ModalRoute.of(context)?.isCurrent != true ||
        !_ownsActiveTab ||
        confirmed != true ||
        !_canEditDelete(document.id)) {
      return;
    }
    if (activeStore.documentById(document.id) == null) {
      _showMessage(RepositoryIssue.unavailable.message);
      return;
    }
    if (activeStore.applications.any(
      (application) => application.documentIds.contains(document.id),
    )) {
      _showMessage(RepositoryIssue.documentInUse.message);
      return;
    }

    setState(() => _deleteBusy = true);
    try {
      if (!activeStore.isConnected) {
        activeStore.deleteDocument(document.id);
        _showMutationResult(activeStore, 'Metadata dokumen dihapus.');
        return;
      }
      if (revisionBeforeConfirm == null || revisionBeforeConfirm <= 0) return;
      final result = await activeStore.deleteDocumentRemote(
        document.id,
        revisionBeforeConfirm,
      );
      if (!mounted || !identical(store, activeStore)) return;
      if (!result.snapshotCurrent ||
          activeStore.documentById(result.receipt) != null) {
        setState(() {
          _deleteRecovery = (id: result.receipt, committed: true);
        });
        _showMutationResult(
          activeStore,
          'Penghapusan dikonfirmasi server. Muat ulang daftar dokumen.',
        );
        return;
      }
      _showMutationResult(activeStore, 'Metadata dokumen dihapus.');
    } on RepositoryFailure catch (failure) {
      if (!mounted || !identical(store, activeStore)) return;
      if (failure.writeOutcomeUnknown) {
        setState(() {
          _deleteRecovery = (id: document.id, committed: false);
        });
        _showMutationResult(
          activeStore,
          'Hasil hapus belum terkonfirmasi. Muat ulang sebelum mencoba lagi.',
        );
      } else {
        _showMutationResult(activeStore, failure.issue.message);
      }
    } on StateError catch (error) {
      _showMutationResult(activeStore, error.message);
    } catch (_) {
      if (!mounted || !identical(store, activeStore)) return;
      if (activeStore.isConnected) {
        setState(() {
          _deleteRecovery = (id: document.id, committed: false);
        });
      }
      _showMutationResult(activeStore, RepositoryIssue.unexpected.message);
    } finally {
      if (mounted && identical(store, activeStore)) {
        setState(() => _deleteBusy = false);
      }
    }
  }

  Widget _buildDeleteRecovery() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            _deleteRecovery!.committed
                ? 'Penghapusan dikonfirmasi server. Daftar perlu dimuat ulang.'
                : 'Hasil hapus belum terkonfirmasi. Periksa data terbaru dahulu.',
          ),
        ),
        TextButton(
          key: const ValueKey('documents-delete-refresh'),
          onPressed: _deleteBusy || store.isMutating || store.isRefreshing
              ? null
              : _refreshAfterDelete,
          child: const Text('Muat Ulang Dokumen'),
        ),
      ],
    ),
  );

  Future<void> _refreshAfterDelete() async {
    final activeStore = store;
    final recovery = _deleteRecovery;
    if (recovery == null ||
        _deleteBusy ||
        activeStore.isMutating ||
        activeStore.isRefreshing) {
      return;
    }
    setState(() => _deleteBusy = true);
    try {
      await activeStore.refresh();
      if (!mounted || !identical(store, activeStore)) return;
      if (!_canSaveDocuments(activeStore)) {
        _showMutationResult(
          activeStore,
          activeStore.failure?.issue.message ?? RepositoryIssue.busy.message,
        );
        return;
      }
      final stillPresent = activeStore.documentById(recovery.id) != null;
      setState(() => _deleteRecovery = null);
      _showMutationResult(
        activeStore,
        stillPresent
            ? (recovery.committed
                  ? 'Dokumen muncul pada data terbaru. Periksa sebelum bertindak.'
                  : 'Dokumen masih tersedia. Periksa sebelum mencoba hapus lagi.')
            : (recovery.committed
                  ? 'Metadata dokumen dihapus.'
                  : 'Dokumen tidak ditemukan pada data terbaru.'),
      );
    } finally {
      if (mounted && identical(store, activeStore)) {
        setState(() => _deleteBusy = false);
      }
    }
  }

  void _showMutationResult(JobTrailStore activeStore, String message) {
    // IndexedStack children share the shell route and ScaffoldMessenger.
    // Suppress late feedback outside Documents; never notify the destination.
    if (!mounted ||
        !identical(store, activeStore) ||
        (activeStore.isConnected && !activeStore.hasSnapshot) ||
        !_ownsActiveTab ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _showMessage(message);
  }

  void _showMessage(String message) {
    if (!mounted || !_ownsActiveTab) return;
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
    required this.allowEdits,
  });

  final AppDocument document;
  final VoidCallback onTap;
  final ValueChanged<_DocumentAction> onAction;
  final bool allowWrites;
  final bool allowEdits;

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
                    if (allowEdits)
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

class _DocumentFormSheet extends StatefulWidget {
  const _DocumentFormSheet({
    this.document,
    required this.store,
    required this.onLateResult,
    required this.revisionAtDraftOpen,
    required this.isOwnerActive,
  });

  final AppDocument? document;
  final JobTrailStore store;
  final ValueChanged<String> onLateResult;
  final int? revisionAtDraftOpen;
  final bool Function() isOwnerActive;

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
  bool _saving = false;
  bool _committed = false;
  bool _needsReview = false;
  String? _createId;
  String? _committedId;
  AppDocument? _pendingCreate;
  bool _seenPendingCreate = false;
  bool _confirmingDiscard = false;
  late final Listenable _draftChanges;

  JobTrailStore get store => widget.store;
  bool get _creating => widget.document == null;
  bool get _canSubmit =>
      _canSaveDocuments(store) &&
      (_creating ||
          store.allowsLocalWrites ||
          (store.isConnected &&
              (widget.revisionAtDraftOpen ?? 0) > 0 &&
              (store.documentRevision(widget.document!.id) ?? 0) > 0));
  bool get _lockFields => _saving || _committed || _pendingCreate != null;
  bool get _routeCurrent =>
      mounted &&
      widget.isOwnerActive() &&
      ModalRoute.of(context)?.isCurrent == true;
  bool get _routeActive =>
      mounted &&
      widget.isOwnerActive() &&
      ModalRoute.of(context)?.isActive == true;
  String get _successMessage => _creating
      ? 'Metadata dokumen ditambahkan.'
      : 'Metadata dokumen diperbarui.';

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
    _draftChanges = Listenable.merge([
      store,
      _titleController,
      _fileNameController,
      _versionController,
      _notesController,
    ]);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _fileNameController.dispose();
    _versionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // Compare the raw draft, including whitespace and category-only changes.
  // A committed receipt is not an unsaved draft.
  bool get _dirty {
    final original = widget.document;
    return !_committed &&
        (_pendingCreate != null ||
            _needsReview ||
            _titleController.text != (original?.title ?? '') ||
            _fileNameController.text != (original?.fileName ?? '') ||
            _versionController.text != (original?.version ?? '1.0') ||
            _notesController.text != (original?.notes ?? '') ||
            _category != (original?.category ?? DocumentCategory.cvResume));
  }

  Future<void> _requestClose() async {
    if (_saving || _confirmingDiscard || !_routeCurrent) return;
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    _confirmingDiscard = true;
    final bool? discard;
    try {
      discard = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Buang perubahan?'),
          content: Text(
            _pendingCreate != null || _needsReview
                ? 'Draft ini akan ditutup. Jika hasil simpan belum '
                      'terkonfirmasi, periksa data server sebelum membuat '
                      'atau mengubah dokumen lagi.'
                : 'Perubahan metadata yang belum disimpan akan hilang.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Lanjut mengedit'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Buang perubahan'),
            ),
          ],
        ),
      );
    } finally {
      _confirmingDiscard = false;
    }
    if (!mounted) return;
    if (discard == true && _routeCurrent && !_saving) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _draftChanges,
    builder: (context, _) => PopScope<String>(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving) _requestClose();
      },
      child: _buildForm(context),
    ),
  );

  Widget _buildForm(BuildContext context) => SafeArea(
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
              AbsorbPointer(
                absorbing: _lockFields,
                child: ExcludeFocus(
                  excluding: _lockFields,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InputField(
                        label: 'Judul dokumen',
                        controller: _titleController,
                        validator: _requiredValidator,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<DocumentCategory>(
                        key: const ValueKey('document-form-category'),
                        initialValue: _category,
                        decoration: const InputDecoration(
                          labelText: 'Kategori',
                        ),
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
                    ],
                  ),
                ),
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
              if (_needsReview && !_creating && store.isConnected)
                _buildServerReview(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('document-form-save'),
                  onPressed:
                      _saving || _committed || _needsReview || !_canSubmit
                      ? null
                      : _save,
                  child: Text(
                    _saving
                        ? 'Memproses...'
                        : _pendingCreate != null
                        ? 'Coba Simpan Lagi'
                        : _creating
                        ? 'Simpan Metadata'
                        : 'Simpan Perubahan',
                  ),
                ),
              ),
              if (store.isConnected &&
                  (_committed ||
                      _needsReview ||
                      store.phase == StorePhase.error))
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const ValueKey('document-form-refresh'),
                    onPressed: _saving || store.isMutating || store.isRefreshing
                        ? null
                        : _refreshSnapshot,
                    child: const Text('Muat ulang data'),
                  ),
                ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _saving ? null : _requestClose,
                  child: Text(_committed ? 'Tutup' : 'Batal'),
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

  Widget _buildServerReview() {
    final ready =
        store.hasSnapshot &&
        !store.isRefreshing &&
        !store.isMutating &&
        (store.phase == StorePhase.ready || store.phase == StorePhase.empty);
    final latest = ready ? store.documentById(widget.document!.id) : null;
    final summary = !ready
        ? 'Data server terbaru belum tersedia. Muat ulang untuk meninjau.'
        : latest == null
        ? 'Dokumen tidak tersedia pada snapshot terbaru.'
        : 'Judul: ${latest.title}\n'
              'Kategori: ${latest.category.label}\n'
              'Nama file: ${latest.fileName}\n'
              'Versi file: ${latest.version}\n'
              'Catatan: ${latest.notes}\n'
              'Revisi server: ${latest.revision ?? "-"}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tinjau metadata server'),
            Text(summary, key: const ValueKey('document-server-review')),
            const Text(
              'Draft tidak diubah. Bandingkan isian, lalu tutup form dan '
              'buka intent edit baru jika diperlukan.',
            ),
          ],
        ),
      ),
    );
  }

  bool _sameDocument(AppDocument? a, AppDocument b) =>
      a != null &&
      a.id == b.id &&
      a.updatedAt == b.updatedAt &&
      a.revision == b.revision &&
      a.title == b.title &&
      a.category == b.category &&
      a.fileName == b.fileName &&
      a.version == b.version &&
      a.notes == b.notes;

  Future<void> _refreshSnapshot() async {
    if (_saving || !_routeCurrent) return;
    setState(() => _saving = true);
    await store.refresh();
    if (!_routeActive) return;
    final ready = _canSaveDocuments(store);
    if (_pendingCreate != null && ready) {
      _seenPendingCreate |= store.documentById(_pendingCreate!.id) != null;
    }
    setState(() {
      _saving = false;
      _saveError = !ready
          ? (_committed
                ? 'Metadata sudah disimpan di server, tetapi data terbaru '
                      'belum dapat dimuat. Coba muat ulang.'
                : store.failure?.issue.message ?? RepositoryIssue.busy.message)
          : _committed
          ? (store.documentById(_committedId!) == null
                ? 'Metadata sudah disimpan, tetapi dokumen tidak tersedia '
                      'pada data terbaru.'
                : 'Metadata sudah disimpan. Data terbaru telah dimuat.')
          : _needsReview
          ? (_creating
                ? 'Data terbaru telah dimuat. Catat draft ini sebelum menutup '
                      'form. Periksa metadata terbaru sebelum membuat dokumen lagi.'
                : 'Data terbaru telah dimuat. Draft tetap tersedia; simpan '
                      'salinan isian Anda, lalu tutup form dan tinjau metadata '
                      'terbaru sebelum memulai edit baru. Jangan ulangi update lama.')
          : _pendingCreate != null
          ? 'Hasil simpan belum terkonfirmasi. Coba simpan lagi dengan '
                'ID dan isian yang sama.'
          : 'Data terbaru telah dimuat. Silakan simpan kembali.';
    });
    if (ready &&
        _committed &&
        store.documentById(_committedId!) != null &&
        _routeCurrent) {
      if (!mounted) return;
      Navigator.pop(context, _successMessage);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _committed ||
        _needsReview ||
        !_routeCurrent ||
        !_canSubmit) {
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final original = widget.document;
    if (original != null &&
        (!_sameDocument(store.documentById(original.id), original) ||
            (store.isConnected &&
                store.documentRevision(original.id) !=
                    widget.revisionAtDraftOpen))) {
      setState(() {
        _needsReview = true;
        _saveError = RepositoryIssue.revisionConflict.message;
      });
      return;
    }
    final pending = _pendingCreate;
    if (pending != null &&
        _seenPendingCreate &&
        store.documentById(pending.id) == null) {
      setState(() {
        _needsReview = true;
        _saveError =
            'Dokumen sebelumnya sudah tidak tersedia. '
            'Jangan ulangi pembuatan lama. Tinjau data terbaru terlebih dahulu.';
      });
      return;
    }
    FocusScope.of(context).unfocus();
    final item =
        pending ??
        AppDocument(
          id: original?.id ?? (_createId ??= store.nextDocumentId()),
          title: _titleController.text.trim(),
          category: _category,
          fileName: _fileNameController.text.trim(),
          version: _versionController.text.trim(),
          updatedAt: store.referenceInstantUtc,
          notes: _notesController.text.trim(),
        );
    setState(() {
      _saving = true;
      _saveError = null;
    });
    // Capture before awaiting: the form can be disposed by showTab().
    final onLateResult = widget.onLateResult;
    final activeStore = store;
    final creating = _creating;
    final successMessage = _successMessage;
    try {
      if (store.allowsLocalWrites) {
        store.saveDocument(item);
        if (_routeCurrent) Navigator.pop(context, _successMessage);
        return;
      }
      final result = await activeStore.saveDocumentRemote(
        item,
        creating ? SaveMode.create : SaveMode.update,
        expectedRevision: creating ? null : widget.revisionAtDraftOpen,
      );
      final message = !result.snapshotCurrent
          ? 'Metadata sudah disimpan di server, tetapi data terbaru '
                'belum dapat dimuat. Muat ulang data, jangan simpan ulang.'
          : activeStore.documentById(result.receipt.id) == null
          ? 'Metadata sudah disimpan, tetapi dokumen tidak tersedia '
                'pada data terbaru.'
          : successMessage;
      if (!_routeActive) {
        onLateResult(message);
        return;
      }
      // A receipt proves the write committed; never submit this intent again.
      setState(() {
        _committed = true;
        _committedId = result.receipt.id;
        _pendingCreate = null;
        _saveError = message;
      });
      if (result.snapshotCurrent &&
          store.documentById(result.receipt.id) != null &&
          _routeCurrent) {
        if (!mounted) return;
        Navigator.pop(context, _successMessage);
      }
    } on RepositoryFailure catch (error) {
      if (!_routeActive) {
        if (error.issue != RepositoryIssue.authentication) {
          onLateResult(
            error.writeOutcomeUnknown
                ? 'Hasil simpan dokumen belum terkonfirmasi. '
                      'Periksa data terbaru sebelum mencoba lagi.'
                : error.issue.message,
          );
        }
        return;
      }
      setState(() {
        if (error.writeOutcomeUnknown && _creating) {
          _pendingCreate = item;
          _seenPendingCreate |= store.documentById(item.id) != null;
          _saveError =
              'Hasil simpan belum terkonfirmasi. '
              'Coba lagi dengan ID dan isian yang sama. '
              '${error.issue.message}';
        } else if (error.writeOutcomeUnknown) {
          _needsReview = true;
          _saveError =
              'Hasil perubahan belum terkonfirmasi. '
              'Muat ulang dan tinjau data terbaru sebelum mencoba lagi. '
              '${error.issue.message}';
        } else {
          _needsReview =
              error.issue == RepositoryIssue.revisionConflict ||
              error.issue == RepositoryIssue.createConflict ||
              error.issue == RepositoryIssue.unavailable ||
              error.issue == RepositoryIssue.authentication;
          _saveError = error.issue.message;
          if (_pendingCreate != null && !_needsReview) {
            _saveError =
                '${error.issue.message} '
                'Retry tetap menggunakan ID dan isian awal.';
          }
        }
      });
    } on ArgumentError catch (error) {
      if (_routeActive) {
        setState(() => _saveError = error.message.toString());
      } else {
        onLateResult(RepositoryIssue.unexpected.message);
      }
    } on StateError catch (error) {
      if (_routeActive) {
        setState(() => _saveError = error.message);
      } else {
        onLateResult(RepositoryIssue.unexpected.message);
      }
    } catch (_) {
      if (_routeActive) {
        setState(() {
          _needsReview = store.isConnected;
          _saveError = RepositoryIssue.unexpected.message;
        });
      } else {
        onLateResult(RepositoryIssue.unexpected.message);
      }
    } finally {
      if (_routeActive) setState(() => _saving = false);
    }
  }
}
