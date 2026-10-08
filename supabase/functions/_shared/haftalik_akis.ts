// Haftalık özetin "para akışı" cümlesi — SAF yardımcılar.
//
// ── Neden haftalık özette (kullanıcı kararı, 2026-10-04) ────────────────────
// Büyük giriş/çıkış olayları için AYRI bildirim açılmıyor: "bildirimi haftalık
// bir portföy durumu yayınlayıp dönebiliriz, haftanın özeti gibi; varlıklara
// giren çıkan paralar burada bahsedilir." Gerekçe ölçümde: olayların %59'u
// bildirim kademesine giriyor; olay başına push, günde tek proaktif mesaj
// bütçesini (RETENTION_STRATEJISI.md §7) tüketirdi. Pazartesi özeti zaten
// haftada bir konuşuyor; söz o hafta varsa akışa da değinir.
//
// ── Kaynak: `balina_olay` (0106) ────────────────────────────────────────────
// Cümle, fon sayfasındaki "Büyük hareketler" listesiyle AYNI satırlardan
// kurulur — kullanıcı bildirimi açıp karta baktığında aynı günü ve aynı
// tutarı görür. Burada yeni eşik YOK; kural `_shared/balina.ts`'te.
//
// ── Dil (weekly-summary ton kuralları geçerli) ──────────────────────────────
// Durum bildirilir, eylem önerilmez; "balina" denmez; emoji ve uyarı dili
// yok. Kimin alıp sattığı bilinmediği için özne fonun kendisidir.

/// `balina_olay` satırının cümle için gereken alanları.
export type HaftaOlayi = {
  ticker: string;
  tarih: string;
  tutar: number;
  bildirime_deger: boolean;
  /// `balina_olay.tur`. Verilmişse fon cümlesi yalnız `fon_*`, hacim cümlesi
  /// yalnız `*_hacim_*` satırlarını alır (tablo 0107'ten beri karışık).
  tur?: string;
};

/// Bir fonun haftadaki olaylarının toplamı.
export type FonHareketi = {
  kod: string;
  tutar: number;
  bildirimeDeger: boolean;
};

/// Cümlede adıyla anılacak en fazla fon. Üçüncüsü "ve N fon daha" olur:
/// bildirim gövdesi iki satırı geçmesin.
export const ADIYLA_ANILAN_FON = 2;

/// 'TEFAS:TTE' → 'TTE'. Önek yoksa olduğu gibi (hisse/kripto ileride).
export function varlikKodu(ticker: string): string {
  const t = String(ticker ?? '').trim().toUpperCase();
  return t.startsWith('TEFAS:') ? t.slice('TEFAS:'.length) : t;
}

/// Yönlü kısa tutar — uygulamadaki `isaretliTutar` ile AYNI biçim
/// (`+₺412,00M`, `−₺2,28Mr`): bildirim ile kart farklı yazmasın.
export function isaretliTutar(v: number): string {
  const abs = Math.abs(v);
  const tr = (n: number, hane: number) => {
    const [tam, kesir] = n.toFixed(hane).split('.');
    const binlik = tam.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    return hane > 0 ? `${binlik},${kesir}` : binlik;
  };
  let govde: string;
  if (abs >= 1e12) govde = `₺${tr(abs / 1e12, 2)}Tn`;
  else if (abs >= 1e9) govde = `₺${tr(abs / 1e9, 2)}Mr`;
  else if (abs >= 1e6) govde = `₺${tr(abs / 1e6, 2)}M`;
  else if (abs >= 1e3) govde = `₺${tr(abs / 1e3, 1)}K`;
  else govde = `₺${tr(abs, 0)}`;
  if (v > 0) return `+${govde}`;
  if (v < 0) return `−${govde}`;
  return govde;
}

/// Kullanıcının TUTTUĞU fonlardaki hafta olayları, fon başına toplanmış.
///
/// Sıra: önce bildirim kademesindekiler, sonra tutarın büyüklüğü. Hafta
/// içinde girişi ve çıkışı birbirini götüren fon (net sıfır) listeden düşer.
export function fonHareketleri(
  olaylar: HaftaOlayi[],
  tutulan: Set<string>,
): FonHareketi[] {
  const m = new Map<string, FonHareketi>();
  for (const o of olaylar) {
    // Hisse/kripto hacim olayının `tutar`ı para hacmidir, akış DEĞİL; fon
    // cümlesine girerse "para girişi" diye yanlış anlatılırdı.
    if (o.tur !== undefined && !o.tur.startsWith('fon_')) continue;
    const kod = varlikKodu(o.ticker);
    if (!tutulan.has(kod) || !Number.isFinite(o.tutar)) continue;
    const eski = m.get(kod);
    if (eski) {
      eski.tutar += o.tutar;
      eski.bildirimeDeger = eski.bildirimeDeger || o.bildirime_deger;
    } else {
      m.set(kod, { kod, tutar: o.tutar, bildirimeDeger: o.bildirime_deger });
    }
  }
  return [...m.values()]
    .filter((h) => h.tutar !== 0)
    .sort((a, b) =>
      Number(b.bildirimeDeger) - Number(a.bildirimeDeger) ||
      Math.abs(b.tutar) - Math.abs(a.tutar) ||
      a.kod.localeCompare(b.kod)
    );
}

/// Haftalık özetin akış cümlesi; söylenecek bir şey yoksa `null`.
///
///   1 fon : "DOV fonunda geçen hafta büyük para çıkışı oldu (−₺2,28Mr)."
///   2 fon : "Geçen hafta 2 fonunda büyük para hareketi oldu: DOV (çıkış),
///            TTE (giriş)."
///   3+ fon: "Geçen hafta 4 fonunda büyük para hareketi oldu: DOV (çıkış),
///            TTE (giriş) ve 2 fon daha."
export function haftalikAkisCumlesi(hareketler: FonHareketi[]): string | null {
  if (hareketler.length === 0) return null;
  const yon = (h: FonHareketi) => (h.tutar > 0 ? 'giriş' : 'çıkış');

  if (hareketler.length === 1) {
    const h = hareketler[0];
    // İyelik eki ünlü uyumuna göre: giriş-i, çıkış-ı.
    const ekli = h.tutar > 0 ? 'girişi' : 'çıkışı';
    return `${h.kod} fonunda geçen hafta büyük para ${ekli} oldu ` +
      `(${isaretliTutar(h.tutar)}).`;
  }

  const anilan = hareketler.slice(0, ADIYLA_ANILAN_FON)
    .map((h) => `${h.kod} (${yon(h)})`)
    .join(', ');
  const kalan = hareketler.length - ADIYLA_ANILAN_FON;
  const son = kalan > 0 ? ` ve ${kalan} fon daha` : '';
  return `Geçen hafta ${hareketler.length} fonunda büyük para hareketi oldu: ` +
    `${anilan}${son}.`;
}

/// Yüzdesi gönderilemeyen haftada (alım/satım yapılmış, snapshot eksik ya da
/// hareket küçük) yalnız akışı anlatan mesaj. Yüzde YAZILMAZ — o kapıların
/// gerekçesi (yanlış sayı göndermemek) aynen geçerli.
export function yalnizAkisMesaji(cumle: string): { title: string; body: string } {
  return {
    title: 'Haftanın özeti',
    body: `${cumle} Yatırım tavsiyesi değildir.`,
  };
}

/// Yüzdeli haftalık mesajın gövdesine akış cümlesini ekler (başa).
export function govdeyeAkisEkle(govde: string, cumle: string | null): string {
  return cumle === null ? govde : `${cumle} ${govde}`;
}

// ── Hisse / kripto: olağandışı hacim ────────────────────────────────────────
//
// Hacim olayı yön ve tutar taşımaz (bkz. `hacim.ts`): cümle yalnız HANGİ
// varlıklarda görüldüğünü söyler, "giriş/çıkış" demez.

/// `THYAO.IS` → `THYAO`, `KRIPTO:BTC` → `BTC`.
export function hacimVarlikAdi(ticker: string): string {
  const t = String(ticker ?? '').trim().toUpperCase();
  if (t.startsWith('KRIPTO:')) return t.slice('KRIPTO:'.length);
  return t.endsWith('.IS') ? t.slice(0, -3) : t;
}

/// Kullanıcının tuttuğu varlıklardan geçen hafta olağandışı hacim görülenler
/// (ad sırasıyla, tekil). [tutulan] `balina_olay.ticker` biçimindedir.
export function hacimVarliklari(olaylar: HaftaOlayi[], tutulan: Set<string>): string[] {
  const adlar = new Set<string>();
  for (const o of olaylar) {
    if (o.tur === undefined || !o.tur.includes('_hacim_')) continue;
    const t = String(o.ticker ?? '').trim().toUpperCase();
    if (tutulan.has(t)) adlar.add(hacimVarlikAdi(t));
  }
  return [...adlar].sort((a, b) => a.localeCompare(b));
}

///   1 : "Geçen hafta olağandışı hacim görülen varlık: ASTOR."
///   2 : "Geçen hafta olağandışı hacim görülen varlıklar: ASELS, ASTOR."
///   3+: "… varlıklar: ASELS, ASTOR ve 2 varlık daha."
export function hacimCumlesi(adlar: string[]): string | null {
  if (adlar.length === 0) return null;
  if (adlar.length === 1) {
    return `Geçen hafta olağandışı hacim görülen varlık: ${adlar[0]}.`;
  }
  const kalan = adlar.length - ADIYLA_ANILAN_FON;
  const son = kalan > 0 ? ` ve ${kalan} varlık daha` : '';
  return 'Geçen hafta olağandışı hacim görülen varlıklar: ' +
    `${adlar.slice(0, ADIYLA_ANILAN_FON).join(', ')}${son}.`;
}

/// Fon cümlesi ile hacim cümlesini birleştirir; ikisi de yoksa `null`.
export function ozetCumlesi(fon: string | null, hacim: string | null): string | null {
  const parcalar = [fon, hacim].filter((c): c is string => c !== null);
  return parcalar.length === 0 ? null : parcalar.join(' ');
}

/// Hareket satırının sonuna not eki (S19, 2026-10-05): kullanıcının tuttuğu
/// varlıklardan en az birinin bu haftaki yapay zekâ notu YAYINDAYSA "Notların
/// hazır." eklenir. Not yoksa ya da hepsi reddedildiyse cümle aynen kalır:
/// bildirim, açınca bulunamayacak bir şey vaat etmez.
export function notEkiyle(cumle: string, notVar: boolean): string {
  return notVar ? `${cumle} Varlık notların hazır.` : cumle;
}
