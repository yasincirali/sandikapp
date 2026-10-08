import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset_type.dart';
import '../models/position.dart';
import '../services/crash_reporter.dart';
import '../services/fon_karnesi.dart' show fonKoduOf;
import '../services/supabase_service.dart';
import '../services/varlik_analizi.dart';
import '../widgets/hacim_radari_karti.dart' show bistSembolu, kriptoTickeri;
import 'fon_akisi_provider.dart';
import 'portfolio_provider.dart';

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
/// 'THYAO', 'KRIPTO:BTC' → 'BTC'.
String notKodu(String ticker) => ticker
    .replaceFirst(RegExp(r'^(TEFAS|KRIPTO):'), '')
    .replaceFirst(RegExp(r'\.IS$'), '');

/// Kullanıcının BUGÜN tuttuğu (kendi) varlıkların not anahtarları.
final tutulanNotAnahtarlariProvider = Provider.autoDispose<List<String>>((ref) {
  final durum = ref.watch(portfolioProvider).valueOrNull;
  if (durum == null) return const [];
  final kendi = [
    for (final a in durum.assets)
      if (a.userId == durum.ownerId) a,
  ];
  return {
    for (final p in aggregatePositions(kendi))
      if (notAnahtari(
              tur: p.representative.type, ticker: p.representative.ticker)
          case final String k)
        k,
  }.toList();
});
