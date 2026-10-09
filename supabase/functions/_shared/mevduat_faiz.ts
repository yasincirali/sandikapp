// Mevduat faiz ortalaması — saf yardımcılar (mevduat-faiz).
//
// Kaynak: TCMB EVDS "TL mevduat ağırlıklı ortalama faiz (akım, haftalık)".
// Bankaya özel DEĞİL; sektör ortalaması (0129 kaynak kararı).

/// EVDS servis kökü (fetch-inflation ile aynı; 2026-09'da evds3'e taşındı,
/// parametreler YOLA gömülür — `?` ile 404).
export const EVDS_BASE = 'https://evds3.tcmb.gov.tr/igmevdsms-dis/';

/// Geçerli faiz aralığı: tablo CHECK'iyle aynı. Dışındaki değer EVDS'nin
/// başka bir seriyi (endeks, tutar) döndürdüğü anlamına gelir; yazılmaz.
export const FAIZ_ALT = 0;
export const FAIZ_UST = 300;

export type FaizNoktasi = { tarih: string; faiz: number };

/// `GG-AA-YYYY` → `YYYY-MM-DD`; haftalık EVDS tarihi bu biçimde gelir.
/// `YYYY-MM-DD` de kabul edilir. Tanınmayan biçim `null` — tarih tahmin
/// edilmez.
export function evdsGunu(tarih: string): string | null {
  const t = tarih.trim();
  let m = /^(\d{1,2})-(\d{1,2})-(\d{4})$/.exec(t);
  if (m) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(t);
  if (m) return `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;
  return null;
}

/// EVDS yanıtındaki EN SON geçerli nokta.
///
/// Gövde `{ items: [{ Tarih: '03-10-2026', TP_TRY_MT02: '38.12' }, …] }`;
/// alan adı seri kodunun noktaları alt çizgiye dönmüş hâli. Boş/`null`/
/// aralık dışı değerler atlanır — tek bozuk hafta turu düşürmez, uydurma
/// sayı da yazılmaz.
export function sonFaiz(json: unknown, seri: string): FaizNoktasi | null {
  const govde = json as { items?: unknown } | null;
  const items = Array.isArray(govde?.items) ? govde!.items : [];
  const alan = seri.replaceAll('.', '_');
  let son: FaizNoktasi | null = null;
  for (const raw of items) {
    const item = raw as Record<string, unknown>;
    const tarih = evdsGunu(String(item['Tarih'] ?? ''));
    const ham = item[alan];
    if (tarih === null || ham === null || ham === undefined || ham === '') continue;
    const faiz = typeof ham === 'number' ? ham : Number(String(ham).trim().replace(',', '.'));
    if (!Number.isFinite(faiz) || faiz <= FAIZ_ALT || faiz >= FAIZ_UST) continue;
    if (son === null || tarih > son.tarih) son = { tarih, faiz };
  }
  return son;
}

/// EVDS tarih parametresi `GG-AA-YYYY`.
export function evdsTarih(d: Date): string {
  const g = d.getUTCDate().toString().padStart(2, '0');
  const a = (d.getUTCMonth() + 1).toString().padStart(2, '0');
  return `${g}-${a}-${d.getUTCFullYear()}`;
}

/// Son [gun] günün seri adresi. Haftalık seri: `frequency` verilmez,
/// EVDS serinin kendi sıklığında döndürür.
export function seriAdresi(seri: string, simdi: Date, gun = 70): string {
  const bas = new Date(simdi.getTime() - gun * 86_400_000);
  return `${EVDS_BASE}series=${seri}`
    + `&startDate=${evdsTarih(bas)}`
    + `&endDate=${evdsTarih(simdi)}`
    + '&type=json';
}

/// Veri bayat mı: TCMB haftalık yayımlıyor; 45 günden eski son nokta seri
/// kodunun durduğunu (TCMB kod değiştirmiş) gösterir. Bayat veri
/// "güncel ortalama" diye gösterilmez.
export function bayatMi(veriTarihi: string, simdi: Date, gun = 45): boolean {
  const t = Date.parse(`${veriTarihi}T00:00:00Z`);
  if (!Number.isFinite(t)) return true;
  return simdi.getTime() - t > gun * 86_400_000;
}
