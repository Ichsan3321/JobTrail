import 'package:flutter/material.dart';

import '../core/constants/app_tokens.dart';
import '../core/routes/app_navigation.dart';

class BottomNavbar extends StatelessWidget {
  const BottomNavbar({
    super.key,
    required this.selectedTab,
    required this.onSelected,
  });
  final AppTab selectedTab;
  final ValueChanged<AppTab> onSelected;
  static const _labels = ['Beranda', 'Board', 'Jadwal', 'Dokumen', 'Statistik'];
  static const _icons = [
    Icons.grid_view_outlined,
    Icons.work_outline,
    Icons.calendar_today_outlined,
    Icons.description_outlined,
    Icons.bar_chart,
  ];
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.white,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tab in AppTab.values)
            Expanded(
              child: Semantics(
                selected: selectedTab == tab,
                button: true,
                child: InkWell(
                  key: ValueKey('nav-${tab.name}'),
                  onTap: () => onSelected(tab),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 2,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _icons[tab.index],
                            size: 22,
                            color: selectedTab == tab
                                ? AppColors.primary
                                : AppColors.gray,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _labels[tab.index],
                            textAlign: TextAlign.center,
                            style: AppTypography.label.copyWith(
                              fontSize: 10,
                              color: selectedTab == tab
                                  ? AppColors.primary
                                  : AppColors.gray,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
