part of 'board_screen.dart';

/// Applied filter state returned by the Filter & Urutkan sheet.
class _BoardFilter {
  const _BoardFilter({required this.sort, required this.sources});
  final BoardSort sort;
  final Set<String> sources;
}

/// Shared sheet chrome per Figma: white, top radius 28, handle, title + close.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.header,
    required this.children,
    this.spacing = 16,
  });
  final Widget header;
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          28 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: const ShapeDecoration(
                  color: AppColors.border,
                  shape: StadiumBorder(),
                ),
              ),
            ),
            SizedBox(height: spacing),
            header,
            for (final child in children) ...[SizedBox(height: spacing), child],
          ],
        ),
      ),
    ),
  );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Tutup',
    child: Material(
      color: AppColors.background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).pop(),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.close, size: 18, color: AppColors.navy),
        ),
      ),
    ),
  );
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
    color: primary ? AppColors.primary : AppColors.primaryLight,
    borderRadius: BorderRadius.circular(AppRadius.button),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.button),
      onTap: onPressed,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: _jakarta(
            15,
            FontWeight.w700,
            primary ? AppColors.white : AppColors.primaryDark,
          ),
        ),
      ),
    ),
  );
}

/// Figma 173:3304 Sheet/Filter & Urutkan. Changes apply only on Terapkan.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.sources});
  final _BoardFilter initial;
  final List<String> sources;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late BoardSort _sort = widget.initial.sort;
  late Set<String> _sources = {...widget.initial.sources};

  @override
  Widget build(BuildContext context) => _SheetFrame(
    spacing: 18,
    header: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter & Urutkan',
                style: _jakarta(18, FontWeight.w800, AppColors.navy),
              ),
              const SizedBox(height: 2),
              Text(
                'Atur tampilan daftar lamaranmu',
                style: _jakarta(12, FontWeight.w400, AppColors.gray),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const _CloseButton(),
      ],
    ),
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Urutkan berdasarkan',
            style: _jakarta(13, FontWeight.w700, AppColors.navy),
          ),
          for (final option in BoardSort.values) ...[
            const SizedBox(height: AppSpacing.xs),
            _SortOption(
              key: ValueKey('board-sheet-sort-${option.name}'),
              label: option.sheetLabel,
              selected: option == _sort,
              onTap: () => setState(() => _sort = option),
            ),
          ],
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sumber lowongan',
            style: _jakarta(13, FontWeight.w700, AppColors.navy),
          ),
          const SizedBox(height: 10),
          if (widget.sources.isEmpty)
            Text(
              'Belum ada sumber lowongan tercatat.',
              style: _jakarta(12, FontWeight.w400, AppColors.gray),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final source in widget.sources)
                  _SourceChip(
                    key: ValueKey('board-sheet-source-$source'),
                    label: source,
                    selected: _sources.contains(source),
                    onTap: () => setState(() {
                      _sources.contains(source)
                          ? _sources.remove(source)
                          : _sources.add(source);
                    }),
                  ),
              ],
            ),
        ],
      ),
      Row(
        children: [
          SizedBox(
            width: 110,
            child: _SheetButton(
              key: const ValueKey('board-sheet-reset'),
              label: 'Reset',
              onPressed: () => setState(() {
                _sort = BoardSort.newest;
                _sources = {};
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SheetButton(
              key: const ValueKey('board-sheet-apply'),
              label: 'Terapkan Filter',
              primary: true,
              onPressed: () => Navigator.of(context).pop(
                _BoardFilter(sort: _sort, sources: Set.unmodifiable(_sources)),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _SortOption extends StatelessWidget {
  const _SortOption({
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
    selected: selected,
    inMutuallyExclusiveGroup: true,
    child: Material(
      color: selected ? AppColors.primaryLight : AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: _jakarta(14, FontWeight.w600, AppColors.navy),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
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
    selected: selected,
    button: true,
    child: Material(
      color: selected ? AppColors.primaryLight : AppColors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: _jakarta(
              13,
              FontWeight.w600,
              selected ? AppColors.primaryDark : AppColors.navy,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Figma 173:3582 Sheet/Pratinjau Lamaran. Pops `true` for Buka Detail.
class _PreviewSheet extends StatefulWidget {
  const _PreviewSheet({required this.store, required this.applicationId});
  final JobTrailStore store;
  final String applicationId;

  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  String? _error;

  Future<void> _changeStatus(Application app) async {
    final status = await showModalBottomSheet<RecruitmentStatus>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatusPickerSheet(current: app.status),
    );
    if (status == null || !mounted) return;
    try {
      widget.store.changeStatus(app.id, status);
      setState(() => _error = null);
    } on ArgumentError catch (error) {
      setState(() => _error = '${error.message}');
    } on StateError catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final app = widget.store.applicationById(widget.applicationId);
      if (app == null) {
        return _SheetFrame(
          header: Row(
            children: [
              Expanded(
                child: Text(
                  'Lamaran tidak ditemukan.',
                  style: _jakarta(15, FontWeight.w700, AppColors.navy),
                ),
              ),
              const _CloseButton(),
            ],
          ),
          children: const [],
        );
      }
      final documents = [
        for (final id in app.documentIds)
          if (widget.store.documentById(id) case final doc?) doc.title,
      ];
      final agenda = _highlightAgenda(
        widget.store.agendasFor(app.id),
        widget.store.referenceDate,
      );
      final upcoming =
          agenda != null &&
          !_wib(agenda.scheduledAt).isBefore(widget.store.referenceDate);
      return _SheetFrame(
        header: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardStatusChip(status: app.status),
                  const SizedBox(height: 6),
                  Text(
                    app.company,
                    key: const ValueKey('board-preview-company'),
                    style: _jakarta(20, FontWeight.w800, AppColors.navy),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    app.position,
                    style: _jakarta(14, FontWeight.w700, AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const _CloseButton(),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoItem(
                      label: 'Tanggal melamar',
                      value: _formatDate(app.appliedAt),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _InfoItem(label: 'Sumber', value: app.source),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoItem(
                      label: 'Lokasi & tipe kerja',
                      value: '${app.location} · ${app.workType.label}',
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _InfoItem(
                      label: 'Dokumen dipakai',
                      value: documents.isEmpty ? '-' : documents.join(', '),
                      accent: documents.isNotEmpty,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (agenda != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: RecruitmentStatus.interview.background,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 20,
                    color: RecruitmentStatus.interview.foreground,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          upcoming ? 'Agenda berikutnya' : 'Agenda terakhir',
                          style: _jakarta(
                            11,
                            FontWeight.w700,
                            RecruitmentStatus.interview.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatAgenda(agenda),
                          style: _jakarta(13, FontWeight.w700, AppColors.navy),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Catatan',
                style: _jakarta(13, FontWeight.w700, AppColors.navy),
              ),
              const SizedBox(height: 4),
              Text(
                app.notes.trim().isEmpty ? 'Belum ada catatan.' : app.notes,
                style: _jakarta(13, FontWeight.w400, AppColors.gray),
              ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              key: const ValueKey('board-preview-error'),
              style: _jakarta(
                12,
                FontWeight.w600,
                RecruitmentStatus.rejected.foreground,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _SheetButton(
                  key: const ValueKey('board-preview-status'),
                  label: 'Ubah Status',
                  onPressed: () => _changeStatus(app),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetButton(
                  key: const ValueKey('board-preview-detail'),
                  label: 'Buka Detail',
                  primary: true,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.label,
    required this.value,
    this.accent = false,
  });
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _jakarta(11, FontWeight.w400, AppColors.gray)),
        const SizedBox(height: 2),
        Text(
          value,
          style: _jakarta(
            13,
            FontWeight.w700,
            accent ? AppColors.primaryDark : AppColors.navy,
          ),
        ),
      ],
    ),
  );
}

/// Status picker for the preview's Ubah Status. No S02 Figma frame exists for
/// this step; it reuses the sheet chrome and shared status colors.
class _StatusPickerSheet extends StatelessWidget {
  const _StatusPickerSheet({required this.current});
  final RecruitmentStatus current;

  @override
  Widget build(BuildContext context) => _SheetFrame(
    spacing: 12,
    header: Row(
      children: [
        Expanded(
          child: Text(
            'Ubah Status',
            style: _jakarta(18, FontWeight.w800, AppColors.navy),
          ),
        ),
        const _CloseButton(),
      ],
    ),
    children: [
      for (final status in RecruitmentStatus.values)
        _SortOption(
          key: ValueKey('board-status-${status.name}'),
          label: status.label,
          selected: status == current,
          onTap: () => Navigator.of(context).pop(status),
        ),
    ],
  );
}

/// Figma 173:3813 Pencarian Kosong.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('board-no-match'),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.border, width: 1.5),
    ),
    child: Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.search, size: 22, color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Tidak ada lamaran yang cocok',
          textAlign: TextAlign.center,
          style: _jakarta(15, FontWeight.w800, AppColors.navy),
        ),
        const SizedBox(height: 4),
        Text(
          'Coba kata kunci lain atau ubah filter status.',
          textAlign: TextAlign.center,
          style: _jakarta(12, FontWeight.w400, AppColors.gray),
        ),
        const SizedBox(height: AppSpacing.md),
        IntrinsicWidth(
          child: _SheetButton(
            key: const ValueKey('board-reset-search'),
            label: 'Reset Pencarian',
            onPressed: onReset,
          ),
        ),
      ],
    ),
  );
}
