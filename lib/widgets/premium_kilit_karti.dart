import 'package:flutter/material.dart';

import '../theme/sandik.dart';
import 'para_akisi_karti.dart' show KilitSatiri;

/// Premium'a ait bütün bir yüzeyin kilitli hâli (2026-10-10).
///
/// "Bir iş = bir bileşen" (docs/TASARIM_DILI.md): bir özelliğin TAMAMI
/// Premium olduğunda (teknik sinyaller, aylık rapor, yıllık rapor, dışa
/// aktarma, fon dağılımı, temettü tahmini, portföyler) her yüzey aynı
/// kartı çizer: ne olduğunu söyleyen başlık, ücret ödeyenin TAM OLARAK ne
/// alacağını söyleyen tek paragraf ve paywall'u açan [KilitSatiri].
/// Bir yüzeyin yalnız bir kısmı kilitliyse (para akışının 8 haftası,
/// notun gövdesi) bu kart değil, içerikle yan yana [KilitSatiri] kullanılır.
///
/// Kilitli içerik bulanıklaştırılmaz ya da sahte veriyle doldurulmaz:
/// uydurma sayı yasak (fiyat kaynağı sözleşmesi), bulanık gerçek veri ise
/// sunucuda RLS ile zaten verilmiyor.
class PremiumKilitKarti extends StatelessWidget {
  const PremiumKilitKarti({
    super.key,
    required this.ikon,
    required this.baslik,
    required this.govde,
    required this.kilitMetni,
    required this.kaynak,
    this.kisisel,
  });

  final IconData ikon;
  final String baslik;

  /// Ücret ödeyenin alacağı şey, somut olarak.
  final String govde;

  /// Kilit satırının metni ("… Premium'da").
  final String kilitMetni;

  /// Analitikte paywall'ın nereden açıldığı (`premium_upgrade_started`).
  final String kaynak;

  /// Kullanıcının kendi verisinden tek satır (2026-11-12, Ar-Ge 12 Kas #3):
  /// "Portföyündeki 3 hisse son 12 ayda temettü dağıttı: …". Kilitli
  /// içeriği VERMEZ (tutar yok); paragraf "ne alırsın"ı genel söyler, bu
  /// satır "senin için dolu mu"yu söyler, boşsa bunu da dürüstçe söyler.
  /// `null` (veri yok, yükleniyor, okunamadı) → satır yok. Geç gelirse kart
  /// zıplamasın diye boy değişimi yumuşak (hareketi azalt açıkken anlık).
  final String? kisisel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ikon, color: c.amberText),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: Text(baslik,
                    style: context.t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: c.text90)),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(govde,
              style:
                  context.t.bodySmall?.copyWith(color: c.text58, height: 1.4)),
          AnimatedSize(
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.move,
            alignment: Alignment.topCenter,
            child: kisisel == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: SandikSpace.sm),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(kisisel!,
                          style: context.t.bodySmall?.copyWith(
                              color: c.text90,
                              fontWeight: FontWeight.w600,
                              height: 1.4)),
                    ),
                  ),
          ),
          const SizedBox(height: SandikSpace.sm),
          KilitSatiri(metin: kilitMetni, kaynak: kaynak),
        ],
      ),
    );
  }
}

/// Bir ekranın tamamı Premium olduğunda gövde: tek [PremiumKilitKarti],
/// ekran kenar boşluklarıyla. Ekran kendi `Scaffold`/`SandikAppBar`'ını
/// korur; kullanıcı nerede olduğunu başlıktan bilir.
class PremiumKilitGovdesi extends StatelessWidget {
  const PremiumKilitGovdesi({super.key, required this.kart});

  final PremiumKilitKarti kart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(
          horizontal: SandikSpace.screenH(context), vertical: SandikSpace.md),
      children: [kart],
    );
  }
}
