import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import 'premium_abonelik_satiri.dart' show aboneligiYonet;
import 'sandik_acilir.dart';

/// Yardım'ın başındaki "Sık sorulanlar" (Ar-Ge 5 Kas 21:20 #4, müşteri
/// raporu YAP).
///
/// Neden: tek destek yolu e-postaydı. Cevabı uygulamanın içinde olan soru
/// düşük puana ya da destek e-postasına dönüşmesin. Yeni sayfa açılmadı
/// (29 Eki'de Yardım 6 satıra inmişti); tek kart, satırlar yerinde açılır.
///
/// Cevaplar kodun gerçek davranışını anlatır; davranış değişince metin de
/// değişir:
/// - fon: TEFAS günde bir fiyat (`fiyat_kaynagi.dart`, fon Günlük notu #287);
/// - sıklık: `TazelikRitmi.temel` 30 sn, aşağı çekince hemen;
/// - kripto: yalnız Binance (kullanıcı kararı);
/// - veri: Supabase Frankfurt, ayrıntı Aydınlatma Metni (Tokyo kopyası
///   notu orada); silme Hesap & Güvenlik'te;
/// - ortak: kod gönder / kod gir, istediğin an ayrıl;
/// - Premium: fiyat yazılmaz (mağaza fiyatı esas), iptal mağazadan.
///   Cevabın altında "Bize yaz"ın yanında "Aboneliği yönet" (Ar-Ge 26 Kas
///   02:03 #1): "nasıl iptal ederim?" diyen kişiye yolu tarif etmek yerine
///   mağazanın abonelik sayfasını açar. Abone olmayana da görünür: soruyu
///   soran kişi aboneliği başka hesapta/cihazda almış olabilir, mağaza
///   sayfası boşsa zararı yok (Premium satırındaki "Yönet" ile aynı karar).
class SikSorulanlar extends StatefulWidget {
  const SikSorulanlar({super.key, required this.onBizeYaz});

  /// "Çözülmedi mi? Bize yaz": Bize ulaş satırıyla aynı form.
  final VoidCallback onBizeYaz;

  @override
  State<SikSorulanlar> createState() => _SikSorulanlarState();
}

class _SikSorulanlarState extends State<SikSorulanlar> {
  int? _acik;

  /// Premium sorusunun sırası; cevabında abonelik düğmesi de çıkar.
  int _premiumSira = -1;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final sorular = <(String, String)>[
      (l.sssFonSoru, l.sssFonCevap),
      (l.sssSiklikSoru, l.sssSiklikCevap),
      (l.sssKriptoSoru, l.sssKriptoCevap),
      (l.sssVeriSoru, l.sssVeriCevap),
      (l.sssOrtakSoru, l.sssOrtakCevap),
      (l.sssPremiumSoru, l.sssPremiumCevap),
    ];
    _premiumSira = sorular.length - 1;
    final c = context.c;
    return SandikCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sorular.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: SandikSpace.md,
                  color: c.overlay),
            _satir(context, i, sorular[i].$1, sorular[i].$2),
          ],
        ],
      ),
    );
  }

  Widget _satir(BuildContext context, int i, String soru, String cevap) {
    final c = context.c;
    final t = context.t;
    final acik = _acik == i;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: acik,
          child: SandikTappable(
            key: ValueKey('sss$i'),
            onTap: () => setState(() => _acik = acik ? null : i),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: SandikTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: SandikSpace.md, vertical: SandikSpace.smd),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(soru,
                          style: t.bodyMedium?.copyWith(color: c.text90)),
                    ),
                    const SizedBox(width: SandikSpace.sm),
                    SandikAcilirOk(
                      acik: acik,
                      child: Icon(Icons.expand_more_rounded,
                          size: 20, color: c.text58),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SandikAcilir(
          acik: acik,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                SandikSpace.md, 0, SandikSpace.md, SandikSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cevap, style: t.bodySmall?.copyWith(color: c.text58)),
                Wrap(
                  spacing: SandikSpace.md,
                  children: [
                    TextButton(
                      key: ValueKey('sssBizeYaz$i'),
                      style: _baglantiStili(c),
                      onPressed: widget.onBizeYaz,
                      child: Text(context.l10n.sssBizeYaz),
                    ),
                    if (i == _premiumSira)
                      TextButton(
                        key: const ValueKey('sssAboneligiYonet'),
                        style: _baglantiStili(c),
                        onPressed: () => aboneligiYonet(context),
                        child: Text(context.l10n.aboneligiYonet),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static ButtonStyle _baglantiStili(SandikPalette c) => TextButton.styleFrom(
        foregroundColor: c.amberText,
        minimumSize: SandikTouch.minSize,
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
      );
}
