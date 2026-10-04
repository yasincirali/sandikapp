import 'package:flutter/material.dart';

import '../theme/sandik.dart';
import 'sandik_async_button.dart';

/// Zirvedeki Portföyler — açık rıza kartı (0091, 2026-10-01).
///
/// ## Neden bu metin
/// Kullanıcı kararı (2026-10-01): "açık rıza ve in-app açıklama yazalım;
/// her türlü anonim olduğunu ve diğer kullanıcıların hangi oranlarda hangi
/// varlıkları tuttuğu bilgilerinin kendilerine hizmet olarak sunulacağı
/// bilgisi verilebilir." KVKK açık rızası belirli, bilgilendirmeye dayalı
/// ve özgür iradeyle olmalı; bu yüzden kart dört soruyu AYRI satırda
/// yanıtlar: ne paylaşılır, ne paylaşılMAZ, karşılığında ne alırsın,
/// nasıl geri çekersin. "Katılıyorum" tek açık eylemdir; varsayılan
/// katılmamaktır ve "Şimdi değil" hiçbir şeyi kilitlemez (uygulamanın geri
/// kalanı aynen çalışır).
///
/// Metin anlamca değişirse `LeaderboardService.zirveRizaMetniSurumu` da
/// değişmeli — sunucu hangi sürüme rıza verildiğini saklar. 2026-10-04'ten
/// beri bu bir TESTLE zorlanır: kartın metni (başlık, açıklama, maddeler,
/// hukuk notu, düğme) `yasal_metinler`'e (0102) hash'iyle girer;
/// `yasal_metin_kilidi_test` sürüm artırılmadan değişen metni yakalar.
class ZirveRizaKarti extends StatelessWidget {
  const ZirveRizaKarti({
    super.key,
    required this.onKatil,
    this.onSimdiDegil,
  });

  /// Rızayı sunucuya yazar; hata fırlatırsa kart yerinde kalır.
  final Future<void> Function() onKatil;
  final VoidCallback? onSimdiDegil;

  static const baslik = 'Zirvedeki Portföyler\'e katıl';

  /// Başlığın altındaki tek cümle. Sabit olarak burada: yasal metin kataloğu
  /// (`YasalMetinKatalogu`) kartın gösterdiği metni bu sabitlerden kurar ve
  /// hash'ler — kart ile veritabanındaki metin ayrışamaz.
  static const aciklama =
      'Katılanların portföyleri anonim olarak yan yana konur; en çok '
      'kazandıranların neye yatırdığını görürsün.';

  /// Rızanın verildiği eylem — kanonik metnin son satırı.
  static const katilEtiketi = 'Katılıyorum';

  /// (başlık, metin) — sırası bilinçli: önce ne verdiğin, sonra ne aldığın.
  static const maddeler = <(String, String)>[
    (
      'Ne paylaşılır',
      'Seçilen dönemdeki getiri yüzden ve portföyünün tür dağılımı '
          '(ör. %40 hisse, %35 altın). Fonlarda TEFAS fon kodu ve portföy '
          'içindeki payı.',
    ),
    (
      'Ne paylaşılmaz',
      'Adın, e-postan, kullanıcı adın, TL tutarların, adetlerin ve hangi '
          'hisseleri tuttuğun. Hiçbir yerde kim olduğun yazmaz.',
    ),
    (
      'Nasıl görünür',
      'Tamamen anonim: portföyün yalnız en az 8 kişilik havuzda, sıra '
          'numarasıyla ("2. portföy") görünebilir.',
    ),
    (
      'Karşılığında',
      'Katılan diğer kullanıcıların hangi varlıkları hangi oranlarda '
          'tuttuğunu ve getirilerini yine anonim olarak görür, kendi '
          'portföyünle kıyaslarsın. Bu hizmet yalnız katılanlara açıktır.',
    ),
    (
      'Geri çekme',
      'İstediğin an bu ekrandan ayrılabilirsin; ölçümlerin hemen silinir. '
          'Katılmaman uygulamanın başka hiçbir özelliğini etkilemez.',
    ),
  ];

  static const hukukNotu =
      'KVKK m.5/1 kapsamında açık rızana dayanır. Ayrıntı: Gizlilik '
      'Politikası §5.1 ve KVKK Aydınlatma Metni §5.3.';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            baslik,
            style: context.t.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: c.text90,
            ),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            aciklama,
            style: context.t.bodyMedium?.copyWith(color: c.text58, height: 1.4),
          ),
          const SizedBox(height: SandikSpace.md),
          for (final (b, m) in maddeler) ...[
            Text(
              b,
              style: context.t.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: c.amberText,
              ),
            ),
            const SizedBox(height: SandikSpace.xxs),
            Text(
              m,
              style:
                  context.t.bodyMedium?.copyWith(color: c.text90, height: 1.4),
            ),
            const SizedBox(height: SandikSpace.smd),
          ],
          Text(
            hukukNotu,
            style: context.t.labelMedium?.copyWith(
              letterSpacing: 0,
              color: c.text36,
              height: 1.4,
            ),
          ),
          const SizedBox(height: SandikSpace.md),
          SandikAsyncButton(
            onPressed: onKatil,
            child: const Text(katilEtiketi),
          ),
          if (onSimdiDegil != null) ...[
            const SizedBox(height: SandikSpace.xs),
            Center(
              child: TextButton(
                onPressed: onSimdiDegil,
                child: const Text('Şimdi değil'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
