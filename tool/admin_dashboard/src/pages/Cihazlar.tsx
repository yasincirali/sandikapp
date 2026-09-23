import { useState } from 'react';
import { useRpc } from '../useRpc';
import type { DeviceRow, VersionHealth } from '../types';
import { Card, Empty, Hata, Kopyala, Pill, SaatSecici, Stat, Yukleniyor } from '../ui';
import { fmtMs, fmtNum, fmtRelative, fmtTs, kisaKimlik, pct } from '../format';

/* Cihaz ve sürüm takibi.
 *
 * İki soru, iki blok:
 *   · Sürüm sağlığı → "yeni sürümde hata arttı mı" (rollout kararı)
 *   · Cihaz envanteri → "bu telefonda ne oluyor, kim kullanıyor"
 *
 * `kullanici > 1` olan cihaz özellikle işaretlenir: aynı telefonda hesap
 * değişimi demektir ve push token devralma gibi sorunların ilk ipucudur. */

export default function Cihazlar({
  saat,
  saatAyarla,
  kullaniciyaGit,
}: {
  saat: number;
  saatAyarla: (v: number) => void;
  kullaniciyaGit: (q: string) => void;
}) {
  const [q, setQ] = useState('');
  const [aranan, setAranan] = useState('');

  const cihazlar = useRpc<DeviceRow[]>('admin_devices', {
    p_hours: saat,
    p_q: aranan || null,
    p_limit: 200,
  });

  const surumler = useRpc<VersionHealth[]>('admin_version_health', {
    p_hours: saat,
  });

  const paylasilan = (cihazlar.data ?? []).filter((c) => c.kullanici > 1).length;
  const toplamCihaz = cihazlar.data?.length ?? 0;
  const hataliCihaz = (cihazlar.data ?? []).filter((c) => c.hata > 0).length;

  return (
    <>
      <div className="topbar">
        <h1>Cihazlar ve sürümler</h1>
        <Yukleniyor görünür={cihazlar.loading || surumler.loading} />
        <span className="spacer" />
        <form
          onSubmit={(e) => {
            e.preventDefault();
            setAranan(q);
          }}
          style={{ display: 'flex', gap: 8 }}
        >
          <input
            className="input"
            style={{ width: 260 }}
            placeholder="cihaz id, sürüm, platform, model, e-posta…"
            value={q}
            onChange={(e) => setQ(e.target.value)}
          />
          <button className="btn" type="submit">
            Ara
          </button>
        </form>
        <SaatSecici deger={saat} ayarla={saatAyarla} />
      </div>

      <Hata mesaj={cihazlar.error ?? surumler.error} />

      <div className="banner warn">
        Cihaz ve sürüm alanları <b>migration 0071</b> ile açıldı; uygulama
        tarafı (<code>DbLogger</code>) henüz doldurmuyor. O sürüm yayınlanana
        kadar buradaki satırlar <b>(bilinmiyor)</b> olarak görünür.
      </div>

      <div className="grid cols-4">
        <Stat label="Cihaz" value={fmtNum(toplamCihaz)} sub={`son ${saat} saat`} />
        <Stat
          label="Hatalı cihaz"
          value={fmtNum(hataliCihaz)}
          sub="en az bir hata"
          tone={hataliCihaz > 0 ? 'bad' : 'good'}
        />
        <Stat
          label="Paylaşılan cihaz"
          value={fmtNum(paylasilan)}
          sub="birden çok hesap"
          tone={paylasilan > 0 ? 'warn' : undefined}
        />
        <Stat
          label="Sürüm"
          value={fmtNum(surumler.data?.length ?? 0)}
          sub="platform × sürüm"
        />
      </div>

      {/* ── Sürüm sağlığı ────────────────────────────────────────────── */}
      <div className="section-gap">
        <Card title="Sürüm sağlığı">
          {!surumler.data || surumler.data.length === 0 ? (
            <Empty>Kayıt yok.</Empty>
          ) : (
            <div className="scroll">
              <table>
                <thead>
                  <tr>
                    <th>Uygulama</th>
                    <th>Platform</th>
                    <th>OS</th>
                    <th className="num">Cihaz</th>
                    <th className="num">Kişi</th>
                    <th className="num">Olay</th>
                    <th className="num">Hata</th>
                    <th className="num">Oran</th>
                    <th className="num">p95</th>
                    <th className="nowrap">Son</th>
                  </tr>
                </thead>
                <tbody>
                  {surumler.data.map((v, i) => (
                    <tr key={i}>
                      <td className="mono nowrap">{v.app_version}</td>
                      <td>
                        <Pill tone={v.platform === 'ios' ? 'info' : undefined}>
                          {v.platform}
                        </Pill>
                      </td>
                      <td className="mono dim nowrap">{v.os_version}</td>
                      <td className="num">{fmtNum(v.cihaz)}</td>
                      <td className="num">{fmtNum(v.kullanici)}</td>
                      <td className="num dim">{fmtNum(v.olay)}</td>
                      <td className={`num${v.hata > 0 ? ' err-text' : ' dim'}`}>
                        {fmtNum(v.hata)}
                      </td>
                      <td className="num">
                        {Number(v.hata_orani ?? 0) > 0 ? (
                          <Pill tone={Number(v.hata_orani) >= 25 ? 'err' : 'warn'}>
                            {pct(v.hata_orani)}
                          </Pill>
                        ) : (
                          <span className="dim">—</span>
                        )}
                      </td>
                      <td className={`num${v.p95_ms > 3000 ? ' err-text' : ' dim'}`}>
                        {fmtMs(v.p95_ms)}
                      </td>
                      <td className="nowrap dim">{fmtRelative(v.son_gorulme)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>

      {/* ── Cihaz envanteri ──────────────────────────────────────────── */}
      <div className="section-gap">
        <Card
          title="Cihaz envanteri"
          action={
            <span className="dim mono" style={{ fontSize: 11 }}>
              {fmtNum(toplamCihaz)} cihaz
            </span>
          }
        >
          {!cihazlar.data || cihazlar.data.length === 0 ? (
            <Empty>Cihaz kaydı yok.</Empty>
          ) : (
            <div className="scroll tall">
              <table>
                <thead>
                  <tr>
                    <th>Cihaz</th>
                    <th>Platform / OS</th>
                    <th>Sürüm</th>
                    <th>Model</th>
                    <th className="num">Kişi</th>
                    <th className="wrapcell">Hesaplar</th>
                    <th className="num">Seans</th>
                    <th className="num">Olay</th>
                    <th className="num">Hata</th>
                    <th className="nowrap">Son</th>
                  </tr>
                </thead>
                <tbody>
                  {cihazlar.data.map((c) => (
                    <tr key={c.device_id}>
                      <td className="mono nowrap" title={c.device_id}>
                        {kisaKimlik(c.device_id)}{' '}
                        <Kopyala metin={c.device_id} etiket="⧉" />
                      </td>
                      <td className="mono nowrap dim">
                        {c.platform ?? '—'} {c.os_version ?? ''}
                      </td>
                      <td className="mono nowrap">{c.app_version ?? '—'}</td>
                      <td className="mono nowrap dim">{c.device_model ?? '—'}</td>
                      <td className="num">
                        {c.kullanici > 1 ? (
                          <Pill tone="warn">{fmtNum(c.kullanici)}</Pill>
                        ) : (
                          fmtNum(c.kullanici)
                        )}
                      </td>
                      <td className="wrapcell mono" style={{ fontSize: 11 }}>
                        {c.emailler ? (
                          c.emailler.split(', ').map((e) => (
                            <button
                              key={e}
                              className="btn sm ghost mono"
                              style={{ fontSize: 11 }}
                              onClick={() => kullaniciyaGit(e)}
                            >
                              {e}
                            </button>
                          ))
                        ) : (
                          <span className="dim">—</span>
                        )}
                      </td>
                      <td className="num dim">{fmtNum(c.seans)}</td>
                      <td className="num dim">{fmtNum(c.olay)}</td>
                      <td className={`num${c.hata > 0 ? ' err-text' : ' dim'}`}>
                        {fmtNum(c.hata)}
                      </td>
                      <td
                        className="nowrap dim"
                        title={`ilk: ${fmtTs(c.ilk_gorulme)}`}
                      >
                        {fmtRelative(c.son_gorulme)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {paylasilan > 0 && (
            <div className="banner warn" style={{ marginTop: 12, marginBottom: 0 }}>
              <b>{fmtNum(paylasilan)} cihazda birden çok hesap görüldü.</b> Aynı
              telefonda hesap değişimi push token devralma sorununa yol açabilir
              (migration 0069, <code>claim_push_token</code>). Kişi sütunundaki
              sayıya tıklayıp hesapları karşılaştır.
            </div>
          )}
        </Card>
      </div>

    </>
  );
}
