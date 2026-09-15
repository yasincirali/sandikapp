// TEFAS NAV yayın anı gözlemi — SAF yardımcılar.
//
// `observe-tefas-nav/index.ts` ağ + veritabanı işini yapar; buradaki
// fonksiyonlar girdi alıp çıktı döner ki `supabase/tests/tefas_nav_test.ts`
// onları TEFAS'a ve Postgres'e dokunmadan sınayabilsin.
//
// ── Neden bu gözlem var ──────────────────────────────────────────────────────
// TEFAS `fonFiyatBilgiGetir` yanıtı NAV'ın TARİHİNİ (`tarih`) taşır, yayım-
// landığı ANI değil. Uygulama fonun gün içi basamağını bu yüzden sabit
// 10:00'a çapalıyordu. Bir (fon, NAV tarihi) çiftini sunucuda İLK gördüğümüz
// anı kaydedersek gerçek bir yayın damgası üretmiş oluruz — cron sıklığı
// kadar (30 dk) belirsiz, ama uydurma değil. Bkz. 0063_tefas_nav_gozlem.sql.

/// Bir TEFAS satırından süzülmüş NAV.
export type NavSatiri = { tarih: string; fiyat: number };

/// Bir turda TEFAS'a sorulacak en fazla kod. Yayın öncesi turlarda her kod
/// bir istek demek; 150 × 4'lü paralel ≈ 40 sn, edge function sınırının
/// (150 sn) altında kalır. Üstü bir sonraki tura kalır (kodlar sıralı).
export const TUR_KOD_USTU = 150;

/// Bir önceki tur bundan eskiyse "önceki kontrol" bilinmiyor sayılır:
/// cron 30 dk'da bir koşuyor; 45 dk atlanmış/başarısız tur demek.
export const ONCEKI_TUR_AZAMI_MS = 45 * 60 * 1000;

/// TEFAS tarih alanını `YYYY-MM-DD`'ye çevirir.
///
/// Görülen biçimler: ISO (`2026-09-10T00:00:00`, `2026-09-10`), Türk biçimi
/// (`10.09.2026`, `10/09/2026`) ve epoch milisaniye (sayı ya da sayı dizesi).
/// Tanınmayan biçim `null` — tarihi tahmin etmek yanlış güne yazmak olur.
export function tefasTarihToIso(raw: unknown): string | null {
  if (raw === null || raw === undefined) return null;
  if (typeof raw === 'number' && Number.isFinite(raw)) return epochToIso(raw);
  const t = String(raw).trim();
  if (t.length === 0) return null;

  let m = /^(\d{4})-(\d{2})-(\d{2})/.exec(t);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;

  m = /^(\d{1,2})[./](\d{1,2})[./](\d{4})$/.exec(t);
  if (m) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;

  if (/^\d{12,13}$/.test(t)) return epochToIso(Number(t));
  return null;
}

/// Epoch ms → TR gününe göre `YYYY-MM-DD`. TEFAS gece yarısı damgası verir;
/// UTC'ye göre gün bir gün geri kayardı (21:00Z = TR 00:00).
function epochToIso(ms: number): string {
  return trGun(new Date(ms));
}

/// Bir anın Europe/Istanbul takvim günü, `YYYY-MM-DD`.
///
/// `en-CA` locale ISO biçimi (`2026-09-14`) verir; elle ofset toplamak yerine
/// runtime DST'yi çözer (Türkiye 2016'dan beri sabit +03, ama kural runtime'da
/// dursun).
export function trGun(now: Date): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}

/// `resultList`'ten EN YENİ geçerli NAV satırı.
///
/// Liste çoğunlukla tarih sıralı ama buna güvenilmez: tarihe göre en büyük
/// seçilir. `fiyat` yoksa `birimPayDegeri` (Dart tarafı `_fetchPriceRow` ile
/// aynı ikili). Sıfır/negatif/NaN fiyatlı satır yok sayılır.
export function sonNavSatiri(resultList: unknown): NavSatiri | null {
  if (!Array.isArray(resultList)) return null;
  let en: NavSatiri | null = null;
  for (const row of resultList) {
    if (row === null || typeof row !== 'object') continue;
    const r = row as Record<string, unknown>;
    const ham = r.fiyat ?? r.birimPayDegeri ?? r.FIYAT;
    const fiyat = typeof ham === 'number' ? ham : Number(String(ham ?? '').replace(',', '.'));
    if (!Number.isFinite(fiyat) || fiyat <= 0) continue;
    const tarih = tefasTarihToIso(r.tarih ?? r.TARIH);
    if (tarih === null) continue;
    if (en === null || tarih > en.tarih) en = { tarih, fiyat };
  }
  return en;
}

/// `assets.ticker` değerlerinden ('TEFAS:AFT') tekil, büyük harfli fon
/// kodları. Biçimi bozuk olanlar (boş, çok uzun, harf/rakam dışı) atılır —
/// TEFAS'a anlamsız istek atmamak ve yanıtı kodla eşlerken şaşmamak için.
/// Sıralı döner ki üst sınır (TUR_KOD_USTU) kesimi turdan tura kararlı olsun.
export function fonKodlari(tickers: Iterable<string>): string[] {
  const out = new Set<string>();
  for (const t of tickers) {
    const s = String(t ?? '').trim().toUpperCase();
    const kod = s.startsWith('TEFAS:') ? s.slice('TEFAS:'.length) : '';
    if (/^[A-Z0-9]{2,6}$/.test(kod)) out.add(kod);
  }
  return [...out].sort();
}

/// Bu turda TEFAS'a sorulacak kodlar.
///
/// BUGÜN tarihli NAV'ı zaten görülmüş kod bir daha sorulmaz: fon günde bir
/// kez fiyatlanır, gözlem alındıktan sonra o gün için yeni bilgi yoktur.
/// Kalanlar sıralı ve üst sınırlı.
export function sorulacakKodlar(
  kodlar: string[],
  bugunGorulen: Set<string>,
  ust: number = TUR_KOD_USTU,
): string[] {
  return kodlar.filter((k) => !bugunGorulen.has(k)).slice(0, Math.max(0, ust));
}

/// Görülen satır yeni bir gözlem mi? Bilinen son NAV tarihinden daha yeni
/// bir tarih taşıyorsa evet. Eşit ya da eski tarih (TEFAS geriye dönük
/// düzeltme yapsa bile) yeni gözlem değildir — ilk görülme anı değişmez.
export function gozlemYeniMi(
  satir: NavSatiri,
  bilinenSonTarih: string | undefined,
): boolean {
  return bilinenSonTarih === undefined || satir.tarih > bilinenSonTarih;
}

/// Önceki turun zamanı yeterince yakınsa (aralık dar) `onceki_kontrol`
/// olarak kullanılır; değilse `null` (gözlem yalnız üst sınır).
export function oncekiKontrol(
  sonTur: Date | null,
  now: Date,
  azamiMs: number = ONCEKI_TUR_AZAMI_MS,
): Date | null {
  if (sonTur === null) return null;
  const fark = now.getTime() - sonTur.getTime();
  if (fark < 0 || fark > azamiMs) return null;
  return sonTur;
}
