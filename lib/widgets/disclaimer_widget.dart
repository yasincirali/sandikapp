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
              'Bu uygulama yalnızca bilgilendirme amaçlıdır. '
              'Gösterilen veriler, analizler ve bildirimler kesinlikle '
              'yatırım tavsiyesi, alım-satım önerisi veya finansal danışmanlık '
              'niteliği taşımaz. Yatırım kararlarınızı yetkili bir mali danışmana '
              'danışarak veriniz. Geçmiş performans gelecekteki sonuçları garanti etmez.',
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
