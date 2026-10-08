import '../services/symbol_search_service.dart';
import 'asset_categories.dart';
import 'asset_type.dart';
import 'eurobond.dart';
import 'varlik_kimligi.dart';

/// Varlık Ekle'nin "gruplu ızgara + arama" tür seçicisinin saf kuralları
/// (bayrak `tur_secici_izgara`, 2026-10-08).
///
/// ## Neden ayrı dosya
/// Hangi kutunun hangi grupta durduğu, bayrağı kapalı türün süzülmesi ve
/// arama sonucunun hangi türe/kimliğe gideceği widget ağacında yazılsaydı
/// test edilemez ve `build()` her karede yeniden hesaplardı (CLAUDE.md
/// katmanlama kuralı). Ekran yalnızca buradan dönen değerleri çizer ve
/// formun VAR OLAN geçişlerini (`AddAssetFormNotifier.select*`) çağırır;
/// kimlik kuralları burada yeniden yazılmaz.

/// Izgaranın üç grubu — okuma sırası.
///
/// Kullanıcının zihnindeki soru "param nerede duruyor": borsada/fonda,
/// dövizde/değerli metalde, yoksa bir birikim sözleşmesinde. Tür sayısı
/// 11'e çıkınca (ABD, eurobond) düz çip yığını bu soruyu cevaplamıyordu.
enum TurGrubu { borsaVeFon, dovizVeDegerli, birikim }

/// Izgaradaki tek kutu. [abd] yalnız hissede anlamlı: ABD hissesi ayrı bir
/// tür DEĞİL (`type='hisse'`, `sub_category='abd'`); kutu formu hisse +
/// ABD pazarıyla açar.
class TurKutusu {
  const TurKutusu(this.tur, {this.abd = false});
  final AssetType tur;
  final bool abd;

  @override
  bool operator ==(Object other) =>
      other is TurKutusu && other.tur == tur && other.abd == abd;

  @override
  int get hashCode => Object.hash(tur, abd);

  @override
  String toString() => abd ? 'TurKutusu(${tur.name}/abd)' : 'TurKutusu(${tur.name})';
}

/// Grupların TAM içeriği, süzmeden önce. Yeni tür eklenirse buraya da
/// yazılmalı — unutulursa ızgarada hiç görünmez (`tur_secici_duzeni_test`
/// her `AssetType`'ın tam bir grupta olduğunu kilitler).
const Map<TurGrubu, List<TurKutusu>> turGruplariTam = {
  TurGrubu.borsaVeFon: [
    TurKutusu(AssetType.hisse),
    TurKutusu(AssetType.hisse, abd: true),
    TurKutusu(AssetType.fon),
    TurKutusu(AssetType.kripto),
  ],
  TurGrubu.dovizVeDegerli: [
    TurKutusu(AssetType.doviz),
    TurKutusu(AssetType.altin),
    TurKutusu(AssetType.eurobond),
    TurKutusu(AssetType.emtia),
  ],
  TurGrubu.birikim: [
    TurKutusu(AssetType.mevduat),
    TurKutusu(AssetType.bes),
    TurKutusu(AssetType.diger),
  ],
};

/// Ekranda çizilecek gruplar.
///
/// Süzme kuralları eski çip satırıyla (`_typeSelector`) BİREBİR:
/// - [turAcik]: türün kendi bayrağı (`RemoteConfigService.turSecenegi`;
///   eurobond). Gizli tür ne kutuda ne aramada görünür.
/// - [abdAcik]: `abd_hisse` bayrağı; kapalıyken ABD kutusu yok.
/// - [sozlesmeliAcik]: mevduat/BES yalnız YENİ kayıtta (sepet ve düzenleme
///   değil) — sepet miktar × fiyat satırı taşır, düzenlemede tür
///   değiştirmek lotu sözleşmesiz bırakırdı.
/// Boşalan grup başlığıyla birlikte düşer.
List<(TurGrubu, List<TurKutusu>)> turSeciciGruplari({
  required bool Function(AssetType) turAcik,
  required bool abdAcik,
  required bool sozlesmeliAcik,
}) {
  final out = <(TurGrubu, List<TurKutusu>)>[];
  for (final g in TurGrubu.values) {
    final kutular = [
      for (final k in turGruplariTam[g]!)
        if (turAcik(k.tur) &&
            (!k.abd || abdAcik) &&
            (!k.tur.sozlesmeli || sozlesmeliAcik))
          k,
    ];
    if (kutular.isNotEmpty) out.add((g, kutular));
  }
  return out;
}

/// Formun şu anki durumunun kutusu (seçili kutuyu ve katlanmış satırı
/// çizmek için). [isAbd] formun `AddAssetFormState.isAbd`'si — bayrak
/// kapalıyken zaten `false`.
TurKutusu seciliKutu(AssetType tur, {required bool isAbd}) =>
    TurKutusu(tur, abd: tur == AssetType.hisse && isAbd);

/// Kutunun altındaki küçük ipucu. Yalnız VAR OLAN bilgiden: BIST seansı
/// `BugunService.seansAcikMi`'den, kripto 7/24 işler (piyasa kapalı
/// kuralındaki gerekçe, `piyasa_kapali_etiketi.dart`). ABD seansı ve
/// eurobond piyasası için uygulamada saat bilgisi yok — ipucu UYDURULMAZ,
/// çizilmez.
enum TurIpucu { bistAcik, bistKapali, yediYirmiDort }

TurIpucu? turKutusuIpucu(TurKutusu k, {required bool bistSeansAcik}) {
  if (k.tur == AssetType.hisse && !k.abd) {
    return bistSeansAcik ? TurIpucu.bistAcik : TurIpucu.bistKapali;
  }
  if (k.tur == AssetType.kripto) return TurIpucu.yediYirmiDort;
  return null;
}

/// Arama sonucunun yanındaki küçük pazar etiketi.
enum PazarEtiketi { bist, abd, tefas, kripto, eurobond, altin, doviz }

/// Arama listesindeki tek satır: hangi kutuya gidecek + formun hangi var
/// olan geçişini besleyecek. Alanlar türe göre dolar:
/// - BIST → [ticker] (`selectBist100`)
/// - ABD → [ticker] (`selectHisseBorsasi` + `selectAbdHisse`)
/// - fon → [ticker] `TEFAS:KOD` + [ad] (`selectFund`)
/// - kripto → [ticker] `KRIPTO:KOD` + [ad] (`selectKripto`)
/// - altın → [altin] (`selectGold`)
/// - döviz → [dovizEtiketi] (`selectDoviz(dovizOptFor(…))`)
/// - eurobond → [eurobond] (`selectEurobond`)
class TurAramaSonucu {
  const TurAramaSonucu({
    required this.kutu,
    required this.etiket,
    required this.sembol,
    required this.ad,
    this.ticker,
    this.altin,
    this.dovizEtiketi,
    this.eurobond,
  });

  final TurKutusu kutu;
  final PazarEtiketi etiket;

  /// Satırda görünen kısa kod (THYAO, AAPL, BTC, ISIN).
  final String sembol;
  final String ad;
  final String? ticker;
  final GoldSubCategory? altin;
  final String? dovizEtiketi;
  final (EurobondSozlesmesi, EurobondFiyati?)? eurobond;
}

/// Arama sonuçlarını seçici satırlarına çevirir.
///
/// Kimlik kararı (`TEFAS:` → fon, `KRIPTO:` → kripto, `ABD` kaynağı → USD
/// hisse…) `VarlikKimligi.fromSymbolHit`'ten gelir — takip listesindeki
/// "Portföye ekle" ile AYNI kural; burada yeniden yazılmaz.
///
/// Listeye GİRMEYENLER (bilinçli):
/// - Endeks (`XU100.IS`): portföye eklenemez, kıyas noktasıdır.
/// - Küresel emtia vadelileri (`BZ=F`): USD kote referanstır; Emtia formu
///   serbest ad + sembol ister, TL varsayılanlı lot yanlış ölçekte olurdu.
///   Emtia kutusu ızgarada durur.
/// - Bayrağı kapalı tür ([turAcik]) ve bayrak kapalıyken ABD ([abdAcik]).
///
/// [eurobondlar]: katalogdan bu sorguyla eşleşen eklenebilir tahviller
/// (arama servisi ISIN bilmez). Servis sonuçları bunları boğmasın diye en
/// fazla 2 yer ayrılır; toplam [limit].
List<TurAramaSonucu> turAramaSonuclari(
  List<SymbolHit> hits, {
  List<(EurobondSozlesmesi, EurobondFiyati?)> eurobondlar = const [],
  required bool Function(AssetType) turAcik,
  required bool abdAcik,
  int limit = 6,
}) {
  final eb = turAcik(AssetType.eurobond)
      ? [
          for (final e in eurobondlar.take(2))
            TurAramaSonucu(
              kutu: const TurKutusu(AssetType.eurobond),
              etiket: PazarEtiketi.eurobond,
              sembol: e.$1.isin,
              ad: e.$1.ad,
              eurobond: e,
            ),
        ]
      : const <TurAramaSonucu>[];
  final out = <TurAramaSonucu>[];
  final gorulen = <String>{};
  for (final h in hits) {
    if (out.length >= limit - eb.length) break;
    final s = _sonuc(h, turAcik: turAcik, abdAcik: abdAcik);
    if (s == null || !gorulen.add('${s.kutu}|${s.sembol}')) continue;
    out.add(s);
  }
  return [...out, ...eb];
}

TurAramaSonucu? _sonuc(
  SymbolHit h, {
  required bool Function(AssetType) turAcik,
  required bool abdAcik,
}) {
  if (h.source == 'Endeks') return null;
  final k = VarlikKimligi.fromSymbolHit(h);
  if (k == null || !turAcik(k.type)) return null;
  switch (k.type) {
    case AssetType.hisse:
      final abd = h.source == SymbolSearchService.abdKaynagi;
      if (abd && !abdAcik) return null;
      return TurAramaSonucu(
        kutu: TurKutusu(AssetType.hisse, abd: abd),
        etiket: abd ? PazarEtiketi.abd : PazarEtiketi.bist,
        sembol: h.ticker.replaceAll('.IS', ''),
        ad: h.name,
        ticker: h.ticker,
      );
    case AssetType.fon:
      return TurAramaSonucu(
        kutu: const TurKutusu(AssetType.fon),
        etiket: PazarEtiketi.tefas,
        sembol: h.ticker.replaceFirst('TEFAS:', ''),
        ad: h.name,
        ticker: h.ticker,
      );
    case AssetType.kripto:
      return TurAramaSonucu(
        kutu: const TurKutusu(AssetType.kripto),
        etiket: PazarEtiketi.kripto,
        sembol: kriptoKodu(h.ticker) ?? h.ticker,
        ad: h.name,
        ticker: h.ticker,
      );
    case AssetType.altin:
      // Altın seçicisi `GoldSubCategory` ister; arama adı onun etiketiyle
      // aynı (`goldTickerMap` anahtarı, `VarlikKimligi.fromGold`).
      final g = GoldSubCategory.values
          .where((g) => g.label == h.name)
          .firstOrNull;
      if (g == null) return null;
      return TurAramaSonucu(
        kutu: const TurKutusu(AssetType.altin),
        etiket: PazarEtiketi.altin,
        sembol: g.label,
        ad: h.name,
        altin: g,
      );
    case AssetType.doviz:
      final kod = k.subCategory;
      if (kod == null) return null;
      return TurAramaSonucu(
        kutu: const TurKutusu(AssetType.doviz),
        etiket: PazarEtiketi.doviz,
        sembol: kod,
        ad: h.name,
        dovizEtiketi: kod,
      );
    default:
      return null;
  }
}
