import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/fon_akisi.dart';
import '../services/fon_karnesi.dart' show fonKoduOf;
import '../services/hisse_hacmi.dart';
import '../services/radar_okuma.dart';
import '../widgets/hacim_radari_karti.dart' show bistSembolu, kriptoTickeri;
import 'fon_akisi_provider.dart';
import 'portfolio_provider.dart';

/// Haftanın özetinde bir satırın rozeti (S6-B, 2026-10-05). Önem sırası
/// enum sırasıdır: üstteki olağandışı, `hareketli` orta, `sakin` en alt.
///
/// Rozet VERİDEN gelir, nottan değil — sunucudaki `rozetBelirle`
/// (`_shared/analiz.ts`) ile aynı olaylara bakar; kart ile özetin dili
/// `radar_okuma.dart`'taki kademe eşikleriyle aynıdır.
enum HaftaRozeti {
  buyukGiris,
  buyukCikis,
  olagandisiHacim,
  aliciIstekli,
  saticiIstekli,
  hareketli,
  sakin;

  /// Başlıktaki "N varlığında olağandışı hareket" sayısına girer mi.
  bool get olagandisi => index <= HaftaRozeti.saticiIstekli.index;
}

enum HaftaVarlikTuru { fon, hisse, kripto }

/// "Haftanın özeti"nde tek satır: tutulan bir varlık ve son haftası.
/// Tam olarak biri dolu: [fon] (fon/BES) ya da [hacim] (hisse/kripto).
class HaftaSatiri {
  const HaftaSatiri({
    required this.pozisyon,
    required this.tur,
    required this.anahtar,
    required this.rozet,
    required this.onem,
    this.fon,
    this.hacim,
    this.hacimOlayi,
  });

  /// Kullanıcının BUGÜN açık olan pozisyonu (kapanmış pozisyon gelmez).
  final Position pozisyon;
  final HaftaVarlikTuru tur;

  /// Not anahtarı ('TEFAS:TTE', 'THYAO.IS', 'KRIPTO:BTC').
  final String anahtar;
  final HaftaRozeti rozet;

  /// Aynı rozet içinde sıralama ölçüsü (büyük önce): fonda akış / büyüklük,
  /// hissede hacim katı, kriptoda alıcı payının %50'den uzaklığı.
  final double onem;
  final FonAkisOzeti? fon;
  final HacimOzeti? hacim;

  /// Son 7 günün en yeni olağandışı hacim günü (hisse/kripto).
  final HacimOlayi? hacimOlayi;
}

/// Fon satırı: rozet ve önem. Saf; test edilir.
HaftaSatiri fonSatiri(Position p, String kod, FonAkisOzeti o) {
  final olay = sonHaftaOlayi(o);
  final kademe = fonOkunusu(o).kademe;
  final rozet = olay != null
      ? (olay.giris ? HaftaRozeti.buyukGiris : HaftaRozeti.buyukCikis)
      : kademe == null || kademe == Kademe.sakin
          ? HaftaRozeti.sakin
          : HaftaRozeti.hareketli;
  return HaftaSatiri(
    pozisyon: p,
    tur: HaftaVarlikTuru.fon,
    anahtar: 'TEFAS:$kod',
    rozet: rozet,
    // Mutlak tutar değil oran: 50 mr'lik fonda ₺100 mn gürültü, 500 mn'lik
    // fonda haberdir.
    onem: o.buyukluk > 0 ? o.sonHaftaNet.abs() / o.buyukluk : 0,
    fon: o,
  );
}

/// Hisse / kripto satırı.
HaftaSatiri hacimSatiri(Position p, String anahtar, HacimOzeti o,
    {required bool kripto}) {
  final olay = sonHaftaHacimOlayi(o);
  final HaftaRozeti rozet;
  final double onem;
  if (kripto) {
    final okunus = kriptoOkunusu(o);
    onem = o.aliciPayi == null ? 0 : (o.aliciPayi! - 0.5).abs();
    if (olay != null) {
      rozet = HaftaRozeti.olagandisiHacim;
    } else if (okunus != null && okunus.kademe == Kademe.cokHareketli) {
      rozet = okunus.yon == Yon.giris
          ? HaftaRozeti.aliciIstekli
          : HaftaRozeti.saticiIstekli;
    } else if (okunus != null && okunus.kademe == Kademe.hareketli) {
      rozet = HaftaRozeti.hareketli;
    } else {
      rozet = HaftaRozeti.sakin;
    }
  } else {
    final kademe = hacimKademesi(o);
    onem = olay?.ortalamaKati ?? o.kat ?? 0;
    rozet = olay != null
        ? HaftaRozeti.olagandisiHacim
        : kademe == null || kademe == Kademe.sakin
            ? HaftaRozeti.sakin
            : HaftaRozeti.hareketli;
  }
  return HaftaSatiri(
    pozisyon: p,
    tur: kripto ? HaftaVarlikTuru.kripto : HaftaVarlikTuru.hisse,
    anahtar: anahtar,
    rozet: rozet,
    onem: onem,
    hacim: o,
    hacimOlayi: olay,
  );
}

/// Önem sırası: rozet, sonra aynı rozette önem ölçüsü, eşitlikte kod.
List<HaftaSatiri> haftaSirasi(List<HaftaSatiri> liste) =>
    [...liste]..sort((a, b) {
        final r = a.rozet.index.compareTo(b.rozet.index);
        if (r != 0) return r;
        final o = b.onem.compareTo(a.onem);
        if (o != 0) return o;
        return a.anahtar.compareTo(b.anahtar);
      });

/// Kullanıcının tuttuğu fon, hisse ve coinlerin son haftası, tek listede
/// (Balina B4 2026-10-04; tek liste S6-B 2026-10-05).
///
/// Yeni bir sorgu türü yok: her varlık için kartın kullandığı AYNI
/// provider okunur — ekran ile varlık sayfasındaki kart aynı sayıyı
/// gösterir, ikinci bir hesap yolu açılmaz. Verisi olmayan (yeni, bayat)
/// varlık listeye girmez; "veri yok" satırı uydurulmaz.
///
/// Yalnız KENDİ pozisyonları: ortak lot'ları başka bir kullanıcının
/// portföyüdür (`partner_aggregation_invariant`), haftalık bildirim de
/// yalnız sahibine gider.
final haftaOzetiProvider =
    FutureProvider.autoDispose<List<HaftaSatiri>>((ref) async {
  final durum = ref.watch(portfolioProvider).valueOrNull;
  if (durum == null) return const [];
  final kendi = [
    for (final a in durum.assets)
      if (a.userId == durum.ownerId) a,
  ];

  // Aynı varlık iki pozisyon anahtarına düşse de (önekli/öneksiz kod) tek
  // satır.
  final gorulen = <String>{};
  final isler = <Future<HaftaSatiri?>>[];
  for (final p in aggregatePositions(kendi)) {
    final v = p.representative;
    final hisse = bistSembolu(tur: v.type, ticker: v.ticker);
    final coin = kriptoTickeri(tur: v.type, ticker: v.ticker);
    final fon = hisse == null && coin == null
        ? fonKoduOf(tur: v.type, ticker: v.ticker)
        : null;
    if (fon != null) {
      if (!gorulen.add('TEFAS:$fon')) continue;
      isler.add(ref
          .watch(fonAkisiProvider(fon).future)
          .then((o) => o == null ? null : fonSatiri(p, fon, o)));
    } else if (hisse != null) {
      if (!gorulen.add(hisse)) continue;
      isler.add(ref.watch(hisseHacmiProvider(hisse).future).then(
          (o) => o == null ? null : hacimSatiri(p, hisse, o, kripto: false)));
    } else if (coin != null) {
      if (!gorulen.add(coin)) continue;
      isler.add(ref.watch(kriptoBaskiProvider(coin).future).then(
          (o) => o == null ? null : hacimSatiri(p, coin, o, kripto: true)));
    }
  }
  return haftaSirasi((await Future.wait(isler)).nonNulls.toList());
});

/// Bu hafta olağandışı hareket olan varlık sayısı (Bugün şeridi, S7).
/// Bayrak kapalıyken 0 ve HİÇ sorgu yok — ana ekran eski hâliyle aynı.
final haftaOlagandisiSayisiProvider = Provider.autoDispose<int>((ref) {
  if (!ref.watch(balinaRadariAcikProvider)) return 0;
  final liste = ref.watch(haftaOzetiProvider).valueOrNull ?? const [];
  return liste.where((s) => s.rozet.olagandisi).length;
});

/// Sunucu notundaki rozet ('buyuk_giris'…) → enum; tanınmayan → null.
HaftaRozeti? haftaRozetiSunucudan(String? r) => switch (r) {
      'buyuk_giris' => HaftaRozeti.buyukGiris,
      'buyuk_cikis' => HaftaRozeti.buyukCikis,
      'olagandisi_hacim' => HaftaRozeti.olagandisiHacim,
      'alici_istekli' => HaftaRozeti.aliciIstekli,
      'satici_istekli' => HaftaRozeti.saticiIstekli,
      'sakin' => HaftaRozeti.sakin,
      _ => null,
    };
