import 'package:flutter/material.dart';

import '../core/constants/app_tokens.dart';

/// Shared scaffold content only; individual PICs replace it after Figma review.
class PlaceholderContent extends StatelessWidget {
  const PlaceholderContent({
    super.key,
    required this.screenId,
    required this.title,
    required this.owner,
    this.children = const [],
  });
  final String screenId;
  final String title;
  final String owner;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.lg),
    children: [
      Text(
        '$screenId · $title',
        key: ValueKey(screenId),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text('Placeholder fondasi · PIC: $owner'),
      const Text('UI final dan interaksi screen menunggu implementasi PIC.'),
      const SizedBox(height: AppSpacing.lg),
      for (final child in children) ...[
        child,
        const SizedBox(height: AppSpacing.md),
      ],
      const SizedBox(height: AppSpacing.xl),
    ],
  );
}
