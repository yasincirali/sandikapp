import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../services/crash_reporter.dart';
import '../services/fon_karnesi.dart' show fonKoduOf;
import '../services/supabase_service.dart';
import '../services/aylik_rapor_kalemleri.dart' show NotPozisyonu;
import '../services/varlik_analizi.dart';
import '../widgets/hacim_radari_karti.dart' show bistSembolu, kriptoTickeri;
import 'fon_akisi_provider.dart';
import 'portfolio_provider.dart';
import '../utils/pozisyon_etiketi.dart';

/// Varlığın not anahtarı — sunucunun (`analiz-hazirla`) kullandığı biçim:
/// 'TEFAS:TTE', 'THYAO.IS', 'KRIPTO:BTC'. Radar dışı varlık → null.
String? notAnahtari({required AssetType tur, required String ticker}) {
  final hisse = bistSembolu(tur: tur, ticker: ticker);
  if (hisse != null) return hisse;
  final coin = kriptoTickeri(tur: tur, ticker: ticker);
  if (coin != null) return coin;
  final fon = fonKoduOf(tur: tur, ticker: ticker);
  return fon == null ? null : 'TEFAS:$fon';
}

/// Aylık notun anahtarı (2026-11-07, yasin: "tüm varlıklar yorumlansın").
/// Radar türlerinde [notAnahtari] ile aynı; akış/hacim verisi olmayan
/// türler fiyat serisinden ölçülür ve kendi anahtarını taşır. Sunucu eşi
/// `analiz-hazirla › lotSecimi`; biçim iki yanda aynı olmalı:
///   ABD/yurt dışı hisse 'HISSE:AAPL' (önek: 'F' gibi kısa sembol tablonun
///   en az 3 karakter kısıtına takılmasın), bütün altın türleri tek
///   'ALTIN:GRAM' (aynı gram serisinin ağırlık katı, yüzdesi aynı), döviz
///   'USDTRY=X', emtia 'SI=F' / 'GRAM:SI=F', eurobond 'EUROBOND:XS…'.
/// Elle fiyatlı lot, mevduat, diğer, USDT → null (seri yok / piyasa
/// hareketi yok). Haftalık yüzeyler [notAnahtari]'nı kullanmaya devam eder:
/// haftalık not bu türleri kapsamaz.
String? aylikNotAnahtari({
  required AssetType tur,
  required String ticker,
  bool elleFiyat = false,
}) {
  final radar = notAnahtari(tur: tur, ticker: ticker);
  if (radar != null) return radar;
  if (elleFiyat) return null;
  final t = ticker.trim().toUpperCase();
  switch (tur) {
    case AssetType.hisse:
      return RegExp(r'^[A-Z0-9.\-^=]{1,20}$').hasMatch(t) && !t.endsWith('.IS')
          ? 'HISSE:$t'
          : null;
    case AssetType.altin:
      return altinNotAnahtari;
    case AssetType.doviz:
      return RegExp(r'^[A-Z]{3}TRY=X$').hasMatch(t) ? t : null;
    case AssetType.emtia:
      return RegExp(r'^(GRAM:)?[A-Z0-9]{1,6}=F$').hasMatch(t) ? t : null;
    case AssetType.eurobond:
      return t.startsWith('EUROBOND:') && t.length <= 40 ? t : null;
    default:
      return null;
  }
}

/// Bütün altın lotlarının ortak aylık not anahtarı.
const altinNotAnahtari = 'ALTIN:GRAM';

/// Verilen ticker'ların en yeni yayındaki notunun başlığı (ücretsiz katman).
/// Liste anahtar olamaz (eşitlik), bu yüzden virgülle birleşik + sıralı
/// metin: aynı varlık kümesi aynı önbelleği paylaşır.
///
/// Bayrak kapalı → hiç sorgu yok, boş. Hata → boş + Crashlytics: not ek
/// bilgidir, yoksa satırda "Not:" yazmaz, başka hiçbir şey değişmez.
final notOzetleriProvider = FutureProvider.autoDispose
    .family<Map<String, AnalizOzeti>, (String, String)>((ref, anahtar) async {
  final (birlesik, tur) = anahtar;
  if (!ref.watch(balinaRadariAcikProvider) || birlesik.isEmpty) return const {};
  try {
    final satirlar = await SupabaseService.instance
        .analizOzetleri(birlesik.split(','), tur: tur);
    return {
      for (final o in satirlar.map(AnalizOzeti.satirdan).nonNulls) o.ticker: o,
    };
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'notOzetleriProvider');
    return const {};
  }
});

/// `notOzetleriProvider` için anahtar: tekrarsız, sıralı, en çok 200
/// (RPC de 200'de keser).
(String, String) notKumesi(Iterable<String> tickerlar, String tur) {
  final s = tickerlar.toSet().toList()..sort();
  return (s.take(200).join(','), tur);
}

/// Tek varlığın haftalık notunun başlığı (varlık sayfasındaki kutu, S15).
final varlikNotOzetiProvider = FutureProvider.autoDispose
    .family<AnalizOzeti?, String>((ref, ticker) async {
  final m = await ref
      .watch(notOzetleriProvider(notKumesi([ticker], 'haftalik')).future);
  return m[ticker];
});

/// Notun tamamı (S17). Premium kapısı açık ve kullanıcı Premium değilse
/// RLS satır vermez → null; ekran kilit çizer.
final varlikNotuProvider = FutureProvider.autoDispose
    .family<VarlikNotu?, (String, String, DateTime)>((ref, a) async {
  final (ticker, tur, donem) = a;
  try {
    final r = await SupabaseService.instance
        .varlikAnalizi(ticker, tur: tur, donem: donem);
    return r == null ? null : VarlikNotu.satirdan(r);
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'varlikNotuProvider');
    return null;
  }
});

/// Not anahtarının ekrandaki kısa adı: 'TEFAS:TTE' → 'TTE', 'THYAO.IS' →
/// 'THYAO', 'KRIPTO:BTC' → 'BTC', 'HISSE:AAPL' → 'AAPL', 'USDTRY=X' →
/// 'USD/TRY', 'ALTIN:GRAM' → 'Altın' (dile göre ad için [notAdi]).
String notKodu(String ticker) {
  if (ticker == altinNotAnahtari) return 'Altın';
  final t = ticker
      .replaceFirst(RegExp(r'^(TEFAS|KRIPTO|HISSE|EUROBOND):'), '')
      .replaceFirst(RegExp(r'\.IS$'), '');
  final d = RegExp(r'^([A-Z]{3})TRY=X$').firstMatch(t);
  return d == null ? t : '${d.group(1)}/TRY';
}

/// [notKodu]'nun dile göre hâli: yalnız altının adı çevrilir (diğerleri
/// sembol).
String notAdi(String ticker, AppLocalizations l) =>
    ticker == altinNotAnahtari ? AssetType.altin.labelOf(l) : notKodu(ticker);

/// Kullanıcının BUGÜN tuttuğu (kendi) varlıkların AYLIK not anahtarları
/// ([aylikNotAnahtari]; 2026-11-07'ye kadar yalnız radar türleriydi ve
/// yurt dışı hisse/altın/döviz/emtia/eurobond raporda hiç sorulmuyordu).
final tutulanNotAnahtarlariProvider = Provider.autoDispose<List<String>>((ref) {
  final durum = ref.watch(portfolioProvider).valueOrNull;
  if (durum == null) return const [];
  final kendi = [
    for (final a in durum.assets)
      if (a.userId == durum.ownerId) a,
  ];
  return {
    for (final p in aggregatePositions(kendi))
      if (aylikNotAnahtari(
              tur: p.representative.type,
              ticker: p.representative.ticker,
              elleFiyat: p.representative.isManualPrice)
          case final String k)
        k,
  }.toList();
});

/// `positionKey` → aylık not karşılığı (ad, tür); kullanıcının tutulan
/// (kendi) pozisyonlarından (2026-11-07, yasin: "rapor anlaşılır olmalı" —
/// ekranda 'THYAO.IS', 'KRIPTO:' gibi ham kod görünmez). Ad
/// `pozisyonEtiketi` ile, uygulamanın her yerde gösterdiği adla aynı; altın
/// lotları tek not anahtarında birleşir, adı tür adıdır ("Altın").
final notPozisyonlariProvider =
    Provider.autoDispose.family<Map<String, NotPozisyonu>, AppLocalizations>(
        (ref, l) {
  final durum = ref.watch(portfolioProvider).valueOrNull;
  if (durum == null) return const {};
  final out = <String, NotPozisyonu>{};
  for (final p in aggregatePositions([
    for (final a in durum.assets)
      if (a.userId == durum.ownerId) a,
  ])) {
    final r = p.representative;
    final k = aylikNotAnahtari(
        tur: r.type, ticker: r.ticker, elleFiyat: r.isManualPrice);
    if (k == null) continue;
    final anahtar = positionKey(r);
    out[anahtar] = (
      notAnahtari: k,
      tur: r.type,
      ad: k == altinNotAnahtari
          ? AssetType.altin.labelOf(l)
          : pozisyonEtiketi(anahtar, r.type, l, ad: r.name),
    );
  }
  return out;
});
