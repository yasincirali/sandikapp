import 'package:flutter/material.dart';
import '../theme/sandik.dart';

/// Yasal uyarı — sinyal/analiz içeren her ekranın altına eklenir.
class DisclaimerWidget extends StatelessWidget {
  const DisclaimerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 14, color: Sandik.text36),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Bu uygulama yalnızca bilgilendirme amaçlıdır. '
              'Gösterilen veriler, analizler ve bildirimler kesinlikle '
              'yatırım tavsiyesi, alım-satım önerisi veya finansal danışmanlık '
              'niteliği taşımaz. Yatırım kararlarınızı yetkili bir mali danışmana '
              'danışarak veriniz. Geçmiş performans gelecekteki sonuçları garanti etmez.',
              style: context.t.labelMedium?.copyWith(
                letterSpacing: 0,
                color: Sandik.text36,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
