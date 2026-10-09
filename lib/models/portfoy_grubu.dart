import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import 'asset.dart';
import 'asset_type.dart';

/// Portföy ekranının dağılım ve süzgeç anahtarı: tür, hissede pazar.
///
/// ## Neden (yasin 2026-10-09, bayrak `abd_hisse`)
/// "Portföy ekranında ABD ve Türk hisseleri arasında fark görmek, ayrı
/// süzmek ve ayrı gözlemek istiyorum" — çipte, üstteki süzgeçte ve halka
/// dilim dokunuşunda. Halka, lejant ve liste süzgeci [AssetType] ile
/// anahtarlıydı; ABD hissesi ise ayrı bir tür DEĞİL (`hisse` +
/// `sub_category='abd'`, gerekçe `Asset.abdHissesi`: eski sürüm yeni enum
/// değerini "Diğer"e ezerdi). Veri modeline dokunmadan ayrımı yalnız
/// görünümde yapmak için anahtar türün üstüne pazar ekler.
///
/// [abd] `null` → ayrım yok (bayrak kapalı ya da portföyde ABD hissesi
/// yok): grup türün kendisidir, etiket/renk birebir eski. Hissede `false`
/// → "BIST Hisse", `true` → "ABD Hisse". Ayrım ancak iki pazar yan yana
/// anlam taşıdığında açılır; yalnız BIST tutan kullanıcı "Hisse"yi görmeye
/// devam eder.
@immutable
class PortfoyGrubu {
  const PortfoyGrubu(this.tur, {this.abd});

  final AssetType tur;

  /// Yalnız hissede ve ayrım açıkken dolu; bkz. sınıf notu.
  final bool? abd;

  /// [a]'nın grubu. [pazarAyir] `false` iken her zaman türün kendisi.
  factory PortfoyGrubu.of(Asset a, {required bool pazarAyir}) =>
      pazarAyir && a.type == AssetType.hisse
          ? PortfoyGrubu(a.type, abd: a.abdHissesi)
          : PortfoyGrubu(a.type);

  /// Ayrım bu varlık kümesinde açılır mı: bayrak açık VE en az bir ABD
  /// hissesi var. Bayrak kapalıyken eski davranış birebir (ana kural).
  static bool pazarAyrimi(Iterable<Asset> varliklar,
          {required bool bayrak}) =>
      bayrak && varliklar.any((a) => a.abdHissesi);

  /// [a] bu gruba girer mi (liste süzgeci).
  bool kapsar(Asset a) =>
      a.type == tur && (abd == null || a.abdHissesi == abd);

  /// Dolgu/nokta rengi. BIST hissesi hisse amberinde kalır: bugüne kadarki
  /// "amber = hisse" kimliği bozulmaz, yeni olan ABD diliminin tonudur.
  Color get color => abd == true ? Sandik.abdHisse : tur.color;

  /// Metin/ikon olarak okunur ton (bkz. [AssetType.onSurface]).
  Color onSurface(BuildContext context) =>
      abd == true ? color.metinTonu(context) : tur.onSurface(context);

  String labelOf(AppLocalizations l) => switch (abd) {
        null => tur.labelOf(l),
        true => l.portfolioGroupUsStock,
        false => l.portfolioGroupBistStock,
      };

  @override
  bool operator ==(Object other) =>
      other is PortfoyGrubu && other.tur == tur && other.abd == abd;

  @override
  int get hashCode => Object.hash(tur, abd);

  @override
  String toString() => 'PortfoyGrubu($tur, abd: $abd)';
}
