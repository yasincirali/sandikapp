import '../l10n/generated/app_localizations_tr.dart';
import '../models/asset.dart';
import '../providers/analiz_provider.dart' show notKodu;
import '../providers/hafta_ozeti_provider.dart'
    show HaftaRozeti, haftaRozetiSunucudan;
import 'crash_reporter.dart';
import 'disa_aktarim/aylik_rapor_belgesi.dart';
import 'disa_aktarim/rapor_belgesi.dart';
import 'history_service.dart';
import 'inflation_service.dart';
import 'period_summary_service.dart';
import 'supabase_service.dart';
import 'varlik_analizi.dart';

/// Aylık raporun PDF'i için veriyi toplar (2026-10-31). Belgenin içeriği
/// saf kurucuda (`aylikRaporBelgesi`); burası okumalar:
///   - varlık notlarının TAMAMI (maddeler) — saklanan satır, yapay zekâ
///     yeniden çağrılmaz;
///   - ayın getirisi — Performans'ın aylık özetiyle aynı hesap
///     (`PeriodSummaryService.compute`, pencere ayın 1'inden ay sonuna ya da
///     bugüne);
///   - ayın TÜFE'si — endeksten tek bölme (`InflationService.changePct`).
///
/// Bir okuma düşerse o parça çıkmaz, belge yine yazılır: not maddesi yoksa
/// yalnız öz cümle, getiri yoksa kutu yok. Hata Crashlytics'e gider,
/// kullanıcıya yarım belge değil eksik kutu gösterilir (uydurma yok).
///
/// Metinler Türkçe (`AppLocalizationsTr`): diğer Premium PDF'ler gibi belge
/// Türkçe, alıcısı çoğunlukla Türk mali müşavir ya da aile.
class AylikRaporDisaAktarim {
  AylikRaporDisaAktarim._();

  static Future<RaporBelgesi> belgeHazirla({
    required DateTime donem,
    required List<AnalizOzeti> notlar,
    required List<String> eksik,
    required List<Asset> lotlar,
    required String kim,
    double? canliToplam,
    DateTime? simdi,
  }) async {
    final now = simdi ?? DateTime.now();
    final tr = AppLocalizationsTr();
    final sonuclar = await Future.wait([
      Future.wait(notlar.map(_tamNot)),
      _ayinGetirisi(donem, lotlar, now, canliToplam),
      _ayinTufesi(donem),
    ]);
    final tamNotlar = sonuclar[0] as List<VarlikNotu?>;
    final hareketli = notlar.where((n) => n.rozet != 'sakin').length;
    return aylikRaporBelgesi(
      donem: donem,
      notlar: [
        for (var i = 0; i < notlar.length; i++)
          AylikRaporNotu(
            kod: notKodu(notlar[i].ticker),
            baslik: notlar[i].baslik,
            rozet: _rozetMetni(tr, haftaRozetiSunucudan(notlar[i].rozet)),
            maddeler: [
              for (final m in tamNotlar[i]?.maddeler ?? const <NotMaddesi>[])
                m.metin,
            ],
          ),
      ],
      ozetCumlesi: hareketli > 0
          ? tr.anzAylikOzetVar('${notlar.length}', '$hareketli')
          : tr.anzAylikOzetYok,
      eksikCumlesi: eksik.isEmpty ? null : tr.anzAylikEksik(eksik.join(', ')),
      kim: kim,
      olusturma: now,
      getiriPct: sonuclar[1] as double?,
      tufePct: sonuclar[2] as double?,
    );
  }

  static Future<VarlikNotu?> _tamNot(AnalizOzeti o) async {
    try {
      final r = await SupabaseService.instance
          .varlikAnalizi(o.ticker, tur: 'aylik', donem: o.donem);
      return r == null ? null : VarlikNotu.satirdan(r);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'AylikRaporPdf.not');
      return null;
    }
  }

  /// [canliToplam]: bugünkü canlı kapsam toplamı (`DailySummary
  /// .kapsamToplami`). Yalnız pencere BUGÜNDE bitiyorsa (süren ay) uç olarak
  /// verilir; Performans'ın aylık özeti de ucu canlıya bağlar, verilmezse
  /// bugünkü alımlar katkıda sayılıp değerde sayılmaz ve getiri ekrandan
  /// farklı çıkar (`ozet_canli_uc_test`). Kapanmış ayda uç ay sonu slotudur.
  static Future<double?> _ayinGetirisi(DateTime donem, List<Asset> lotlar,
      DateTime now, double? canliToplam) async {
    if (lotlar.isEmpty) return null;
    final ayBasi = DateTime(donem.year, donem.month);
    final aySonu = DateTime(donem.year, donem.month + 1)
        .subtract(const Duration(seconds: 1));
    final son = aySonu.isAfter(now) ? now : aySonu;
    if (!son.isAfter(ayBasi)) return null;
    try {
      final gun = son.difference(ayBasi).inHours / 24;
      final bd = await HistoryService.instance
          .getPortfolioHistoryBreakdownAtResolution(
        assets: lotlar,
        from: ayBasi,
        to: son,
        tier: ResolutionTierMeta.pickForSpan(gun),
      );
      return PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: lotlar,
        breakdown: bd,
        now: son,
        pencereBaslangici: ayBasi,
        canliSon: identical(son, now) ? canliToplam : null,
      ).getiriPct;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'AylikRaporPdf.getiri');
      return null;
    }
  }

  /// Ayın TÜFE'si: endeks[ay] / endeks[önceki ay]. Ay açıklanmadıysa null
  /// (belge açıklanacağı günü yazar).
  static Future<double?> _ayinTufesi(DateTime donem) async {
    try {
      final endeks = await InflationService.instance.indexSeries();
      return InflationService.changePct(
          endeks, DateTime(donem.year, donem.month - 1), donem);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'AylikRaporPdf.tufe');
      return null;
    }
  }

  /// Sakin ya da bilinmeyen rozet etiketsiz: PDF'te yalnız belirgin hareket
  /// işaretlenir (ekranda sakin çipi de var; kâğıtta gürültü olurdu).
  static String? _rozetMetni(AppLocalizationsTr tr, HaftaRozeti? r) =>
      switch (r) {
        HaftaRozeti.buyukGiris => tr.rdrRozetBuyukGiris,
        HaftaRozeti.buyukCikis => tr.rdrRozetBuyukCikis,
        HaftaRozeti.olagandisiHacim => tr.rdrRozetHacim,
        HaftaRozeti.aliciIstekli => tr.rdrRozetAlici,
        HaftaRozeti.saticiIstekli => tr.rdrRozetSatici,
        HaftaRozeti.hareketli => tr.rdrRozetHareketli,
        HaftaRozeti.sakin || null => null,
      };
}
