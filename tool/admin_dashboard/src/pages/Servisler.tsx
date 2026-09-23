import { useMemo, useState } from 'react';
import { useRpc } from '../useRpc';
import type { ErrorCluster, ServiceHealth } from '../types';
import { Card, Empty, Hata, Pill, SaatSecici, Yukleniyor } from '../ui';
import { fmtMs, fmtNum, fmtRelative, fmtTs, kisalt, pct, prettyJson, servisAdi } from '../format';

/* Servis sağlığı — "hangi endpoint bozuk / yavaş".
 *
 * Hata SAYISI ile hata ORANI ayrı sütunlar: 1000 çağrıda 5 hata normal,
 * 6 çağrıda 5 hata felakettir. Sıralama varsayılanı hata sayısı, çünkü
 * "bugün ne oldu" sorusu önce hacmi sorar; oranla sıralama tek tıkla. */

type Siralama = 'errors' | 'rate' | 'p95' | 'calls';

export default function Servisler({
  saat,
  saatAyarla,
}: {
  saat: number;
  saatAyarla: (v: number) => void;
}) {
  const [sirala, setSirala] = useState<Siralama>('errors');
  const [filtre, setFiltre] = useState('');
  const [secili, setSecili] = useState<ServiceHealth | null>(null);

  const saglik = useRpc<ServiceHealth[]>('admin_service_health', { p_hours: saat });

  const satirlar = useMemo(() => {
    const d = (saglik.data ?? []).filter(
      (r) =>
        !filtre ||
        r.source.toLowerCase().includes(filtre.toLowerCase()) ||
        r.table_name.toLowerCase().includes(filtre.toLowerCase()),
    );
    const kopya = [...d];
    kopya.sort((a, b) => {
      switch (sirala) {
        case 'rate':
          return Number(b.error_rate ?? 0) - Number(a.error_rate ?? 0);
        case 'p95':
          return b.p95_ms - a.p95_ms;
        case 'calls':
          return b.calls - a.calls;
        default:
          return b.errors - a.errors || b.calls - a.calls;
      }
    });
    return kopya;
  }, [saglik.data, sirala, filtre]);

  // Servis bazında toplama: tek tek endpoint'ten önce "hangi katman".
  const servisOzet = useMemo(() => {
    const m = new Map<string, { calls: number; errors: number; p95: number }>();
    for (const r of saglik.data ?? []) {
      const ad = servisAdi(r.source);
      const v = m.get(ad) ?? { calls: 0, errors: 0, p95: 0 };
      v.calls += Number(r.calls);
      v.errors += Number(r.errors);
      v.p95 = Math.max(v.p95, r.p95_ms);
      m.set(ad, v);
    }
    return [...m.entries()]
      .map(([ad, v]) => ({ ad, ...v }))
      .sort((a, b) => b.errors - a.errors || b.calls - a.calls);
  }, [saglik.data]);

  return (
    <>
      <div className="topbar">
        <h1>Servisler</h1>
        <Yukleniyor görünür={saglik.loading} />
        <span className="spacer" />
        <input
          className="input"
          style={{ width: 220 }}
          placeholder="servis / tablo filtresi…"
          value={filtre}
          onChange={(e) => setFiltre(e.target.value)}
        />
        <div className="seg">
          {(
            [
              ['errors', 'hata'],
              ['rate', 'oran'],
              ['p95', 'p95'],
              ['calls', 'hacim'],
            ] as const
          ).map(([v, l]) => (
            <button key={v} className={sirala === v ? 'on' : ''} onClick={() => setSirala(v)}>
              {l}
            </button>
          ))}
        </div>
        <SaatSecici deger={saat} ayarla={saatAyarla} />
      </div>

      <Hata mesaj={saglik.error} />

      {servisOzet.length > 0 && (
        <Card title="Katman özeti">
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {servisOzet.map((s) => (
              <button
                key={s.ad}
                className="btn sm"
                onClick={() => setFiltre(s.ad)}
                title={`${fmtNum(s.calls)} çağrı · p95 ${fmtMs(s.p95)}`}
              >
                <span className="mono">{s.ad}</span>{' '}
                {s.errors > 0 ? (
                  <span className="err-text">{fmtNum(s.errors)}</span>
                ) : (
                  <span className="dim">0</span>
                )}
              </button>
            ))}
          </div>
        </Card>
      )}

      <div className="section-gap">
        <Card
          title="Endpoint sağlığı"
          action={
            <span className="dim mono" style={{ fontSize: 11 }}>
              {fmtNum(satirlar.length)} satır
            </span>
          }
        >
          {satirlar.length === 0 ? (
            <Empty>Kayıt yok.</Empty>
          ) : (
            <div className="scroll tall">
              <table>
                <thead>
                  <tr>
                    <th>Servis</th>
                    <th>Hedef</th>
                    <th className="num">Çağrı</th>
                    <th className="num">Hata</th>
                    <th className="num">Oran</th>
                    <th className="num">p50</th>
                    <th className="num">p95</th>
                    <th className="num">Maks</th>
                    <th className="num">Kişi</th>
                    <th className="nowrap">Son</th>
                  </tr>
                </thead>
                <tbody>
                  {satirlar.map((r, i) => (
                    <tr
                      key={i}
                      className={`clickable${secili === r ? ' sel' : ''}`}
                      onClick={() => setSecili(secili === r ? null : r)}
                    >
                      <td className="mono nowrap">{r.source}</td>
                      <td className="mono nowrap">{r.table_name}</td>
                      <td className="num">{fmtNum(r.calls)}</td>
                      <td className={`num${r.errors > 0 ? ' err-text' : ' dim'}`}>
                        {fmtNum(r.errors)}
                      </td>
                      <td className="num">
                        {Number(r.error_rate ?? 0) > 0 ? (
                          <Pill tone={Number(r.error_rate) >= 25 ? 'err' : 'warn'}>
                            {pct(r.error_rate)}
                          </Pill>
                        ) : (
                          <span className="dim">—</span>
                        )}
                      </td>
                      <td className="num dim">{fmtMs(r.p50_ms)}</td>
                      <td className={`num${r.p95_ms > 3000 ? ' err-text' : ''}`}>
                        {fmtMs(r.p95_ms)}
                      </td>
                      <td className="num dim">{fmtMs(r.max_ms)}</td>
                      <td className="num dim">{fmtNum(r.users)}</td>
                      <td className="nowrap dim">{fmtRelative(r.last_seen)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>

      {secili && <EndpointHatalari satir={secili} saat={saat} />}
    </>
  );
}

/* Seçilen endpoint'in hata kümeleri. Ayrı bir RPC çağırmak yerine genel
 * küme sorgusunu çekip istemcide daraltmak, tek ekstra ağ turu yerine
 * her seçimde yeni tur demek olurdu — burada sunucuda filtrelemek daha
 * doğru ama `admin_error_clusters` zaten küçük bir sonuç döndürüyor
 * (limit 200) ve seçim sık değişiyor; istemcide filtreleme yeterli. */
function EndpointHatalari({ satir, saat }: { satir: ServiceHealth; saat: number }) {
  const kume = useRpc<ErrorCluster[]>('admin_error_clusters', {
    p_hours: saat,
    p_limit: 200,
  });

  const kendi = (kume.data ?? []).filter(
    (c) => c.source === satir.source && c.table_name === satir.table_name,
  );

  return (
    <div className="section-gap">
      <Card
        title={`${satir.source} → ${satir.table_name} · hata kırılımı`}
        action={<Yukleniyor görünür={kume.loading} />}
      >
        <Hata mesaj={kume.error} />
        {kendi.length === 0 ? (
          <Empty>Bu endpoint'te kayıtlı hata yok.</Empty>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Op</th>
                <th className="wrapcell">Hata</th>
                <th className="num">Adet</th>
                <th className="num">Kişi</th>
                <th className="num">p95</th>
                <th className="nowrap">İlk</th>
                <th className="nowrap">Son</th>
              </tr>
            </thead>
            <tbody>
              {kendi.map((c, i) => (
                <tr key={i}>
                  <td>
                    <Pill>{c.op}</Pill>
                  </td>
                  <td className="wrapcell err-text mono">{c.error_text}</td>
                  <td className="num">{fmtNum(c.hits)}</td>
                  <td className="num">{fmtNum(c.affected_users)}</td>
                  <td className="num dim">{fmtMs(c.p95_ms)}</td>
                  <td className="nowrap dim" title={fmtTs(c.first_seen)}>
                    {fmtRelative(c.first_seen)}
                  </td>
                  <td className="nowrap" title={fmtTs(c.last_seen)}>
                    {fmtRelative(c.last_seen)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {kendi[0]?.sample_request ? (
          <>
            <div className="dim" style={{ margin: '16px 0 8px' }}>
              Örnek istek gövdesi
            </div>
            <pre className="json">{kisalt(prettyJson(kendi[0].sample_request), 2000)}</pre>
          </>
        ) : null}
      </Card>
    </div>
  );
}
