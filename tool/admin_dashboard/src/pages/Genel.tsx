import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { useRpc, useOtomatikYenile } from '../useRpc';
import type { ErrorCluster, Overview, TimelinePoint } from '../types';
import { Card, Hata, Pill, SaatSecici, Stat, Yukleniyor, Empty } from '../ui';
import { fmtHour, fmtNum, fmtRelative, fmtTs, kisalt } from '../format';
import { HataBasligi } from '../HataDetay';

/* Panelin ilk ekranı: "şu an her şey yolunda mı".
 *
 * Sıralama kasıtlı — önce sayılar (bir bakışta), sonra eğri (ne zaman
 * başladı), sonra kümeler (ne bozuk). Şikayet gelmeden önce buradan
 * görülmesi hedeflenir. */

export default function Genel({
  saat,
  saatAyarla,
  kullaniciyaGit,
}: {
  saat: number;
  saatAyarla: (v: number) => void;
  kullaniciyaGit: (q: string) => void;
}) {
  const ozet = useRpc<Overview>('admin_overview', { p_hours: saat });
  const seri = useRpc<TimelinePoint[]>('admin_error_timeline', {
    p_hours: Math.max(saat, 24),
  });
  const kume = useRpc<ErrorCluster[]>('admin_error_clusters', {
    p_hours: saat,
    p_limit: 12,
  });

  // 60 sn: canlı takip için yeterince sık, RPC'leri yormayacak kadar seyrek.
  useOtomatikYenile(() => {
    ozet.yenile();
    seri.yenile();
    kume.yenile();
  }, 60);

  const o = ozet.data;
  const hataOrani = o && o.istek > 0 ? (100 * o.hata) / o.istek : 0;

  return (
    <>
      <div className="topbar">
        <h1>Genel durum</h1>
        <Yukleniyor görünür={ozet.loading || seri.loading || kume.loading} />
        <span className="spacer" />
        <span className="dim mono" style={{ fontSize: 11 }}>
          60 sn'de bir yenilenir
        </span>
        <SaatSecici deger={saat} ayarla={saatAyarla} />
      </div>

      <Hata mesaj={ozet.error ?? seri.error ?? kume.error} />

      {/* db_logs release'te yalnızca HATALARI yazar (DbLogger._persistAsync).
          Bu not olmadan "istek sayısı neden bu kadar düşük" diye yanlış
          okunur — panelin en kolay yanlış anlaşılan yeri. */}
      <div className="banner warn">
        Üretim yapılarında <code>db_logs</code> yalnızca <b>hatalı</b> istekleri yazar
        (KVKK kararı, <code>DbLogger._persistAsync</code>). "İstek" sayısı debug
        yapılarından gelen trafiği de içerir; hata oranını mutlak doğru kabul etme —
        <b> hata sayısı</b> ve <b>etkilenen kullanıcı</b> gerçek sinyaldir.
      </div>

      <div className="grid cols-6">
        <Stat
          label="Hata"
          value={fmtNum(o?.hata ?? 0)}
          sub={`${fmtNum(o?.hatali_kullanici ?? 0)} kullanıcı`}
          tone={(o?.hata ?? 0) > 0 ? 'bad' : 'good'}
        />
        <Stat
          label="Auth hatası"
          value={fmtNum(o?.auth_hata ?? 0)}
          sub="giriş / OTP / şifre"
          tone={(o?.auth_hata ?? 0) > 0 ? 'warn' : undefined}
        />
        <Stat
          label="Kilitli"
          value={fmtNum(o?.kilitli_subject ?? 0)}
          sub="rate limit, 10 dk"
          tone={(o?.kilitli_subject ?? 0) > 0 ? 'warn' : undefined}
        />
        <Stat
          label="Yavaş istek"
          value={fmtNum(o?.yavas_istek ?? 0)}
          sub="&gt; 3 sn"
          tone={(o?.yavas_istek ?? 0) > 0 ? 'warn' : undefined}
        />
        <Stat
          label="Aktif kullanıcı"
          value={fmtNum(o?.aktif_kullanici ?? 0)}
          sub={`${fmtNum(o?.toplam_kullanici ?? 0)} toplam`}
        />
        <Stat
          label="Yeni kayıt"
          value={fmtNum(o?.yeni_kullanici ?? 0)}
          sub={`son ${saat} saat`}
        />
      </div>

      <div className="section-gap">
        <Card
          title="İstek ve hata eğrisi"
          action={
            <span className="dim mono" style={{ fontSize: 11 }}>
              saatlik kova · son log {fmtRelative(o?.son_log)}
            </span>
          }
        >
          {!seri.data || seri.data.length === 0 ? (
            <Empty>Bu aralıkta kayıt yok.</Empty>
          ) : (
            <div style={{ height: 220 }}>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={seri.data} margin={{ top: 8, right: 8, left: -18, bottom: 0 }}>
                  <defs>
                    <linearGradient id="gHata" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#ff6b52" stopOpacity={0.5} />
                      <stop offset="100%" stopColor="#ff6b52" stopOpacity={0.04} />
                    </linearGradient>
                    <linearGradient id="gIstek" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#4ea8de" stopOpacity={0.28} />
                      <stop offset="100%" stopColor="#4ea8de" stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid stroke="rgba(255,255,255,0.06)" vertical={false} />
                  <XAxis
                    dataKey="kova"
                    tickFormatter={fmtHour}
                    stroke="rgba(255,255,255,0.35)"
                    fontSize={11}
                    tickLine={false}
                    minTickGap={28}
                  />
                  <YAxis
                    stroke="rgba(255,255,255,0.35)"
                    fontSize={11}
                    tickLine={false}
                    axisLine={false}
                    allowDecimals={false}
                  />
                  <Tooltip
                    contentStyle={{
                      background: '#112e28',
                      border: '1px solid rgba(255,255,255,0.1)',
                      borderRadius: 12,
                      fontSize: 12,
                    }}
                    labelFormatter={(v) => fmtTs(String(v))}
                  />
                  <Legend wrapperStyle={{ fontSize: 11 }} />
                  <Area
                    type="monotone"
                    dataKey="istek"
                    name="istek"
                    stroke="#4ea8de"
                    fill="url(#gIstek)"
                    strokeWidth={1.5}
                  />
                  <Area
                    type="monotone"
                    dataKey="hata"
                    name="hata"
                    stroke="#ff6b52"
                    fill="url(#gHata)"
                    strokeWidth={2}
                  />
                  <Area
                    type="monotone"
                    dataKey="auth_hata"
                    name="auth hatası"
                    stroke="#f5a623"
                    fill="none"
                    strokeWidth={1.5}
                    strokeDasharray="4 3"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          )}
        </Card>
      </div>

      <div className="section-gap">
        <Card
          title="En çok tekrarlayan hatalar"
          action={
            <span className="dim mono" style={{ fontSize: 11 }}>
              genel hata oranı %{hataOrani.toFixed(1)}
            </span>
          }
        >
          {!kume.data || kume.data.length === 0 ? (
            <Empty>Bu aralıkta hata yok. 🎉</Empty>
          ) : (
            <div className="scroll">
              <table>
                <thead>
                  <tr>
                    <th>Tip / kod</th>
                    <th>Servis</th>
                    <th className="wrapcell">Hata</th>
                    <th className="num">Adet</th>
                    <th className="num">Kişi</th>
                    <th>Sürüm</th>
                    <th className="nowrap">Son</th>
                  </tr>
                </thead>
                <tbody>
                  {kume.data.map((c, i) => (
                    <tr key={i}>
                      <td className="nowrap">
                        <HataBasligi hata={{ error_type: c.error_type, error_code: c.error_code }} />
                      </td>
                      <td className="mono nowrap">
                        {c.source}
                        <div className="dim" style={{ fontSize: 11 }}>
                          {c.table_name} {c.op}
                        </div>
                      </td>
                      <td className="wrapcell err-text mono" title={c.error_text}>
                        {kisalt(c.error_text, 110)}
                      </td>
                      <td className="num">{fmtNum(c.hits)}</td>
                      <td className="num">
                        {c.affected_users > 1 ? (
                          <button
                            className="btn sm ghost"
                            onClick={() => kullaniciyaGit('')}
                            title="Kullanıcılar sekmesinde ara"
                          >
                            {fmtNum(c.affected_users)}
                          </button>
                        ) : (
                          fmtNum(c.affected_users)
                        )}
                      </td>
                      <td className="mono nowrap dim" style={{ fontSize: 11 }}>
                        {c.surumler || '—'}
                      </td>
                      <td className="nowrap dim">
                        <Pill tone="err">{fmtRelative(c.last_seen)}</Pill>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>
    </>
  );
}
