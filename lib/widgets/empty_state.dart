import 'package:flutter/material.dart';

import '../core/constants/app_tokens.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Text(message, textAlign: TextAlign.center),
  );
}
