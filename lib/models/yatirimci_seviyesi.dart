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

  /// Başlangıç sade düzende daha çok şey gizler (bkz. [seviyeGorunurlugu]);
  /// açıklama bunu söyler. Bayrak `seviye_anketi` kapalıyken kullanılan
  /// kısa Başlangıç açıklaması (`levelBeginnerDesc`) bayrakla birlikte
  /// 2026-10-05'te kalktı.
  String aciklamaOf(AppLocalizations l) => switch (this) {
        YatirimciSeviyesi.baslangic => l.levelBeginnerDescSade,
        YatirimciSeviyesi.orta => l.levelIntermediateDesc,
        YatirimciSeviyesi.ileri => l.levelAdvancedDesc,
      };

  /// Tercih dosyasındaki indeks. Aralık dışı → varsayılan (Orta): eski bir
  /// sürümden gelen bozuk değer ekranı boşaltmasın.
  static YatirimciSeviyesi fromIndex(int i) =>
      i >= 0 && i < values.length ? values[i] : varsayilan;

  static const varsayilan = YatirimciSeviyesi.orta;
}

/// Seviyeye göre metrik yüzeylerinin görünürlüğü — saf karar tablosu.
///
/// Tek yerde durur ki "Başlangıç'ta X görünüyor mu" sorusu ekran koduna
/// dağılmasın; her ekran bunu okuyup ilgili bloğu çizer ya da çizmez.
///
/// ## Neden Özet sekmesiyle sınırlı DEĞİL (2026-09-15)
/// İlk sürümde yalnızca Performans › Özet kartlarını süzüyordu. Üç kart da
/// **1Y dönemine** bağlı (sağlık/XIRR) ya da k-anonimlik eşiğine (yüzdelik);
/// bir yıllık geçmişi ya da sekiz kişilik havuzu olmayan kullanıcıda seviye
/// değiştirmek EKRANDA HİÇBİR ŞEYİ değiştirmiyordu — "ayar çalışmıyor"
/// (kullanıcı bildirimi 2026-09-15). Şimdi ilk açılışta görülen yüzeyleri de
/// kapsıyor: ana ekranın yüzdelik şeridi ve teknik sinyal yüzeyleri
/// (ana ekran sinyal zili, tekil varlıkta sinyal kartı + gösterge paneli).
///
/// Kural değişmedi: **Başlangıç yalnızca GİZLER, İleri yalnızca EKLER**,
/// Orta bugünkü görünümdür. Hiçbir hesap seviyeye bakmaz.
///
/// ## Sade Başlangıç (2026-10-04; bayrak `seviye_anketi` 2026-10-05'te kalktı)
/// Kullanıcı isteği: Performans *"çelişkili olmamalı, kafada soru işareti
/// oluşturmamalı; yatırımcı seviyesine göre detaylı bilgiler sergilenebilir."*
/// Başlangıç ayrıca şunları gizler:
///   * [grafikAraclari] — grafik tipi seçici (Alan/Taban/çubuk/mum),
///     Gerçek|Simülasyon anahtarı, varlık grafiğinde MA20/LOG ve (Premium) MUM/EMA50/EMA200 çipleri.
///     Grafik düz çizgide kalır, rakamlar gerçek geçmişten gelir.
///   * [derinlik] — Özet'in "Daha fazlası" bölümü (eski adı DERİNLİK:
///     endeks kıyası, XIRR, sağlık, karakter, sabır). "Ne oldu?" /
///     "Neden böyle?" / "Ayrıntılar" aynen durur.
///
/// ## İleri terimler seviye dışında (2026-10-04, sadeleştirme 2)
/// "Risk-ayarlı getiri" ve "Zamanlama etkisi" yalnız [ileri] kartında
/// çizilir; seviye dışında yalnız seviye AÇIKLAMASINDA geçer ve orada
/// gündelik karşılıkla yazılır ("riske göre getiri", "alım zamanlamanın
/// etkisi"). "XIRR" Orta'da görünen yüzeylerden (Derinlik ipucu, paylaşım
/// kartı/metni, seviye açıklamaları) çıkarıldı → "yıllık getiri". Bu
/// yüzden yeni görünürlük alanı GEREKMEDİ: metin her seviyede anlaşılır,
/// gizleme kararı değişmedi.
/// Orta ve İleri bundan etkilenmez — mevcut kullanıcının varsayılanı Orta
/// olduğu için hiç dokunmayan kimse bir şey kaybetmez.
typedef SeviyeGorunurluk = ({
  bool saglik,
  bool xirr,
  bool percentile,
  bool teknikSinyaller,
  bool ileri,
  bool grafikAraclari,
  bool derinlik,
});

SeviyeGorunurluk seviyeGorunurlugu(YatirimciSeviyesi s) {
  switch (s) {
    case YatirimciSeviyesi.baslangic:
      return (
        saglik: false,
        xirr: false,
        percentile: false,
        teknikSinyaller: false,
        ileri: false,
        grafikAraclari: false,
        derinlik: false,
      );
    case YatirimciSeviyesi.orta:
      return (
        saglik: true,
        xirr: true,
        percentile: true,
        teknikSinyaller: true,
        ileri: false,
        grafikAraclari: true,
        derinlik: true,
      );
    case YatirimciSeviyesi.ileri:
      return (
        saglik: true,
        xirr: true,
        percentile: true,
        teknikSinyaller: true,
        ileri: true,
        grafikAraclari: true,
        derinlik: true,
      );
  }
}

/// Seviye anketi (2026-10-04) — üç sorunun cevabından seviye. Saf fonksiyon.
///
/// Kullanıcı sorusu: *"Seviyeyi de bir anketle mi almak mantıklı?"* Evet:
/// "Başlangıç mısın, İleri misin" diye sorulan kişi kendini çoğu zaman
/// olduğundan yukarıda ya da aşağıda konumlar, ve "Başlangıç" etiketi
/// kimseye hoş gelmez. Davranışa dair üç soru daha isabetli ve etiketsiz.
///
/// Her cevap 0 (yeni), 1 (orta) ya da 2 (deneyimli) puan. Toplam 0–6:
///   0–1 → Başlangıç, 2–4 → Orta, 5–6 → İleri.
/// Eşikler bilinçli olarak Orta'yı geniş tutar: Orta bugünkü görünümdür,
/// yanlış sınıflamanın en ucuz olduğu seviye.
/// Eksik/geçersiz cevap listesi → `null` (seviye değişmez).
YatirimciSeviyesi? seviyeAnketSonucu(List<int> cevaplar) {
  if (cevaplar.length != seviyeAnketSoruSayisi) return null;
  if (cevaplar.any((c) => c < 0 || c > 2)) return null;
  final toplam = cevaplar.fold<int>(0, (a, b) => a + b);
  if (toplam <= 1) return YatirimciSeviyesi.baslangic;
  if (toplam >= 5) return YatirimciSeviyesi.ileri;
  return YatirimciSeviyesi.orta;
}

const seviyeAnketSoruSayisi = 3;

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
