import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';

/// Varlığa özgü masraflar — varlık ekranındaki "Masraflar" kartının hesabı
/// (bayrak `varlik_masraflari`, 2026-10-08).
///
/// ## Neden (kullanıcı, 2026-10-08)
/// "Her varlık türü için detaycı olmalıyız, kendine has masraflarını
/// ekranda gösterebilmeliyiz." Hisse komisyon ve stopaj, ABD hissesi SEC/
/// FINRA ücreti ve kur makası, fon yönetim ücreti, altın/döviz alış-satış
/// makası öder; kullanıcı bunları tek yerde görmeli.
///
/// ## Kural: tutar YALNIZ iki kaynaktan (uydurma sayı yasak)
///   · [MasrafNiteligi.odendi] — kullanıcının KAYDETTİĞİ veri: lot
///     komisyonları, her lot kendi kuruyla TL'ye çevrilir.
///   · [MasrafNiteligi.tahmini] — RESMÎ bir oranın kullanıcının KENDİ
///     pozisyonuna uygulanması (SEC Section 31, FINRA TAF). Oran sabitlerin
///     yanında kaynak URL'si ve yürürlük tarihiyle durur.
/// Geri kalan her şey [MasrafNiteligi.bilgi]: tutar YOK. Aracı kurum makası,
/// kuyumcu farkı, kripto borsa ücreti kişiden kişiye değişir; "tipik" bir
/// sayı yazmak, kullanıcıya ödemediği bir rakamı ödemiş gibi göstermektir.
/// Gerekli girdi (kur, güncel fiyat) yoksa tahmini kalem de bilgiye iner —
/// bilinmeyen kurla tutar üretilmez.
///
/// Saf Dart: ağ yok, Flutter yok; ekran yalnız sonucu çizer
/// (`widgets/masraf_karti.dart`).

/// Bir masraf kaleminin dayanağı.
enum MasrafNiteligi {
  /// Kayıtlı veriden toplandı (komisyon).
  odendi,

  /// Resmî oran × kullanıcının pozisyonu — satışta ödenecek tahmini tutar.
  tahmini,

  /// Açıklama; tutar yok (oran olabilir).
  bilgi,
}

@immutable
class MasrafKalemi {
  const MasrafKalemi({
    required this.baslik,
    required this.aciklama,
    required this.nitelik,
    this.tutarTry,
    this.oran,
    this.kaynak,
  });

  final String baslik;
  final String aciklama;
  final MasrafNiteligi nitelik;

  /// TL tutar; [MasrafNiteligi.bilgi] kaleminde her zaman `null`.
  final double? tutarTry;

  /// Oran, kesir olarak (0,15 = %15). Tutarla birlikte de verilebilir.
  final double? oran;

  /// Oranın resmî kaynağı (URL).
  final String? kaynak;
}

@immutable
class MasrafOzeti {
  const MasrafOzeti(this.kalemler);

  final List<MasrafKalemi> kalemler;

  /// Kayıtlı veriden ödenmiş toplam (komisyonlar).
  double get odenenToplamTry => _topla(MasrafNiteligi.odendi);

  /// Satışta ödenecek tahmini toplam (resmî oranlı kalemler).
  double get tahminiToplamTry => _topla(MasrafNiteligi.tahmini);

  bool get tahminiVar =>
      kalemler.any((k) => k.nitelik == MasrafNiteligi.tahmini);

  double _topla(MasrafNiteligi n) => kalemler
      .where((k) => k.nitelik == n)
      .fold(0.0, (t, k) => t + (k.tutarTry ?? 0));
}

// ── Resmî oranlar ───────────────────────────────────────────────────────────
//
// Değişince: yeni oran + yürürlük tarihi + kaynak birlikte güncellenir ve
// `test/varlik_masraflari_test.dart` yeni sayıyla kilitlenir. Yürürlük
// tarihinden ÖNCEKİ bir an için oran bilinmiyor sayılır (kalem bilgiye
// iner) — eski oranı tahmin etmek de uydurmadır.

/// SEC Section 31 işlem ücreti: satış tutarının milyon dolarında $20,60.
/// Yürürlük 2026-04-04. Kaynak: SEC Fee Rate Advisory 2026-2.
const secUcretOrani = 20.60 / 1000000;
final secUcretYururluk = DateTime(2026, 4, 4);
const secUcretKaynagi =
    'https://www.sec.gov/rules-regulations/fee-rate-advisories/2026-2';

/// FINRA Trading Activity Fee (satışta): pay başına $0,000195, işlem başına
/// en çok $9,79. 2026 tarifesi. Kaynak: FINRA Information Notice 2026-03-17.
/// Yürürlük günü kaynakta tarife yılı olarak geçer; gün uydurulmadığı için
/// SEC'teki tarih kapısı burada yok.
const finraTafPayBasina = 0.000195;
const finraTafIslemBasiAzami = 9.79;
const finraTafKaynagi =
    'https://www.finra.org/rules-guidance/notices/information-notice-20260317';

/// ABD kaynaklı temettüde stopaj: W-8BEN ile %20 (Türkiye–ABD çifte
/// vergilendirmeyi önleme anlaşması, md. 10), formsuz %30. Kaynak: IRS
/// Tax Treaty Table 1.
const abdTemettuStopajOrani = 0.20;
const abdTemettuStopajKaynagi =
    'https://www.irs.gov/individuals/international-taxpayers/tax-treaty-tables';

// ── Hesap ───────────────────────────────────────────────────────────────────

/// [varlik]'ın masraf özeti.
///
/// [varlik] ekranın pozisyon görünümüdür (`Position.asDisplayAsset`): toplam
/// miktar ve güncel fiyat oradan. [lotlar] pozisyonun alım/satım/temettü
/// satırları — komisyon onlardan toplanır. [usdTry] canlı kur; `null` ise
/// ABD tahmini kalemleri bilgiye iner. [temettuStopajOrani] Remote Config
/// `temettu_stopaj_orani` (`null` = bilinmiyor; oran yazılmaz).
MasrafOzeti varlikMasraflari({
  required Asset varlik,
  required List<Asset> lotlar,
  required double? usdTry,
  required double? temettuStopajOrani,
  DateTime? simdi,
}) {
  final g = MasrafGirdisi(
    varlik: varlik,
    lotlar: lotlar,
    usdTry: usdTry,
    temettuStopajOrani: temettuStopajOrani,
    simdi: simdi ?? DateTime.now(),
  );
  return MasrafOzeti([
    // Sözleşmeli türlerin formu komisyon almaz (mevduat faizi, BES katkısı);
    // "komisyon kaydetmedin" demek yanlış yönlendirirdi.
    if (!varlik.type.sozlesmeli) komisyonKalemi(lotlar),
    ...turKalemleri(g),
  ]);
}

/// Tür kalemlerinin girdisi — tek nesne: yeni bir türün işlevi aynı imzayla
/// eklenir, çağıran değişmez.
@immutable
class MasrafGirdisi {
  const MasrafGirdisi({
    required this.varlik,
    required this.lotlar,
    required this.usdTry,
    required this.temettuStopajOrani,
    required this.simdi,
  });

  final Asset varlik;
  final List<Asset> lotlar;
  final double? usdTry;
  final double? temettuStopajOrani;
  final DateTime simdi;
}

/// Türün kendine has kalemleri. Yeni bir tür (ör. eurobond) kendi
/// işleviyle buraya bir `case` olarak girer; komisyon kalemi ortaktır ve
/// [varlikMasraflari]'nda kalır.
List<MasrafKalemi> turKalemleri(MasrafGirdisi g) {
  switch (g.varlik.type) {
    case AssetType.hisse:
      if (g.varlik.abdHissesi) return abdHisseKalemleri(g);
      if (g.varlik.currency.trim().toUpperCase() == 'TRY') {
        return bistHisseKalemleri(g);
      }
      // Bayraktan önce elle girilmiş dövizli hisse: pazarı bilinmiyor,
      // hangi kuralın geçerli olduğunu söyleyemeyiz — yalnız komisyon.
      return const [];
    case AssetType.fon:
    case AssetType.bes:
      return fonKalemleri(g);
    case AssetType.mevduat:
      return mevduatKalemleri(g);
    case AssetType.kripto:
      return kriptoKalemleri(g);
    case AssetType.altin:
    case AssetType.doviz:
      return makasKalemleri(g);
    case AssetType.emtia:
    case AssetType.diger:
      return const [];
  }
}

/// Kayıtlı komisyonların TL toplamı.
///
/// Her lot KENDİ kuruyla çevrilir: alım ve temettü satırı [Asset.purchaseFxRate]
/// (işlem günü kuru), satış satırı [Asset.satisKuru] — satış günü kuru
/// kayıtlıysa o (0111), yoksa alım kuru; `sellProceedsTRY` ile aynı kural.
/// Bugünün kuruyla çevirmek, geçmişte ödenmiş TL'yi bugünün kuruna taşırdı.
MasrafKalemi komisyonKalemi(List<Asset> lotlar) {
  var toplam = 0.0;
  for (final l in lotlar) {
    if (!l.isActive || l.commission <= 0) continue;
    toplam += l.commission * (l.isSell ? l.satisKuru : l.purchaseFxRate);
  }
  if (toplam <= 0) {
    return const MasrafKalemi(
      baslik: 'İşlem komisyonu',
      aciklama: 'Komisyon kaydetmedin; işlem eklerken yazarsan burada '
          'toplanır.',
      nitelik: MasrafNiteligi.bilgi,
    );
  }
  return MasrafKalemi(
    baslik: 'İşlem komisyonu',
    aciklama: 'Alım ve satışlarda kaydettiğin komisyonların toplamı, her '
        'işlem kendi günündeki kurla.',
    nitelik: MasrafNiteligi.odendi,
    tutarTry: toplam,
  );
}

List<MasrafKalemi> bistHisseKalemleri(MasrafGirdisi g) => [
      MasrafKalemi(
        baslik: 'Temettü stopajı',
        aciklama: 'Şirket temettüyü öderken stopajı kaynağında keser; '
            'hesabına net tutar geçer.',
        nitelik: MasrafNiteligi.bilgi,
        oran: g.temettuStopajOrani,
      ),
      const MasrafKalemi(
        baslik: 'BSMV',
        aciklama: 'Aracı kurum komisyona BSMV ekler; komisyonu ekstredeki '
            'toplamla yazdıysan BSMV içindedir.',
        nitelik: MasrafNiteligi.bilgi,
      ),
    ];

/// ABD hissesi: satış tarafı düzenleyici ücretleri (tahmini), temettü
/// stopajı, kur çevrimi ve vergi (bilgi).
///
/// Tahmin bugünkü piyasa değerini TEK satış emriyle satmayı varsayar:
/// FINRA TAF'ın üst sınırı emir başınadır, parçalı satışta toplam artar.
List<MasrafKalemi> abdHisseKalemleri(MasrafGirdisi g) {
  final v = g.varlik;
  final kur = g.usdTry;
  final usd = v.currency.trim().toUpperCase() == 'USD';
  final degerUsd = usd && v.currentPrice > 0 && v.quantity > 0
      ? v.quantity * v.currentPrice
      : null;
  final kurVar = kur != null && kur > 0;

  MasrafKalemi sec() {
    const baslik = 'SEC ücreti (satışta)';
    const aciklama = 'ABD düzenleyicisinin satış tutarından aldığı ücret; '
        'aracı kurum satışta keser. Bugünkü değerinle tek seferde satış '
        'varsayılır.';
    final yururlukte = !g.simdi.isBefore(secUcretYururluk);
    if (degerUsd == null || !kurVar || !yururlukte) {
      return MasrafKalemi(
        baslik: baslik,
        aciklama: aciklama,
        nitelik: MasrafNiteligi.bilgi,
        oran: yururlukte ? secUcretOrani : null,
        kaynak: secUcretKaynagi,
      );
    }
    return MasrafKalemi(
      baslik: baslik,
      aciklama: aciklama,
      nitelik: MasrafNiteligi.tahmini,
      tutarTry: degerUsd * secUcretOrani * kur,
      oran: secUcretOrani,
      kaynak: secUcretKaynagi,
    );
  }

  MasrafKalemi finra() {
    const baslik = 'FINRA TAF (satışta)';
    const aciklama = r'Satılan pay başına 0,000195 $, emir başına en çok '
        r'9,79 $. Tek satış emri varsayılır.';
    if (v.quantity <= 0 || !kurVar) {
      return const MasrafKalemi(
        baslik: baslik,
        aciklama: aciklama,
        nitelik: MasrafNiteligi.bilgi,
        kaynak: finraTafKaynagi,
      );
    }
    final ucretUsd =
        math.min(v.quantity * finraTafPayBasina, finraTafIslemBasiAzami);
    return MasrafKalemi(
      baslik: baslik,
      aciklama: aciklama,
      nitelik: MasrafNiteligi.tahmini,
      tutarTry: ucretUsd * kur,
      kaynak: finraTafKaynagi,
    );
  }

  return [
    sec(),
    finra(),
    const MasrafKalemi(
      baslik: 'ABD temettü stopajı',
      aciklama: "W-8BEN ile %20, formsuz %30; Türkiye'de beyanda mahsup "
          'edilir.',
      nitelik: MasrafNiteligi.bilgi,
      oran: abdTemettuStopajOrani,
      kaynak: abdTemettuStopajKaynagi,
    ),
    const MasrafKalemi(
      baslik: 'Kur çevrimi',
      aciklama: 'Aracı kurum TL↔USD çevriminde makas alır; alışta ve '
          'satışta ayrı ödenir.',
      nitelik: MasrafNiteligi.bilgi,
    ),
    const MasrafKalemi(
      baslik: 'Vergi',
      aciklama: 'Yurt dışı hisse kazancında stopaj yok, yıllık beyan; '
          "maliyet Yİ-ÜFE %10'dan fazla arttıysa endekslenir.",
      nitelik: MasrafNiteligi.bilgi,
    ),
  ];
}

List<MasrafKalemi> fonKalemleri(MasrafGirdisi g) => const [
      MasrafKalemi(
        baslik: 'Yönetim ücreti',
        aciklama: 'Fonun yıllık yönetim ücreti fiyata yansır; ayrıca '
            'kesilmez.',
        nitelik: MasrafNiteligi.bilgi,
      ),
    ];

/// Mevduat stopajının oranı ve tutarı sözleşme kartında, net getiriyle
/// birlikte hesaplanıyor (`SozlesmeKarti`); burada aynı sayıyı ikinci kez
/// yazmak iki kaynağın ayrışma riskini doğururdu. Kalem oraya yönlendirir.
List<MasrafKalemi> mevduatKalemleri(MasrafGirdisi g) => const [
      MasrafKalemi(
        baslik: 'Stopaj',
        aciklama: 'Faizden kesilen stopaj yukarıdaki sözleşme kartında, net '
            'getiriyle birlikte.',
        nitelik: MasrafNiteligi.bilgi,
      ),
    ];

List<MasrafKalemi> kriptoKalemleri(MasrafGirdisi g) => const [
      MasrafKalemi(
        baslik: 'Borsa işlem ücreti',
        aciklama: 'Kripto borsası her alım ve satımda işlem ücreti keser; '
            'oranı borsaya ve işlem hacmine göre değişir.',
        nitelik: MasrafNiteligi.bilgi,
      ),
    ];

List<MasrafKalemi> makasKalemleri(MasrafGirdisi g) => const [
      MasrafKalemi(
        baslik: 'Alış-satış makası',
        aciklama: 'Kuyumcu/banka alış ile satış arasındaki fark, satarken '
            'ödenir.',
        nitelik: MasrafNiteligi.bilgi,
      ),
    ];
