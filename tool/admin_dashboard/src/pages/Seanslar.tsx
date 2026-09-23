import { useState } from 'react';
import { useRpc } from '../useRpc';
import type { SessionEvent, SessionRow } from '../types';
import { Card, Empty, Hata, Kopyala, Pill, SaatSecici, Yukleniyor } from '../ui';
import {
  cihazKunye,
  fmtBosluk,
  fmtMs,
  fmtNum,
  fmtRelative,
  fmtSure,
  fmtTs,
  kisaKimlik,
  kisalt,
  prettyJson,
} from '../format';
import { HataBasligi, StackTrace, ZamanKunyesi } from '../HataDetay';

/* Seans takibi — "bu açılışta ne oldu".
 *
 * Liste (kim, ne zaman, kaç olay, hangi cihaz) → seçince zaman çizelgesi.
 * Çizelge sıralaması ARTAN: bir seansı okumak baştan sona yapılır, log
 * listesinin aksine. Aradaki boşluk sütunu davranışı okutur — 40 sn'lik
 * bir boşluk "kullanıcı düşündü", 0.2 sn "otomatik yeniden deneme". */

export default function Seanslar({
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
  const [sadeceHatali, setSadeceHatali] = useState(false);
  const [secili, setSecili] = useState<SessionRow | null>(null);

  const liste = useRpc<SessionRow[]>('admin_sessions', {
    p_q: aranan || null,
    p_hours: saat,
    p_only_errors: sadeceHatali,
    p_limit: 150,
  });

  return (
    <>
      <div className="topbar">
        <h1>Seanslar</h1>
        <Yukleniyor görünür={liste.loading} />
        <span className="spacer" />
        <label className="check">
          <input
            type="checkbox"
            checked={sadeceHatali}
            onChange={(e) => setSadeceHatali(e.target.checked)}
          />
          yalnız hatalı seanslar
        </label>
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
            placeholder="e-posta, isim, seans, cihaz, sürüm…"
            value={q}
            onChange={(e) => setQ(e.target.value)}
          />
          <button className="btn" type="submit">
            Ara
          </button>
        </form>
        <SaatSecici deger={saat} ayarla={saatAyarla} />
      </div>

      <Hata mesaj={liste.error} />

      <SeansUyarisi />

      <Card
        title={aranan ? `"${aranan}" için seanslar` : 'Son seanslar'}
        action={
          <span className="dim mono" style={{ fontSize: 11 }}>
            {fmtNum(liste.data?.length ?? 0)} seans
          </span>
        }
      >
        {!liste.data || liste.data.length === 0 ? (
          <Empty>
            {liste.loading
              ? 'Yükleniyor…'
              : 'Seans kaydı yok. Seans kimliği uygulamanın yeni sürümüyle yazılmaya başlar.'}
          </Empty>
        ) : (
          <div className="scroll">
            <table>
              <thead>
                <tr>
                  <th>Seans</th>
                  <th>Kullanıcı</th>
                  <th className="nowrap">Başlangıç</th>
                  <th className="num">Süre</th>
                  <th className="num">Olay</th>
                  <th className="num">Hata</th>
                  <th>Cihaz</th>
                  <th className="wrapcell">Son hata</th>
                </tr>
              </thead>
              <tbody>
                {liste.data.map((s) => (
                  <tr
                    key={s.session_id}
                    className={`clickable${secili?.session_id === s.session_id ? ' sel' : ''}`}
                    onClick={() => setSecili(s)}
                  >
                    <td className="mono nowrap" title={s.session_id}>
                      {kisaKimlik(s.session_id)}
                    </td>
                    <td>
                      {s.email ? (
                        <button
                          className="btn sm ghost mono"
                          onClick={(e) => {
                            e.stopPropagation();
                            kullaniciyaGit(s.email!);
                          }}
                        >
                          {s.email}
                        </button>
                      ) : (
                        <span className="dim">oturumsuz</span>
                      )}
                    </td>
                    <td className="nowrap dim" title={fmtTs(s.baslangic)}>
                      {fmtRelative(s.baslangic)}
                    </td>
                    <td className="num">{fmtSure(s.sure_sn)}</td>
                    <td className="num">{fmtNum(s.olay)}</td>
                    <td className={`num${s.hata > 0 ? ' err-text' : ' dim'}`}>
                      {fmtNum(s.hata)}
                    </td>
                    <td className="mono nowrap dim" title={s.device_id ?? ''}>
                      {cihazKunye(s)}
                    </td>
                    <td className="wrapcell err-text mono" title={s.son_hata ?? ''}>
                      {kisalt(s.son_hata, 70)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {secili && (
        <SeansCizelgesi seans={secili} kapat={() => setSecili(null)} />
      )}
    </>
  );
}

/* Seans kimliği henüz istemci tarafından yazılmıyor: kullanıcı boş
 * listeye bakıp "bozuk mu" diye düşünmesin. */
function SeansUyarisi() {
  return (
    <div className="banner warn">
      Seans ve cihaz alanları <b>migration 0071</b> ile açıldı ama uygulama
      tarafı (<code>DbLogger</code>) henüz doldurmuyor — bu ayrı bir turda
      yapılacak. O sürüm yayınlanana kadar bu ekran yalnızca{' '}
      <b>(seanssız — eski sürüm)</b> kayıtlarını görür.
    </div>
  );
}

/* ── Seçilen seansın zaman çizelgesi ─────────────────────────────────── */

function SeansCizelgesi({
  seans,
  kapat,
}: {
  seans: SessionRow;
  kapat: () => void;
}) {
  const [acik, setAcik] = useState<SessionEvent | null>(null);

  const olaylar = useRpc<SessionEvent[]>('admin_session_timeline', {
    p_session_id: seans.session_id,
    p_limit: 500,
  });

  return (
    <div className="section-gap">
      <Card
        title={`Seans çizelgesi · ${kisaKimlik(seans.session_id)}`}
        action={
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <Yukleniyor görünür={olaylar.loading} />
            <span className="dim mono" style={{ fontSize: 11 }}>
              {fmtTs(seans.baslangic)} → {fmtTs(seans.bitis)} ·{' '}
              {fmtSure(seans.sure_sn)}
            </span>
            <Kopyala metin={seans.session_id} etiket="seans id" />
            {seans.device_id ? (
              <Kopyala metin={seans.device_id} etiket="cihaz id" />
            ) : null}
            <button className="btn sm ghost" onClick={kapat}>
              kapat
            </button>
          </div>
        }
      >
        <Hata mesaj={olaylar.error} />

        <div className="grid cols-4" style={{ marginBottom: 12 }}>
          <KucukKutu etiket="Kullanıcı" deger={seans.email ?? 'oturumsuz'} />
          <KucukKutu etiket="Cihaz" deger={cihazKunye(seans)} />
          <KucukKutu etiket="Olay" deger={fmtNum(seans.olay)} />
          <KucukKutu
            etiket="Hata"
            deger={fmtNum(seans.hata)}
            tone={seans.hata > 0 ? 'bad' : undefined}
          />
        </div>

        {!olaylar.data || olaylar.data.length === 0 ? (
          <Empty>Bu seansta olay yok.</Empty>
        ) : (
          <div className="scroll tall">
            <table>
              <thead>
                <tr>
                  <th className="nowrap">Saat</th>
                  <th className="num" title="Bir önceki olaydan bu yana">
                    Boşluk
                  </th>
                  <th>Tür</th>
                  <th>Servis</th>
                  <th>Hedef</th>
                  <th className="num">Süre</th>
                  <th className="nowrap" title="İstek atıldı → yanıt döndü">
                    İstek → Yanıt
                  </th>
                  <th className="wrapcell">Sonuç</th>
                </tr>
              </thead>
              <tbody>
                {olaylar.data.map((o) => (
                  <tr key={o.id} className="clickable" onClick={() => setAcik(o)}>
                    <td className="nowrap mono dim" title={fmtTs(o.ts)}>
                      {new Date(o.ts).toLocaleTimeString('tr-TR', {
                        timeZone: 'Europe/Istanbul',
                      })}
                    </td>
                    <td className="num dim">{fmtBosluk(o.onceki_bosluk_sn)}</td>
                    <td>
                      <Pill tone={o.event_kind === 'auth' ? 'info' : undefined}>
                        {o.event_kind ?? 'db'}
                      </Pill>
                    </td>
                    <td className="mono nowrap">{o.source}</td>
                    <td className="mono nowrap">{o.table_name}</td>
                    <td className={`num${o.duration_ms > 3000 ? ' err-text' : ''}`}>
                      {fmtMs(o.duration_ms)}
                    </td>
                    <td className="nowrap mono dim" style={{ fontSize: 11 }}>
                      {o.requested_at ? (
                        <>
                          {saatSadece(o.requested_at)}
                          {' → '}
                          {o.responded_at ? saatSadece(o.responded_at) : '?'}
                        </>
                      ) : (
                        '—'
                      )}
                    </td>
                    <td className="wrapcell">
                      {o.is_error ? (
                        <span className="err-text mono">
                          {kisalt(ozetle(o.response_json), 80)}
                        </span>
                      ) : (
                        <span className="dim mono">
                          {kisalt(ozetle(o.response_json), 50)}
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {acik && <OlayCekmecesi olay={acik} kapat={() => setAcik(null)} />}
    </div>
  );
}

function KucukKutu({
  etiket,
  deger,
  tone,
}: {
  etiket: string;
  deger: string;
  tone?: 'bad';
}) {
  return (
    <div>
      <div className="dim" style={{ fontSize: 11 }}>
        {etiket}
      </div>
      <div className={`mono${tone === 'bad' ? ' err-text' : ''}`} style={{ fontSize: 13 }}>
        {deger}
      </div>
    </div>
  );
}

const saatSadece = (s: string) =>
  new Date(s).toLocaleTimeString('tr-TR', {
    timeZone: 'Europe/Istanbul',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });

function ozetle(v: unknown): string {
  if (v === null || v === undefined) return '—';
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>;
    if ('error' in o) return String(o.error);
    if ('rows' in o) return `${o.rows} satır`;
    if ('result' in o) return String(o.result);
    if ('keys' in o && Array.isArray(o.keys)) return (o.keys as string[]).join(', ');
  }
  return String(v);
}

function OlayCekmecesi({
  olay,
  kapat,
}: {
  olay: SessionEvent;
  kapat: () => void;
}) {
  return (
    <>
      <div className="scrim" onClick={kapat} />
      <div className="drawer">
        <div className="drawer-head">
          <div style={{ flex: 1 }}>
            <h2>{olay.source}</h2>
            <div className="dim mono" style={{ fontSize: 12 }}>
              {olay.table_name} · {olay.op} · {olay.event_kind ?? 'db'}
            </div>
          </div>
          {olay.is_error ? <Pill tone="err">hata</Pill> : <Pill tone="ok">başarılı</Pill>}
          <button className="btn sm ghost" onClick={kapat}>
            ✕
          </button>
        </div>

        {olay.is_error ? (
          <div style={{ marginBottom: 16 }}>
            <HataBasligi hata={olay} />
            {olay.error_message ? (
              <div className="err-text mono" style={{ marginTop: 8, fontSize: 12 }}>
                {olay.error_message}
              </div>
            ) : null}
            <div style={{ margin: '12px 0 6px' }} className="dim">
              Stack trace
            </div>
            <StackTrace stack={olay.stack_trace} />
          </div>
        ) : null}

        <ZamanKunyesi
          ts={olay.ts}
          requested_at={olay.requested_at}
          responded_at={olay.responded_at}
          duration_ms={olay.duration_ms}
        />

        <dl className="kv" style={{ marginBottom: 16 }}>
          <dt>Önceki olaydan</dt>
          <dd>{fmtBosluk(olay.onceki_bosluk_sn)}</dd>
          <dt>Kullanıcı</dt>
          <dd>{olay.email ?? 'oturumsuz'}</dd>
        </dl>

        <div style={{ marginBottom: 8 }} className="dim">
          İstek
        </div>
        <pre className="json">{prettyJson(olay.request_json)}</pre>

        <div style={{ margin: '16px 0 8px' }} className="dim">
          Yanıt
        </div>
        <pre className="json">{prettyJson(olay.response_json)}</pre>

        <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
          <Kopyala metin={prettyJson(olay)} etiket="tüm kaydı kopyala" />
        </div>
      </div>
    </>
  );
}
