// Haftalık varlık notu ve aylık rapor — SAF yardımcılar (Balina F2, 0117).
//
// `analiz-hazirla` (paket kurar, Batch gönderir) ve `analiz-topla` (sonucu
// kapıdan geçirip yazar) ağ ve veritabanı işini yapar; buradaki her şey
// girdi alıp çıktı döner ki `supabase/tests/analiz_test.ts` Anthropic'e ve
// Postgres'e dokunmadan sınayabilsin.
//
// ── Ölçüm paketi: model sayı ÜRETMEZ, seçer ─────────────────────────────────
// Modele ham tablo verilmez; her sayı önceden hesaplanmış, Türkçe biçimlenmiş
// bir ÖLÇÜM olarak gider (`anahtar`, `gosterim`, `kaynak`, `tarih`). Model
// metni yazarken yalnız bu gösterimleri kullanır ve her maddenin dayandığı
// ölçümlerin anahtarlarını `kanit` alanına koyar. İki kazanç:
//   1) Sayı kapısı basitleşir: metindeki her sayı, ölçümlerin gösterim
//      metinlerinde aynen geçmeli. Hesap yapan, yuvarlayan, uyduran not reddedilir.
//   2) Uygulama her maddenin altına kanıt çipini (`₺398 mn · TEFAS 30 Eyl`)
//      ölçümden çizer; finansal okuryazar kullanıcı doğrulayabilir.
//
// ── Rozet veriden gelir ─────────────────────────────────────────────────────
// "Büyük giriş", "olağandışı hacim" gibi etiketler modelin yorumu değil, aynı
// kuralların (`balina_olay`, alıcı payı eşiği) sonucudur. Kart, liste ve not
// aynı rozeti gösterir.
//
// ── Dil kapısı ──────────────────────────────────────────────────────────────
// Betimleyici metin, SPK yatırım danışmanlığı sınırı: al/sat/hedef fiyat,
// kesinlik, aciliyet, tahmin dili yayına çıkmaz. "Balina" denmez (kimin aldığı
// bilinmiyor). Model "yatırım tavsiyesi değildir" de yazmaz; uygulama her
// notun altına kendisi ekler — modelin yazdığı "tavsiye" kelimesi her durumda
// red sebebidir.

import { gunEkle } from './balina.ts';
import { isaretliTutar } from './haftalik_akis.ts';

// ── Tipler ──────────────────────────────────────────────────────────────────

// 2026-11-07 (yasin, "tüm varlıklar"): aylık raporda akış/hacim verisi
// olmayan türler fiyat serisinden ölçülür (`fiyatPaketi`).
export type VarlikTuru =
  | 'fon'
  | 'hisse'
  | 'kripto'
  | 'yabanci_hisse'
  | 'altin'
  | 'doviz'
  | 'emtia'
  | 'eurobond';
export type NotTuru = 'haftalik' | 'aylik';
export type Rozet =
  | 'buyuk_giris'
  | 'buyuk_cikis'
  | 'olagandisi_hacim'
  | 'alici_istekli'
  | 'satici_istekli'
  // Fiyat paketinin "önemli gelişme" rozeti (0180): aylık değişim olağan
  // oynaklığın 2 katı ya da üstü, oynaklık sıçraması ya da 52 haftalık uç.
  // İstemci eşi `HaftaRozeti.hareketli` (aynı ad, aynı orta kademe).
  | 'hareketli'
  | 'sakin';

export type Olcum = {
  anahtar: string;
  /// Ham değer (TL, oran 0–1, adet). Uygulama yeniden biçimlemez; yalnız kayıt.
  deger: number;
  /// Metinde ve kanıt çipinde aynen kullanılacak gösterim.
  gosterim: string;
  /// Okunur ad ("Son hafta net akış").
  ad: string;
  kaynak: 'TEFAS' | 'Yahoo Finance' | 'Binance' | 'Börse Frankfurt';
  /// Verinin ait olduğu gün (ISO).
  tarih: string;
};

export type Paket = {
  ticker: string;
  /// Ekranda görünen kısa ad ('TTE', 'THYAO', 'BTC').
  kod: string;
  varlik: VarlikTuru;
  /// Fonun TEFAS kategorisi; diğerlerinde null.
  kategori: string | null;
  tur: NotTuru;
  /// Dönemin ilk ve son günü (ISO).
  baslangic: string;
  bitis: string;
  rozet: Rozet;
  olcumler: Olcum[];
  /// Dönemdeki olaylar, düz Türkçe ("29 Eyl büyük giriş").
  olaylar: string[];
  /// Yalnız fiyat paketinde: serinin kote olduğu para ('TRY', 'USD'…).
  /// Akış/hacim paketinde yok (eski batch girdileri de böyle).
  para?: string;
};

// ── Biçim (uygulamadaki fmtTRYCompact / fmtPct ile aynı) ───────────────────

const AYLAR = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

export function gunAy(iso: string): string {
  const [, a, g] = iso.split('-').map(Number);
  return `${g} ${AYLAR[a - 1]}`;
}

function trSayi(n: number, hane: number): string {
  const [tam, kesir] = Math.abs(n).toFixed(hane).split('.');
  const binlik = tam.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return (n < 0 ? '−' : '') + (hane > 0 ? `${binlik},${kesir}` : binlik);
}

/// Oran (0,031) → '%3,1'; işaretli istenirse '+%3,1' / '−%3,1'.
export function yuzde(oran: number, isaretli = false, hane = 1): string {
  const g = `%${trSayi(Math.abs(oran) * 100, hane)}`;
  if (!isaretli || oran === 0) return g;
  return oran > 0 ? `+${g}` : `−${g}`;
}

export function adet(n: number, isaretli = false): string {
  const g = trSayi(Math.abs(Math.round(n)), 0);
  if (!isaretli || n === 0) return g;
  return n > 0 ? `+${g}` : `−${g}`;
}

/// USDT kısa: '$212,40M'. Kripto tutarları TL'ye çevrilmez.
export function dolar(v: number, isaretli = false): string {
  const a = Math.abs(v);
  let g: string;
  if (a >= 1e9) g = `$${trSayi(a / 1e9, 2)}Mr`;
  else if (a >= 1e6) g = `$${trSayi(a / 1e6, 2)}M`;
  else if (a >= 1e3) g = `$${trSayi(a / 1e3, 1)}K`;
  else g = `$${trSayi(a, 0)}`;
  if (!isaretli || v === 0) return g;
  return v > 0 ? `+${g}` : `−${g}`;
}

/// TL kısa tutar: '₺3,32Mr'; işaretli istenirse '+₺137,66M' / '−₺56,37M'
/// (bildirimdeki `isaretliTutar` ile aynı biçim).
export function tlTutar(v: number, isaretli = false): string {
  const g = isaretliTutar(v);
  return isaretli ? g : g.replace(/^[+−]/, '');
}

export function kat(x: number): string {
  return `${trSayi(x, 1)} kat`;
}

// ── Dönem ───────────────────────────────────────────────────────────────────

/// Haftalık notun anlattığı hafta: [simdi]'den önceki son TAM hafta
/// (Pazartesi–Pazar). Pazar 20:00'de koşan iş o haftayı anlatır.
export function haftaAraligi(bugunIso: string): { baslangic: string; bitis: string } {
  const d = new Date(`${bugunIso}T12:00:00Z`);
  const haftaGunu = (d.getUTCDay() + 6) % 7; // Pzt=0 … Paz=6
  // Pazar ise bu hafta, değilse geçen hafta.
  const pazartesi = haftaGunu === 6 ? gunEkle(bugunIso, -6) : gunEkle(bugunIso, -haftaGunu - 7);
  return { baslangic: pazartesi, bitis: gunEkle(pazartesi, 6) };
}

/// Aylık rapor: [bugun]'den önceki tam takvim ayı.
export function ayAraligi(bugunIso: string): { baslangic: string; bitis: string } {
  const [y, a] = bugunIso.split('-').map(Number);
  const onceki = a === 1 ? [y - 1, 12] : [y, a - 1];
  const bas = `${onceki[0]}-${String(onceki[1]).padStart(2, '0')}-01`;
  const bit = gunEkle(`${y}-${String(a).padStart(2, '0')}-01`, -1);
  return { baslangic: bas, bitis: bit };
}

// ── Paket kurucular ─────────────────────────────────────────────────────────

export type FonGunu = {
  tarih: string;
  net_akis: number | null;
  portfoy_degeri: number;
  yatirimci: number | null;
  fon_turu: string | null;
};
export type OlaySatiri = {
  tarih: string;
  tur: string;
  tutar: number;
  buyukluk_orani?: number | null;
  ortalama_kati?: number | null;
  fiyat_degisim?: number | null;
  alici_payi?: number | null;
};
export type KategoriSirasi = { sira: number; fonSayisi: number } | null;

const icinde = (t: string, bas: string, bit: string) => t >= bas && t <= bit;

/// Fon/BES paketi. Dönemde hiç akış satırı yoksa `null` (not üretilmez —
/// "bu hafta ₺0" diye uydurma bir not çıkmasın).
/// `akis_kati` için bakılan önceki hafta sayısı ve en az verili hafta
/// (uygulamada `haftaSayisi - 1` ve `fonAsgariHafta`).
export const ONCEKI_HAFTA = 7;
export const ASGARI_ONCEKI_HAFTA = 3;

export function fonPaketi(
  ticker: string,
  tur: NotTuru,
  aralik: { baslangic: string; bitis: string },
  gunler: FonGunu[],
  olaylar: OlaySatiri[],
  kategoriSirasi: KategoriSirasi,
): Paket | null {
  const kod = ticker.replace(/^TEFAS:/, '');
  const sirali = [...gunler].sort((a, b) => a.tarih.localeCompare(b.tarih));
  const donemde = sirali.filter((g) => icinde(g.tarih, aralik.baslangic, aralik.bitis));
  const akisli = donemde.filter((g) => g.net_akis !== null);
  if (akisli.length === 0) return null;
  const son = donemde[donemde.length - 1];
  const net = akisli.reduce((t, g) => t + (g.net_akis as number), 0);
  // Oranın paydası dönem BAŞINDAKİ büyüklük (uygulamadaki kartla aynı kural).
  const once = sirali.filter((g) => g.tarih < aralik.baslangic).pop();
  const basBuyukluk = once?.portfoy_degeri ?? donemde[0].portfoy_degeri;
  const ilkGun = akisli[0].tarih;
  const sonGun = akisli[akisli.length - 1].tarih;

  const o: Olcum[] = [
    { anahtar: 'net_akis', ad: tur === 'haftalik' ? 'Haftalık net akış' : 'Aylık net akış',
      deger: net, gosterim: tlTutar(net, true), kaynak: 'TEFAS', tarih: sonGun },
    { anahtar: 'akis_orani', ad: 'Akışın dönem başı fon büyüklüğüne oranı',
      deger: net / basBuyukluk, gosterim: yuzde(net / basBuyukluk, true), kaynak: 'TEFAS', tarih: sonGun },
    { anahtar: 'buyukluk', ad: 'Fon büyüklüğü', deger: son.portfoy_degeri,
      gosterim: tlTutar(son.portfoy_degeri), kaynak: 'TEFAS', tarih: son.tarih },
  ];
  const degisim = son.portfoy_degeri / basBuyukluk - 1;
  o.push({ anahtar: 'buyukluk_degisim', ad: 'Fon büyüklüğü değişimi (fiyat + para)',
    deger: degisim, gosterim: yuzde(degisim, true), kaynak: 'TEFAS', tarih: son.tarih });
  o.push({ anahtar: 'fiyat_etkisi', ad: 'Büyüklük değişiminin fiyattan gelen kısmı',
    deger: degisim - net / basBuyukluk, gosterim: yuzde(degisim - net / basBuyukluk, true),
    kaynak: 'TEFAS', tarih: son.tarih });

  // Haftalık: akışın önceki haftaların ortalamasına katı. Uygulamadaki
  // "Hareketli" rozetinin ölçüsüyle aynı kural (`radar_okuma.dart`
  // `fonOkunusu`): önceki 7 takvim haftasından verisi olanların |net|
  // ortalaması, en az 3 hafta. Bu ölçü olmadan model, rozeti "Hareketli"
  // olan haftayı "olağan" diye anlatabiliyordu (2026-10-05 web testi).
  if (tur === 'haftalik') {
    const onceki: number[] = [];
    for (let i = 1; i <= ONCEKI_HAFTA; i++) {
      const bas = gunEkle(aralik.baslangic, -7 * i);
      const son6 = gunEkle(bas, 6);
      const hafta = sirali.filter((g) => g.net_akis !== null && icinde(g.tarih, bas, son6));
      if (hafta.length > 0) onceki.push(Math.abs(hafta.reduce((t, g) => t + (g.net_akis as number), 0)));
    }
    const ort = onceki.length >= ASGARI_ONCEKI_HAFTA ? onceki.reduce((a, b) => a + b, 0) / onceki.length : 0;
    if (ort > 0) {
      o.push({ anahtar: 'akis_kati', ad: 'Haftalık akışın önceki haftaların ortalamasına göre katı',
        deger: Math.abs(net) / ort, gosterim: kat(Math.abs(net) / ort), kaynak: 'TEFAS', tarih: sonGun });
    }
  }

  const kisililer = donemde.filter((g) => g.yatirimci !== null);
  const kisiOnce = sirali.filter((g) => g.tarih < aralik.baslangic && g.yatirimci !== null).pop();
  if (kisililer.length > 0) {
    const sonKisi = kisililer[kisililer.length - 1].yatirimci as number;
    o.push({ anahtar: 'yatirimci', ad: 'Yatırımcı sayısı', deger: sonKisi,
      gosterim: adet(sonKisi), kaynak: 'TEFAS', tarih: kisililer[kisililer.length - 1].tarih });
    if (kisiOnce) {
      const fark = sonKisi - (kisiOnce.yatirimci as number);
      o.push({ anahtar: 'yatirimci_degisim', ad: 'Yatırımcı sayısı değişimi', deger: fark,
        gosterim: adet(fark, true), kaynak: 'TEFAS', tarih: kisililer[kisililer.length - 1].tarih });
    }
  }
  if (kategoriSirasi && kategoriSirasi.fonSayisi >= 2) {
    o.push({ anahtar: 'kategori_sira', ad: 'Kategoride akış sırası', deger: kategoriSirasi.sira,
      gosterim: `${kategoriSirasi.sira}. / ${kategoriSirasi.fonSayisi} fon`, kaynak: 'TEFAS', tarih: sonGun });
  }

  const donemOlay = olaylar
    .filter((x) => x.tur.startsWith('fon_') && icinde(x.tarih, aralik.baslangic, aralik.bitis))
    .sort((a, b) => a.tarih.localeCompare(b.tarih));
  const olayMetni: string[] = [];
  donemOlay.forEach((x, i) => {
    const giris = x.tutar > 0;
    olayMetni.push(`${gunAy(x.tarih)} büyük ${giris ? 'giriş' : 'çıkış'}`);
    o.push({ anahtar: `olay_${i + 1}_tutar`, ad: `${gunAy(x.tarih)} büyük ${giris ? 'giriş' : 'çıkış'} tutarı`,
      deger: x.tutar, gosterim: tlTutar(x.tutar, true), kaynak: 'TEFAS', tarih: x.tarih });
    if (x.buyukluk_orani != null) {
      o.push({ anahtar: `olay_${i + 1}_oran`, ad: `${gunAy(x.tarih)} hareketinin fon büyüklüğüne oranı`,
        deger: x.buyukluk_orani, gosterim: yuzde(x.buyukluk_orani), kaynak: 'TEFAS', tarih: x.tarih });
    }
  });

  let rozet: Rozet = 'sakin';
  if (donemOlay.length > 0) {
    const olayNet = donemOlay.reduce((t, x) => t + x.tutar, 0);
    rozet = olayNet >= 0 ? 'buyuk_giris' : 'buyuk_cikis';
  }

  return {
    ticker, kod, varlik: 'fon', kategori: son.fon_turu ?? null, tur,
    baslangic: ilkGun, bitis: sonGun, rozet, olcumler: o, olaylar: olayMetni,
  };
}

export type HacimSatiri = { tarih: string; kapanis: number; para_hacmi: number; alici_payi?: number | null };

/// Hisse ya da kripto paketi. Ortalama, dönemden ÖNCEKİ 20 işlem günüdür.
export function hacimPaketi(
  ticker: string,
  varlik: 'hisse' | 'kripto',
  tur: NotTuru,
  aralik: { baslangic: string; bitis: string },
  gunler: HacimSatiri[],
  olaylar: OlaySatiri[],
): Paket | null {
  const kaynak = varlik === 'hisse' ? 'Yahoo Finance' : 'Binance';
  const para = varlik === 'hisse' ? (v: number, i = false) => tlTutar(v, i) : dolar;
  const kod = varlik === 'hisse' ? ticker.replace(/\.IS$/, '') : ticker.replace(/^KRIPTO:/, '');
  const sirali = [...gunler].sort((a, b) => a.tarih.localeCompare(b.tarih));
  const donemde = sirali.filter((g) => icinde(g.tarih, aralik.baslangic, aralik.bitis));
  if (donemde.length === 0) return null;
  const once = sirali.filter((g) => g.tarih < aralik.baslangic);
  const onceki20 = once.slice(-20);
  const son = donemde[donemde.length - 1];
  const ilkGun = donemde[0].tarih;

  const toplam = donemde.reduce((t, g) => t + g.para_hacmi, 0);
  const gunluk = toplam / donemde.length;
  const o: Olcum[] = [
    { anahtar: 'gunluk_hacim', ad: 'Dönemde ortalama günlük işlem hacmi', deger: gunluk,
      gosterim: para(gunluk), kaynak, tarih: son.tarih },
  ];
  if (onceki20.length === 20) {
    const ort = onceki20.reduce((t, g) => t + g.para_hacmi, 0) / 20;
    o.push({ anahtar: 'ortalama_hacim', ad: 'Önceki 20 günün ortalama günlük hacmi', deger: ort,
      gosterim: para(ort), kaynak, tarih: onceki20[19].tarih });
    o.push({ anahtar: 'hacim_kati', ad: 'Günlük hacmin önceki ortalamaya oranı', deger: gunluk / ort,
      gosterim: kat(gunluk / ort), kaynak, tarih: son.tarih });
  }
  const oncekiKapanis = once.length > 0 ? once[once.length - 1].kapanis : null;
  if (oncekiKapanis !== null) {
    const d = son.kapanis / oncekiKapanis - 1;
    o.push({ anahtar: 'fiyat_degisim', ad: 'Dönemde fiyat değişimi', deger: d,
      gosterim: yuzde(d, true), kaynak, tarih: son.tarih });
  }

  let rozet: Rozet = 'sakin';
  if (varlik === 'kripto') {
    const payli = donemde.filter((g) => g.alici_payi != null);
    if (payli.length > 0) {
      const hac = payli.reduce((t, g) => t + g.para_hacmi, 0);
      const pay = payli.reduce((t, g) => t + g.para_hacmi * (g.alici_payi as number), 0) / hac;
      const net = 2 * hac * pay - hac;
      o.push({ anahtar: 'alici_payi', ad: 'Hacim ağırlıklı alıcı payı', deger: pay,
        gosterim: yuzde(pay), kaynak, tarih: son.tarih });
      o.push({ anahtar: 'net_alim', ad: 'Dönem boyunca net alım (alıcı − satıcı hacmi)', deger: net,
        gosterim: dolar(net, true), kaynak, tarih: son.tarih });
      if (pay >= ALICI_ISTEKLI) rozet = 'alici_istekli';
      else if (pay <= SATICI_ISTEKLI) rozet = 'satici_istekli';
    }
  }

  const donemOlay = olaylar
    .filter((x) => x.tur.includes('_hacim_') && icinde(x.tarih, aralik.baslangic, aralik.bitis))
    .sort((a, b) => a.tarih.localeCompare(b.tarih));
  const olayMetni: string[] = [];
  donemOlay.forEach((x, i) => {
    // Tür adı fiyatın yönünü taşır: yüksek hacimle yükseliş / düşüş.
    olayMetni.push(`${gunAy(x.tarih)} olağandışı yüksek hacim, fiyat ${x.tur.endsWith('_yukselis') ? 'yükseldi' : 'düştü'}`);
    o.push({ anahtar: `olay_${i + 1}_hacim`, ad: `${gunAy(x.tarih)} işlem hacmi`, deger: x.tutar,
      gosterim: para(x.tutar), kaynak, tarih: x.tarih });
    if (x.ortalama_kati != null) {
      o.push({ anahtar: `olay_${i + 1}_kat`, ad: `${gunAy(x.tarih)} hacminin ortalamaya oranı`,
        deger: x.ortalama_kati, gosterim: kat(x.ortalama_kati), kaynak, tarih: x.tarih });
    }
    if (x.fiyat_degisim != null) {
      o.push({ anahtar: `olay_${i + 1}_fiyat`, ad: `${gunAy(x.tarih)} fiyat değişimi`,
        deger: x.fiyat_degisim, gosterim: yuzde(x.fiyat_degisim, true), kaynak, tarih: x.tarih });
    }
  });
  if (donemOlay.length > 0) rozet = 'olagandisi_hacim';

  return {
    ticker, kod, varlik, kategori: null, tur,
    baslangic: ilkGun, bitis: son.tarih, rozet, olcumler: o, olaylar: olayMetni,
  };
}

// ── Fiyat paketi (2026-11-07, yasin: "tüm varlıklar") ──────────────────────
//
// Akış (TEFAS) ya da hacim (Yahoo/Binance) tablosu olmayan türler — yurt
// dışı hisse, altın, döviz, emtia, eurobond — ve o tablolarda ay boyu satırı
// çıkmayan fon/hisse/coin için TEK ölçü fiyattır. Seri, uygulamanın da
// kullandığı sağlayıcıdan gelir (`dated_history.ts`, fiyat kaynağı sözleşmesi).
//
// ## Neden yalnız YÜZDE, fiyat düzeyi yok
// Sunucunun altın serisi GC=F × USDTRY'dir; uygulama ekranda truncgil
// kotasyonunu gösterir (sözleşme madde 2: ölçek ekranla aynı olmalı). Fiyat
// düzeyi yazılsaydı nottaki "₺3.150" ekrandaki fiyatla çelişirdi. Oran
// (değişim, oynaklık) kaynak farkında sönümlenir; not bu yüzden düzey yazmaz.
//
// ## "Önemli gelişme" veriden (rozet `hareketli`)
// Haber kaynağı yok (KAP lisansı, `docs/KAP_VERI_LISANSI_2026_09.md`);
// öne çıkma sinyali ölçümlerden türer ve türden bağımsızdır: değişim,
// varlığın KENDİ olağan oynaklığıyla ölçülür (döviz için %4 büyük, kripto
// için olağan). Eşikler `FIYAT_HAREKET_KATI`, `FIYAT_OYNAKLIK_KATI`.
//
// ## Neden TÜFE'ye göre reel getiri yok
// Aylık iş ayın 1'i 06:00'da koşar; TÜİK o ayın TÜFE'sini ayın 3'ünde
// açıklar. O an elde olan TÜFE başka bir ayındır; onunla "reel" yazmak
// dönemi karıştırır (uydurma sayı). Reel getiri raporun sayısal bölümünde
// (istemci, TÜFE açıklandıktan sonra) kalır.

/// Olağan oynaklık için bakılan önceki işlem günü ve asgari gün.
export const FIYAT_ONCEKI_GUN = 60;
export const FIYAT_ASGARI_ONCEKI_GUN = 40;
/// Dönemde en az bu kadar kapanış yoksa paket yok (yarım ay yorumlanmaz).
export const FIYAT_ASGARI_GUN = 5;
/// Rozet eşikleri: aylık değişim olağan aylık oynaklığın 2 katı; dönem
/// oynaklığı önceki dönemin 2 katı.
export const FIYAT_HAREKET_KATI = 2;
export const FIYAT_OYNAKLIK_KATI = 2;
/// 52 haftalık uç için serinin dönem sonundan en az bu kadar gün geriye
/// uzanması gerekir (kısa seride "yılın zirvesi" uydurma olur).
export const YILLIK_ASGARI_GUN = 330;

const GUN_MS = 24 * 60 * 60 * 1000;
const isoGun = (ms: number) => new Date(ms).toISOString().slice(0, 10);

function sapma(xs: number[]): number {
  const ort = xs.reduce((a, b) => a + b, 0) / xs.length;
  return Math.sqrt(xs.reduce((t, x) => t + (x - ort) ** 2, 0) / (xs.length - 1));
}

/// [ms, kapanış] serisinde gün ≤ [iso] olan SON kapanış; yoksa null.
function gunundeki(seri: Array<[number, number]>, iso: string): number | null {
  let out: number | null = null;
  for (const [t, v] of seri) {
    if (isoGun(t) <= iso) out = v;
    else break;
  }
  return out;
}

/// Fiyat paketi. [seri] artan zamanlı [ms, kapanış]; [kur] serinin parası
/// TL değilse `<PARA>TRY=X` serisi (TL bazında değişim için), değilse null.
/// Dönemde [FIYAT_ASGARI_GUN]'den az kapanış ya da dönem öncesi kapanış
/// yoksa `null` — veri yoksa not yok.
export function fiyatPaketi(g: {
  ticker: string;
  kod: string;
  varlik: VarlikTuru;
  tur: NotTuru;
  aralik: { baslangic: string; bitis: string };
  seri: Array<[number, number]>;
  para: string;
  kur: Array<[number, number]> | null;
  kaynak: Olcum['kaynak'];
}): Paket | null {
  const { aralik, kaynak } = g;
  const sirali = [...g.seri].sort((a, b) => a[0] - b[0]);
  const gunlu = sirali.map(([t, v]) => ({ tarih: isoGun(t), t, v }));
  const donemde = gunlu.filter((x) => icinde(x.tarih, aralik.baslangic, aralik.bitis));
  const once = gunlu.filter((x) => x.tarih < aralik.baslangic);
  if (donemde.length < FIYAT_ASGARI_GUN || once.length === 0) return null;

  const onceki = once[once.length - 1];
  const son = donemde[donemde.length - 1];
  const ilk = donemde[0];
  const degisim = son.v / onceki.v - 1;
  const o: Olcum[] = [{
    anahtar: 'fiyat_degisim', ad: g.tur === 'aylik' ? 'Ay boyunca fiyat değişimi' : 'Hafta boyunca fiyat değişimi',
    deger: degisim, gosterim: yuzde(degisim, true), kaynak, tarih: son.tarih,
  }];

  if (g.kur && g.para !== 'TRY') {
    const kurSirali = [...g.kur].sort((a, b) => a[0] - b[0]);
    const kOnce = gunundeki(kurSirali, onceki.tarih);
    const kSon = gunundeki(kurSirali, son.tarih);
    if (kOnce !== null && kSon !== null && kOnce > 0) {
      const tl = (1 + degisim) * (kSon / kOnce) - 1;
      o.push({ anahtar: 'tl_degisim', ad: 'TL bazında değişim (kur etkisi dahil)', deger: tl,
        gosterim: yuzde(tl, true), kaynak: 'Yahoo Finance', tarih: son.tarih });
    }
  }

  const enYuksek = donemde.reduce((m, x) => (x.v > m.v ? x : m));
  const enDusuk = donemde.reduce((m, x) => (x.v < m.v ? x : m));
  o.push({ anahtar: 'donem_araligi', ad: 'Ay içinde en yüksek ve en düşük kapanış arasındaki fark',
    deger: enYuksek.v / enDusuk.v - 1, gosterim: yuzde(enYuksek.v / enDusuk.v - 1), kaynak, tarih: son.tarih });

  // Günlük getiriler: dönemin ilk günü önceki kapanışa göre.
  const zincir = [onceki, ...donemde];
  const getiriler = zincir.slice(1).map((x, i) => ({ tarih: x.tarih, r: x.v / zincir[i].v - 1 }));
  let rozet: Rozet = 'sakin';
  const olayMetni: string[] = [];
  if (getiriler.length >= FIYAT_ASGARI_GUN) {
    const oyn = sapma(getiriler.map((x) => x.r));
    o.push({ anahtar: 'oynaklik', ad: 'Günlük dalgalanma (oynaklık): fiyatın bir günde ortalama ne kadar oynadığı',
      deger: oyn, gosterim: yuzde(oyn, false, 2), kaynak, tarih: son.tarih });
    const enIyi = getiriler.reduce((m, x) => (x.r > m.r ? x : m));
    const enKotu = getiriler.reduce((m, x) => (x.r < m.r ? x : m));
    if (enIyi.r > 0) {
      o.push({ anahtar: 'en_iyi_gun', ad: `En güçlü gün (${gunAy(enIyi.tarih)})`, deger: enIyi.r,
        gosterim: yuzde(enIyi.r, true), kaynak, tarih: enIyi.tarih });
    }
    if (enKotu.r < 0) {
      o.push({ anahtar: 'en_zayif_gun', ad: `En zayıf gün (${gunAy(enKotu.tarih)})`, deger: enKotu.r,
        gosterim: yuzde(enKotu.r, true), kaynak, tarih: enKotu.tarih });
    }

    // Olağan oynaklık: dönemden önceki en çok 60 günlük değişim.
    const oncekiZincir = once.slice(-(FIYAT_ONCEKI_GUN + 1));
    const oncekiGetiri = oncekiZincir.slice(1).map((x, i) => x.v / oncekiZincir[i].v - 1);
    if (oncekiGetiri.length >= FIYAT_ASGARI_ONCEKI_GUN) {
      const olagan = sapma(oncekiGetiri);
      if (olagan > 0) {
        const oynKati = oyn / olagan;
        o.push({ anahtar: 'onceki_oynaklik', ad: `Önceki ${oncekiGetiri.length} işlem gününde günlük dalgalanma`,
          deger: olagan, gosterim: yuzde(olagan, false, 2), kaynak, tarih: once[once.length - 1].tarih });
        o.push({ anahtar: 'oynaklik_kati', ad: 'Dalgalanmanın önceki döneme göre katı', deger: oynKati,
          gosterim: kat(oynKati), kaynak, tarih: son.tarih });
        // Değişimin, aynı gün sayısında olağan oynaklıkla beklenen
        // hareketin (σ·√n) kaçı olduğu: türden bağımsız "büyüklük".
        const hareketKati = Math.abs(degisim) / (olagan * Math.sqrt(getiriler.length));
        o.push({ anahtar: 'hareket_kati', ad: 'Değişimin bu varlık için olağan harekete göre büyüklüğü',
          deger: hareketKati, gosterim: kat(hareketKati), kaynak, tarih: son.tarih });
        if (hareketKati >= FIYAT_HAREKET_KATI || oynKati >= FIYAT_OYNAKLIK_KATI) rozet = 'hareketli';
      }
    }
  }

  // 52 haftalık uç: dönem sonu kapanışı son bir yılın en yükseği/düşüğü mü.
  const yilBasi = isoGun(new Date(`${aralik.bitis}T12:00:00Z`).getTime() - 364 * GUN_MS);
  const uzanir = gunlu.length > 0 &&
    new Date(`${aralik.bitis}T12:00:00Z`).getTime() - gunlu[0].t >= YILLIK_ASGARI_GUN * GUN_MS;
  if (uzanir) {
    const yil = gunlu.filter((x) => icinde(x.tarih, yilBasi, son.tarih));
    const yilMax = Math.max(...yil.map((x) => x.v));
    const yilMin = Math.min(...yil.map((x) => x.v));
    if (son.v >= yilMax) {
      olayMetni.push(`${gunAy(son.tarih)} kapanışı son 52 haftanın en yükseği`);
      rozet = 'hareketli';
    } else if (son.v <= yilMin) {
      olayMetni.push(`${gunAy(son.tarih)} kapanışı son 52 haftanın en düşüğü`);
      rozet = 'hareketli';
    } else {
      o.push({ anahtar: 'yillik_zirveye_uzaklik', ad: 'Son kapanışın 52 haftanın en yükseğine uzaklığı',
        deger: son.v / yilMax - 1, gosterim: yuzde(son.v / yilMax - 1, true), kaynak, tarih: son.tarih });
    }
  }

  return {
    ticker: g.ticker, kod: g.kod, varlik: g.varlik, kategori: null, tur: g.tur,
    baslangic: ilk.tarih, bitis: son.tarih, rozet, olcumler: o, olaylar: olayMetni, para: g.para,
  };
}

/// Kripto rozet eşikleri: hacim ağırlıklı alıcı payı. %50 ± 5 puan "olağan"
/// bandı; Binance'te büyük coinlerde günlük pay çoğunlukla %48–52 arasında.
export const ALICI_ISTEKLI = 0.55;
export const SATICI_ISTEKLI = 0.45;

// ── İstek ───────────────────────────────────────────────────────────────────

export const NOT_SEMASI = {
  type: 'object',
  additionalProperties: false,
  required: ['baslik', 'maddeler'],
  properties: {
    baslik: { type: 'string', description: 'Tek cümle, en çok 140 karakter.' },
    maddeler: {
      type: 'array',
      description: 'En az 1, en çok 4 madde.',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['metin', 'kanit'],
        properties: {
          metin: { type: 'string', description: 'Tek cümle, en çok 220 karakter.' },
          kanit: {
            type: 'array',
            description: 'Bu maddenin dayandığı ölçümlerin anahtarları.',
            items: { type: 'string' },
          },
        },
      },
    },
  },
} as const;

/// Sabit sistem talimatı. Sabit kalmalı: Batch istekleri arasında önbelleğe
/// alınır (değişirse her istek tam fiyat öder).
export const SISTEM_TALIMATI = `Sen sandık adlı bir portföy takip uygulamasında varlık notları yazan bir editörsün. Okurun finans bilgisi az ya da çok olabilir; her ikisi de notu yanlış anlamamalı.

Görev: Sana bir varlığın bir dönemine ait ÖLÇÜMLER verilecek. Bu ölçümlere dayanarak o dönemde varlığa ne olduğunu betimleyen kısa bir not yaz.

Kesin kurallar:
1. Yalnız verilen ölçümleri kullan. Metne yazdığın her sayı, bir ölçümün "gosterim" alanında AYNEN geçmeli. Hesap yapma, yuvarlama, sayı türetme, toplama ya da karşılaştırma oranı uydurma.
2. Geleceğe dair hiçbir şey söyleme: tahmin, beklenti, hedef, yön yorumu yok.
3. Eylem önerme. "al", "sat", "ekle", "çık", "fırsat", "kaçırma", "tavsiye", "öneri", "kesin", "garanti", "mutlaka" gibi kelimeler kullanma.
4. "Balina" deme. Verilerden kimin alıp sattığı bilinmez; özne her zaman varlığın kendisi ya da piyasadır ("fona para girdi", "hissede işlem hacmi arttı").
5. Fon için "net akış" fona giren paradan çıkanın düşülmesidir; fiyat değişimi dahil değildir. Hisse ve kriptoda hacim, el değiştiren tutardır; para girişi değildir. Bunları karıştırma.
6. Kripto alıcı payı, piyasa emriyle alan tarafın hacimdeki payıdır; %50'nin üstü alıcıların daha istekli olduğunu gösterir, para girişi değildir.
7. Sade Türkçe, "sen" hitabı yok, ünlem yok, emoji yok. "Yatırım tavsiyesi değildir" yazma; uygulama kendisi ekler. Okur finans terimi bilmeyebilir: "volatilite", "standart sapma", "sigma", "momentum", "likidite", "spread" gibi terimleri kullanma. "Oynaklık" dersen aynı notta "dalgalanma" sözcüğüyle açıkla (ör. "oynaklık, yani fiyatın gün içi dalgalanması"). Ölçüm anahtarlarını (fiyat_degisim gibi) metne yazma.
8. Dönem sakinse kısa yaz: başlık + 1 madde yeter.
9. "Olağan", "hareketli", "olağandışı" sözcüklerini uygulamadaki rozetlerle aynı ölçekte kullan. Fonda akis_kati 1,5 katın altı olağan, 1,5 ile 3 kat arası hareketli, 3 kat ve üstü çok hareketli. Hisse ve kriptoda hacim_kati 1,3 katın altı olağan, 1,3 ile 2 kat arası hareketli, 2 kat ve üstü çok hareketli. Kriptoda alıcı payı %52 ile %55 arası hafif, %55 ve üstü belirgin alıcı ağırlığıdır (%48 ile %45 arası ve %45 altı satıcı için aynı). Fiyat ölçümlü varlıkta (altın, döviz, emtia, yurt dışı hisse, eurobond ya da yalnız fiyatı olan fon, hisse, kripto) hareket_kati 1 katın altı olağan, 1 ile 2 kat arası belirgin, 2 kat ve üstü olağandışı büyüklükte bir değişimdir; oynaklik_kati 2 kat ve üstü oynaklığın belirgin arttığını gösterir. Kat ölçüsü yoksa bu sözcükleri kullanma. Bu eşik sayılarını metne yazma.
10. Fiyat ölçümleri yalnız fiyat hareketini anlatır; para girişi ya da hacim değildir. Fiyat düzeyi (TL ya da dolar tutarı) yazma; ölçümlerde yoktur. "tl_degisim" kur etkisi dahil TL bazında değişimdir; "fiyat_degisim" varlığın kendi para birimindedir, ikisini karıştırma. Dönemdeki "52 haftanın en yükseği/en düşüğü" olayı varsa başlığa taşı.

Madde sırası: 1. madde "ne oldu" (dönemde fiyat ya da büyüklük nasıl değişti), 2. madde "neye eşlik etti" (para akışı, hacim ya da dönemdeki olay; ölçümü yoksa yazma), varsa son madde "dikkat çeken" (oynaklık artışı, 52 haftalık uç gibi tek gözlem). Ölçümü olmayan maddeyi uydurma; sakin dönemde tek madde yeter.

Çıktı: "baslik" tek cümle (en çok 140 karakter), dönemin en önemli gözlemi. "maddeler" en az 1, en çok 4; her madde tek cümle (en çok 220 karakter) ve "kanit" alanında dayandığı ölçümlerin "anahtar" değerleri.`;

export const VARLIK_ADI: Record<VarlikTuru, string> = {
  fon: 'yatırım fonu',
  hisse: 'Borsa İstanbul hissesi',
  kripto: 'kripto para',
  yabanci_hisse: 'yurt dışı borsada işlem gören hisse',
  altin: 'altın, gram fiyatı TL',
  doviz: 'döviz kuru, TL karşılığı',
  emtia: 'emtia',
  eurobond: 'eurobond, temiz fiyat',
};

/// Bir paketin kullanıcı mesajı. Ölçümler JSON olarak gider (anahtar sırası
/// sabit: önbellek değil ama tekrarlanabilirlik için).
export function kullaniciMesaji(p: Paket): string {
  const varlikAdi = p.varlik === 'fon'
    ? `${p.kod} (yatırım fonu${p.kategori ? `, kategori: ${p.kategori}` : ''})`
    : p.varlik === 'hisse'
    ? `${p.kod} (Borsa İstanbul hissesi)`
    : p.varlik === 'kripto'
    ? `${p.kod} (kripto para${p.para ? '' : ', Binance USDT paritesi'})`
    : `${p.kod} (${VARLIK_ADI[p.varlik]})`;
  const donem = p.tur === 'haftalik' ? 'hafta' : 'ay';
  return [
    `Varlık: ${varlikAdi}`,
    ...(p.para ? [`Ölçü: fiyat serisi (${p.para} kote); akış ve hacim verisi yok`] : []),
    `Dönem (${donem}): ${gunAy(p.baslangic)} – ${gunAy(p.bitis)}`,
    `Dönemdeki olaylar: ${p.olaylar.length > 0 ? p.olaylar.join('; ') : 'yok'}`,
    'Ölçümler:',
    JSON.stringify(p.olcumler.map(({ anahtar, ad, gosterim, kaynak, tarih }) =>
      ({ anahtar, ad, gosterim, kaynak, tarih })), null, 1),
  ].join('\n');
}

/// Batch isteğinin `params` gövdesi. Model ve efor çağırandan: haftalık not
/// ve aylık rapor Sonnet 5.5 düşük efor (2026-10-12'ye kadar aylık Opus'tu); tavan
/// aşılınca Haiku 4.5 (efor parametresi yok).
export function istekGovdesi(p: Paket, model: string): Record<string, unknown> {
  const outputConfig: Record<string, unknown> = {
    format: { type: 'json_schema', schema: NOT_SEMASI },
  };
  if (!model.startsWith('claude-haiku')) outputConfig.effort = 'low';
  return {
    model,
    max_tokens: 4000,
    system: [{ type: 'text', text: SISTEM_TALIMATI, cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: kullaniciMesaji(p) }],
    output_config: outputConfig,
  };
}

/// Batch `custom_id`: 64 karaktere kadar [a-zA-Z0-9_-]. Ticker ':' ve '.'
/// taşır; geri çevrilebilir bir kodlama.
export function ozelKimlik(ticker: string): string {
  return ticker.replace(/:/g, '__').replace(/\./g, '_d_');
}
export function tickerdan(ozel: string): string {
  return ozel.replace(/_d_/g, '.').replace(/__/g, ':');
}

// ── Kapılar ─────────────────────────────────────────────────────────────────

export type NotMaddesi = { metin: string; kanit: string[] };
export type Not = { baslik: string; maddeler: NotMaddesi[] };

/// Metindeki sayı parçaları: '412,00', '3,1', '48.210', '30', '2026'.
export function sayilar(metin: string): string[] {
  return metin.match(/\d+(?:[.,]\d+)*/g) ?? [];
}

/// Yasak ifadeler (Türkçe ekleriyle). Kelime sınırı: 'satış' (betimleyici)
/// serbest, 'satın'/'satmalı' (eylem) yasak.
export const YASAK: RegExp[] = [
  /(^|[^\p{L}])(al|sat)(ın|ınız|malı|malısın|manız|mak için|abilirsiniz|ın\.)([^\p{L}]|$)/iu,
  /satın al/iu,
  /hedef fiyat/iu,
  /(^|[^\p{L}])kesin(likle)?([^\p{L}]|$)/iu,
  /garanti/iu,
  /kaçırma/iu,
  /fırsat/iu,
  /tavsiye/iu,
  /öneri(r|riz|yoruz|lir)?([^\p{L}]|$)/iu,
  /mutlaka/iu,
  /yükselecek|düşecek|artacak|azalacak|beklen(iyor|ir|ti)/iu,
  /balina/iu,
  /portföyüne ekle|pozisyon aç/iu,
];

/// Teknik terim kapısı (2026-11-07, yasin: "not sayfası anlaşılır
/// olmalı"). Bu terimler hiç yazılmaz; "oynaklık" yalnız aynı notta
/// "dalgalan…" ile açıklanırsa geçer. Ölçüm anahtarı (snake_case) metne
/// sızarsa da red: okur `fiyat_degisim` görmemeli.
export const TEKNIK: RegExp[] = [
  /volatilite/iu,
  /standart sapma/iu,
  /sigma|σ/iu,
  /momentum/iu,
  /likidite/iu,
  /spread/iu,
  /z[- ]?skor/iu,
  /[a-z]+_[a-z_]+/u,
];

export type KapiSonucu = { gecti: true } | { gecti: false; neden: string };

/// Yapı + sayı + dil kapısı. Sırayla; ilk başarısızlık nedeni döner.
export function kapidanGecir(n: unknown, p: Paket): KapiSonucu {
  const not = n as Not;
  if (!not || typeof not.baslik !== 'string' || !Array.isArray(not.maddeler)) {
    return { gecti: false, neden: 'yapi: baslik/maddeler yok' };
  }
  const baslik = not.baslik.trim();
  if (baslik.length < 10 || baslik.length > 200) return { gecti: false, neden: 'yapi: baslik uzunlugu' };
  if (not.maddeler.length < 1 || not.maddeler.length > 4) {
    return { gecti: false, neden: 'yapi: madde sayisi' };
  }
  const anahtarlar = new Set(p.olcumler.map((o) => o.anahtar));
  for (const m of not.maddeler) {
    if (typeof m?.metin !== 'string' || m.metin.trim().length < 5 || m.metin.length > 300) {
      return { gecti: false, neden: 'yapi: madde metni' };
    }
    if (!Array.isArray(m.kanit) || m.kanit.some((k) => !anahtarlar.has(k))) {
      return { gecti: false, neden: 'kanit: bilinmeyen olcum anahtari' };
    }
  }

  // Sayı kapısı: izinli sayılar = gösterimlerdeki ve dönem/olay tarihlerindeki
  // sayı parçaları. Model '412' yazıp gösterim '412,00M' ise '412' parçası
  // izinli DEĞİL: aynen kullan kuralı.
  const izinli = new Set<string>();
  // Ölçüm adları da bizim metnimiz ('Önceki 20 günün ortalaması').
  for (const o of p.olcumler) {
    sayilar(o.gosterim).forEach((s) => izinli.add(s));
    sayilar(o.ad).forEach((s) => izinli.add(s));
  }
  for (const t of [p.baslangic, p.bitis, ...p.olcumler.map((o) => o.tarih)]) {
    sayilar(gunAy(t)).forEach((s) => izinli.add(s));
  }
  p.olaylar.forEach((x) => sayilar(x).forEach((s) => izinli.add(s)));
  sayilar(p.kategori ?? '').forEach((s) => izinli.add(s));
  sayilar(p.kod).forEach((s) => izinli.add(s));
  const metinler = [baslik, ...not.maddeler.map((m) => m.metin)];
  for (const metin of metinler) {
    for (const s of sayilar(metin)) {
      if (!izinli.has(s)) return { gecti: false, neden: `sayi: ${s} girdide yok` };
    }
    for (const r of YASAK) {
      if (r.test(metin)) return { gecti: false, neden: `dil: ${r.source.slice(0, 40)}` };
    }
    for (const r of TEKNIK) {
      if (r.test(metin)) return { gecti: false, neden: `terim: ${r.source.slice(0, 40)}` };
    }
  }
  const tumu = metinler.join(' ');
  if (/oynaklı/iu.test(tumu) && !/dalgalan/iu.test(tumu)) {
    return { gecti: false, neden: 'terim: oynaklik aciklanmadi' };
  }
  return { gecti: true };
}

// ── Sonuç → satır ──────────────────────────────────────────────────────────

/// Bir batch sonucundan `varlik_analizi` satırı. SAF: test edilebilir.
export function sonucSatiri(
  b: { id: string; tur: string; donem: string; model: string },
  paket: Paket,
  sonuc: {
    type: string;
    message?: {
      stop_reason?: string | null;
      content?: Array<{ type: string; text?: string }>;
      usage?: Record<string, number | null | undefined>;
      model?: string;
    };
  },
): Record<string, unknown> {
  const temel: Record<string, unknown> = {
    ticker: paket.ticker,
    tur: b.tur,
    donem: b.donem,
    rozet: paket.rozet,
    girdi: {
      kod: paket.kod, varlik: paket.varlik, kategori: paket.kategori,
      baslangic: paket.baslangic, bitis: paket.bitis,
      olcumler: paket.olcumler, olaylar: paket.olaylar,
    },
    model: b.model,
    batch_id: b.id,
    olusturuldu: new Date().toISOString(),
    baslik: null,
    maddeler: [],
    girdi_token: null,
    cikti_token: null,
    maliyet_usd: null,
    red_nedeni: null,
  };
  if (sonuc.type !== 'succeeded' || !sonuc.message) {
    return { ...temel, durum: 'hata', red_nedeni: `batch: ${sonuc.type}`.slice(0, 500) };
  }
  const m = sonuc.message;
  const u = m.usage ?? {};
  const kullanim = {
    input_tokens: Number(u.input_tokens ?? 0),
    output_tokens: Number(u.output_tokens ?? 0),
    cache_read_input_tokens: Number(u.cache_read_input_tokens ?? 0),
    cache_creation_input_tokens: Number(u.cache_creation_input_tokens ?? 0),
  };
  const sayac = {
    girdi_token: kullanim.input_tokens + kullanim.cache_read_input_tokens + kullanim.cache_creation_input_tokens,
    cikti_token: kullanim.output_tokens,
    maliyet_usd: maliyetUsd(b.model, kullanim),
  };
  if (m.stop_reason !== 'end_turn') {
    return { ...temel, ...sayac, durum: 'reddedildi', red_nedeni: `stop_reason: ${m.stop_reason}` };
  }
  const metin = (m.content ?? []).filter((c) => c.type === 'text').map((c) => c.text ?? '').join('');
  let not: Not | null = null;
  try { not = JSON.parse(metin) as Not; } catch (_) { /* aşağıda red */ }
  if (not === null) return { ...temel, ...sayac, durum: 'reddedildi', red_nedeni: 'yapi: json degil' };

  const kapi = kapidanGecir(not, paket);
  const baslik = typeof not.baslik === 'string' ? not.baslik.trim().slice(0, 300) : null;
  const maddeler = Array.isArray(not.maddeler)
    ? not.maddeler.map((x) => ({ metin: String(x?.metin ?? '').trim(), kanit: Array.isArray(x?.kanit) ? x.kanit : [] }))
    : [];
  if (!kapi.gecti) {
    return { ...temel, ...sayac, baslik, maddeler, durum: 'reddedildi', red_nedeni: kapi.neden.slice(0, 500) };
  }
  return { ...temel, ...sayac, baslik, maddeler, durum: 'yayinda' };
}

// ── Maliyet (N-08, N-04) ────────────────────────────────────────────────────

/// $/MTok liste fiyatı (girdi, çıktı, önbellek okuma, önbellek yazma 5 dk).
/// Batch %50 indirim ayrıca uygulanır.
const FIYAT: Record<string, [number, number, number, number]> = {
  'claude-sonnet-5-5': [2, 10, 0.2, 2.5],
  'claude-opus-5-5': [4, 20, 0.2, 5],
  'claude-haiku-4-5': [1, 5, 0.1, 1.25],
  // Haiku 5.5 (100K token altı istem). Önbellek oranları liste fiyatının
  // standart katları (okuma %10, yazma %125) varsayımı; portföy yorumu (0145).
  'claude-haiku-5-5': [0.1, 0.5, 0.01, 0.125],
};

export type Kullanim = {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
  /// Sunucu taraflı araç sayacı (aylık nottaki haber araması, 0177).
  server_tool_use?: { web_search_requests?: number | null } | null;
};

/// Web araması liste fiyatı: 1.000 arama 10 $ (2026-11-07). Batch indirimi
/// aramaya UYGULANMAZ ("Batch'te aynı fiyat"); yalnız token yarı fiyat.
export const ARAMA_USD = 0.01;

export function maliyetUsd(model: string, u: Kullanim, batch = true): number | null {
  const f = FIYAT[model];
  if (!f) return null;
  const t = (u.input_tokens ?? 0) * f[0] + (u.output_tokens ?? 0) * f[1] +
    (u.cache_read_input_tokens ?? 0) * f[2] + (u.cache_creation_input_tokens ?? 0) * f[3];
  const arama = Number(u.server_tool_use?.web_search_requests ?? 0) * ARAMA_USD;
  return Math.round(((t / 1e6) * (batch ? 0.5 : 1) + arama) * 1e5) / 1e5;
}

/// Maliyet tavanı (N-04): ay içi harcama tavanı aştıysa model bir kademe iner.
/// Tavan tanımsızsa (0) kısıtlama yok.
export function tavanaGoreModel(istenen: string, ayHarcama: number, tavan: number): string {
  if (!(tavan > 0) || ayHarcama < tavan) return istenen;
  return 'claude-haiku-4-5';
}
