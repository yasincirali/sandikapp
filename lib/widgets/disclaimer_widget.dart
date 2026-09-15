import 'package:flutter/material.dart';
import '../theme/sandik.dart';
import '../l10n/l10n.dart';

/// Yasal uyarı — sinyal/analiz içeren her ekranın altına eklenir.
class DisclaimerWidget extends StatelessWidget {
  const DisclaimerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.c.overlay,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: context.c.text36),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.disclaimerText,
              style: context.t.labelMedium?.copyWith(
                letterSpacing: 0,
                color: context.c.text36,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
