// Fon para akışı ve büyük giriş/çıkış tespiti — SAF yardımcılar.
//
// `akis-gozlem/index.ts` ağ + veritabanı işini yapar; buradaki fonksiyonlar
// girdi alıp çıktı döner ki `supabase/tests/balina_test.ts` onları TEFAS'a ve
// Postgres'e dokunmadan sınayabilsin (emsal: `tefas_nav.ts`).
//
// ── Net akış neden "pay farkı × fiyat" ──────────────────────────────────────
// Fon büyüklüğü iki nedenle değişir: fiyat oynar, yatırımcı pay alır/satar.
// Büyüklük farkını akış saymak, fiyatı %5 artan bir fona "para girdi" demek
// olurdu. Dolaşımdaki pay adedi yalnız alım-satımla değişir; farkı o günün
// birim fiyatıyla çarpmak giren/çıkan parayı verir. Fiyat ayrı bir kaynaktan
// alınmaz: aynı satırın `deger / pay` oranıdır — ekranda görünen TEFAS
// fiyatıyla aynı sayı (ölçüldü 2026-10-04: TTE 2.385.068.751,83 / 2.013.904.583
// = 1,184301).
//
// ── "Balina" neden iki eşikli ───────────────────────────────────────────────
// Yalnız sapma kuralı sakin bir fonda küçük bir hareketi olay yapar; yalnız
// büyüklük kuralı hareketli bir fonda her günü olay yapar. İkisinin BÜYÜĞÜ
// aşılmalı. Küçük fonlarda tek kişinin birikimi bile oranı geçer; bu yüzden
// büyüklük tabanı var (yanlış alarm, hiç alarm vermemekten kötü: kullanıcı
// kartı bir kez boşa çıkarsa bir daha inanmaz).
//
// ── Eşikler neden bu sayılar (ölçüm 2026-10-04, 29 işlem günü, 1.144 fon) ───
// İlk kural (3 sapma, %2, fon ≥ 50 mn) fon başına ayda ~1 olay üretti: dört
// fonu olan kullanıcı ayda dört "büyük hareket" görür, olay olağanlaşır.
// Fon akışları yığınlı (birkaç büyük yatırımcı); sapma kuralı sık tetiklenir.
// 4 sapma + %3 + fon ≥ 250 mn sıklığı ~0,4'e indirdi (kullanıcı onayı
// 2026-10-04). Para piyasası fonları hiç olay üretmez: günlük giriş-çıkış o
// fonların işleyişidir, haber değil.
//
// ── İki kademe: liste ve bildirim ───────────────────────────────────────────
// Kartta listelenen her olay bildirim gönderilecek kadar önemli değildir.
// `bildirime_deger` daha sıkı üç koşulu birden ister (%5, 25 mn TL, son ~60
// işlem gününün en büyüğü). Bildirimi B4 gönderir; bayrak burada, olayla
// AYNI satırda durur ki liste ile bildirim farklı kural okumasın.

/// TEFAS büyüklük ucundan süzülmüş, bir fonun bir günkü durumu.
export type BuyuklukSatiri = { kod: string; pay: number; deger: number; tur: string | null };

/// `fon_akis_gunluk` satırı (yazılacak hâli).
export type AkisSatiri = {
  fon_kodu: string;
  tarih: string;
  fon_tipi: string;
  fon_turu: string | null;
  pay_adedi: number;
  portfoy_degeri: number;
  net_akis: number | null;
};

/// Olay kararı için bir fonun geçmiş istatistiği (`akis_sapma` RPC'si).
export type AkisIstatistigi = {
  gozlem: number;
  sapma: number | null;
  /// Penceredeki en büyük |günlük akış|; bildirim kademesi buna bakar.
  enBuyuk?: number | null;
};

/// Tespit edilen olay (`balina_olay` satırının hesaplanan alanları).
export type BalinaOlayi = {
  tur: 'fon_giris' | 'fon_cikis';
  tutar: number;
  buyukluk_orani: number;
  sapma_kati: number;
  bildirime_deger: boolean;
};

/// Geriye dönük doldurma penceresi (takvim günü). Sapma 90 takvim günü
/// (~60 işlem günü) ister; olaylar son ~40 gün için üretilir. 130 gün ikisini
/// birlikte karşılar.
export const PENCERE_GUN = 130;

/// Bir turda çekilecek en fazla gün. Gün başına 2 TEFAS isteği (yatırım +
/// emeklilik, her biri ~375 KB) ve ~1.400 satırlık yazma; 14 gün edge function
/// süre sınırının (150 sn) altında kalır. İlk kurulumda pencere birkaç turda
/// dolar.
export const TUR_GUN_USTU = 14;

/// Bu kadar günden yeni günler "kesin" sayılmaz ve her turda yeniden çekilir:
/// TEFAS bir günün fiyatlarını fon fon yayınlıyor; erken turda eksik gelen
/// fon sonraki turda tamamlanır.
export const KESINLESME_GUN = 2;

/// Sapma hesabına girecek en az gözlem. Azıyla σ güvenilmez; olay ÜRETİLMEZ
/// (tahmini eşik yazılmaz).
export const ASGARI_GOZLEM = 20;

/// Akış, geçmiş günlük akışların sapmasının en az bu katı olmalı.
export const SAPMA_KATI = 4;

/// Akış, fon büyüklüğünün en az bu oranı olmalı.
export const BUYUKLUK_ORANI = 0.03;

/// Bundan küçük fonlarda olay üretilmez (TL).
export const ASGARI_BUYUKLUK = 250_000_000;

/// Bildirim kademesi: akış fon büyüklüğünün en az bu oranı olmalı.
export const BILDIRIM_ORANI = 0.05;

/// Bildirim kademesi: akış en az bu tutar olmalı (TL).
export const BILDIRIM_TUTARI = 25_000_000;

/// Olayların üretildiği geriye dönük süre (takvim günü). Kart son 30 günü
/// gösterir; pay, turun geç koştuğu günler için.
export const OLAY_PENCERE_GUN = 40;

/// `2026-10-02` → `20261002`. TEFAS büyüklük ucu tarihi bu biçimde ister
/// (ölçüldü: tireli biçim "could not be parsed at index 4" döndürüyor).
export function tefasGunParam(isoGun: string): string {
  return isoGun.replaceAll('-', '');
}

/// `YYYY-MM-DD` gününe takvim günü ekler (UTC öğlesi üzerinden; DST'siz).
export function gunEkle(isoGun: string, gun: number): string {
  const d = new Date(`${isoGun}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + gun);
  return d.toISOString().slice(0, 10);
}

/// Hafta sonu mu? Fonlar hafta sonu fiyatlanmaz; o günleri sormak boşa istek.
export function haftaSonuMu(isoGun: string): boolean {
  const g = new Date(`${isoGun}T12:00:00Z`).getUTCDay();
  return g === 0 || g === 6;
}

/// Bu turda çekilecek günler, ESKİDEN YENİYE.
///
/// Pencere içindeki hafta içi günlerden `kesin` kümesinde OLMAYANLAR. Sıra
/// önemli: bir günün net akışı bir önceki günün pay adedine bakar; eski gün
/// önce yazılmalı.
export function cekilecekGunler(
  bugun: string,
  kesin: Set<string>,
  pencere: number = PENCERE_GUN,
  ust: number = TUR_GUN_USTU,
): string[] {
  const out: string[] = [];
  for (let i = pencere; i >= 0 && out.length < Math.max(0, ust); i--) {
    const gun = gunEkle(bugun, -i);
    if (haftaSonuMu(gun) || kesin.has(gun)) continue;
    out.push(gun);
  }
  return out;
}

/// Gün artık değişmez mi? `KESINLESME_GUN` günden eskiyse evet.
export function gunKesinMi(
  gun: string,
  bugun: string,
  bekleme: number = KESINLESME_GUN,
): boolean {
  return gun < gunEkle(bugun, -bekleme);
}

/// `fonBuyuklukBazliBilgiGetir` yanıtından geçerli satırlar.
///
/// Aynı gün için sorulduğunda (`basTarih == bitTarih`) `son*` alanları o
/// günün değeridir. Kodu bozuk, payı ya da değeri sıfır/negatif/sayı olmayan
/// satır ATILIR — sıfıra bölüp fiyat uydurmamak için.
export function buyuklukSatirlari(resultList: unknown): BuyuklukSatiri[] {
  if (!Array.isArray(resultList)) return [];
  const out = new Map<string, BuyuklukSatiri>();
  for (const row of resultList) {
    if (row === null || typeof row !== 'object') continue;
    const r = row as Record<string, unknown>;
    const kod = String(r.fonKodu ?? '').trim().toUpperCase();
    if (!/^[A-Z0-9]{2,6}$/.test(kod)) continue;
    const pay = sayi(r.sonPayAdedi);
    const deger = sayi(r.sonPortfoyDegeri);
    if (pay === null || deger === null || pay <= 0 || deger <= 0) continue;
    const turHam = typeof r.fonTurAciklama === 'string' ? r.fonTurAciklama.trim() : '';
    out.set(kod, { kod, pay, deger, tur: turHam.length > 0 ? turHam.slice(0, 80) : null });
  }
  return [...out.values()];
}

function sayi(ham: unknown): number | null {
  if (typeof ham === 'number') return Number.isFinite(ham) ? ham : null;
  if (typeof ham !== 'string' || ham.trim().length === 0) return null;
  const n = Number(ham.replace(',', '.'));
  return Number.isFinite(n) ? n : null;
}

/// Günün net para akışı (TL). Önceki günün pay adedi bilinmiyorsa `null` —
/// ilk gözlemde akış yoktur, sıfır yazmak "para girmedi" demek olurdu.
export function netAkis(
  pay: number,
  deger: number,
  oncekiPay: number | undefined,
): number | null {
  if (oncekiPay === undefined || !(oncekiPay > 0) || !(pay > 0) || !(deger > 0)) {
    return null;
  }
  const akis = (pay - oncekiPay) * (deger / pay);
  // Kuruşa yuvarla: numeric sütuna 15 basamaklı kayan nokta artığı yazılmasın.
  return Math.round(akis * 100) / 100;
}

/// Bir günün TEFAS satırlarını yazılacak satırlara çevirir ve `oncekiPay`
/// haritasını o günün paylarıyla GÜNCELLER (sonraki gün buna bakar).
export function gunSatirlari(
  gun: string,
  fonTipi: string,
  satirlar: BuyuklukSatiri[],
  oncekiPay: Map<string, number>,
): AkisSatiri[] {
  const out: AkisSatiri[] = [];
  for (const s of satirlar) {
    out.push({
      fon_kodu: s.kod,
      tarih: gun,
      fon_tipi: fonTipi,
      fon_turu: s.tur,
      pay_adedi: s.pay,
      portfoy_degeri: s.deger,
      net_akis: netAkis(s.pay, s.deger, oncekiPay.get(s.kod)),
    });
  }
  for (const s of satirlar) oncekiPay.set(s.kod, s.pay);
  return out;
}

/// Para piyasası fonu mu? TEFAS tür adı üzerinden ("Para Piyasası Fonu",
/// "Katılım Para Piyasası…"). Tür bilinmiyorsa `false`: bilinmeyeni
/// susturmak, gerçek bir olayı gizlemek olurdu.
export function paraPiyasasiMi(fonTuru: string | null | undefined): boolean {
  if (!fonTuru) return false;
  return fonTuru.toLocaleLowerCase('tr-TR').includes('para piyasası');
}

/// Bu günkü akış bir "büyük giriş/çıkış" olayı mı?
///
/// Koşulların HEPSİ: para piyasası fonu değil, fon yeterince büyük, yeterli
/// geçmiş var, akış fon büyüklüğünün %3'ünü VE geçmiş sapmanın 4 katını
/// aşıyor. Biri eksikse `null` (olay yok).
export function balinaOlayi(
  netAkisTl: number | null,
  portfoyDegeri: number,
  ist: AkisIstatistigi | undefined,
  fonTuru?: string | null,
): BalinaOlayi | null {
  if (paraPiyasasiMi(fonTuru)) return null;
  if (netAkisTl === null || !Number.isFinite(netAkisTl) || netAkisTl === 0) return null;
  // Oranın paydası akıştan ÖNCEKİ büyüklük (bugünkü değer − bugünkü akış).
  // Bugünkü değere bölmek büyük çıkışı şişirir: 34 mr'lik fondan 20 mr
  // çıkınca kalan 14 mr'ye oran %143 çıkıyordu (DOH, 18 Eylül 2026 ölçümü);
  // doğrusu %59. Fon akışı raporlamasında payda dönem başı varlıktır.
  const taban = portfoyDegeri - netAkisTl;
  if (!(taban >= ASGARI_BUYUKLUK)) return null;
  if (ist === undefined || ist.gozlem < ASGARI_GOZLEM) return null;
  if (ist.sapma === null || !(ist.sapma > 0)) return null;

  const mutlak = Math.abs(netAkisTl);
  const esik = Math.max(SAPMA_KATI * ist.sapma, BUYUKLUK_ORANI * taban);
  if (mutlak < esik) return null;

  return {
    tur: netAkisTl > 0 ? 'fon_giris' : 'fon_cikis',
    tutar: netAkisTl,
    buyukluk_orani: Math.round((mutlak / taban) * 10000) / 10000,
    sapma_kati: Math.round((mutlak / ist.sapma) * 10) / 10,
    // Üç koşul birden; penceredeki en büyük akış bilinmiyorsa bildirim YOK.
    bildirime_deger: mutlak >= BILDIRIM_ORANI * taban &&
      mutlak >= BILDIRIM_TUTARI &&
      typeof ist.enBuyuk === 'number' && mutlak > ist.enBuyuk,
  };
}

/// `fonBilgiGetir` anlık görüntüsündeki yatırımcı sayısı, YALNIZ görüntü
/// elimizdeki günün satırıyla aynı büyüklüğü taşıyorsa.
///
/// Uç tarih vermiyor; büyüklük eşleşmesi "bu sayı o güne ait" demenin tek
/// kanıtı. Eşleşmiyorsa (TEFAS yeni günü yayınlamış, biz henüz çekmemişiz)
/// `null` — yanlış güne yazmaktansa boş bırakılır.
export function yatirimciSayisi(
  resultList: unknown,
  satirDegeri: number,
): number | null {
  if (!Array.isArray(resultList) || resultList.length === 0) return null;
  const r = resultList[0];
  if (r === null || typeof r !== 'object') return null;
  const o = r as Record<string, unknown>;
  const deger = sayi(o.portBuyukluk);
  const kisi = sayi(o.yatirimciSayi);
  if (deger === null || kisi === null || kisi < 0 || !Number.isInteger(kisi)) return null;
  if (Math.abs(deger - satirDegeri) > 1) return null;
  return kisi;
}
