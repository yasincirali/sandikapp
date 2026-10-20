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

  return { gecerliAylar: gecerliAylar, hesapla: hesapla, ayAdi: ayAdi, sayiOku: sayiOku };
});
