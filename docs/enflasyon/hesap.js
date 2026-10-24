/*
 * Enflasyon hesaplayıcısının saf hesabı (2026-10-20).
 *
 * Tarayıcıda `window.TufeHesap`, Node'da `require()` ile gelir; aynı dosya
 * test/tufe_web_test.dart tarafından `node` ile koşulur ki sayfanın gösterdiği
 * sayı ile test edilen sayı aynı kod olsun.
 *
 * Kararlar:
 * - Endeks DEĞERİ kullanılır (0045_inflation_index.sql kararı): iki ay arası
 *   değişim tek bölme, son / ilk. Aylık yüzdeleri çarpmak yuvarlama biriktirir.
 * - "Bugün" = son AÇIKLANMIŞ ay. Açıklanmamış ay hesaplanmaz; listede olmayan
 *   ay için sonuç null döner, tahmin yürütülmez (uydurma sayı yasak).
 * - Başlangıç son ayın kendisiyse sonuç null: aynı ayı kendisiyle kıyaslamak
 *   ziyaretçiye "%0" diye yanlış bir güven verir.
 */
(function (kok, kur) {
  if (typeof module === 'object' && module.exports) module.exports = kur();
  else kok.TufeHesap = kur();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var AY_ADLARI = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

  /** tufe.json'daki ayları süzer: geçerli "YYYY-MM" + pozitif endeks, eskiden yeniye. */
  function gecerliAylar(veri) {
    var aylar = (veri && Array.isArray(veri.aylar)) ? veri.aylar : [];
    return aylar
      .filter(function (a) {
        return a && /^\d{4}-(0[1-9]|1[0-2])$/.test(a.ay) &&
          typeof a.endeks === 'number' && isFinite(a.endeks) && a.endeks > 0;
      })
      .slice()
      .sort(function (x, y) { return x.ay < y.ay ? -1 : x.ay > y.ay ? 1 : 0; });
  }

  /**
   * `tutar` lira `baslangic` ayında neye denkse, son açıklanan ayda kaç lira eder.
   * Dönüş: { karsilik, artis, alimGucuKaybi, sonAy } ya da null.
   *   artis          fiyatlar ne kadar arttı (0,5 = %50)
   *   alimGucuKaybi  aynı paranın alım gücü ne kadar azaldı (0,333 = %33,3)
   */
  function hesapla(veri, tutar, baslangic) {
    if (typeof tutar !== 'number' || !isFinite(tutar) || tutar <= 0) return null;
    var aylar = gecerliAylar(veri);
    if (aylar.length < 2) return null;
    var son = aylar[aylar.length - 1];
    if (baslangic === son.ay) return null;
    var ilk = null;
    for (var i = 0; i < aylar.length; i++) if (aylar[i].ay === baslangic) ilk = aylar[i];
    if (!ilk) return null;
    var oran = son.endeks / ilk.endeks;
    return {
      karsilik: tutar * oran,
      artis: oran - 1,
      alimGucuKaybi: 1 - 1 / oran,
      sonAy: son.ay
    };
  }

  /** "2026-09" → "Eylül 2026". */
  function ayAdi(ay) {
    var p = /^(\d{4})-(\d{2})$/.exec(ay || '');
    if (!p) return '';
    return AY_ADLARI[parseInt(p[2], 10) - 1] + ' ' + p[1];
  }

  /** "10.000", "10 000", "10000,50" → sayı; çözülemezse NaN. */
  function sayiOku(metin) {
    var s = String(metin == null ? '' : metin).replace(/[\s.₺]/g, '').replace(',', '.');
    if (!/^\d+(\.\d+)?$/.test(s)) return NaN;
    return parseFloat(s);
  }

  // ── Paylaşım (2026-10-24, Ar-Ge 2045 §3 / rapor 2115 §3) ────────────────
  //
  // Bağlantı YALNIZ iki parametre taşır: `ay` (YYYY-MM) ve isteğe bağlı
  // `tutar` (düz rakam, nokta ondalık). Fikirdeki `yil`/`tur=altin` yok:
  // sayfa yalnız TÜFE hesaplar (dolar/altın kıyası lisans sorusu yüzünden
  // sonraya), olmayan bir türü bağlantıya koymak açılışta uydurma sonuç
  // demekti. Her parametre sınırlı ve doğrulanır; biri bile geçersizse
  // bağlantının TAMAMI yok sayılır (yarım okunmuş bağlantı paylaşanın
  // gördüğünden farklı bir sonuç gösterirdi).

  var TUTAR_UST = 1e12; // 1 trilyon ₺: üstü yazım hatası ya da saçma bağlantı

  /**
   * `?ay=2025-01&tutar=10000` → { ay, tutar } (tutar yoksa null), parametre
   * yoksa { bos: true }, geçersizse null. `ay` açıklanmış ve son aydan önce
   * olmalı (hesapla() ile aynı kural); tutar 0 < t ≤ 1e12, en çok 2 ondalık.
   */
  function paylasimOku(sorgu, veri) {
    var p;
    try { p = new URLSearchParams(String(sorgu || '')); } catch (e) { return null; }
    var ay = p.get('ay');
    var tutarHam = p.get('tutar');
    if (ay === null && tutarHam === null) return { bos: true };
    if (p.getAll('ay').length > 1 || p.getAll('tutar').length > 1) return null;
    var aylar = gecerliAylar(veri);
    if (aylar.length < 2) return null;
    if (ay !== null) {
      var bulundu = false;
      for (var i = 0; i < aylar.length - 1; i++) if (aylar[i].ay === ay) bulundu = true;
      if (!bulundu) return null;
    }
    var tutar = null;
    if (tutarHam !== null) {
      if (!/^\d{1,13}(\.\d{1,2})?$/.test(tutarHam)) return null;
      tutar = parseFloat(tutarHam);
      if (!(tutar > 0) || tutar > TUTAR_UST) return null;
    }
    return { ay: ay, tutar: tutar };
  }

  /** Paylaşılacak adres; `tutar` null ise bağlantıda tutar YOK. */
  function paylasimAdresi(taban, ay, tutar) {
    var p = new URLSearchParams();
    p.set('ay', ay);
    // Açılışta paylasimOku'nun reddedeceği tutar bağlantıya hiç girmez.
    var t = (tutar === null || tutar === undefined) ? 0 : Math.round(tutar * 100) / 100;
    if (t > 0 && t <= TUTAR_UST) p.set('tutar', String(t));
    return String(taban).split(/[?#]/)[0] + '?' + p.toString();
  }

  var YUZDE = new Intl.NumberFormat('tr-TR', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
  var LIRA = new Intl.NumberFormat('tr-TR', { maximumFractionDigits: 0 });
  var KURUS = new Intl.NumberFormat('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  function tl(x) { return (x >= 100 ? LIRA : KURUS).format(x) + ' ₺'; }
  function pct(x) { return '%' + YUZDE.format(x * 100); }

  /**
   * Paylaşım metni. Varsayılan YALNIZ oran: tutar kişinin kendi bilgisi,
   * ancak `tutar` verilirse (kullanıcı kutuyu işaretlediyse) metne girer.
   * Ay/sayıdan sonra ek yok (sayfadaki cümleyle aynı kural).
   */
  function paylasimMetni(s, baslangic, tutar) {
    var govde = tutar !== null && tutar !== undefined
      ? ayAdi(baslangic) + ' fiyatlarıyla ' + tl(tutar) + ', ' + ayAdi(s.sonAy) +
        ' fiyatlarıyla ' + tl(tutar * (1 + s.artis)) + ' eder. Alım gücü ' +
        pct(s.alimGucuKaybi) + ' azaldı.'
      : ayAdi(baslangic) + ' ile ' + ayAdi(s.sonAy) + ' arasında fiyatlar ' +
        pct(s.artis) + ' arttı, kenarda bekleyen paranın alım gücü ' +
        pct(s.alimGucuKaybi) + ' azaldı.';
    return govde + ' Kendi rakamınla hesapla:';
  }

  return {
    gecerliAylar: gecerliAylar, hesapla: hesapla, ayAdi: ayAdi, sayiOku: sayiOku,
    paylasimOku: paylasimOku, paylasimAdresi: paylasimAdresi, paylasimMetni: paylasimMetni,
    tl: tl, pct: pct
  };
});
