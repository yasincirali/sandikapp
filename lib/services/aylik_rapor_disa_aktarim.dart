import '../l10n/generated/app_localizations_tr.dart';
import '../models/asset_type.dart';
import '../utils/pozisyon_etiketi.dart';
import '../utils/tr_format.dart';
import '../widgets/aylik_rapor_bolumleri.dart' show gelismeCumlesi;
import 'aylik_rapor_ozeti.dart';
import '../providers/analiz_provider.dart' show notKodu;
import '../providers/hafta_ozeti_provider.dart'
    show HaftaRozeti, haftaRozetiSunucudan;
import 'crash_reporter.dart';
import 'disa_aktarim/aylik_rapor_belgesi.dart';
import 'disa_aktarim/rapor_belgesi.dart';
import 'inflation_service.dart';
import 'supabase_service.dart';
import 'varlik_analizi.dart';

/// Aylık raporun PDF'i için veriyi toplar (2026-10-31). Belgenin içeriği
/// saf kurucuda (`aylikRaporBelgesi`); burası okumalar:
///   - varlık notlarının TAMAMI (maddeler) — saklanan satır, yapay zekâ
///     yeniden çağrılmaz;
///   - ayın getirisi ve köprüsü (ay başı, yatırılan, piyasa, ay sonu, en
///     iyi/en zayıf), ayın varlıkları, para girişi/çıkışı ve gelişmeler —
///     ekranın elindeki `AylikRaporOzeti`'nden (2026-11-07; eskiden PDF
///     getiriyi kendi hesaplıyordu, ekranla iki yol olurdu). Getiri
///     Performans'ın aylık özetiyle aynı hesap (`PeriodSummaryService
///     .compute`, pencere ayın 1'inden ay sonuna ya da bugüne);
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
    required AylikRaporOzeti? ozet,
    required String kim,
    DateTime? simdi,
  }) async {
    final now = simdi ?? DateTime.now();
    final tr = AppLocalizationsTr();
    final sonuclar = await Future.wait([
      Future.wait(notlar.map(_tamNot)),
      _ayinTufesi(donem),
    ]);
    final tamNotlar = sonuclar[0] as List<VarlikNotu?>;
    final ay = ozet?.ay;
    final hareketli = notlar.where((n) => n.rozet != 'sakin').length;
    final (bas, bit, suren) = AylikRaporOzeti.pencere(donem, now);
    final aralik = fmtTarihAraligi(bas, bit);
    final notAraligi = notVeriAraligi(notlar);
    String etiket(String k, AssetType tur, String ad) =>
        pozisyonEtiketi(k, tur, tr, ad: ad);
    return aylikRaporBelgesi(
      donem: donem,
      kapsam: suren ? tr.raporKapsamSuren(aralik) : tr.raporKapsam(aralik),
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
      notAraligiCumlesi: notAraligi == null
          ? null
          : tr.anzAylikNotlarAralik(
              fmtTarihAraligi(notAraligi.$1, notAraligi.$2)),
      ozetCumlesi: hareketli > 0
          ? tr.anzAylikOzetVar('${notlar.length}', '$hareketli')
          : tr.anzAylikOzetYok,
      eksikCumlesi: eksik.isEmpty ? null : tr.anzAylikEksik(eksik.join(', ')),
      kim: kim,
      olusturma: now,
      getiriPct: ay?.getiriPct,
      tufePct: sonuclar[1] as double?,
      portfoy: ay == null
          ? null
          : AyinPortfoyu(
              baslangicTRY: ay.baslangicTRY,
              sonTRY: ay.sonTRY,
              katkiTRY: ay.katkiTRY,
              piyasaTRY: ay.piyasaTRY,
              // `enIyi` adı ham `positionKey`'dir (compute'a etiket
              // verilmedi); belgeye kısa adıyla yazılır.
              enIyi: ay.enIyi == null
                  ? null
                  : (_kisaAd(ay.enIyi!.name), ay.enIyi!.changePct),
              enZayif: ay.enZayif == null
                  ? null
                  : (_kisaAd(ay.enZayif!.name), ay.enZayif!.changePct),
            ),
      varliklar: [
        for (final v in ozet?.varliklar ?? const <AyinVarligi>[])
          (etiket(v.anahtar, v.tur, v.ad), v.pct, v.piyasaTRY),
      ],
      olculemeyenCumlesi: (ozet?.olculemeyen.isEmpty ?? true)
          ? null
          : tr.anzAylikOlculemeyen(([
              for (final (k, tur, ad) in ozet!.olculemeyen) etiket(k, tur, ad)
            ]..sort())
              .join(', ')),
      fiyatCumlesi: ozet?.fiyatTarihi == null
          ? null
          : tr.raporFiyatTarihi(fmtTarih(ozet!.fiyatTarihi!, saat: true)),
      akis: ozet?.akis,
      gelismeler: [
        for (final g in ozet?.gelismeler ?? const <AyinGelismesi>[])
          (g.tarih, g.kod, gelismeCumlesi(tr, g)),
      ],
      haberCumlesi: tr.anzAylikHaberYok,
    );
  }

  /// `positionKey` ('hisse|THYAO.IS|TRY') → ekrandaki kısa ad. Tür bilinmez
  /// (PeriodSummary yalnız adı taşır); sembol çekirdeği yeterli.
  static String _kisaAd(String anahtar) {
    final p = anahtar.split('|');
    if (p.length < 2) return anahtar;
    final tur = AssetType.values.where((t) => t.name == p[0]).firstOrNull;
    return pozisyonEtiketi(
        anahtar, tur ?? AssetType.diger, AppLocalizationsTr());
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
