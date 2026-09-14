import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/insight_metrics_service.dart';

/// Yatırımcı seviyesi — Özet sekmesinde HANGİ metriklerin çizileceğini seçer.
///
/// Ürün gereksinimi başlangıç / orta / ileri için farklı metrik kümesi
/// istiyordu; profilde deneyim alanı OLMADIĞI ve zorunlu onboarding adımı
/// istenmediği için ertelenmişti (TECHNICAL_DEBT "Yatırımcı seviyesine göre
/// görünüm yok"). Çözüm: sunucuda alan açmak yerine Ayarlar › Görünüm'de
/// OPSİYONEL bir tercih (`SharedPreferences`, kişiye özel). Sorulmaz,
/// dayatılmaz; varsayılan bugünkü görünüm (Orta).
///
/// ## Neden gizleme, veri değil
/// Bir kartın verisi yoksa zaten çizilmiyor (yeni kullanıcıda sağlık/XIRR
/// gibi). Seviye o kuralın ÜSTÜNE gelir: Başlangıç'ta veri olsa da bazı
/// kartlar çizilmez, İleri'de ek bir kart eklenir. Hesap katmanı seviyeyi
/// bilmez — yalnızca görünürlük değişir.
enum YatirimciSeviyesi {
  baslangic(Icons.spa_outlined),
  orta(Icons.insights_outlined),
  ileri(Icons.science_outlined);

  const YatirimciSeviyesi(this.ikon);

  final IconData ikon;

  /// Etiket ve açıklama dile göre (3.20) — enum bağlamsız, `context` ister;
  /// `...Of(l)` sürümleri testte sözlükle doğrudan çağrılır.
  String etiket(BuildContext context) => etiketOf(context.l10n);
  String aciklama(BuildContext context) => aciklamaOf(context.l10n);

  String etiketOf(AppLocalizations l) => switch (this) {
        YatirimciSeviyesi.baslangic => l.levelBeginner,
        YatirimciSeviyesi.orta => l.levelIntermediate,
        YatirimciSeviyesi.ileri => l.levelAdvanced,
      };

  String aciklamaOf(AppLocalizations l) => switch (this) {
        YatirimciSeviyesi.baslangic => l.levelBeginnerDesc,
        YatirimciSeviyesi.orta => l.levelIntermediateDesc,
        YatirimciSeviyesi.ileri => l.levelAdvancedDesc,
      };

  /// Tercih dosyasındaki indeks. Aralık dışı → varsayılan (Orta): eski bir
  /// sürümden gelen bozuk değer ekranı boşaltmasın.
  static YatirimciSeviyesi fromIndex(int i) =>
      i >= 0 && i < values.length ? values[i] : varsayilan;

  static const varsayilan = YatirimciSeviyesi.orta;
}

/// Seviyeye göre Özet kartlarının görünürlüğü — saf karar tablosu.
///
/// Tek yerde durur ki "Başlangıç'ta X görünüyor mu" sorusu ekran koduna
/// dağılmasın; `_OzetYanVeri` bunu okuyup ilgili parametreyi `null` geçer.
({bool saglik, bool xirr, bool percentile, bool ileri}) seviyeGorunurlugu(
    YatirimciSeviyesi s) {
  switch (s) {
    case YatirimciSeviyesi.baslangic:
      return (saglik: false, xirr: false, percentile: false, ileri: false);
    case YatirimciSeviyesi.orta:
      return (saglik: true, xirr: true, percentile: true, ileri: false);
    case YatirimciSeviyesi.ileri:
      return (saglik: true, xirr: true, percentile: true, ileri: true);
  }
}

/// İleri seviye metrikleri — Özet 1Y bloğunun ek kartı. Saf hesap.
///
/// Üç sayı, üçü de zaten hesaplanan girdilerden türetilir; ağa çıkmaz:
///   * [riskAyarliGetiri] = getiri / yıllık oynaklık. Sharpe'ın risksiz
///     oransız hâli: "aldığın her birim dalgalanma için kaç puan getiri".
///     TL'de risksiz oran (mevduat/TLREF) uygulamada tutulmuyor; onu
///     uydurmak yerine oransız tanım açıkça yazılır.
///   * [zamanlamaEtkisi] = XIRR − piyasa getirisi. Pozitifse alım
///     tarihlerin piyasayı yendi, negatifse yanlış zamanda girmişsin.
///   * [toparlanmaGun] en büyük düşüşten eski zirveye dönüş süresi; `null`
///     ise hâlâ dönülmedi ([toparlanmadi] true).
class IleriMetrikler {
  const IleriMetrikler({
    required this.riskAyarliGetiri,
    required this.zamanlamaEtkisi,
    required this.toparlanmaGun,
    required this.toparlanmadi,
  });

  final double? riskAyarliGetiri;
  final double? zamanlamaEtkisi;
  final int? toparlanmaGun;
  final bool toparlanmadi;

  bool get hasData =>
      riskAyarliGetiri != null || zamanlamaEtkisi != null || toparlanmaGun != null || toparlanmadi;

  /// `null` döner: hiçbir metrik hesaplanamıyorsa (kart çizilmez).
  static IleriMetrikler? hesapla({
    required double? getiriPct,
    required double? volatilitePct,
    required double? xirrPct,
    required Drawdown? drawdown,
  }) {
    final risk = (getiriPct != null &&
            volatilitePct != null &&
            volatilitePct.isFinite &&
            volatilitePct > 0)
        ? getiriPct / volatilitePct
        : null;
    final zamanlama =
        (xirrPct != null && getiriPct != null) ? xirrPct - getiriPct : null;
    final toparlanma = drawdown?.toparlanmaGun;
    final toparlanmadi = drawdown != null && drawdown.toparlanmaGun == null;
    final m = IleriMetrikler(
      riskAyarliGetiri: risk,
      zamanlamaEtkisi: zamanlama,
      toparlanmaGun: toparlanma,
      toparlanmadi: toparlanmadi,
    );
    return m.hasData ? m : null;
  }
}
