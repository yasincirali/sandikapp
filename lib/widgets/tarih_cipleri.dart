import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/bugun_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'tur_filtre_cipleri.dart' show SandikFiltreCipi;

/// Hızlı tarih çipinin türü.
enum HizliTarihTuru { bugun, dun, sonIsGunu }

/// Çip satırının bir hızlı seçeneği: tür + takvim günü (gün başı).
typedef HizliTarih = ({HizliTarihTuru tur, DateTime gun});

/// [bugun] için hızlı tarih seçenekleri: Bugün · Dün · (son iş günü).
///
/// Son iş günü ([BugunService.sonIslemGunu]) "Dün"e denk geliyorsa çıkmaz:
/// Salı günü dün = Pazartesi = son iş günü; aynı günü iki çip göstermek
/// kullanıcıya "fark ne?" sorusunu sordurur. Pazartesi günü dün Pazar, son
/// iş günü Cuma → iki ayrı çip. Takvim kapsamı dışındaki yılda son iş günü
/// bilinemez ([BugunService.sonIslemGunu] `null`) → çip yok, gün uydurulmaz.
///
/// Saf: tarih satırı ve testler aynı listeyi okur.
List<HizliTarih> hizliTarihler(DateTime bugun, {bool sonIsGunu = true}) {
  final b = dayKey(bugun);
  final dun = DateTime(b.year, b.month, b.day - 1);
  final son = sonIsGunu ? BugunService.sonIslemGunu(b) : null;
  return [
    (tur: HizliTarihTuru.bugun, gun: b),
    (tur: HizliTarihTuru.dun, gun: dun),
    if (son != null && son != dun) (tur: HizliTarihTuru.sonIsGunu, gun: son),
  ];
}

/// İşlem tarihi hızlı seçim satırı (2026-11-11): Bugün · Dün · (son iş
/// günü) · (Başka tarih).
///
/// ## Neden ortak bileşen
/// Geçmiş tarihli kayıtların çoğu "dün" ya da "Cuma"dır; tek "Bugün" çipi
/// her seferinde takvimi açtırıyordu. Varlık ekle formu ve hızlı al/sat aynı
/// soruyu sorar; iki ekran kendi çipini kursaydı biri "Dün"ü takvim günü,
/// öbürü iş günü sayardı. Seçim çipi uygulamanın tek seçilebilir çipi
/// [SandikFiltreCipi] (44 pt, seçiliyken amber + onay işareti — durum
/// yalnız renkle verilmez).
///
/// ## Etiket kararı: "Son iş günü" değil gün adı ("Cuma")
/// Çip zaten bir günü seçtirir; gün adı hangi gün olduğunu doğrudan söyler,
/// "Son iş günü" ise kullanıcıya hesap yaptırır. Ekran okuyucu "Cuma, son
/// işlem günü" duyar (neden bu çipin orada olduğu). Bayram sonrası bile
/// boşluk 6 günü geçmez; geçerse (savunma) gün adı belirsizleşeceği için
/// kısa tarih yazılır.
///
/// "Dün" her zaman TAKVİM günü dündür (Pazar da olabilir): işlemin tarihi
/// odur; o günün fiyatı çağıranın fiyat yolunun kuralıyla bulunur.
///
/// [takvim] verilirse sonda "Başka tarih" çipi durur: dokununca takvimi
/// açar (`pickSandikDate` çağıranın işi — sınırları o bilir); seçili tarih
/// hızlı seçeneklerden biri değilse bu çip seçili görünür ve tarihi yazar.
class TarihCipleri extends StatelessWidget {
  const TarihCipleri({
    super.key,
    required this.secili,
    required this.onSecildi,
    this.takvim,
    this.sonIsGunu = true,
    this.bugun,
  });

  /// Şu an seçili tarih (yalnız günü okunur).
  final DateTime secili;

  /// Hızlı çip ya da takvimden seçilen gün (gün başı).
  final ValueChanged<DateTime> onSecildi;

  /// "Başka tarih" çipinin açacağı takvim; `null` → çip yok (hızlı al/sat).
  final Future<DateTime?> Function()? takvim;

  /// Son iş günü çipi gösterilsin mi.
  final bool sonIsGunu;

  /// Testte sabit "bugün"; verilmezse cihaz saati.
  final DateTime? bugun;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dil = context.tarihDili;
    final b = dayKey(bugun ?? DateTime.now());
    final secilenGun = dayKey(secili);
    final secenekler = hizliTarihler(b, sonIsGunu: sonIsGunu);
    final hizlidan = secenekler.any((s) => s.gun == secilenGun);

    final cipler = <Widget>[
      for (final s in secenekler)
        switch (s.tur) {
          HizliTarihTuru.bugun => SandikFiltreCipi(
              ad: l.tarihCipiBugun,
              secili: s.gun == secilenGun,
              onTap: () => onSecildi(s.gun),
            ),
          HizliTarihTuru.dun => SandikFiltreCipi(
              ad: l.tarihCipiDun,
              secili: s.gun == secilenGun,
              onTap: () => onSecildi(s.gun),
            ),
          HizliTarihTuru.sonIsGunu => SandikFiltreCipi(
              ad: b.difference(s.gun).inDays <= 6
                  ? gunAdi(s.gun, dil: dil)
                  : fmtTarih(s.gun, dil: dil, kisa: true),
              semantik: l.tarihCipiSonIsGunuSemantik(gunAdi(s.gun, dil: dil)),
              secili: s.gun == secilenGun,
              onTap: () => onSecildi(s.gun),
            ),
        },
      if (takvim case final ac?)
        SandikFiltreCipi(
          ad: hizlidan
              ? l.tarihCipiBaskaTarih
              : fmtTarih(secilenGun, dil: dil, kisa: true),
          semantik: hizlidan
              ? null
              : l.tarihCipiSeciliTarihSemantik(fmtTarih(secilenGun, dil: dil)),
          secili: !hizlidan,
          ikon: Icons.event_rounded,
          onTap: () async {
            final secilen = await ac();
            if (secilen != null) onSecildi(dayKey(secilen));
          },
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final (i, cip) in cipler.indexed) ...[
            if (i > 0) const SizedBox(width: SandikSpace.xs2),
            // Yatay kaydırmada genişlik sınırsız; çipin içindeki `Flexible`
            // sınır ister (alarm hızlı çipleriyle aynı tavan).
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: cip,
            ),
          ],
        ],
      ),
    );
  }
}
