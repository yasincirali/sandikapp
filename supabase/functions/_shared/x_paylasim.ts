// X (Twitter) paylaşımı — saf parçalar (0146, 2026-10-13).
//
// ## Neden
// yasin (13 Eki): "finansal yorumlar yapan bir twitter botu … sandık
// markasıyla açılıp, o günün en öne çıkan haberleri paylaşılabilir,
// istatistiki veri verilir, yorumlamaktan çok ancak insansı cümlelerle."
// Fizibilite ve önizleme: proje klasörü `twitter-bot/`,
// https://claude.ai/artifact/GPwtuCmf67XGZnAA97G63J.
//
// ## Ne söylenir, ne söylenmez (SPKn 107 / 109/2)
// Bot OLANI anlatır: ne oldu, ne kadar, kaynağı ne. Tahmin, yönlendirme,
// al/sat/tut, hedef, sinyal YOK. Tek fon/hisse öne çıkarılmaz — ilk sürüm
// yalnız KATEGORİ ve makro düzeyinde konuşur. Bu yüzden kart ve metin
// aynı sayılardan, ŞABLONDAN kurulur; model yalnız cümleyi insansılaştırır
// ve kapıdan geçemezse şablon metin kullanılır (uydurma sayı yasağı).
//
// ## Veri hakkı
// TEFAS (fon akışı) ve TÜİK (TÜFE) kamuya açık; serbestçe kullanılır.
// Altın/döviz kotasyonu truncgil'den gelir ve kamuya yeniden yayın hakkı
// belirsiz: haftalık karttaki kur satırları ancak `X_KUR_IZINLI=1` ile
// girer (varsayılan kapalı). BIST verisi (Yahoo) hiç kullanılmaz.
//
// ## Kullanıcı verisi
// Hiçbir kullanıcının portföyü, sayısı ya da davranışı kullanılmaz. Yeni bir
// kişisel veri amacı yok → yasal metin değişmez.

import { sayilar, YASAK } from './analiz.ts';

// ── Biçim ───────────────────────────────────────────────────────────────────

const AYLAR = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const AY_KISA = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

/// '2026-10-13' → '13 Ekim'.
export function gunAyYazisi(iso: string): string {
  const [, a, g] = iso.split('-').map(Number);
  return `${g} ${AYLAR[a - 1]}`;
}

/// '2026-09-01' → 'Eylül 2026'.
export function ayYilYazisi(iso: string): string {
  const [y, a] = iso.split('-').map(Number);
  return `${AYLAR[a - 1]} ${y}`;
}

function virgul(n: number, basamak: number): string {
  return n.toFixed(basamak).replace('.', ',');
}

/// Binlik ayraçlı Türkçe sayı: 4912.37 → '4.912,37'.
export function trSayi(n: number, basamak = 2): string {
  const [tam, ond] = Math.abs(n).toFixed(basamak).split('.');
  const binli = tam.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return (n < 0 ? '−' : '') + (ond ? `${binli},${ond}` : binli);
}

/// TL tutarını okunur büyüklüğe çevirir (işaretsiz): 3_240_000_000 →
/// '3,2 milyar TL', 520_000_000 → '520 milyon TL'.
export function tutarYazisi(tl: number): string {
  const m = Math.abs(tl);
  if (m >= 1e9) return `${virgul(m / 1e9, 1)} milyar TL`;
  if (m >= 1e6) return `${Math.round(m / 1e6)} milyon TL`;
  return `${trSayi(m, 0)} TL`;
}

/// Kart için kısa tutar: '+2,4 mr', '−520 mn'.
export function kisaTutar(tl: number): string {
  const isaret = tl < 0 ? '−' : '+';
  const m = Math.abs(tl);
  if (m >= 1e9) return `${isaret}${virgul(m / 1e9, 1)} mr`;
  return `${isaret}${Math.round(m / 1e6)} mn`;
}

/// Yüzde: 1.83 → '%1,8' (işaretsiz), isaretli: '+%1,8' / '−%0,3'.
/// Günlük fon getirisi gibi küçük değerler için `basamak` 2.
export function yuzde(p: number, isaretli = false, basamak = 1): string {
  const s = `%${virgul(Math.abs(p), basamak)}`;
  if (!isaretli) return s;
  return (p < 0 ? '−' : '+') + s;
}

// ── Fon akışı ───────────────────────────────────────────────────────────────

export type FonAkisSatiri = {
  fon_kodu: string;
  tarih: string;
  fon_tipi: 'YAT' | 'EMK';
  fon_turu: string | null;
  net_akis: number | null;
};

/// TEFAS tür adından okur dostu kategori. Sıra önemli: "Katılım Para
/// Piyasası" para piyasasıdır, "Hisse Senedi Serbest" serbesttir.
export function fonKategorisi(fonTuru: string | null): string {
  const t = (fonTuru ?? '').toLocaleLowerCase('tr-TR');
  if (t.includes('para piyasası')) return 'Para piyasası';
  if (t.includes('serbest')) return 'Serbest';
  if (t.includes('hisse')) return 'Hisse senedi';
  if (t.includes('kıymetli maden') || t.includes('altın')) return 'Altın ve kıymetli maden';
  if (t.includes('borçlanma') || t.includes('kira sertifika')) return 'Borçlanma araçları';
  if (t.includes('katılım')) return 'Katılım';
  if (t.includes('değişken') || t.includes('karma') || t.includes('fon sepeti')) return 'Değişken ve karma';
  return 'Diğer';
}

export type KategoriAkisi = { kategori: string; net: number };
export type AkisOzeti = {
  baslangic: string;
  bitis: string;
  toplam: number;
  fon_sayisi: number;
  kategoriler: KategoriAkisi[]; // net'e göre büyükten küçüğe
};

/// En az bu kadar fonun akışı bilinmiyorsa gün "eksik" sayılır, paylaşılmaz:
/// yarım günün toplamı yanlış bir hikâye anlatır.
export const ASGARI_FON = 300;

/// Yatırım fonlarının (BES hariç: emeklilik akışı maaş kesintisiyle mekanik
/// gelir, "para nereye gitti" sorusuna cevap değil) akışını kategoriye toplar.
export function akisOzeti(satirlar: FonAkisSatiri[], baslangic: string, bitis: string): AkisOzeti | null {
  const top = new Map<string, number>();
  const fonlar = new Set<string>();
  let toplam = 0;
  for (const s of satirlar) {
    if (s.fon_tipi !== 'YAT' || s.net_akis === null || !Number.isFinite(s.net_akis)) continue;
    if (s.tarih < baslangic || s.tarih > bitis) continue;
    const k = fonKategorisi(s.fon_turu);
    top.set(k, (top.get(k) ?? 0) + s.net_akis);
    toplam += s.net_akis;
    fonlar.add(s.fon_kodu);
  }
  if (fonlar.size < ASGARI_FON) return null;
  const kategoriler = [...top.entries()]
    .map(([kategori, net]) => ({ kategori, net }))
    .sort((a, b) => b.net - a.net);
  return { baslangic, bitis, toplam, fon_sayisi: fonlar.size, kategoriler };
}

// ── TÜFE ────────────────────────────────────────────────────────────────────

export type EndeksSatiri = { period: string; tufe_index: number };
export type TufeOzeti = {
  donem: string; // ayın ilk günü
  aylik: number; // %
  yillik: number; // %
  son_aylar: { donem: string; aylik: number }[]; // en eski → en yeni, ≤ 6
};

/// Endeks serisinden son ayın aylık ve yıllık değişimi. 13 ardışık ay yoksa
/// null (yıllık hesaplanamaz; tahmin edilmez).
export function tufeOzeti(satirlar: EndeksSatiri[]): TufeOzeti | null {
  const s = [...satirlar].sort((a, b) => a.period.localeCompare(b.period));
  if (s.length < 13) return null;
  const ayNo = (p: string) => {
    const [y, a] = p.split('-').map(Number);
    return y * 12 + a;
  };
  const son = s[s.length - 1];
  const onceki = s[s.length - 2];
  const yilOnce = s.find((r) => ayNo(r.period) === ayNo(son.period) - 12);
  if (!yilOnce || ayNo(onceki.period) !== ayNo(son.period) - 1) return null;
  const son_aylar: { donem: string; aylik: number }[] = [];
  for (let i = Math.max(1, s.length - 6); i < s.length; i++) {
    if (ayNo(s[i - 1].period) !== ayNo(s[i].period) - 1) continue;
    son_aylar.push({ donem: s[i].period, aylik: (s[i].tufe_index / s[i - 1].tufe_index - 1) * 100 });
  }
  return {
    donem: son.period,
    aylik: (son.tufe_index / onceki.tufe_index - 1) * 100,
    yillik: (son.tufe_index / yilOnce.tufe_index - 1) * 100,
    son_aylar,
  };
}

// ── Kur (yalnız X_KUR_IZINLI=1) ─────────────────────────────────────────────

/// Haftalık kartın kur satırları. ALTIN_GRAM uygulamada 22 ayardır
/// (live_prices.ts); kamuoyunun "gram altın"ı 24 ayar → ALTIN_GRAM24.
export const KUR_SEMBOLLERI: { sembol: string; ad: string; basamak: number; birim: string }[] = [
  { sembol: 'ALTIN_GRAM24', ad: 'Gram altın', basamak: 0, birim: ' ₺' },
  { sembol: 'USDTRY=X', ad: 'Dolar/TL', basamak: 2, birim: '' },
  { sembol: 'EURTRY=X', ad: 'Euro/TL', basamak: 2, birim: '' },
];

export type KurDegisimi = { ad: string; son: string; degisim: number };

export type KotasyonSatiri = { sembol: string; ts: string; fiyat: number };

/// Her sembolün `bitisTs` anındaki ve `baslangicTs` anındaki son fiyatı;
/// ikisi de yoksa sembol atlanır (uydurma yok).
export function kurDegisimleri(satirlar: KotasyonSatiri[], baslangicTs: string, bitisTs: string): KurDegisimi[] {
  const out: KurDegisimi[] = [];
  for (const k of KUR_SEMBOLLERI) {
    const s = satirlar.filter((r) => r.sembol === k.sembol).sort((a, b) => a.ts.localeCompare(b.ts));
    const ilk = [...s].reverse().find((r) => r.ts <= baslangicTs);
    const son = [...s].reverse().find((r) => r.ts <= bitisTs);
    if (!ilk || !son || son.ts <= ilk.ts) continue;
    out.push({
      ad: k.ad,
      son: trSayi(son.fiyat, k.basamak) + k.birim,
      degisim: (son.fiyat / ilk.fiyat - 1) * 100,
    });
  }
  return out;
}


// ── ABD istihdam (yasin, 19 Eki: "işsizlik bilgileri de paylaşılmalı") ────────

/// BLS seri kimlikleri: işsizlik oranı (LNS14000000) ve tarım dışı istihdam
/// (CES0000000001, bin kişi), ikisi de mevsimsellikten arındırılmış — BLS'nin
/// "Employment Situation" bülteninin manşetleri.
export const BLS_ISTIHDAM = ['LNS14000000', 'CES0000000001'];

export type IstihdamOzeti = {
  donem: string;
  issizlik: number;
  onceki_issizlik: number;
  /// Tarım dışı istihdamdaki aylık değişim, bin kişi.
  istihdam_degisim: number;
  son_aylar: { donem: string; issizlik: number }[];
};

export function abdIstihdamOzeti(json: unknown): IstihdamOzeti | null {
  const u = blsSerisi(json, 'LNS14000000');
  const p = blsSerisi(json, 'CES0000000001');
  if (u.length < 2 || p.length < 2) return null;
  const son = u[u.length - 1];
  const uo = u.find((x) => x.ay === son.ay - 1);
  const ps = p.find((x) => x.ay === son.ay);
  const po = p.find((x) => x.ay === son.ay - 1);
  if (!uo || !ps || !po) return null;
  return {
    donem: blsDonem(son.ay),
    issizlik: son.deger,
    onceki_issizlik: uo.deger,
    istihdam_degisim: ps.deger - po.deger,
    son_aylar: u.slice(-6).map((x) => ({ donem: blsDonem(x.ay), issizlik: x.deger })),
  };
}

export function abdIstihdamTaslagi(t: IstihdamOzeti): Taslak {
  const ay = ayYilYazisi(t.donem);
  const ayAdi = ay.split(' ')[0].toLocaleLowerCase('tr-TR');
  const artti = t.istihdam_degisim >= 0;
  const bin = `${trSayi(Math.abs(t.istihdam_degisim), 0)} bin`;
  return {
    tur: 'abd_istihdam',
    donem: t.donem,
    olgular: [
      { ad: 'ay', gosterim: ay },
      { ad: `ABD tarım dışı istihdam aylık değişimi (${artti ? 'artış' : 'azalış'}, kişi)`, gosterim: bin },
      { ad: 'ABD işsizlik oranı', gosterim: yuzde(t.issizlik) },
      { ad: 'bir önceki ay ABD işsizlik oranı', gosterim: yuzde(t.onceki_issizlik) },
    ],
    sablon_metin: `ABD'de ${ayAdi} ayında tarım dışı istihdam ${bin} kişi ${artti ? 'arttı' : 'azaldı'}. İşsizlik oranı ${yuzde(t.issizlik)} oldu, bir önceki ay ${yuzde(t.onceki_issizlik)} idi.`,
    kart: {
      bicim: 'buyuk',
      ust: `ABD İSTİHDAM · ${ay.toLocaleUpperCase('tr-TR')}`,
      buyuk: `${artti ? '+' : '−'}${bin}`,
      alt: 'tarım dışı istihdam, aylık değişim',
      sutunlar: t.son_aylar.map((m) => ({ etiket: AY_KISA[Number(m.donem.split('-')[1]) - 1], deger: m.issizlik })),
      yan_baslik: 'İşsizlik oranı',
      yan_deger: yuzde(t.issizlik),
      kaynak: 'Kaynak: ABD Çalışma İstatistikleri Bürosu (BLS)',
    },
  };
}

// ── Brent petrol (EIA; yalnız EIA_API_KEY varken) ───────────────────────────

/// EIA (ABD Enerji Bakanlığı) günlük Brent spot fiyatı, $/varil. Kamu verisi
/// (ABD federal eseri), yeniden yayımı serbest. EIA seriyi gecikmeli günceller:
/// son nokta birkaç gün eski olabilir, bu yüzden satır kendi tarihini taşır.
export type BrentSatiri = { period?: string; value?: unknown };

/// Son noktanın bir hafta öncesine göre değişimi. Son nokta `bugun`den 10
/// günden eskiyse ya da hafta öncesinde nokta yoksa null (bayat veri yazılmaz).
export function brentDegisimi(json: unknown, bugun: string): KurDegisimi | null {
  const ham = (json as { response?: { data?: BrentSatiri[] } })?.response?.data ?? [];
  const n = ham
    .map((d) => ({ gun: String(d.period ?? ''), deger: Number(d.value) }))
    .filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d.gun) && Number.isFinite(d.deger) && d.deger > 0)
    .sort((a, b) => a.gun.localeCompare(b.gun));
  const son = n[n.length - 1];
  if (!son || son.gun < gunEkle(bugun, -10)) return null;
  const ilk = [...n].reverse().find((d) => d.gun <= gunEkle(son.gun, -7));
  if (!ilk) return null;
  return {
    ad: `Brent petrol (${gunAyYazisi(son.gun)})`,
    son: `${trSayi(son.deger, 2)} $`,
    degisim: (son.deger / ilk.deger - 1) * 100,
  };
}

// ── Gönderi ─────────────────────────────────────────────────────────────────

export type GonderiTuru = 'fon_akisi' | 'haftalik' | 'tufe' | 'abd_tufe' | 'fed' | 'fon_getiri' | 'takvim' | 'abd_istihdam';

export type KartSatiri = {
  ad: string;
  deger: string;
  yon: 'u' | 'd' | 'n';
  /// Çubuk uzunluğu, en büyük mutlak değere göre 0…1. Yoksa çubuk çizilmez.
  oran?: number;
  /// Tablo kipinde ikinci sütun (ör. fiyat).
  ek?: string;
};

export type Kart =
  | { bicim: 'liste'; ust: string; baslik: string; vurgu?: string; vurgu_yon?: 'u' | 'd' | 'n'; son?: string; satirlar: KartSatiri[]; kaynak: string }
  | {
    bicim: 'buyuk';
    ust: string;
    buyuk: string;
    alt: string;
    sutunlar: { etiket: string; deger: number }[];
    yan_baslik: string;
    yan_deger: string;
    kaynak: string;
  };

/// Modele ve kapıya giden olgu: ad + metinde aynen geçecek gösterim.
export type Olgu = { ad: string; gosterim: string };

export type Taslak = {
  tur: GonderiTuru;
  donem: string;
  olgular: Olgu[];
  sablon_metin: string;
  kart: Kart;
  /// Model çağrılmaz, şablon metin gider. Takvim gelecekteki olayları sayar;
  /// modelin "gelecek dili yok" kuralıyla çelişir ve anlatacak cümle yoktur.
  yalniz_sablon?: boolean;
  /// Varsayılan yerine bu etiketler (bkz. `etiketle`).
  etiketler?: string[];
};

const UST_SATIR = 5;

/// Günlük fon akışı gönderisi.
export function fonAkisiTaslagi(o: AkisOzeti): Taslak {
  const girdi = o.toplam >= 0;
  const enBuyuk = Math.max(...o.kategoriler.map((k) => Math.abs(k.net)), 1);
  // Kartta en çok 5 satır: en büyük girişler ve en büyük çıkışlar mutlak
  // büyüklüğe göre seçilir, sonra net'e göre sıralanır.
  const secili = [...o.kategoriler]
    .filter((k) => Math.abs(k.net) >= 1e6)
    .sort((a, b) => Math.abs(b.net) - Math.abs(a.net))
    .slice(0, UST_SATIR)
    .sort((a, b) => b.net - a.net);
  const ilk = o.kategoriler[0];
  const son = o.kategoriler[o.kategoriler.length - 1];
  const olgular: Olgu[] = [
    { ad: 'tarih', gosterim: gunAyYazisi(o.bitis) },
    { ad: girdi ? 'fonlara net giriş' : 'fonlardan net çıkış', gosterim: tutarYazisi(o.toplam) },
    ...secili.map((k) => ({ ad: `${k.kategori} fonları net ${k.net >= 0 ? 'giriş' : 'çıkış'}`, gosterim: tutarYazisi(k.net) })),
  ];
  const cumleler = [
    girdi
      ? `Fonlara bugün net ${tutarYazisi(o.toplam)} girdi.`
      : `Fonlardan bugün net ${tutarYazisi(o.toplam)} çıktı.`,
  ];
  if (ilk && ilk.net > 0) cumleler.push(`En çok giriş ${ilk.kategori.toLocaleLowerCase('tr-TR')} fonlarına oldu: ${tutarYazisi(ilk.net)}.`);
  if (son && son.net < 0 && son !== ilk) cumleler.push(`${son.kategori} fonlarından ${tutarYazisi(son.net)} çıktı.`);
  return {
    tur: 'fon_akisi',
    donem: o.bitis,
    olgular,
    sablon_metin: cumleler.join(' '),
    kart: {
      bicim: 'liste',
      ust: `FON PARA AKIŞI · ${gunAyYazisi(o.bitis).toLocaleUpperCase('tr-TR')}`,
      baslik: girdi ? 'Fonlara bugün net' : 'Fonlardan bugün net',
      vurgu: `${girdi ? '+' : '−'}${tutarYazisi(o.toplam)}`,
      vurgu_yon: girdi ? 'u' : 'd',
      son: girdi ? 'girdi' : 'çıktı',
      satirlar: secili.map((k) => ({
        ad: k.kategori,
        deger: kisaTutar(k.net),
        yon: k.net >= 0 ? 'u' : 'd',
        oran: Math.abs(k.net) / enBuyuk,
      })),
      kaynak: 'Kaynak: TEFAS · Yatırım fonları, BES hariç',
    },
  };
}

/// Cuma: haftanın özeti (fon akışı + izinliyse kur satırları).
export function haftalikTaslak(o: AkisOzeti, kurlar: KurDegisimi[]): Taslak {
  const girdi = o.toplam >= 0;
  const aralik = `${gunAyYazisi(o.baslangic).split(' ')[0]}–${gunAyYazisi(o.bitis)}`;
  const ilk = o.kategoriler[0];
  const satirlar: KartSatiri[] = [
    ...kurlar.map((k) => ({
      ad: k.ad,
      ek: k.son,
      deger: yuzde(k.degisim, true),
      yon: (k.degisim > 0.05 ? 'u' : k.degisim < -0.05 ? 'd' : 'n') as KartSatiri['yon'],
    })),
    { ad: girdi ? 'Fonlara net giriş' : 'Fonlardan net çıkış', ek: tutarYazisi(o.toplam).replace(' TL', ' ₺'), deger: '5 gün', yon: 'n' },
  ];
  if (ilk && ilk.net > 0) {
    satirlar.push({ ad: `En çok giriş: ${ilk.kategori.toLocaleLowerCase('tr-TR')}`, ek: tutarYazisi(ilk.net).replace(' TL', ' ₺'), deger: '', yon: 'n' });
  }
  const olgular: Olgu[] = [
    { ad: 'hafta', gosterim: aralik },
    { ad: girdi ? 'haftalık fonlara net giriş' : 'haftalık fonlardan net çıkış', gosterim: tutarYazisi(o.toplam) },
    ...(ilk && ilk.net > 0 ? [{ ad: `en çok giriş alan kategori: ${ilk.kategori}`, gosterim: tutarYazisi(ilk.net) }] : []),
    ...kurlar.map((k) => ({ ad: `${k.ad} haftalık değişim (${k.degisim >= 0 ? 'artış' : 'düşüş'})`, gosterim: yuzde(k.degisim) })),
  ];
  const cumleler = ['Haftanın özeti:'];
  if (kurlar.length) {
    const yurtIci = kurlar.filter((k) => !k.ad.startsWith('Brent'));
    const brent = kurlar.find((k) => k.ad.startsWith('Brent'));
    if (yurtIci.length) cumleler.push(yurtIci.map((k) => `${k.ad} haftayı ${yuzde(k.degisim)} ${k.degisim >= 0 ? 'artışla' : 'düşüşle'} kapattı`).join(', ') + '.');
    // EIA gecikmeli günceller: Brent "haftayı kapattı" denmez, kendi tarihiyle yazılır.
    if (brent) cumleler.push(`${brent.ad.replace(/ \((.+)\)$/, ' $1 itibarıyla')} bir haftada ${yuzde(brent.degisim)} ${brent.degisim >= 0 ? 'yükseldi' : 'düştü'}.`);
  }
  cumleler.push(girdi ? `Fonlara beş günde net ${tutarYazisi(o.toplam)} girdi.` : `Fonlardan beş günde net ${tutarYazisi(o.toplam)} çıktı.`);
  return {
    tur: 'haftalik',
    donem: o.bitis,
    olgular,
    etiketler: [
      '#fon',
      ...(kurlar.some((k) => k.ad.includes('altın')) ? ['#altın'] : []),
      ...(kurlar.some((k) => k.ad.startsWith('Brent')) ? ['#petrol'] : []),
    ],
    sablon_metin: cumleler.join(' '),
    kart: {
      bicim: 'liste',
      ust: `HAFTANIN ÖZETİ · ${aralik.toLocaleUpperCase('tr-TR')}`,
      baslik: 'Haftanın özeti',
      satirlar,
      kaynak: kurlar.some((k) => k.ad.startsWith('Brent'))
        ? 'Kaynak: TEFAS, EIA, piyasa kotasyonları'
        : kurlar.length ? 'Kaynak: TEFAS, piyasa kotasyonları' : 'Kaynak: TEFAS · Yatırım fonları, BES hariç',
    },
  };
}

/// TÜİK açıklaması günü: aylık ve yıllık TÜFE.
export function tufeTaslagi(t: TufeOzeti): Taslak {
  const ay = ayYilYazisi(t.donem);
  const ayAdi = ay.split(' ')[0];
  return {
    tur: 'tufe',
    donem: t.donem,
    olgular: [
      { ad: 'ay', gosterim: ay },
      { ad: 'aylık TÜFE', gosterim: yuzde(t.aylik) },
      { ad: 'yıllık TÜFE', gosterim: yuzde(t.yillik) },
      ...t.son_aylar.slice(0, -1).map((m) => ({ ad: `${ayYilYazisi(m.donem)} aylık TÜFE`, gosterim: yuzde(m.aylik) })),
    ],
    sablon_metin: `${ayAdi} enflasyonu ${yuzde(t.aylik)} geldi; yıllık enflasyon ${yuzde(t.yillik)} oldu.`,
    kart: {
      bicim: 'buyuk',
      ust: `ENFLASYON · ${ay.toLocaleUpperCase('tr-TR')}`,
      buyuk: yuzde(t.aylik),
      alt: 'aylık TÜFE',
      sutunlar: t.son_aylar.map((m) => ({ etiket: AY_KISA[Number(m.donem.split('-')[1]) - 1], deger: m.aylik })),
      yan_baslik: 'Yıllık enflasyon',
      yan_deger: yuzde(t.yillik),
      kaynak: 'Kaynak: TÜİK',
    },
  };
}

// ── ABD (Türkçe anlatılır; yasin 13 Eki "olur ok") ─────────────────────────
//
// Kitle: ABD hissesi tutan Türk yatırımcı; uygulama ABD hisselerini zaten
// destekliyor. Yalnız ABD kamu verisi (ABD federal eseri, telifsiz):
// BLS TÜFE ve New York Fed'in açıkladığı politika faizi aralığı. S&P 500 /
// Nasdaq endeks verisi lisanslı olduğu için KULLANILMAZ.

type BlsVeri = { year?: string; period?: string; value?: string };

function blsSerisi(json: unknown, id: string): { ay: number; deger: number }[] {
  const seriler = (json as { Results?: { series?: { seriesID?: string; data?: BlsVeri[] }[] } })?.Results?.series ?? [];
  const s = seriler.find((x) => x.seriesID === id);
  const out: { ay: number; deger: number }[] = [];
  for (const d of s?.data ?? []) {
    const m = /^M(0[1-9]|1[0-2])$/.exec(d.period ?? '');
    const y = Number(d.year);
    const v = Number(d.value);
    if (!m || !Number.isInteger(y) || !Number.isFinite(v) || v <= 0) continue;
    out.push({ ay: y * 12 + Number(m[1]) - 1, deger: v });
  }
  return out.sort((a, b) => a.ay - b.ay);
}

function blsDonem(ay: number): string {
  return `${Math.floor(ay / 12)}-${String((ay % 12) + 1).padStart(2, '0')}-01`;
}

/// BLS v1 yanıtından manşet TÜFE: aylık değişim mevsimsellikten arındırılmış
/// seriden (CUSR0000SA0), yıllık değişim ham seriden (CUUR0000SA0) — BLS'nin
/// kendi bülteniyle aynı ayrım. İki uç da yoksa null.
export function abdTufeOzeti(json: unknown): TufeOzeti | null {
  const sa = blsSerisi(json, 'CUSR0000SA0');
  const ham = blsSerisi(json, 'CUUR0000SA0');
  if (sa.length < 2 || ham.length < 13) return null;
  const son = sa[sa.length - 1];
  const onceki = sa.find((x) => x.ay === son.ay - 1);
  const hamSon = ham.find((x) => x.ay === son.ay);
  const hamYil = ham.find((x) => x.ay === son.ay - 12);
  if (!onceki || !hamSon || !hamYil) return null;
  const donem = blsDonem;
  const son_aylar: { donem: string; aylik: number }[] = [];
  for (const x of sa.slice(-6)) {
    const o = sa.find((y) => y.ay === x.ay - 1);
    if (o) son_aylar.push({ donem: donem(x.ay), aylik: (x.deger / o.deger - 1) * 100 });
  }
  return {
    donem: donem(son.ay),
    aylik: (son.deger / onceki.deger - 1) * 100,
    yillik: (hamSon.deger / hamYil.deger - 1) * 100,
    son_aylar,
  };
}

/// ABD TÜFE ancak "geçen ay"ın verisiyse ve ayın ilk 20 gününde paylaşılır
/// (BLS ayın ~10–15'inde açıklar): ilk kurulumda eski ayın verisi atılmasın.
export function abdTufeGuncelMi(donem: string, bugun: string): boolean {
  const [y, a] = bugun.split('-').map(Number);
  const gecenAy = a === 1 ? `${y - 1}-12-01` : `${y}-${String(a - 1).padStart(2, '0')}-01`;
  return donem === gecenAy && Number(bugun.split('-')[2]) <= 20;
}

export function abdTufeTaslagi(t: TufeOzeti): Taslak {
  const ay = ayYilYazisi(t.donem);
  const ayAdi = ay.split(' ')[0].toLocaleLowerCase('tr-TR');
  const isaretli = (p: number) => (p < 0 ? '−' : '') + yuzde(p);
  return {
    tur: 'abd_tufe',
    donem: t.donem,
    olgular: [
      { ad: 'ay', gosterim: ay },
      { ad: 'ABD aylık TÜFE (mevsimsellikten arındırılmış)', gosterim: isaretli(t.aylik) },
      { ad: 'ABD yıllık TÜFE', gosterim: isaretli(t.yillik) },
    ],
    sablon_metin: `ABD'de ${ayAdi} ayı enflasyonu aylık ${isaretli(t.aylik)}, yıllık ${isaretli(t.yillik)} oldu.`,
    kart: {
      bicim: 'buyuk',
      ust: `ABD ENFLASYONU · ${ay.toLocaleUpperCase('tr-TR')}`,
      buyuk: isaretli(t.aylik),
      alt: 'aylık TÜFE (mevsimsellikten arındırılmış)',
      sutunlar: t.son_aylar.map((m) => ({ etiket: AY_KISA[Number(m.donem.split('-')[1]) - 1], deger: m.aylik })),
      yan_baslik: 'Yıllık enflasyon',
      yan_deger: isaretli(t.yillik),
      kaynak: 'Kaynak: ABD Çalışma İstatistikleri Bürosu (BLS)',
    },
  };
}

export type FedKarari = { tarih: string; eski: [number, number]; yeni: [number, number] };

/// New York Fed EFFR yanıtında (en yeni önce) hedef aralığın değiştiği gün.
/// Değişiklik yoksa null. `tarih` = yeni aralığın geçerli olduğu ilk gün.
export function fedKarariBul(json: unknown): FedKarari | null {
  const satir = ((json as { refRates?: unknown[] })?.refRates ?? []) as {
    effectiveDate?: string;
    targetRateFrom?: number;
    targetRateTo?: number;
  }[];
  const temiz = satir
    .filter((r) => /^\d{4}-\d{2}-\d{2}$/.test(r.effectiveDate ?? '') && Number.isFinite(r.targetRateFrom) && Number.isFinite(r.targetRateTo))
    .sort((a, b) => b.effectiveDate!.localeCompare(a.effectiveDate!));
  for (let i = 0; i + 1 < temiz.length; i++) {
    const y = temiz[i];
    const e = temiz[i + 1];
    if (y.targetRateFrom !== e.targetRateFrom || y.targetRateTo !== e.targetRateTo) {
      return { tarih: y.effectiveDate!, eski: [e.targetRateFrom!, e.targetRateTo!], yeni: [y.targetRateFrom!, y.targetRateTo!] };
    }
  }
  return null;
}

function aralik(a: [number, number]): string {
  return `%${virgul(a[0], 2)}–${virgul(a[1], 2)}`;
}

export function fedTaslagi(k: FedKarari): Taslak {
  const bp = Math.round((k.yeni[1] - k.eski[1]) * 100);
  const fiil = bp < 0 ? 'indirdi' : 'artırdı';
  const bpYazi = `${Math.abs(bp)} baz puan`;
  return {
    tur: 'fed',
    donem: k.tarih,
    olgular: [
      { ad: 'değişim', gosterim: bpYazi },
      { ad: 'yeni hedef aralık', gosterim: aralik(k.yeni) },
      { ad: 'önceki hedef aralık', gosterim: aralik(k.eski) },
    ],
    sablon_metin: `Fed politika faizini ${bpYazi} ${fiil}. Yeni hedef aralık ${aralik(k.yeni)}, önceki aralık ${aralik(k.eski)} idi.`,
    kart: {
      bicim: 'liste',
      ust: 'FED FAİZ KARARI',
      baslik: 'Fed faizi',
      vurgu: bpYazi,
      // Faiz yönü iyi/kötü değil: nötr altın (değer yargısı yok).
      vurgu_yon: 'n',
      son: fiil,
      satirlar: [
        { ad: 'Yeni hedef aralık', ek: aralik(k.yeni), deger: '', yon: 'n' },
        { ad: 'Önceki hedef aralık', ek: aralik(k.eski), deger: '', yon: 'n' },
      ],
      kaynak: `Kaynak: New York Fed · Yürürlük ${gunAyYazisi(k.tarih)}`,
    },
  };
}

// ── Sabah gönderisi (yasin, 15 Eki: "günde 2 gönderi", "İkisi dönüşümlü") ──
//
// Sabah TR 09:30: Pazartesi haftanın veri takvimi, diğer günler bir önceki iş
// gününün fon getirileri. Pazartesi takvimde olay yoksa getiri gönderisi
// atılır: sabah boş geçmez. Akşamki fon akışı gönderisi aynen kalır.

export type FonFiyatSatiri = {
  fon_kodu: string;
  tarih: string;
  fon_tipi: 'YAT' | 'EMK';
  fon_turu: string | null;
  pay_adedi: number;
  portfoy_degeri: number;
};

export type KategoriGetirisi = { kategori: string; medyan: number; fon_sayisi: number };
export type GetiriOzeti = {
  onceki: string;
  gun: string;
  fon_sayisi: number;
  kategoriler: KategoriGetirisi[]; // medyana göre büyükten küçüğe
};

/// Bir günde bundan büyük mutlak getiri veri hatası sayılır (pay bölünmesi,
/// TEFAS'ın eksik pay adedi): medyanı bozmasın diye dışarıda kalır.
export const AZAMI_GUNLUK_GETIRI = 20;
/// Medyanı anlamlı olsun: bu kadar fonu olmayan kategori gösterilmez.
export const ASGARI_KATEGORI_FON = 10;

function medyan(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const o = s.length >> 1;
  return s.length % 2 ? s[o] : (s[o - 1] + s[o]) / 2;
}

/// `bugun`den önceki son iki veri gününün fon fiyatlarından (değer / pay)
/// kategori başına MEDYAN günlük getiri. Ortalama değil: tek bir fonun
/// sıçraması kategorinin hikâyesini değiştirmesin. Tek fon adı geçmez
/// (SPKn: tek fon öne çıkarılmaz). BES hariç (akış gönderisiyle aynı).
export function getiriOzeti(satirlar: FonFiyatSatiri[], bugun: string): GetiriOzeti | null {
  const gunler = new Map<string, Map<string, FonFiyatSatiri>>();
  for (const s of satirlar) {
    if (s.fon_tipi !== 'YAT' || s.tarih >= bugun) continue;
    if (!(s.pay_adedi > 0) || !(s.portfoy_degeri > 0)) continue;
    if (!gunler.has(s.tarih)) gunler.set(s.tarih, new Map());
    gunler.get(s.tarih)!.set(s.fon_kodu, s);
  }
  // Yarım gün (akış turu bitmemiş) sayılmaz: en az ASGARI_FON fonu olan günler.
  const tam = [...gunler.entries()].filter(([, m]) => m.size >= ASGARI_FON).map(([g]) => g).sort();
  if (tam.length < 2) return null;
  const gun = tam[tam.length - 1];
  const onceki = tam[tam.length - 2];
  const bas = gunler.get(onceki)!;
  const kat = new Map<string, number[]>();
  let n = 0;
  for (const [kod, s] of gunler.get(gun)!) {
    const o = bas.get(kod);
    if (!o) continue;
    const r = ((s.portfoy_degeri / s.pay_adedi) / (o.portfoy_degeri / o.pay_adedi) - 1) * 100;
    if (!Number.isFinite(r) || Math.abs(r) > AZAMI_GUNLUK_GETIRI) continue;
    const k = fonKategorisi(s.fon_turu);
    if (!kat.has(k)) kat.set(k, []);
    kat.get(k)!.push(r);
    n++;
  }
  if (n < ASGARI_FON) return null;
  const kategoriler = [...kat.entries()]
    .filter(([k, rs]) => k !== 'Diğer' && rs.length >= ASGARI_KATEGORI_FON)
    .map(([kategori, rs]) => ({ kategori, medyan: medyan(rs), fon_sayisi: rs.length }))
    .sort((a, b) => b.medyan - a.medyan);
  if (kategoriler.length < 2) return null;
  return { onceki, gun, fon_sayisi: n, kategoriler };
}

/// Bir önceki iş gününün kategori getirileri.
export function fonGetiriTaslagi(o: GetiriOzeti, kurlar: KurDegisimi[] = []): Taslak {
  const enBuyuk = Math.max(...o.kategoriler.map((k) => Math.abs(k.medyan)), 0.01);
  const ilk = o.kategoriler[0];
  const son = o.kategoriler[o.kategoriler.length - 1];
  // Kur satırları varsa kart 6 satırı aşmasın: en yüksek iki ve en düşük kategori.
  const secili = kurlar.length
    ? [...new Set([...o.kategoriler.slice(0, 6 - kurlar.length - 1), son])]
    : o.kategoriler.slice(0, 6);
  const tarih = gunAyYazisi(o.gun);
  const olgular: Olgu[] = [
    { ad: 'tarih', gosterim: tarih },
    ...secili.map((k) => ({
      ad: `${k.kategori} fonlarının medyan günlük getirisi (${k.medyan >= 0 ? 'artış' : 'düşüş'})`,
      gosterim: yuzde(k.medyan, false, 2),
    })),
    ...kurlar.map((k) => ({ ad: `${k.ad} günlük değişim (${k.degisim >= 0 ? 'artış' : 'düşüş'})`, gosterim: yuzde(k.degisim, false, 2) })),
  ];
  if (!secili.includes(son)) {
    olgular.push({ ad: `${son.kategori} fonlarının medyan günlük getirisi (${son.medyan >= 0 ? 'artış' : 'düşüş'})`, gosterim: yuzde(son.medyan, false, 2) });
  }
  const ad = (k: KategoriGetirisi) => k.kategori.toLocaleLowerCase('tr-TR');
  const cumleler: string[] = [];
  if (kurlar.length) {
    cumleler.push(`${tarih}'de ` + kurlar.map((k) => `${k.ad.replace(/^Gram/, 'gram')} ${yuzde(k.degisim, false, 2)} ${k.degisim >= 0 ? 'arttı' : 'geriledi'}`).join(', ') + '.');
    cumleler.push(`Fonlarda en yüksek medyan getiri ${yuzde(ilk.medyan, false, 2)} ile ${ad(ilk)} fonlarında oldu.`);
  } else {
    cumleler.push(`${tarih}'de fon kategorileri içinde en yüksek medyan getiri ${yuzde(ilk.medyan, false, 2)} ile ${ad(ilk)} fonlarında oldu.`);
  }
  if (son !== ilk) {
    cumleler.push(son.medyan < 0
      ? `${son.kategori} fonları ${yuzde(son.medyan, false, 2)} geriledi.`
      : `En düşük getiri ${yuzde(son.medyan, false, 2)} ile ${ad(son)} fonlarında.`);
  }
  const yon = (p: number) => (p > 0.005 ? 'u' : p < -0.005 ? 'd' : 'n') as KartSatiri['yon'];
  return {
    tur: 'fon_getiri',
    donem: o.gun,
    olgular,
    sablon_metin: cumleler.join(' '),
    etiketler: kurlar.some((k) => k.ad.includes('altın')) ? ['#altın', '#fon', '#TEFAS'] : undefined,
    kart: {
      bicim: 'liste',
      ust: `${kurlar.length ? 'DÜNÜN PİYASASI' : 'FON GETİRİLERİ'} · ${tarih.toLocaleUpperCase('tr-TR')}`,
      baslik: kurlar.length ? 'Dünün piyasası' : 'Kategorilerin günlük getirisi',
      satirlar: [
        ...kurlar.map((k) => ({ ad: k.ad, deger: yuzde(k.degisim, true, 2), yon: yon(k.degisim) })),
        ...secili.map((k) => ({
          ad: k.kategori,
          deger: yuzde(k.medyan, true, 2),
          yon: yon(k.medyan),
          oran: Math.abs(k.medyan) / enBuyuk,
        })),
      ],
      kaynak: kurlar.length ? 'Kaynak: TEFAS, piyasa kotasyonları · Fon: kategori medyanı' : 'Kaynak: TEFAS · Kategori medyanı, BES hariç',
    },
  };
}

/// `x_takvim` satırı: açıklanacak veri ya da karar. `saat` TR saati.
export type TakvimOlayi = { tarih: string; saat: string | null; baslik: string };

const GUN_KISA = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const GUN_UZUN = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
/// Gönderi tek parça kalsın (270 karakter): haftada en çok bu kadar olay.
export const AZAMI_TAKVIM_OLAYI = 4;

/// Pazartesi: bu haftanın (Pzt–Cum) takvimi. Olay yoksa null → getiri gönderisi.
/// Tarihler yalnız `x_takvim`'den gelir; kural ("ayın 3'ü") ile tahmin
/// edilmez — tatile kayan bir açıklama yanlış gün yazdırır (uydurma yasağı).
export function takvimTaslagi(pazartesi: string, olaylar: TakvimOlayi[]): Taslak | null {
  const cuma = gunEkle(pazartesi, 4);
  const hafta = olaylar
    .filter((o) => o.tarih >= pazartesi && o.tarih <= cuma)
    .sort((a, b) => (a.tarih + (a.saat ?? '')).localeCompare(b.tarih + (b.saat ?? '')))
    .slice(0, AZAMI_TAKVIM_OLAYI);
  if (!hafta.length) return null;
  const saat = (o: TakvimOlayi) => (o.saat ? o.saat.slice(0, 5) : '');
  const gunYazisi = (o: TakvimOlayi) => `${gunAyYazisi(o.tarih)} ${GUN_UZUN[haftaGunu(o.tarih) - 1]}`;
  const olgular: Olgu[] = hafta.map((o) => ({
    ad: o.baslik,
    gosterim: [gunYazisi(o), saat(o)].filter(Boolean).join(' '),
  }));
  const satir = (o: TakvimOlayi) => `${gunYazisi(o)}${o.saat ? ` ${saat(o)}` : ''} ${o.baslik}.`;
  const aralik = `${gunAyYazisi(pazartesi).split(' ')[0]}–${gunAyYazisi(cuma)}`;
  let metin = `Bu hafta takvimde: ${hafta.map(satir).join(' ')}`;
  // Uzun başlıklar sınırı aşarsa saatsiz yazılır; yine aşarsa son olay düşer.
  for (let n = hafta.length; [...metin].length > AZAMI_KARAKTER && n > 1; n--) {
    metin = `Bu hafta takvimde: ${hafta.slice(0, n - 1).map((o) => `${gunYazisi(o)} ${o.baslik}.`).join(' ')}`;
  }
  return {
    tur: 'takvim',
    donem: pazartesi,
    olgular,
    sablon_metin: metin,
    yalniz_sablon: true,
    etiketler: [
      ...(hafta.some((o) => o.baslik.includes('TCMB')) ? ['#TCMB'] : []),
      ...(hafta.some((o) => o.baslik.includes('Fed')) ? ['#Fed'] : []),
      '#piyasa',
    ],
    kart: {
      bicim: 'liste',
      ust: `HAFTANIN TAKVİMİ · ${aralik.toLocaleUpperCase('tr-TR')}`,
      baslik: 'Bu hafta takvimde',
      satirlar: hafta.map((o) => ({
        ad: o.baslik,
        ek: saat(o),
        deger: `${GUN_KISA[haftaGunu(o.tarih) - 1]} ${gunAyYazisi(o.tarih).replace(/(\p{L}{3})\p{L}*/u, '$1')}`,
        yon: 'n' as const,
      })),
      kaynak: 'Kaynak: kurumların resmi takvimleri · TR saati',
    },
  };
}

/// Sabah hangi gönderi? Pazartesi takvim (olay varsa), diğer iş günleri ve
/// olaysız Pazartesi fon getirisi. Hafta sonu yok (cron da hafta içi).
export function sabahGonderisi(bugun: string): 'takvim' | 'fon_getiri' | null {
  const g = haftaGunu(bugun);
  if (g >= 6) return null;
  return g === 1 ? 'takvim' : 'fon_getiri';
}

// ── Etiket (yasin, 19 Eki: "ilgili konularda hashtag") ──────────────────────

/// Tür başına sabit etiketler. Model etiket yazmaz (`PAYLASIM_YASAK` '#'
/// reddeder); etiket metin kapısından SONRA eklenir, sayı/dil kuralı bozulmaz.
export const ETIKETLER: Record<GonderiTuru, string[]> = {
  fon_akisi: ['#fon', '#TEFAS'],
  haftalik: ['#fon', '#piyasa'],
  tufe: ['#enflasyon', '#TÜFE'],
  abd_tufe: ['#enflasyon', '#ABD'],
  fed: ['#Fed', '#faiz'],
  fon_getiri: ['#fon', '#TEFAS'],
  takvim: ['#piyasa'],
  abd_istihdam: ['#işsizlik', '#ABD'],
};

/// X sınırı. Etiket sığmıyorsa hiç eklenmez (gönderi kesilmez).
export const X_SINIRI = 280;

export function etiketle(t: Taslak, metin: string): string {
  const e = t.etiketler ?? ETIKETLER[t.tur] ?? [];
  if (!e.length) return metin;
  const sonuc = `${metin}\n\n${e.join(' ')}`;
  return [...sonuc].length <= X_SINIRI ? sonuc : metin;
}

// ── Model ───────────────────────────────────────────────────────────────────

/// AI işleri kuralı (yasin, 12 Eki): Sonnet 5.5. Gönderi başına tek çağrı,
/// metin saklanır, yeniden üretilmez.
export const MODEL = 'claude-sonnet-5-5';

export const SISTEM_TALIMATI = `Sen sandık adlı bir portföy takip uygulamasının X (Twitter) hesabı için kısa piyasa gönderileri yazan bir editörsün.

Görev: Sana bir günün ya da haftanın piyasa OLGULARI verilecek. Bunları doğal, sade, insan gibi konuşan 1–3 cümlelik tek bir gönderiye çevir. Robot gibi liste değil, bir arkadaşa anlatır gibi; ama abartısız ve ölçülü.

Kesin kurallar:
1. Yalnız verilen olguları kullan. Metne yazdığın her sayı, bir olgunun "gosterim" alanında AYNEN geçmeli. Hesap yapma, yuvarlama, iki sayıyı karşılaştırıp yeni sayı türetme.
2. Yalnız olanı anlat. Tahmin, beklenti, "devam edebilir", "yarın", "önümüzdeki" gibi gelecek dili yok.
3. Hiçbir şey önerme ve yönlendirme: al, sat, tut, fırsat, kaçırma, hedef, sinyal, "-meli/-malı", "dikkat" yok. Değer yargısı yok ("iyi", "kötü", "riskli", "güvenli", "rekor" gibi).
4. Ünlem, emoji, hashtag, link, @ yok. "Yatırım tavsiyesi değildir" yazma; hesap bio'sunda var.
5. En çok 260 karakter. Türkçe, sen dili kullanma; genel anlatım.

Çıktı: "metin" alanında gönderinin kendisi.`;

const METIN_SEMASI = {
  type: 'object',
  properties: { metin: { type: 'string' } },
  required: ['metin'],
  additionalProperties: false,
} as const;

export function istekGovdesi(t: Taslak): Record<string, unknown> {
  return {
    model: MODEL,
    max_tokens: 1000,
    system: [{ type: 'text', text: SISTEM_TALIMATI, cache_control: { type: 'ephemeral' } }],
    messages: [{
      role: 'user',
      content: ['Olgular:', JSON.stringify(t.olgular, null, 1), '', `Örnek düz anlatım (daha doğal yaz): ${t.sablon_metin}`].join('\n'),
    }],
    output_config: { format: { type: 'json_schema', schema: METIN_SEMASI }, effort: 'low' },
  };
}

/// Paylaşıma özel ek yasaklar (analiz.ts YASAK'a ek).
export const PAYLASIM_YASAK: RegExp[] = [
  /[!#@]/u,
  /https?:|www\.|\.com|\.app/iu,
  /\p{Extended_Pictographic}/u,
  /(^|[^\p{L}])(tut(un|mal|abilir)|sinyal|hedef (seviye|fiyat)|rekor|tarihi zirve)/iu,
  /\p{L}(meli|malı)(sin|sın|siniz|sınız|dir|dır)?([^\p{L}]|$)/iu,
  /(^|[^\p{L}])(riskli|güvenli|agresif|başarılı|kötü|iyi bir|harika|müthiş)([^\p{L}]|$)/iu,
  /önümüzdeki|yarın|gelecek (hafta|ay|gün)|devam edebilir|sürebilir|olabilir/iu,
  /dikkat/iu,
];

/// Tek gönderi sınırı (X 280; işaretler/çeviri payı bırakılır).
export const AZAMI_KARAKTER = 270;

export type MetinKapisi = { gecti: true; metin: string } | { gecti: false; neden: string };

/// Model metnini (ya da şablonu) yapı + sayı + dil kapısından geçirir.
export function metinKapisi(n: unknown, t: Taslak): MetinKapisi {
  const metin = typeof (n as { metin?: unknown })?.metin === 'string' ? (n as { metin: string }).metin.trim() : null;
  if (!metin) return { gecti: false, neden: 'yapi: metin yok' };
  if (metin.length < 20 || [...metin].length > AZAMI_KARAKTER) return { gecti: false, neden: 'yapi: uzunluk' };
  const izinli = new Set<string>();
  for (const o of t.olgular) {
    sayilar(o.gosterim).forEach((s) => izinli.add(s));
    sayilar(o.ad).forEach((s) => izinli.add(s));
  }
  for (const s of sayilar(metin)) {
    if (!izinli.has(s)) return { gecti: false, neden: `sayi: ${s} olgularda yok` };
  }
  for (const r of [...YASAK, ...PAYLASIM_YASAK]) {
    if (r.test(metin)) return { gecti: false, neden: `dil: ${r.source.slice(0, 40)}` };
  }
  return { gecti: true, metin };
}

// ── Kart SVG (1200×675, X'in 16:9 önizlemesi) ───────────────────────────────

/// Uygulamanın koyu teması (lib/theme/sandik.dart). Kart her zaman koyu:
/// akışta marka görseli olarak tanınsın.
const R = {
  zemin1: '#112E28',
  zemin2: '#0A1E15',
  cizgi: '#22483A',
  t90: '#EEF2EF',
  t58: '#B7C2BD',
  t36: '#8E9C96',
  amber: '#F5A623',
  gold: '#F5C842',
  gain: '#3DB77F',
  loss: '#FF6B52',
} as const;

export function xmlKacis(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/// Uygulama ikonunun dalgaları (assets/images/sandik_logo.svg), 44 px.
function logo(x: number, y: number): string {
  const k = 44 / 384;
  return `<g transform="translate(${x} ${y}) scale(${k}) translate(-64 -64)">
<clipPath id="lk"><rect x="64" y="64" width="384" height="384" rx="90"/></clipPath>
<g clip-path="url(#lk)"><rect x="64" y="64" width="384" height="384" fill="#F8C44E"/>
<path d="M 0 160 S 80 210, 128 210 S 176 160, 256 160 S 336 210, 384 210 S 464 160, 512 160 L 512 512 L 0 512 Z" fill="#E2861F"/>
<path d="M 0 220 S 80 270, 128 270 S 176 220, 256 220 S 336 270, 384 270 S 464 220, 512 220 L 512 512 L 0 512 Z" fill="#C56314"/>
<path d="M 0 280 S 80 330, 128 330 S 176 280, 256 280 S 336 330, 384 330 S 464 280, 512 280 L 512 512 L 0 512 Z" fill="#993D0A"/></g></g>`;
}

function renk(y: 'u' | 'd' | 'n'): string {
  return y === 'u' ? R.gain : y === 'd' ? R.loss : R.t36;
}

function cerceve(ust: string, kaynak: string, govde: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="675" viewBox="0 0 1200 675" font-family="DM Sans">
<defs><linearGradient id="z" x1="0" y1="0" x2="0.6" y2="1"><stop offset="0" stop-color="${R.zemin1}"/><stop offset="0.75" stop-color="${R.zemin2}"/></linearGradient></defs>
<rect width="1200" height="675" fill="url(#z)"/>
${logo(72, 64)}
<text x="128" y="96" font-size="28" font-weight="700" fill="${R.gold}">sandık</text>
<text x="1128" y="96" font-size="24" font-weight="500" fill="${R.t58}" text-anchor="end" letter-spacing="0.5">${xmlKacis(ust)}</text>
${govde}
<text x="72" y="610" font-size="20" font-weight="500" fill="${R.t36}">${xmlKacis(kaynak)}</text>
<text x="1128" y="610" font-size="20" font-weight="500" fill="${R.t36}" text-anchor="end">Yatırım tavsiyesi değildir</text>
</svg>`;
}

export function kartSvg(k: Kart): string {
  if (k.bicim === 'buyuk') {
    const enBuyuk = Math.max(...k.sutunlar.map((s) => s.deger), 0.1);
    const n = k.sutunlar.length;
    const gen = 500 / Math.max(n, 1);
    const sutun = k.sutunlar.map((s, i) => {
      const h = Math.max(4, (Math.max(s.deger, 0) / enBuyuk) * 150);
      const x = 72 + i * gen;
      const sonMu = i === n - 1;
      return `<rect x="${x.toFixed(1)}" y="${(530 - h).toFixed(1)}" width="${(gen - 16).toFixed(1)}" height="${h.toFixed(1)}" rx="6" fill="${sonMu ? R.gold : R.amber}" fill-opacity="${sonMu ? 1 : 0.8}"/>
<text x="${(x + (gen - 16) / 2).toFixed(1)}" y="${(520 - h).toFixed(1)}" font-size="18" font-weight="700" fill="${sonMu ? R.gold : R.t58}" text-anchor="middle">${xmlKacis((s.deger < 0 ? '−' : '') + yuzde(s.deger))}</text>
<text x="${(x + (gen - 16) / 2).toFixed(1)}" y="558" font-size="18" font-weight="500" fill="${R.t58}" text-anchor="middle">${xmlKacis(s.etiket)}</text>`;
    }).join('\n');
    return cerceve(k.ust, k.kaynak, `
<text x="72" y="250" font-size="120" font-weight="700" fill="${R.gold}" letter-spacing="-3">${xmlKacis(k.buyuk)}</text>
<text x="72" y="296" font-size="26" font-weight="500" fill="${R.t58}">${xmlKacis(k.alt)}</text>
${sutun}
<text x="660" y="300" font-size="28" font-weight="500" fill="${R.t58}">${xmlKacis(k.yan_baslik)}</text>
<text x="660" y="410" font-size="104" font-weight="700" fill="${R.t90}" letter-spacing="-3">${xmlKacis(k.yan_deger)}</text>`);
  }

  const vurgu = k.vurgu
    ? `<tspan fill="${k.vurgu_yon === 'd' ? R.loss : k.vurgu_yon === 'n' ? R.gold : R.gain}">${xmlKacis(k.vurgu)}</tspan>`
    : '';
  const baslik = `<text x="72" y="196" font-size="54" font-weight="700" fill="${R.t90}" letter-spacing="-1">${xmlKacis(k.baslik)}${vurgu ? ' ' : ''}${vurgu}${k.son ? ' ' + xmlKacis(k.son) : ''}</text>`;
  const tablo = k.satirlar.some((s) => s.ek !== undefined);
  const y0 = 270;
  const adim = Math.min(64, 300 / Math.max(k.satirlar.length, 1));
  const satirlar = k.satirlar.map((s, i) => {
    const y = y0 + i * adim;
    const ad = `<text x="72" y="${y + 10}" font-size="28" font-weight="500" fill="${R.t58}">${xmlKacis(s.ad)}</text>`;
    const deger = `<text x="1128" y="${y + 10}" font-size="28" font-weight="700" fill="${renk(s.yon)}" text-anchor="end">${xmlKacis(s.deger)}</text>`;
    if (tablo) {
      const ek = s.ek ? `<text x="900" y="${y + 10}" font-size="28" font-weight="700" fill="${R.t90}" text-anchor="end">${xmlKacis(s.ek)}</text>` : '';
      const cizgi = `<line x1="72" x2="1128" y1="${y + 30}" y2="${y + 30}" stroke="${R.cizgi}" stroke-width="1"/>`;
      return ad + ek + deger + cizgi;
    }
    const cubuk = s.oran !== undefined
      ? `<rect x="420" y="${y - 14}" width="${Math.max(10, s.oran * 540).toFixed(1)}" height="30" rx="6" fill="${renk(s.yon)}"/>`
      : '';
    return ad + cubuk + deger;
  }).join('\n');
  return cerceve(k.ust, k.kaynak, `${baslik}\n${satirlar}`);
}

// ── Takvim ──────────────────────────────────────────────────────────────────

/// TR günü (YYYY-MM-DD) için haftanın günü: 1 = Pazartesi … 7 = Pazar.
export function haftaGunu(iso: string): number {
  const d = new Date(`${iso}T12:00:00Z`).getUTCDay();
  return d === 0 ? 7 : d;
}

export function gunEkle(iso: string, gun: number): string {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + gun);
  return d.toISOString().slice(0, 10);
}

/// Bugün hangi gönderiler hazırlanır? Hafta içi günlük fon akışı; Cuma günlük
/// yerine haftalık özet (aynı gün iki fon gönderisi akışı doldurmasın).
/// TÜFE, yayımlandığı gün ayrıca (bkz. `tufeYeniMi`).
export function bugununFonGonderisi(bugun: string): { tur: GonderiTuru; baslangic: string; bitis: string } | null {
  const g = haftaGunu(bugun);
  if (g >= 6) return null;
  if (g === 5) return { tur: 'haftalik', baslangic: gunEkle(bugun, -4), bitis: bugun };
  return { tur: 'fon_akisi', baslangic: bugun, bitis: bugun };
}

/// TÜFE yalnız yeni yayımlandıysa paylaşılır: ilk kurulumda geçmiş ayların
/// gönderisi birikmesin. `eklendi` = inflation_index.created_at.
export function tufeYeniMi(eklendi: string, simdi: Date, gun = 3): boolean {
  return simdi.getTime() - new Date(eklendi).getTime() <= gun * 86400_000;
}

// ── Mod ─────────────────────────────────────────────────────────────────────

/// `X_BOT_MODU` secret'ı. Tanınmayan değer KAPALI sayılır (fail-closed).
///   kapali   → hiçbir şey yapılmaz
///   taslak   → taslak + Telegram önizleme; onay X'e göndermez
///   yayin    → taslak Telegram'da onaylanınca X'e gider
///   otomatik → metin kapısından geçen (ya da şablona düşen) taslak onaysız
///              X'e gider; Telegram'a yalnız bilgi gelir (yasin, 15 Eki:
///              "otomatik atmayacak mı"). Geri dönüş: secret'ı `yayin` yap.
export type XBotModu = 'kapali' | 'taslak' | 'yayin' | 'otomatik';

export function botModu(ham: string | undefined): XBotModu {
  const m = (ham ?? '').trim();
  return m === 'taslak' || m === 'yayin' || m === 'otomatik' ? m : 'kapali';
}

/// Bu modda X'e gönderim yapılabilir mi (onaylı ya da otomatik).
export function xeGonderir(mod: XBotModu): boolean {
  return mod === 'yayin' || mod === 'otomatik';
}

// ── Onay (Telegram) ─────────────────────────────────────────────────────────

/// Onay düğmesi verisi: 'o:<id>' yayınla, 'r:<id>' reddet.
export function geriCagriCoz(veri: unknown): { islem: 'onayla' | 'reddet'; id: number } | null {
  if (typeof veri !== 'string') return null;
  const m = /^([or]):(\d{1,12})$/.exec(veri);
  if (!m) return null;
  return { islem: m[1] === 'o' ? 'onayla' : 'reddet', id: Number(m[2]) };
}

/// Taslak bu kadar saat sonra onaylanamaz: bayat veri yayınlanmasın.
export const ONAY_SURESI_SAAT = 36;

export function onaySuresiGectiMi(olusturuldu: string, simdi: Date): boolean {
  return simdi.getTime() - new Date(olusturuldu).getTime() > ONAY_SURESI_SAAT * 3600_000;
}

// ── OAuth 1.0a (X API, kullanıcı bağlamı) ───────────────────────────────────
//
// Tek bot hesabı için en sade yol: dört sabit anahtar, yenileme yok. X
// HMAC-SHA1'i şart koşar (OAuth 1.0a imza yöntemi; parola saklama değil).

export type XKimlik = { consumerKey: string; consumerSecret: string; token: string; tokenSecret: string };

/// RFC 3986 kaçışı (OAuth'un istediği; encodeURIComponent `!*'()` bırakır).
export function yuzdeKodla(s: string): string {
  return encodeURIComponent(s).replace(/[!*'()]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase());
}

export function imzaTabani(method: string, url: string, params: Record<string, string>): string {
  const sirali = Object.keys(params).sort().map((k) => `${yuzdeKodla(k)}=${yuzdeKodla(params[k])}`).join('&');
  return [method.toUpperCase(), yuzdeKodla(url), yuzdeKodla(sirali)].join('&');
}

async function hmacSha1Base64(anahtar: string, metin: string): Promise<string> {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(anahtar), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const imza = new Uint8Array(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(metin)));
  return btoa(String.fromCharCode(...imza));
}

/// `Authorization: OAuth …` başlığı. `ekParams` yalnız sorgu dizesi ve
/// form-urlencoded gövde alanlarıdır; JSON ve multipart gövde imzaya girmez.
export async function oauthBasligi(
  method: string,
  url: string,
  kimlik: XKimlik,
  ekParams: Record<string, string> = {},
  nonce: string = crypto.randomUUID().replace(/-/g, ''),
  zaman: number = Math.floor(Date.now() / 1000),
): Promise<string> {
  const oauth: Record<string, string> = {
    oauth_consumer_key: kimlik.consumerKey,
    oauth_nonce: nonce,
    oauth_signature_method: 'HMAC-SHA1',
    oauth_timestamp: String(zaman),
    oauth_token: kimlik.token,
    oauth_version: '1.0',
  };
  const taban = imzaTabani(method, url, { ...ekParams, ...oauth });
  const anahtar = `${yuzdeKodla(kimlik.consumerSecret)}&${yuzdeKodla(kimlik.tokenSecret)}`;
  oauth.oauth_signature = await hmacSha1Base64(anahtar, taban);
  return 'OAuth ' + Object.keys(oauth).sort().map((k) => `${yuzdeKodla(k)}="${yuzdeKodla(oauth[k])}"`).join(', ');
}
