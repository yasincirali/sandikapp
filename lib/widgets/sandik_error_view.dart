import 'package:flutter/material.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';

class SandikErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const SandikErrorView({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Sandik.loss, size: 40),
            const SizedBox(height: 16),
            Text(
              friendlyError(error),
              textAlign: TextAlign.center,
              style: context.t.titleMedium?.copyWith(color: Sandik.text58),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: Sandik.amber,
                  textStyle: context.t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
