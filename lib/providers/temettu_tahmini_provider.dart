import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart' show DefterImzasi;
import '../models/position.dart';
import '../services/fiyat_kaynagi.dart';
import '../services/remote_config_service.dart';
import '../services/temettu_gecmisi.dart';
import '../services/temettu_tahmini.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';

/// Kullanıcının KENDİ bugünkü BIST hisseleri için 12 aylık temettü tahmini
/// (Premium, 2026-10-10). Hesap saf `temettuTahmini`'nde; burası yalnız
/// pozisyonları kurar ve olayları çeker (`TemettuGecmisiService`, sembol
/// başına 6 saat önbellek — fiyat turu yeniden ağa çıkarmaz).
///
/// Bugünkü mülkiyet sorusu → `aktifLotlar` (CLAUDE.md "Kapanmış
/// pozisyon"); ortağın lotları girmez. Sembol kararı yalnız
/// `FiyatKaynagi.temettuSembolu` (fiyat kaynağı sözleşmesi madde 1).
final temettuTahminiProvider =
    FutureProvider.autoDispose<TemettuTahmini>((ref) async {
  final uid = ref.watch(authProvider).valueOrNull?.id;
  // Fiyat turu `assets`'ı her seferinde yeni liste yazar; liste kimliğini
  // izlemek tahmini her turda yeniden koşturup ekranı iskelete düşürüyordu
  // (Ar-Ge 12 Kas #6, ölçüldü: `temettu_tazeleme_iskelet_test`). Tahmin
  // fiyattan bağımsız: yalnız defter içeriği değişince yeniden hesaplanır.
  // Aylık raporun `sahip|satır sayısı` seçicisi miktar düzenlemesini
  // kaçırırdı; `DefterImzasi` kaçırmaz.
  ref.watch(portfolioProvider.select((s) => switch (s.valueOrNull) {
        final d? => DefterImzasi(d.assets),
        null => null,
      }));
  final lotlar = ref.read(portfolioProvider).valueOrNull?.assets ?? const [];
  if (uid == null) {
    return TemettuTahmini(satirlar: const [], aylik: List.filled(12, 0));
  }
  final pozisyonlar = aggregatePositions(
      aktifLotlar(lotlar.where((a) => a.userId == uid)).toList());
  final girdiler = await Future.wait([
    for (final p in pozisyonlar)
      if (FiyatKaynagi.temettuSembolu(p.representative) case final sembol?)
        TemettuGecmisiService.instance.olaylariCek(sembol).then((olaylar) =>
            TahminGirdisi(
              ad: p.representative.name,
              sembol: sembol,
              lot: p.totalQuantity,
              olaylar: olaylar,
            )),
  ]);
  return temettuTahmini(
    girdiler,
    stopaj: RemoteConfigService.instance.temettuStopajOrani,
    simdi: DateTime.now(),
  );
});

/// Kilitli temettü tahmini kartının kişisel satırı için temettü dağıtan
/// hisseler (2026-11-12). `null`: oturum/portföy yok ya da bir sembol
/// okunamadı → satır yok.
///
/// ## Ağ maliyeti kararı
/// Kilitli kullanıcı için de olaylar ÇEKİLİR, sembol başına bir Yahoo
/// isteği; ama yalnız bu ekran açıkken (autoDispose) ve
/// `TemettuGecmisiService`'in 6 saatlik oturum önbelleğinden (varlık
/// sayfasının temettü kartı, Premium tahmin ve bu satır aynı kaydı
/// paylaşır). Ekrana kullanıcı kendisi gelmiştir (Raporlar kapısı,
/// paywall kaynağı) ve satır ancak tam okumayla doğru olur: "önbellekte
/// olanı say" yarım sayı üretirdi. Fiyat turu yeniden ağa çıkarmasın diye
/// defter yalnız sahip ve satır sayısı değişince yeniden okunur (aylık
/// rapor sağlayıcısının deseni).
final temettuKancasiProvider =
    FutureProvider.autoDispose<TemettuKancasi?>((ref) async {
  final uid = ref.watch(authProvider).valueOrNull?.id;
  if (uid == null) return null;
  ref.watch(portfolioProvider.select((v) => switch (v.valueOrNull) {
        final d? => '${d.ownerId}|${d.assets.length}',
        null => null,
      }));
  final durum = ref.read(portfolioProvider).valueOrNull;
  if (durum == null) return null;
  final pozisyonlar = aggregatePositions(
      aktifLotlar(durum.assets.where((a) => a.userId == uid)).toList());
  final semboller = <String>{
    for (final p in pozisyonlar)
      if (p.totalQuantity > 0)
        if (FiyatKaynagi.temettuSembolu(p.representative) case final s?) s,
  };
  final girdiler = await Future.wait([
    for (final s in semboller)
      TemettuGecmisiService.instance
          .olaylariCekVeyaNull(s)
          .then((o) => (s.replaceFirst(RegExp(r'\.IS$'), ''), o)),
  ]);
  return temettuKancasi(girdiler, simdi: DateTime.now());
});
