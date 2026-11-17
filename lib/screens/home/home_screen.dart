import 'package:flutter/material.dart';

import '../../core/constants/app_dates.dart';
import '../../core/constants/app_tokens.dart';
import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_store.dart';
import '../../models/agenda.dart';
import '../../models/application.dart';
import '../../models/recruitment_status.dart';
import '../../widgets/status_chip.dart';

const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
TextStyle _text(
  double size, {
  Color color = AppColors.navy,
  bool bold = false,
}) => TextStyle(
  fontFamily: AppTypography.bodyFamily,
  fontSize: size,
  color: color,
  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
);
Widget _label(
  String value,
  double size, {
  Color color = AppColors.navy,
  bool bold = false,
}) => Text(
  value,
  style: _text(size, color: color, bold: bold),
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.navigation});
  final JobTrailStore store;
  final AppNavigation navigation;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Set<String> _read = {};
  JobTrailStore get store => widget.store;
  int get remaining =>
      (store.weeklyGoal.target - store.weeklyAchieved).clamp(0, 1 << 30);
  String get percent =>
      '${(store.weeklyProgress * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
  Widget _progress({bool light = false}) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: LinearProgressIndicator(
      minHeight: 10,
      value: store.weeklyProgress,
      color: light ? AppColors.mint : AppColors.primary,
      backgroundColor: light ? Colors.white24 : Colors.white,
    ),
  );
  Widget _surface(
    Widget child, {
    Color color = Colors.white,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
  Widget _close(BuildContext context) => IconButton(
    tooltip: 'Tutup',
    onPressed: () => Navigator.pop(context),
    style: IconButton.styleFrom(backgroundColor: AppColors.background),
    icon: const Icon(Icons.close, color: AppColors.gray),
  );
  void _sheet(double height, Widget Function(BuildContext, StateSetter) body) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0xCC1E2435),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => FractionallySizedBox(
        heightFactor: height,
        child: SafeArea(top: false, child: StatefulBuilder(builder: body)),
      ),
    );
  }

  Widget _sheetHeader(BuildContext context, String title, String subtitle) =>
      Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.section.copyWith(fontSize: 20),
                      ),
                      _label(subtitle, 13, color: AppColors.gray),
                    ],
                  ),
                ),
                _close(context),
              ],
            ),
          ),
          const Divider(color: AppColors.border),
        ],
      );
  void notifications() {
    var unreadOnly = false;
    _sheet(
      .78,
      (context, refresh) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final agendas = store.agendas
              .where((a) => !unreadOnly || !_read.contains(a.id))
              .toList();
          return Column(
            children: [
              _sheetHeader(
                context,
                'Notifikasi',
                'Jangan lewatkan perkembangan lamaranmu',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _filter(
                      'Semua (${store.agendas.length + 1})',
                      !unreadOnly,
                      () => refresh(() => unreadOnly = false),
                    ),
                    _filter(
                      'Belum dibaca ${store.agendas.where((a) => !_read.contains(a.id)).length}',
                      unreadOnly,
                      () => refresh(() => unreadOnly = true),
                    ),
                    TextButton(
                      onPressed: () => refresh(
                        () => setState(
                          () => _read.addAll(store.agendas.map((a) => a.id)),
                        ),
                      ),
                      child: Text(
                        'Tandai dibaca',
                        style: _text(12, color: AppColors.primary, bold: true),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final a in agendas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _notification(a),
                      ),
                    if (!unreadOnly)
                      _surface(
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.track_changes,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Progress mingguan', 14, bold: true),
                                  _label(
                                    '${store.weeklyAchieved} dari ${store.weeklyGoal.target} lamaran telah tercatat. Tinggal $remaining lagi untuk mencapai targetmu.',
                                    13,
                                    color: AppColors.gray,
                                  ),
                                  _label(
                                    'Target minggu ini',
                                    12,
                                    color: AppColors.gray,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        color: const Color(0xFFFAFAFF),
                      ),
                    if (unreadOnly && agendas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Tidak ada notifikasi belum dibaca.'),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filter(String text, bool selected, VoidCallback tap) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: _label(
          text,
          12,
          color: selected ? AppColors.primaryDark : AppColors.gray,
          bold: selected,
        ),
      ),
    ),
  );
  Widget _notification(Agenda a) => InkWell(
    onTap: () {
      setState(() => _read.add(a.id));
      Navigator.pop(context);
      widget.navigation.openDetail(a.applicationId);
    },
    child: _surface(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tileIcon(a),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(
                  a.type == AgendaType.interview
                      ? 'Interview mendatang'
                      : 'Psikotes terjadwal',
                  14,
                  bold: true,
                ),
                _label(
                  store.applicationById(a.applicationId)?.company ?? '',
                  13,
                  color: AppColors.gray,
                ),
                _label(
                  '${AppDates.formatWib(a.scheduledAt)} · ${a.locationOrLink}',
                  12,
                  color: AppColors.gray,
                ),
              ],
            ),
          ),
          if (!_read.contains(a.id))
            const Icon(
              Icons.radio_button_checked,
              size: 16,
              color: AppColors.primary,
            ),
        ],
      ),
      color: const Color(0xFFFAFAFF),
    ),
  );
  Widget _tileIcon(Agenda a) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: a.type == AgendaType.interview
          ? const Color(0xFFE0F2FE)
          : const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(
      a.type == AgendaType.interview
          ? Icons.calendar_today_outlined
          : Icons.fact_check_outlined,
      color: a.type == AgendaType.interview
          ? const Color(0xFF0369A1)
          : const Color(0xFFB45309),
      size: 22,
    ),
  );
  void weeklyGoal() {
    int? selected;
    _sheet(
      .69,
      (context, refresh) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final start = store.weeklyGoal.weekStart;
          final day = start.add(Duration(days: selected ?? 0));
          final apps = store.applicationsInPeriod(
            start: day,
            end: day.add(const Duration(days: 1)),
          );
          return Column(
            children: [
              _sheetHeader(
                context,
                'Target Mingguan',
                '${AppDates.formatDate(start)} – ${AppDates.formatDate(start.add(const Duration(days: 6)))}',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _surface(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(
                            'Lamaran terkirim minggu ini',
                            13,
                            color: AppColors.gray,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: 20,
                            children: [
                              _label(
                                '${store.weeklyAchieved} / ${store.weeklyGoal.target} lamaran',
                                22,
                                bold: true,
                              ),
                              _label(
                                percent,
                                14,
                                color: AppColors.primaryDark,
                                bold: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _progress(),
                          const SizedBox(height: 8),
                          _label(
                            '$remaining lamaran lagi untuk mencapai target',
                            12,
                            color: AppColors.gray,
                          ),
                        ],
                      ),
                      color: AppColors.primaryLight,
                      padding: const EdgeInsets.all(18),
                    ),
                    const SizedBox(height: 20),
                    _label('Aktivitas Minggu Ini', 15, bold: true),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (var i = 0; i < 7; i++)
                            SizedBox(
                              width: (constraints.maxWidth - 30) / 7,
                              child: _filter(
                                '${_days[i]}\n${store.applicationsInPeriod(
                                  start: start.add(Duration(days: i)),
                                  end: start.add(Duration(days: i + 1)),
                                ).length}',
                                selected == i,
                                () => refresh(() => selected = i),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _surface(
                      _label(
                        selected == null
                            ? 'Ketuk hari untuk melihat ringkasan lamaran.'
                            : '${AppDates.formatDate(day)}: ${apps.length} lamaran',
                        12,
                        color: AppColors.gray,
                      ),
                      color: AppColors.background,
                      padding: const EdgeInsets.all(12),
                    ),
                    if (selected != null)
                      for (final app in apps)
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.navigation.openDetail(app.id);
                          },
                          child: Text(app.company),
                        ),
                    const SizedBox(height: 20),
                    _surface(
                      Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department_outlined,
                            color: Color(0xFFEA7600),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('Konsistensi mingguan', 14, bold: true),
                                _label(
                                  'Data streak belum tersedia.',
                                  12,
                                  color: AppColors.gray,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final dist = store.distribution();
      final agendas =
          store.agendas
              .where(
                (a) =>
                    !AppDates.wibDate(a.scheduledAt)
                        .isBefore(store.referenceDate),
              )
              .toList()
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      final apps = store.applications.toList()
        ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
      return Stack(
        key: const ValueKey('S01'),
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 88),
            children: [
              Row(
                children: [
                  Semantics(
                    label: 'JobTrail',
                    image: true,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/home/logo-background.png',
                            ),
                          ),
                          Positioned(
                            left: 20.3,
                            top: 8.3,
                            width: 6.4,
                            height: 6.4,
                            child: Image.asset('assets/home/logo-dot.png'),
                          ),
                          Positioned(
                            left: 13,
                            top: 16,
                            width: 12,
                            height: 17,
                            child: Image.asset('assets/home/logo-letter.png'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Selamat datang,', 12, color: AppColors.gray),
                        _label('Lanjutkan perjalananmu', 17, bold: true),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Notifikasi',
                    onPressed: notifications,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.border),
                    ),
                    icon: Stack(
                      children: [
                        const Icon(Icons.notifications_outlined, size: 22),
                        if (store.agendas.any((a) => !_read.contains(a.id)))
                          const Positioned(
                            right: 0,
                            top: 0,
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: AppColors.peach,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Semantics(
                button: true,
                key: const ValueKey('home-weekly-goal'),
                label: 'Detail target mingguan',
                child: GestureDetector(
                  onTap: weeklyGoal,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6259F5), Color(0xFF4841E7)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -30,
                          top: -40,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0x18FFFFFF),
                            ),
                          ),
                        ),
                        Positioned(
                          left: -30,
                          bottom: -35,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0x182DD4A7),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: 16,
                                runSpacing: 6,
                                children: [
                                  _label(
                                    'Target minggu ini',
                                    13,
                                    color: Colors.white70,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.peachTint,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: _label(
                                      'Streak belum tersedia',
                                      10,
                                      color: const Color(0xFFB45309),
                                      bold: true,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _label(
                                '${store.weeklyAchieved} dari ${store.weeklyGoal.target} lamaran',
                                24,
                                color: Colors.white,
                                bold: true,
                              ),
                              const SizedBox(height: 12),
                              _progress(light: true),
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: 16,
                                children: [
                                  _label(
                                    '$remaining lamaran lagi untuk capai target',
                                    12,
                                    color: Colors.white,
                                  ),
                                  _label(
                                    percent,
                                    12,
                                    color: AppColors.mint,
                                    bold: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in [
                      (
                        'Total',
                        store.applications.length,
                        Colors.white,
                        AppColors.navy,
                        '+${store.weeklyAchieved} mgg ini',
                      ),
                      (
                        'Interview',
                        dist[RecruitmentStatus.interview]!,
                        const Color(0xFFE0F2FE),
                        const Color(0xFF0369A1),
                        '${agendas.where((a) => a.type == AgendaType.interview).length} mendatang',
                      ),
                      (
                        'Offering',
                        dist[RecruitmentStatus.offering]!,
                        const Color(0xFFD1FAE5),
                        const Color(0xFF047857),
                        'Review',
                      ),
                    ])
                      SizedBox(
                        width: MediaQuery.textScalerOf(context).scale(12) > 18
                            ? c.maxWidth
                            : (c.maxWidth - 20) / 3,
                        child: _surface(
                          Column(
                            children: [
                              _label(item.$1, 12, color: item.$4),
                              const SizedBox(height: 2),
                              Text(
                                '${item.$2}',
                                key: item.$1 == 'Total'
                                    ? const ValueKey('home-total')
                                    : null,
                                style: _text(24, color: item.$4, bold: true),
                              ),
                              _label(item.$5, 10, color: item.$4),
                            ],
                          ),
                          color: item.$3,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                children: [
                  _label('Jadwal Terdekat', 16, bold: true),
                  TextButton(
                    onPressed: () => widget.navigation.showTab(AppTab.schedule),
                    child: _label(
                      'Lihat semua ›',
                      13,
                      color: AppColors.primary,
                      bold: true,
                    ),
                  ),
                ],
              ),
              if (agendas.isEmpty)
                _label(
                  'Tidak ada jadwal mendatang.',
                  13,
                  color: AppColors.gray,
                ),
              for (final a in agendas.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => widget.navigation.openDetail(a.applicationId),
                    child: _surface(
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 54,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: a.type == AgendaType.interview
                                  ? const Color(0xFFE0F2FE)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                _label(
                                  _days[AppDates.wibDate(a.scheduledAt)
                                              .weekday -
                                          1]
                                      .toUpperCase(),
                                  10,
                                ),
                                _label(
                                  '${AppDates.wibDate(a.scheduledAt).day}',
                                  20,
                                  bold: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label(
                                  a.type == AgendaType.interview
                                      ? 'Interview User'
                                      : 'Psikotes Online',
                                  14,
                                  bold: true,
                                ),
                                _label(
                                  store
                                          .applicationById(a.applicationId)
                                          ?.company ??
                                      '',
                                  13,
                                  color: AppColors.gray,
                                ),
                                _label(
                                  '${AppDates.formatWib(a.scheduledAt)} · ${a.locationOrLink}',
                                  11,
                                  color: AppColors.gray,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                children: [
                  _label('Lamaran Terbaru', 16, bold: true),
                  _label('${apps.length} Terdaftar', 12, color: AppColors.gray),
                ],
              ),
              if (apps.isEmpty) const Text('Belum ada lamaran.'),
              for (final app in apps.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _application(app),
                ),
            ],
          ),
          Positioned(
            right: 20,
            bottom: 16,
            child: FloatingActionButton(
              key: const ValueKey('home-add'),
              onPressed: widget.navigation.openAdd,
              tooltip: 'Tambah Lamaran',
              shape: const CircleBorder(),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              child: const Icon(Icons.add, size: 36),
            ),
          ),
        ],
      );
    },
  );
  Widget _application(Application app) => InkWell(
    onTap: () => widget.navigation.openDetail(app.id),
    borderRadius: BorderRadius.circular(20),
    child: _surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _label(
                  app.company
                      .split(' ')
                      .where((s) => s.isNotEmpty)
                      .take(2)
                      .map((s) => s[0])
                      .join(),
                  13,
                  color: AppColors.primary,
                  bold: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(app.company, 14, bold: true),
                    _label(
                      '${app.location} · ${app.workType.label}',
                      12,
                      color: AppColors.gray,
                    ),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width >= 350 &&
                  MediaQuery.textScalerOf(context).scale(12) <= 15)
                StatusChip(status: app.status),
            ],
          ),
          if (MediaQuery.sizeOf(context).width < 350 ||
              MediaQuery.textScalerOf(context).scale(12) > 15)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [StatusChip(status: app.status)],
            ),
          const Divider(height: 12, color: AppColors.border),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 10,
            children: [
              _label(app.position, 12, bold: true),
              _label(
                AppDates.formatDate(app.appliedAt),
                11,
                color: AppColors.gray,
              ),
            ],
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
    ),
  );
}
