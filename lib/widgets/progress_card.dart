import 'package:flutter/material.dart';

import '../core/constants/app_tokens.dart';

class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key, required this.achieved, required this.target});
  final int achieved;
  final int target;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Target minggu ini'),
          Text('$achieved dari $target lamaran'),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: target <= 0 ? 0 : (achieved / target).clamp(0.0, 1.0),
            color: AppColors.mint,
            backgroundColor: AppColors.primaryLight,
          ),
        ],
      ),
    ),
  );
}
