// Saatli fiyat bildirimi — SAF kurallar (0188, yasin 2026-11-26).
//
// `saatli-bildirim` fonksiyonu 15 dakikada bir koşar; hangi satırın bu
// dilime düştüğü ve bildirimin metni burada, ağ ve veritabanı olmadan test
// edilir (`supabase/tests/saatli_bildirim_test.ts`).
//
// ── Zaman ───────────────────────────────────────────────────────────────────
// TR sabit UTC+3, yaz saati yok (2016+; `quiet_hours.ts` › `istanbulHour`
// ile aynı varsayım). Dilim, çağrı anının 15 dakikaya AŞAĞI yuvarlanmışıdır:
// pg_net çağrıyı :00 yerine :00:40'ta ulaştırırsa dilim yine :00 kalır.
// `slotTs` dilimin UTC başlangıcı; gönderim kaydının (user_id, slot_ts)
// anahtarı ondan kurulur, aynı dilime ikinci çağrı ikinci push üretmez.
//
// ── Gün maskesi ─────────────────────────────────────────────────────────────
// bit 0 pazartesi … bit 6 pazar (ISO sırası), 127 = her gün. İstemcideki
// `SaatliBildirim.gunBiti` ile aynı sıra.
//
// ── İçerik (tasarım) ────────────────────────────────────────────────────────
// Tek varlık: başlık "Gram altın ₺4.112,40", gövde "Bugün +%0,8".
// Çok varlık: başlık "15:00 fiyatların", gövde satır başına
// "Gram altın ₺4.112,40 (+%0,8)". Fiyatı bilinmeyen varlık yazılmaz; hiçbiri
// bilinmiyorsa push YOK (uydurma sayı yasak). Borsası kapalı varlıkta
// (BIST seans dışı, fon/hisse tatil) "son fiyat" eki. Günlük değişim
// bilinmiyorsa yüzde yazılmaz.
//
// "Maliyetine göre +%12,3" eki BİLEREK yok: sunucu, alarm sembolünü
// kullanıcının lot'larına ve para birimine güvenle eşleyen bir yol
// bilmiyor; yanlış maliyet yüzdesi uydurma sayıdır. Eşleme sunucuya
// gelince eklenir.

import type { CanliKotasyon } from './live_prices.ts';
import { isTefasSymbol } from './live_prices.ts';
import { fiyatMetni, kotasyonSimgesi } from './fiyat_metni.ts';
import { borsaKapaliGunMu, bistSeansAcikMi } from './piyasa_takvimi.ts';

export const DILIM_DK = 15;
export const GUN_DK = 24 * 60;
const TR_OFFSET_MS = 3 * 3600 * 1000;

export type SaatliSatir = {
  user_id: string;
  symbol: string;
  label: string;
  saatler: number[];
  gunler: number;
};

export type Dilim = {
  /// TR gününün dakikası (0..1425, 15'in katı).
  dakika: number;
  /// Bugünün gün biti (pazartesi 1 … pazar 64).
  gunBiti: number;
  /// Dilimin UTC başlangıcı, ISO.
  slotTs: string;
};

/// Çağrı anının dilimi.
export function trDilimi(simdi: Date): Dilim {
  const dilimMs = DILIM_DK * 60_000;
  const bas = Math.floor(simdi.getTime() / dilimMs) * dilimMs;
  const tr = new Date(bas + TR_OFFSET_MS);
  const dakika = tr.getUTCHours() * 60 + tr.getUTCMinutes();
  // getUTCDay: 0 pazar … 6 cumartesi → ISO: pazartesi 0 … pazar 6.
  const iso = (tr.getUTCDay() + 6) % 7;
  return { dakika, gunBiti: 1 << iso, slotTs: new Date(bas).toISOString() };
}

/// Satır bu dilimde gönderilir mi: saat listede ve gün maskede.
export function dilimeDuser(satir: Pick<SaatliSatir, 'saatler' | 'gunler'>, d: Dilim): boolean {
  return Array.isArray(satir.saatler) &&
    satir.saatler.some((s) => Number(s) === d.dakika) &&
    (Number(satir.gunler) & d.gunBiti) !== 0;
}

/// Kullanıcı → o dilimin satırları (kullanıcı başına TEK push için).
export function kullaniciyaGore(satirlar: SaatliSatir[], d: Dilim): Map<string, SaatliSatir[]> {
  const out = new Map<string, SaatliSatir[]>();
  for (const s of satirlar) {
    if (!dilimeDuser(s, d)) continue;
    const l = out.get(s.user_id);
    if (l) l.push(s);
    else out.set(s.user_id, [s]);
  }
  return out;
}

/// "15:00".
export function saatMetni(dakika: number): string {
  const s = Math.floor(dakika / 60);
  const d = dakika % 60;
  return `${String(s).padStart(2, '0')}:${String(d).padStart(2, '0')}`;
}

/// "+%0,8" / "−%1,2" / "%0,0".
export function degisimMetni(pct: number): string {
  const g = `%${Math.abs(pct).toFixed(1).replace('.', ',')}`;
  if (g === '%0,0') return g;
  return pct > 0 ? `+${g}` : `−${g}`;
}

/// Borsası şu an kapalı mı ("son fiyat" eki). Altın, döviz, kripto ve
/// emtia hiç kapalı sayılmaz; BIST seans dışı ve fon/hisse tatil günü.
export function sonFiyatMi(sembol: string, simdi: Date): boolean {
  const t = sembol.trim().toUpperCase();
  if (isTefasSymbol(t)) return borsaKapaliGunMu('fon', simdi);
  if (t.endsWith('.IS')) return !bistSeansAcikMi(simdi);
  return false;
}

export type SaatliMesaj = {
  title: string;
  body: string;
  /// Dokununca açılacak varlık: fiyatı bilinen ilk satır.
  symbol: string;
  label: string;
  /// Mesaja giren varlık sayısı.
  sayi: number;
};

/// Bildirim metni; fiyatı bilinen hiç varlık yoksa `null` (push yok).
export function mesajKur(
  satirlar: Pick<SaatliSatir, 'symbol' | 'label'>[],
  kotasyonlar: Map<string, CanliKotasyon>,
  d: Dilim,
  simdi: Date,
): SaatliMesaj | null {
  const bilinen = satirlar.flatMap((s) => {
    const k = kotasyonlar.get(s.symbol);
    return k && Number.isFinite(k.price) && k.price > 0 ? [{ s, k }] : [];
  });
  if (bilinen.length === 0) return null;
  const fiyat = (sembol: string, p: number) =>
    fiyatMetni(p, kotasyonSimgesi(sembol)) + (sonFiyatMi(sembol, simdi) ? ' (son fiyat)' : '');
  const degisim = (pct: number | null) =>
    pct !== null && Number.isFinite(pct) ? degisimMetni(pct) : null;

  const ilk = bilinen[0];
  if (bilinen.length === 1) {
    const g = degisim(ilk.k.changePct);
    return {
      title: `${ilk.s.label} ${fiyat(ilk.s.symbol, ilk.k.price)}`,
      body: g ? `Bugün ${g}` : `Saat ${saatMetni(d.dakika)} fiyatı`,
      symbol: ilk.s.symbol,
      label: ilk.s.label,
      sayi: 1,
    };
  }
  return {
    title: `${saatMetni(d.dakika)} fiyatların`,
    body: bilinen.map(({ s, k }) => {
      const g = degisim(k.changePct);
      return `${s.label} ${fiyat(s.symbol, k.price)}${g ? ` (${g})` : ''}`;
    }).join('\n'),
    symbol: ilk.s.symbol,
    label: ilk.s.label,
    sayi: bilinen.length,
  };
}

/// Gönderim kaydı yazma sonucunun kararı. Kayıt push'tan ÖNCE yazılır:
/// birincil anahtar çakışması (23505) = bu dilimde zaten gönderildi, push
/// yok. Başka hata = kaydı olmayan push yeniden denemede ikinci kez giderdi;
/// göndermemek (bir dilim kaçırmak) çift push'tan iyidir.
export function gonderimKarari(
  hata: { code?: string } | null,
): 'gonder' | 'zaten' | 'hata' {
  if (hata === null) return 'gonder';
  return hata.code === '23505' ? 'zaten' : 'hata';
}

/// Tablo bu projede henüz yok mu (fonksiyon migration'dan önce dağıtıldı):
/// sessizce boş tur.
export function tabloYokMu(hata: { code?: string } | null): boolean {
  return hata !== null && (hata.code === '42P01' || hata.code === 'PGRST205');
}
