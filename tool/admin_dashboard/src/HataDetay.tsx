import { Kopyala, Pill } from './ui';
import { fmtMs, fmtSapma, fmtTs, sapmaCiddi } from './format';

/* Hata künyesi + stack trace — üç yerde kullanılır (kullanıcı log
 * çekmecesi, seans olayı, hata kümesi), bu yüzden tek yerde tanımlı.
 *
 * Stack trace `<pre>` içinde ham gösterilir: kare sırası ve girintiler
 * teşhisin kendisidir, biçimlendirme bozarsa okunmaz. */

export type HataAlanlari = {
  error_type?: string | null;
  error_code?: string | null;
  error_message?: string | null;
  stack_trace?: string | null;
};

/** Hata sınıfına göre ton: ağ hatası ile RLS reddi aynı aciliyette değil. */
export function hataTonu(tip: string | null | undefined): 'err' | 'warn' | 'info' {
  if (!tip) return 'err';
  // Ağ/zaman aşımı: kullanıcının bağlantısı. Bizim kodumuz sağlam olabilir.
  if (/Timeout|Client|Socket|Network|Handshake/i.test(tip)) return 'warn';
  // Auth: beklenen bir red olabilir (yanlış şifre), panikletmesin.
  if (/Auth/i.test(tip)) return 'info';
  return 'err';
}

/** Postgres/PostgREST kodlarının insan dilindeki karşılığı. */
const KOD_ACIKLAMA: Record<string, string> = {
  '42501': 'RLS reddi — politika bu satıra izin vermiyor',
  '23505': 'tekillik ihlali — aynı kayıt zaten var',
  '23503': 'yabancı anahtar — bağlı kayıt yok',
  '23502': 'null olamaz — zorunlu alan boş',
  '42703': 'kolon yok — şema kayması',
  '42P01': 'tablo yok — şema kayması',
  '42883': 'fonksiyon yok — imza uyuşmuyor',
  '42P13': 'dönüş tipi değişmiş — drop gerekiyor',
  PGRST202: 'RPC bulunamadı — migration uygulanmamış veya imza farklı',
  PGRST301: 'JWT geçersiz/süresi dolmuş',
  '401': 'yetkisiz — token yok veya geçersiz',
  '403': 'yasak — yetki yetersiz',
  '429': 'çok fazla istek — rate limit',
};

export function kodAciklamasi(kod: string | null | undefined): string | null {
  if (!kod) return null;
  return KOD_ACIKLAMA[kod] ?? null;
}

/** Hata künyesi: tip, kod, mesaj. Tek satırlık üst bilgi. */
export function HataBasligi({ hata }: { hata: HataAlanlari }) {
  const aciklama = kodAciklamasi(hata.error_code);
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center' }}>
      {hata.error_type ? (
        <Pill tone={hataTonu(hata.error_type)}>{hata.error_type}</Pill>
      ) : null}
      {hata.error_code && hata.error_code !== '—' ? (
        <Pill tone="warn">{hata.error_code}</Pill>
      ) : null}
      {aciklama ? <span className="dim" style={{ fontSize: 12 }}>{aciklama}</span> : null}
    </div>
  );
}

/** Stack trace bloğu. Yoksa neden yok olduğunu söyler. */
export function StackTrace({ stack }: { stack: string | null | undefined }) {
  if (!stack) {
    return (
      <div className="dim" style={{ fontSize: 12 }}>
        Stack trace yok — bu alan uygulamanın yeni sürümüyle dolar
        (<code>DbLogger</code> henüz yazmıyor).
      </div>
    );
  }
  return (
    <>
      <pre className="json" style={{ maxHeight: 400 }}>
        {stack}
      </pre>
      <div style={{ marginTop: 8 }}>
        <Kopyala metin={stack} etiket="stack'i kopyala" />
      </div>
    </>
  );
}

/** Zaman künyesi: üç damga + saat sapması. */
export function ZamanKunyesi({
  ts,
  requested_at,
  responded_at,
  saat_farki_ms,
  duration_ms,
}: {
  ts: string;
  requested_at?: string | null;
  responded_at?: string | null;
  saat_farki_ms?: number | null;
  duration_ms?: number | null;
}) {
  return (
    <dl className="kv">
      <dt>Sunucuya yazıldı</dt>
      <dd>{fmtTs(ts)}</dd>
      <dt>İstek atıldı</dt>
      <dd>{fmtTs(requested_at)}</dd>
      <dt>Yanıt döndü</dt>
      <dd>{fmtTs(responded_at)}</dd>
      <dt title="ts − requested_at. Dakikalar mertebesindeyse cihaz saati şaşmıştır.">
        Saat farkı
      </dt>
      <dd className={sapmaCiddi(saat_farki_ms) ? 'err-text' : ''}>
        {fmtSapma(saat_farki_ms)}
        {sapmaCiddi(saat_farki_ms)
          ? ' — cihaz saati sapmış; OTP/token akışlarında sebep olabilir'
          : ''}
      </dd>
      <dt>Süre</dt>
      <dd>{fmtMs(duration_ms)}</dd>
    </dl>
  );
}
