import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../providers/analiz_provider.dart' show notAnahtari, notKodu;
import 'aylik_rapor_ozeti.dart';
import 'crash_reporter.dart';
import 'fon_akisi.dart' show FonBalinaOlayi;
import 'history_service.dart';
import 'hisse_hacmi.dart' show HacimOlayi;
import 'period_summary_service.dart';
import 'supabase_service.dart';

/// Aylık raporun sayısal bölümlerinin okumaları (2026-11-07). Hesap saf
/// fonksiyonlarda (`aylik_rapor_ozeti.dart`); burası yalnız veriyi toplar.
///
/// Ekran ve PDF AYNI sonucu kullanır: ekran provider'dan okur, PDF ekranın
/// elindeki nesneyi alır. Eskiden PDF ayın getirisini kendi başına
/// hesaplıyordu; iki yol ayrışabilirdi.
///
/// Bir okuma düşerse o parça boş gelir, diğerleri yazılır; hata
/// Crashlytics'e gider (uydurma yok, sessiz yutma yok).
class AylikRaporYukleyici {
  AylikRaporYukleyici._();

  /// [lotlar]: sahibin TÜM etkin defter satırları (kapanmış pozisyonun
  /// satışı dahil — geçmişi soran yer). [canliToplam]: süren ayda ucun
  /// canlı kapsam toplamı (Performans'ın aylık özetiyle aynı uç).
  static Future<AylikRaporOzeti> hazirla({
    required DateTime donem,
    required List<Asset> lotlar,
    DateTime? simdi,
    double? canliToplam,
  }) async {
    final now = simdi ?? DateTime.now();
    final (bas, bit, suren) = AylikRaporOzeti.pencere(donem, now);
    final son =
        suren ? now : DateTime(bit.year, bit.month, bit.day, 23, 59, 59);
    final sonuclar = await Future.wait([
      _seriKismi(bas, son, lotlar, suren ? canliToplam : null),
      _olaylar(bas, bit, lotlar),
    ]);
    final seri = sonuclar[0] as _SeriKismi?;
    final olay = sonuclar[1] as _Olaylar;

    final varliklar = seri?.varliklar ?? const <AyinVarligi>[];
    final olculen = {for (final v in varliklar) v.anahtar};
    final olculemeyen = <(String, AssetType, String)>[
      for (final p in aggregatePositions(aktifLotlar(lotlar)))
        if (!olculen.contains(positionKey(p.representative)))
          (
            positionKey(p.representative),
            p.representative.type,
            p.representative.name,
          ),
    ];
    return AylikRaporOzeti(
      bas: bas,
      bit: bit,
      surenAy: suren,
      ay: seri?.ay,
      varliklar: varliklar,
      olculemeyen: seri == null ? const [] : olculemeyen,
      akis: ayinParaAkisi(lotlar, bas, bit),
      gelismeler: ayinGelismeleri(
        bas: bas,
        bit: bit,
        fonOlaylari: olay.fon,
        hacimOlaylari: olay.hacim,
        dolarKodlari: olay.dolar,
        lotlar: lotlar,
      ),
      fiyatTarihi: seri?.sonOlcum,
    );
  }

  static Future<_SeriKismi?> _seriKismi(
      DateTime bas, DateTime son, List<Asset> lotlar, double? canli) async {
    if (lotlar.isEmpty || !son.isAfter(bas)) return null;
    try {
      final gun = son.difference(bas).inHours / 24;
      final bd = await HistoryService.instance
          .getPortfolioHistoryBreakdownAtResolution(
        assets: lotlar,
        from: bas,
        to: son,
        tier: ResolutionTierMeta.pickForSpan(gun),
      );
      final ay = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: lotlar,
        breakdown: bd,
        now: son,
        pencereBaslangici: bas,
        canliSon: canli,
      );
      final sonMs = son.millisecondsSinceEpoch;
      final tsler = [
        for (final e in bd.total.entries)
          if (e.key <= sonMs && e.value > 0) e.key
      ];
      return _SeriKismi(
        ay: ay,
        varliklar: ayinVarliklari(
          byPosition: bd.byPosition,
          positionType: bd.positionType,
          lotlar: lotlar,
          bas: bas,
          son: son,
        ),
        sonOlcum: tsler.isEmpty
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                tsler.reduce((a, b) => a > b ? a : b)),
      );
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'AylikRapor.seri');
      return null;
    }
  }

  /// Radar varlıklarının ay içindeki olayları. Kartların okuduğu aynı
  /// sorgular (`balinaOlaylari` / `hacimOlaylari` / `kriptoHacimOlaylari`),
  /// ay ucuyla sınırlı. Varlık başına bir istek; tutulan radar varlığı
  /// sayısı küçük (onlarca), ve rapor ayda bir açılır.
  static Future<_Olaylar> _olaylar(
      DateTime bas, DateTime bit, List<Asset> lotlar) async {
    final svc = SupabaseService.instance;
    final anahtarlar = <String>{
      for (final p in aggregatePositions(lotlar))
        if (notAnahtari(
                tur: p.representative.type, ticker: p.representative.ticker)
            case final String k)
          k,
    };
    final fon = <String, List<FonBalinaOlayi>>{};
    final hacim = <String, List<HacimOlayi>>{};
    final dolar = <String>{};
    await Future.wait([
      for (final k in anahtarlar)
        () async {
          try {
            final kod = notKodu(k);
            if (k.startsWith('TEFAS:')) {
              final r = await svc.balinaOlaylari(k, baslangic: bas, bitis: bit);
              fon[kod] = r.map(FonBalinaOlayi.satirdan).nonNulls.toList();
            } else if (k.startsWith('KRIPTO:')) {
              final r =
                  await svc.kriptoHacimOlaylari(k, baslangic: bas, bitis: bit);
              hacim[kod] = r.map(HacimOlayi.satirdan).nonNulls.toList();
              dolar.add(kod);
            } else {
              final r = await svc.hacimOlaylari(k, baslangic: bas, bitis: bit);
              hacim[kod] = r.map(HacimOlayi.satirdan).nonNulls.toList();
            }
          } catch (e, st) {
            CrashReporter.report(e, st, reason: 'AylikRapor.olay');
          }
        }(),
    ]);
    return _Olaylar(fon, hacim, dolar);
  }
}

class _SeriKismi {
  const _SeriKismi({this.ay, required this.varliklar, this.sonOlcum});
  final PeriodSummary? ay;
  final List<AyinVarligi> varliklar;
  final DateTime? sonOlcum;
}

class _Olaylar {
  const _Olaylar(this.fon, this.hacim, this.dolar);
  final Map<String, List<FonBalinaOlayi>> fon;
  final Map<String, List<HacimOlayi>> hacim;
  final Set<String> dolar;
}
