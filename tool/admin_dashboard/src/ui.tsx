import type { ReactNode } from 'react';

/* Panelin ortak parçaları. Uygulamadaki SandikCard / SandikSectionHeader
 * ile aynı rol: her ekranda kart ve başlık yeniden yazılmasın. */

export function Card({
  title,
  children,
  action,
}: {
  title?: string;
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="card">
      {(title || action) && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          {title && <h2 style={{ flex: 1 }}>{title}</h2>}
          {action}
        </div>
      )}
      {children}
    </div>
  );
}

export function Stat({
  label,
  value,
  sub,
  tone,
}: {
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  tone?: 'good' | 'warn' | 'bad';
}) {
  return (
    <div className={`card stat${tone ? ` ${tone}` : ''}`}>
      <div className="label">{label}</div>
      <div className="value">{value}</div>
      {sub ? <div className="sub">{sub}</div> : null}
    </div>
  );
}

export function Pill({
  children,
  tone,
}: {
  children: ReactNode;
  tone?: 'err' | 'ok' | 'warn' | 'info';
}) {
  return <span className={`pill${tone ? ` ${tone}` : ''}`}>{children}</span>;
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="empty">{children}</div>;
}

export function Hata({ mesaj }: { mesaj: string | null }) {
  if (!mesaj) return null;
  return <div className="banner err">{mesaj}</div>;
}

export function Yukleniyor({ görünür }: { görünür: boolean }) {
  if (!görünür) return null;
  return <span className="spin" aria-label="yükleniyor" />;
}

/** Zaman aralığı seçici — her ekranda aynı değerler kullanılsın. */
export const SAAT_SECENEKLERI = [
  { v: 1, l: '1s' },
  { v: 6, l: '6s' },
  { v: 24, l: '24s' },
  { v: 72, l: '3g' },
  { v: 168, l: '7g' },
  { v: 720, l: '30g' },
] as const;

export function SaatSecici({
  deger,
  ayarla,
}: {
  deger: number;
  ayarla: (v: number) => void;
}) {
  return (
    <div className="seg" role="group" aria-label="Zaman aralığı">
      {SAAT_SECENEKLERI.map((o) => (
        <button
          key={o.v}
          className={deger === o.v ? 'on' : ''}
          onClick={() => ayarla(o.v)}
          type="button"
        >
          {o.l}
        </button>
      ))}
    </div>
  );
}

/** Panoya kopyala — destek yanıtına user_id yapıştırmak en sık iş. */
export function Kopyala({ metin, etiket }: { metin: string; etiket?: string }) {
  return (
    <button
      type="button"
      className="btn sm ghost"
      title={metin}
      onClick={() => void navigator.clipboard.writeText(metin)}
    >
      {etiket ?? 'kopyala'}
    </button>
  );
}
