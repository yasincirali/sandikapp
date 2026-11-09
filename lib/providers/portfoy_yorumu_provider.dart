import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/asset.dart';
import '../models/position.dart' show positionKey;
import '../services/daily_summary.dart';
import '../services/period_summary_service.dart' show SummaryPeriod;
import '../services/portfoy_yorumu_service.dart';
import '../utils/pozisyon_etiketi.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';

/// AI portföy yorumu (0145) — Özet kartının durumu.
///
/// Paket yalnız DEFTER değişince yeniden kurulur: fiyat tazelemesi yorumun
/// anlattığı kapanmış dönemi değiştirmez, her tick'te seri hesabı yapmak
/// boşa iş olurdu ([_defterImzasi]).
class PortfoyYorumDurumu {
  const PortfoyYorumDurumu({required this.paket, required this.kayit});

  final PortfoyYorumPaketi paket;

  /// Bu dönemin saklı yorumu (yoksa null).
  final PortfoyYorumu? kayit;

  /// Saklı yorum bugünkü paketin dönem sonu portföyüyle aynı mı? Değilse
  /// kart yorumu yine gösterir, "değişti, yeniden yorumla" der.
  bool get guncel => kayit != null && kayit!.parmakIzi == paket.parmakIzi;
}

String _defterImzasi(List<Asset>? assets) {
  if (assets == null) return '';
  final p = [
    for (final a in assets)
      '${a.id}:${a.quantity}:${a.addedDate.millisecondsSinceEpoch}:${a.isActive}',
  ]..sort();
  return p.join(',');
}

/// Kartın "rıza var mı" sorusu. Hata → null (kart rıza varsaymaz).
final portfoyYorumRizaProvider = FutureProvider.autoDispose<bool?>(
    (ref) => PortfoyYorumuService.instance.rizaVarMi());

final portfoyYorumuProvider = FutureProvider.autoDispose
    .family<PortfoyYorumDurumu?, YorumTuru>((ref, tur) async {
  ref.watch(portfolioProvider.select((s) => _defterImzasi(s.valueOrNull?.assets)));
  final uid = ref.watch(authProvider.select((s) => s.valueOrNull?.id));
  final assets = ref.read(portfolioProvider).valueOrNull?.assets;
  if (uid == null || assets == null) return null;
  // Yalnız kendi portföyü: ortak varlıkları başkasının verisidir, modele
  // gönderilmez.
  final lotlar = [for (final a in assets) if (a.userId == uid) a];
  if (lotlar.isEmpty) return null;

  // Ölçüm adları modele Türkçe gider (talimat Türkçe); arayüz dili ne olursa olsun.
  final tr = lookupAppLocalizations(const Locale('tr'));
  final adlar = <String, String>{for (final a in lotlar) positionKey(a): a.name};
  final svc = PortfoyYorumuService.instance;
  final paket = await svc.paketHazirla(
    tur: tur,
    lotlar: lotlar,
    etiket: (k, t) => pozisyonEtiketi(k, t, tr, ad: adlar[k]),
  );
  final kayit = await svc.kayitliYorum(tur, paket.baslangic);
  return PortfoyYorumDurumu(paket: paket, kayit: kayit);
});

/// Seçili dönemin portföy yorumu (0151) — Performans'ın dönem seçicisi.
///
/// GÜNLÜK'te `null` (yorumlanmaz). Paket, kapanmış dönem kartıyla aynı
/// nedenle yalnız DEFTER değişince yeniden kurulur; canlı uç (dönem sonu
/// toplamı) kurulduğu andaki fiyattan okunur.
final portfoySeciliYorumProvider = FutureProvider.autoDispose
    .family<PortfoyYorumDurumu?, SummaryPeriod>((ref, period) async {
  if (!seciliYorumlanabilir(period)) return null;
  ref.watch(portfolioProvider.select((s) => _defterImzasi(s.valueOrNull?.assets)));
  final uid = ref.watch(authProvider.select((s) => s.valueOrNull?.id));
  final pState = ref.read(portfolioProvider).valueOrNull;
  if (uid == null || pState == null) return null;
  final lotlar = [for (final a in pState.assets) if (a.userId == uid) a];
  if (lotlar.isEmpty) return null;

  final tr = lookupAppLocalizations(const Locale('tr'));
  final adlar = <String, String>{for (final a in lotlar) positionKey(a): a.name};
  final svc = PortfoyYorumuService.instance;
  final paket = await svc.seciliPaketHazirla(
    period: period,
    lotlar: lotlar,
    etiket: (k, t) => pozisyonEtiketi(k, t, tr, ad: adlar[k]),
    canliSon: DailySummary.kapsamToplami(pState, lotlar),
    canliDagilim: DailySummary.kapsamDagilimi(pState, lotlar),
  );
  final kayit = await svc.kayitliSeciliYorum(
    kapsam: YorumKapsami.portfoy,
    donemKodu: paket.donemKodu!,
    bitis: paket.bitis,
  );
  return PortfoyYorumDurumu(paket: paket, kayit: kayit);
});

/// Varlık yorumunun sunucu anahtarı: hangi varlık, hangi dönem, hangi gün.
typedef VarlikYorumAnahtari = ({
  String varlikIzi,
  String donemKodu,
  DateTime bitis,
});

/// Varlık detayının bugünkü saklı yorumu (0151). Paket burada KURULMAZ:
/// ölçümler canlı fiyatla her nabızda değişir, istek yalnız "Bu dönemi
/// yorumla"da o anki değerlerle kurulur. Kayıt aramak için anahtar yeter.
final varlikYorumKaydiProvider = FutureProvider.autoDispose
    .family<PortfoyYorumu?, VarlikYorumAnahtari>((ref, a) async {
  final uid = ref.watch(authProvider.select((s) => s.valueOrNull?.id));
  if (uid == null) return null;
  return PortfoyYorumuService.instance.kayitliSeciliYorum(
    kapsam: YorumKapsami.varlik,
    donemKodu: a.donemKodu,
    bitis: a.bitis,
    varlikIzi: a.varlikIzi,
  );
});
