import { useEffect, useState } from 'react';
import { useRpc } from '../useRpc';
import type {
  AdminLog,
  AdminUser,
  PushToken,
  UserDetail,
  UserSession,
} from '../types';
import { HataBasligi, StackTrace, ZamanKunyesi } from '../HataDetay';
import { Card, Empty, Hata, Kopyala, Pill, Yukleniyor } from '../ui';
import {
  cihazKunye,
  fmtMs,
  fmtNum,
  fmtRelative,
  fmtSapma,
  fmtSure,
  fmtTs,
  kisaKimlik,
  kisalt,
  prettyJson,
  sapmaCiddi,
} from '../format';

/* Panelin asıl iş ekranı.
 *
 * Akış tek bir şikayeti karşılamak üzere kuruldu: "müşteri X hata alıyor".
 *   1. e-posta / isim yaz            → admin_find_users
 *   2. satıra tıkla                  → admin_user_detail (künye) + admin_user_logs
 *   3. hatalı satıra tıkla           → ham request/response JSON
 * Üç adım, üç RPC. Arada Supabase Dashboard'a gitmeye gerek kalmamalı. */

export default function Kullanicilar({
  ilkSorgu,
}: {
  ilkSorgu: string;
}) {
  const [q, setQ] = useState(ilkSorgu);
  const [aranan, setAranan] = useState(ilkSorgu);
  const [secili, setSecili] = useState<AdminUser | null>(null);

  // Dışarıdan (başka sekmeden) bir sorgu gelirse kutuyu ve aramayı tazele.
  useEffect(() => {
    if (ilkSorgu) {
      setQ(ilkSorgu);
      setAranan(ilkSorgu);
    }
  }, [ilkSorgu]);

  const liste = useRpc<AdminUser[]>('admin_find_users', {
    p_q: aranan,
    p_limit: 50,
  });

  return (
    <>
      <div className="topbar">
        <h1>Kullanıcılar</h1>
        <Yukleniyor görünür={liste.loading} />
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
            style={{ width: 320 }}
            placeholder="e-posta, isim veya user_id…"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            autoFocus
          />
          <button className="btn primary" type="submit">
            Ara
          </button>
        </form>
      </div>

      <Hata mesaj={liste.error} />

      <Card
        title={aranan ? `"${aranan}" için sonuçlar` : 'Son görülen kullanıcılar'}
        action={
          <span className="dim mono" style={{ fontSize: 11 }}>
            {fmtNum(liste.data?.length ?? 0)} kayıt
          </span>
        }
      >
        {!liste.data || liste.data.length === 0 ? (
          <Empty>
            {liste.loading ? 'Aranıyor…' : 'Eşleşen kullanıcı yok.'}
          </Empty>
        ) : (
          <div className="scroll">
            <table>
              <thead>
                <tr>
                  <th>E-posta</th>
                  <th>İsim</th>
                  <th>Giriş</th>
                  <th className="nowrap">Son giriş</th>
                  <th className="num">Varlık</th>
                  <th className="num">Hata 7g</th>
                  <th>Durum</th>
                </tr>
              </thead>
              <tbody>
                {liste.data.map((u) => (
                  <tr
                    key={u.user_id}
                    className={`clickable${secili?.user_id === u.user_id ? ' sel' : ''}`}
                    onClick={() => setSecili(u)}
                  >
                    <td className="mono">{u.email}</td>
                    <td>{u.display_name}</td>
                    <td>
                      <Pill tone={u.provider === 'email' ? undefined : 'info'}>
                        {u.provider}
                      </Pill>
                    </td>
                    <td className="nowrap dim">{fmtRelative(u.last_sign_in_at)}</td>
                    <td className="num">{fmtNum(u.asset_count)}</td>
                    <td className="num">
                      {u.error_count_7d > 0 ? (
                        <span className="err-text">{fmtNum(u.error_count_7d)}</span>
                      ) : (
                        <span className="dim">0</span>
                      )}
                    </td>
                    <td className="nowrap">
                      {u.banned_until ? (
                        <Pill tone="err">banlı</Pill>
                      ) : !u.email_confirmed_at ? (
                        <Pill tone="warn">onaysız</Pill>
                      ) : (
                        <Pill tone="ok">aktif</Pill>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {secili && (
        <KullaniciDetay
          kullanici={secili}
          kapat={() => setSecili(null)}
        />
      )}
    </>
  );
}

/* ── Seçili kullanıcının künyesi + log akışı ─────────────────────────── */

function KullaniciDetay({
  kullanici,
  kapat,
}: {
  kullanici: AdminUser;
  kapat: () => void;
}) {
  const [sadeceHata, setSadeceHata] = useState(true);
  const [kaynakFiltre, setKaynakFiltre] = useState('');
  const [acikLog, setAcikLog] = useState<AdminLog | null>(null);
  // Seans filtresi: bir seansa tiklaninca log listesi ona daralir.
  const [seansFiltre, setSeansFiltre] = useState<string | null>(null);

  const kunye = useRpc<UserDetail>('admin_user_detail', {
    p_user_id: kullanici.user_id,
  });

  const loglar = useRpc<AdminLog[]>('admin_user_logs', {
    p_user_id: kullanici.user_id,
    p_limit: 300,
    p_only_errors: sadeceHata,
    p_source_like: kaynakFiltre ? `%${kaynakFiltre}%` : null,
    p_session_id: seansFiltre,
  });

  // Kullanicinin seanslari: "kac kez acti, her acilista ne oldu".
  const seanslar = useRpc<UserSession[]>('admin_user_sessions', {
    p_user_id: kullanici.user_id,
    p_limit: 30,
  });

  // Push token'lar: "push gitmiyor" sikayetinin tek ekranlik cevabi.
  const tokenlar = useRpc<PushToken[]>('admin_user_push_tokens', {
    p_user_id: kullanici.user_id,
  });

  const d = kunye.data;

  return (
    <div className="section-gap">
      <Card
        title={`Künye · ${kullanici.email}`}
        action={
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <Kopyala metin={kullanici.user_id} etiket="user_id" />
            <Kopyala metin={kullanici.email} etiket="e-posta" />
            <button className="btn sm ghost" onClick={kapat}>
              kapat
            </button>
          </div>
        }
      >
        <Hata mesaj={kunye.error} />
        {d ? (
          <div className="grid cols-5">
            <KunyeKutu baslik="Hesap">
              <dl className="kv">
                <dt>Kayıt</dt>
                <dd>{fmtTs(d.created_at)}</dd>
                <dt>Son giriş</dt>
                <dd>{fmtTs(d.last_sign_in_at)}</dd>
                <dt>E-posta onayı</dt>
                <dd>{d.email_confirmed_at ? fmtTs(d.email_confirmed_at) : '— onaysız'}</dd>
                <dt>Sağlayıcı</dt>
                <dd>{d.provider}</dd>
                <dt>Ban</dt>
                <dd>{d.banned_until ? fmtTs(d.banned_until) : 'yok'}</dd>
              </dl>
            </KunyeKutu>
            <KunyeKutu baslik="Kullanım">
              <dl className="kv">
                <dt>Varlık</dt>
                <dd>{fmtNum(d.asset_count)}</dd>
                <dt>Push token</dt>
                <dd>
                  {fmtNum(d.push_tokens)}
                  {d.push_tokens === 0 ? ' — push gitmez' : ''}
                </dd>
                <dt>Ortak</dt>
                <dd>{fmtNum(d.partner_count)}</dd>
                <dt>Tanıtım turu</dt>
                <dd>{d.onboarding ? 'tamamladı' : 'tamamlamadı'}</dd>
                <dt>Son görülme</dt>
                <dd>{fmtRelative(d.son_gorulme)}</dd>
                <dt>Seans (7g)</dt>
                <dd>{fmtNum(d.seans_7g)}</dd>
                <dt>Cihaz</dt>
                <dd>{fmtNum(d.cihaz_sayisi)}</dd>
              </dl>
            </KunyeKutu>
            <KunyeKutu baslik="Hata">
              <dl className="kv">
                <dt>24 saat</dt>
                <dd className={d.hata_24h > 0 ? 'err-text' : ''}>{fmtNum(d.hata_24h)}</dd>
                <dt>7 gün</dt>
                <dd className={d.hata_7g > 0 ? 'err-text' : ''}>{fmtNum(d.hata_7g)}</dd>
                <dt>İstek 24s</dt>
                <dd>{fmtNum(d.log_24h)}</dd>
              </dl>
            </KunyeKutu>
            <KunyeKutu baslik="Son hata">
              {d.son_hata ? (
                <dl className="kv">
                  <dt>Zaman</dt>
                  <dd>{fmtRelative(d.son_hata.ts)}</dd>
                  <dt>Servis</dt>
                  <dd>{d.son_hata.source}</dd>
                  <dt>Hedef</dt>
                  <dd>{d.son_hata.table}</dd>
                  <dt>Sürüm</dt>
                  <dd>{d.son_hata.app_version ?? '—'}</dd>
                  <dt>Seans</dt>
                  <dd>
                    {d.son_hata.session_id ? (
                      <button
                        className="btn sm ghost mono"
                        onClick={() => setSeansFiltre(d.son_hata!.session_id)}
                        title="Log listesini bu seansa daralt"
                      >
                        {kisaKimlik(d.son_hata.session_id)}
                      </button>
                    ) : (
                      '—'
                    )}
                  </dd>
                  <dt>Mesaj</dt>
                  <dd className="err-text">{kisalt(d.son_hata.error, 140)}</dd>
                </dl>
              ) : (
                <div className="dim">Kayıtlı hata yok.</div>
              )}
            </KunyeKutu>
            <KunyeKutu baslik="Cihazlar">
              {d.cihazlar && d.cihazlar.length > 0 ? (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                  {d.cihazlar.map((c) => (
                    <div key={c.device_id} className="mono" style={{ fontSize: 11.5 }}>
                      <div title={c.device_id}>
                        {kisaKimlik(c.device_id)}{' '}
                        {c.hata > 0 ? (
                          <span className="err-text">· {fmtNum(c.hata)} hata</span>
                        ) : null}
                      </div>
                      <div className="dim">{cihazKunye(c)}</div>
                      <div className="dim">{fmtRelative(c.son_gorulme)}</div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="dim">
                  Cihaz kaydı yok — bu alan uygulamanın yeni sürümüyle dolar.
                </div>
              )}
            </KunyeKutu>
          </div>
        ) : (
          <Empty>Künye yükleniyor…</Empty>
        )}
      </Card>

      <div className="section-gap">
        <Card
          title="Push token'ları"
          action={<Yukleniyor görünür={tokenlar.loading} />}
        >
          <Hata mesaj={tokenlar.error} />
          {!tokenlar.data || tokenlar.data.length === 0 ? (
            <Empty>
              Kayıtlı push token yok — bu kullanıcıya bildirim{' '}
              <b>gitmez</b>. Bildirim izni verilmemiş ya da çıkışta silinmiş
              olabilir.
            </Empty>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Token</th>
                  <th>Platform</th>
                  <th>Cihaz</th>
                  <th className="nowrap">Güncellendi</th>
                  <th className="num">Yaş</th>
                </tr>
              </thead>
              <tbody>
                {tokenlar.data.map((t) => (
                  <tr key={t.token}>
                    <td className="mono" style={{ fontSize: 11, maxWidth: 380 }}>
                      <span style={{ overflowWrap: 'anywhere' }}>{t.token}</span>{' '}
                      <Kopyala metin={t.token} etiket="⧉" />
                    </td>
                    <td>
                      <Pill tone={t.platform === 'ios' ? 'info' : undefined}>
                        {t.platform}
                      </Pill>
                    </td>
                    <td className="mono nowrap dim" title={t.device_id ?? ''}>
                      {kisaKimlik(t.device_id)}
                    </td>
                    <td className="nowrap dim" title={fmtTs(t.updated_at)}>
                      {fmtRelative(t.updated_at)}
                    </td>
                    <td className={`num${t.yas_gun > 60 ? ' err-text' : ''}`}>
                      {t.yas_gun} gün
                      {t.yas_gun > 60 ? ' ⚠' : ''}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          <div className="banner warn" style={{ marginTop: 12, marginBottom: 0 }}>
            Token değeri <b>tam</b> gösterilir: <code>user_push_tokens</code>{' '}
            tablosunda zaten duruyor, panel yeni bir sır üretmiyor. Log
            satırına <b>yazılmaz</b> — orada 30 gün boyunca her istekte
            çoğalırdı (gizlilik politikası: "token maskelenir"). 60 günden
            eski token büyük olasılıkla ölü bir cihazdır.
          </div>
        </Card>
      </div>

      <div className="section-gap">
        <Card
          title="Seanslar"
          action={
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <Yukleniyor görünür={seanslar.loading} />
              {seansFiltre ? (
                <button className="btn sm" onClick={() => setSeansFiltre(null)}>
                  seans filtresini kaldır
                </button>
              ) : null}
            </div>
          }
        >
          <Hata mesaj={seanslar.error} />
          {!seanslar.data || seanslar.data.length === 0 ? (
            <Empty>
              Seans kaydı yok. <code>session_id</code> uygulamanın yeni
              sürümüyle yazılmaya başlar (migration 0071).
            </Empty>
          ) : (
            <div className="scroll">
              <table>
                <thead>
                  <tr>
                    <th>Seans</th>
                    <th className="nowrap">Başlangıç</th>
                    <th className="nowrap">Bitiş</th>
                    <th className="num">Süre</th>
                    <th className="num">Olay</th>
                    <th className="num">Ekran</th>
                    <th className="num">Hata</th>
                    <th>Cihaz</th>
                    <th className="wrapcell">Son hata</th>
                  </tr>
                </thead>
                <tbody>
                  {seanslar.data.map((se) => (
                    <tr
                      key={se.session_id}
                      className={`clickable${seansFiltre === se.session_id ? ' sel' : ''}`}
                      onClick={() =>
                        setSeansFiltre(
                          seansFiltre === se.session_id ? null : se.session_id,
                        )
                      }
                      title="Log listesini bu seansa daralt"
                    >
                      <td className="mono nowrap" title={se.session_id}>
                        {kisaKimlik(se.session_id)}
                      </td>
                      <td className="nowrap dim" title={fmtTs(se.baslangic)}>
                        {fmtRelative(se.baslangic)}
                      </td>
                      <td className="nowrap dim" title={fmtTs(se.bitis)}>
                        {fmtRelative(se.bitis)}
                      </td>
                      <td className="num">{fmtSure(se.sure_sn)}</td>
                      <td className="num">{fmtNum(se.olay)}</td>
                      <td className="num dim">{fmtNum(se.ekran)}</td>
                      <td className={`num${se.hata > 0 ? ' err-text' : ' dim'}`}>
                        {fmtNum(se.hata)}
                      </td>
                      <td className="mono nowrap dim">{cihazKunye(se)}</td>
                      <td className="wrapcell err-text mono" title={se.son_hata ?? ''}>
                        {kisalt(se.son_hata, 60)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>

      <div className="section-gap">
        <Card
          title={seansFiltre ? `İstek günlüğü · seans ${kisaKimlik(seansFiltre)}` : 'İstek günlüğü'}
          action={
            <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
              <Yukleniyor görünür={loglar.loading} />
              <input
                className="input"
                style={{ width: 200 }}
                placeholder="servis filtresi (AuthService…)"
                value={kaynakFiltre}
                onChange={(e) => setKaynakFiltre(e.target.value)}
              />
              <label className="check">
                <input
                  type="checkbox"
                  checked={sadeceHata}
                  onChange={(e) => setSadeceHata(e.target.checked)}
                />
                yalnız hatalar
              </label>
              <button className="btn sm" onClick={loglar.yenile}>
                yenile
              </button>
            </div>
          }
        >
          <Hata mesaj={loglar.error} />
          {!loglar.data || loglar.data.length === 0 ? (
            <Empty>
              {sadeceHata
                ? 'Bu kullanıcıda kayıtlı hata yok. "Yalnız hatalar" kutusunu kapatıp tüm trafiğe bak.'
                : 'Kayıt yok. db_logs 30 gün saklanır (migration 0056).'}
            </Empty>
          ) : (
            <div className="scroll tall">
              <table>
                <thead>
                  <tr>
                    <th className="nowrap">Zaman</th>
                    <th className="nowrap" title="İstek atıldı → yanıt döndü (istemci saati)">
                      İstek → Yanıt
                    </th>
                    <th>Tür</th>
                    <th>Servis</th>
                    <th>Hedef</th>
                    <th>Op</th>
                    <th className="num">Süre</th>
                    <th>Hata</th>
                    <th>Seans</th>
                    <th className="wrapcell">Sonuç</th>
                  </tr>
                </thead>
                <tbody>
                  {loglar.data.map((l) => (
                    <tr
                      key={l.id}
                      className="clickable"
                      onClick={() => setAcikLog(l)}
                    >
                      <td className="nowrap mono dim" title={fmtTs(l.ts)}>
                        {fmtRelative(l.ts)}
                      </td>
                      <td className="nowrap mono dim" style={{ fontSize: 11 }}>
                        {l.requested_at ? (
                          <span
                            className={sapmaCiddi(l.saat_farki_ms) ? 'err-text' : ''}
                            title={
                              `istek: ${fmtTs(l.requested_at)}\n` +
                              `yanıt: ${fmtTs(l.responded_at)}\n` +
                              `sunucu-istemci farkı: ${fmtSapma(l.saat_farki_ms)}`
                            }
                          >
                            {saatSadece(l.requested_at)}
                            {' → '}
                            {l.responded_at ? saatSadece(l.responded_at) : '?'}
                            {sapmaCiddi(l.saat_farki_ms) ? ' ⚠' : ''}
                          </span>
                        ) : (
                          '—'
                        )}
                      </td>
                      <td>
                        <Pill tone={l.event_kind === 'auth' ? 'info' : undefined}>
                          {l.event_kind ?? 'db'}
                        </Pill>
                      </td>
                      <td className="mono nowrap">{l.source}</td>
                      <td className="mono nowrap">{l.table_name}</td>
                      <td>
                        <Pill>{l.op}</Pill>
                      </td>
                      <td className={`num${l.duration_ms > 3000 ? ' err-text' : ''}`}>
                        {fmtMs(l.duration_ms)}
                      </td>
                      <td className="nowrap">
                        {l.error_type ? (
                          <span title={l.error_code ?? ''}>
                            <HataBasligi hata={l} />
                          </span>
                        ) : (
                          <span className="dim">—</span>
                        )}
                      </td>
                      <td className="mono nowrap dim" title={l.session_id ?? ''}>
                        {l.session_id ? (
                          <button
                            className="btn sm ghost mono"
                            onClick={(ev) => {
                              ev.stopPropagation();
                              setSeansFiltre(l.session_id);
                            }}
                          >
                            {kisaKimlik(l.session_id)}
                          </button>
                        ) : (
                          '—'
                        )}
                      </td>
                      <td className="wrapcell">
                        {l.is_error ? (
                          <span className="err-text mono">
                            {kisalt(ozetle(l.response_json), 100)}
                          </span>
                        ) : (
                          <span className="dim mono">
                            {kisalt(ozetle(l.response_json), 60)}
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
      </div>

      {acikLog && <LogCekmecesi log={acikLog} kapat={() => setAcikLog(null)} />}
    </div>
  );
}

function KunyeKutu({ baslik, children }: { baslik: string; children: React.ReactNode }) {
  return (
    <div>
      <div
        className="dim"
        style={{ fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.04em', marginBottom: 8 }}
      >
        {baslik}
      </div>
      {children}
    </div>
  );
}

/** Saat:dakika:saniye — tablo sütununda tam tarih yer kaplar. */
const saatSadece = (s: string) =>
  new Date(s).toLocaleTimeString('tr-TR', {
    timeZone: 'Europe/Istanbul',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });

/** response_json'u tek satıra indir: tabloda JSON değil özet okunur. */
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

function LogCekmecesi({ log, kapat }: { log: AdminLog; kapat: () => void }) {
  return (
    <>
      <div className="scrim" onClick={kapat} />
      <div className="drawer">
        <div className="drawer-head">
          <div style={{ flex: 1 }}>
            <h2>{log.source}</h2>
            <div className="dim mono" style={{ fontSize: 12 }}>
              {log.table_name} · {log.op}
            </div>
          </div>
          {log.is_error ? <Pill tone="err">hata</Pill> : <Pill tone="ok">başarılı</Pill>}
          <button className="btn sm ghost" onClick={kapat}>
            ✕
          </button>
        </div>

        {log.is_error ? (
          <div style={{ marginBottom: 16 }}>
            <HataBasligi hata={log} />
            {log.error_message ? (
              <div className="err-text mono" style={{ marginTop: 8, fontSize: 12 }}>
                {log.error_message}
              </div>
            ) : null}
            <div style={{ margin: '12px 0 6px' }} className="dim">
              Stack trace
            </div>
            <StackTrace stack={log.stack_trace} />
          </div>
        ) : null}

        <ZamanKunyesi
          ts={log.ts}
          requested_at={log.requested_at}
          responded_at={log.responded_at}
          saat_farki_ms={log.saat_farki_ms}
          duration_ms={log.duration_ms}
        />

        <dl className="kv" style={{ marginBottom: 16 }}>
          <dt>Tür</dt>
          <dd>{log.event_kind ?? 'db'}</dd>
          <dt>Seans</dt>
          <dd>{log.session_id ?? '—'}</dd>
          <dt>Cihaz</dt>
          <dd>{log.device_id ?? '—'}</dd>
          <dt>Cihaz künyesi</dt>
          <dd>{cihazKunye(log)}</dd>
        </dl>

        <div style={{ marginBottom: 8 }} className="dim">
          İstek
        </div>
        <pre className="json">{prettyJson(log.request_json)}</pre>

        <div style={{ margin: '16px 0 8px' }} className="dim">
          Yanıt
        </div>
        <pre className="json">{prettyJson(log.response_json)}</pre>

        {/* Maske kararı görünür olsun: panelde e-posta yerine *** görünce
            "veri kayıp" diye okunmasın. */}
        <div className="banner warn" style={{ marginTop: 16 }}>
          Hassas alanlar istemcide maskelenir (<code>DbLogger._maskSensitive</code>):
          e-posta, parola, token, telefon ve görünen ad <code>***</code> olarak yazılır.
          Hata metninde e-posta/UUID/JWT/IP ayrıca regex ile temizlenir.
        </div>

        <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
          <Kopyala metin={prettyJson(log)} etiket="tüm kaydı kopyala" />
          <Kopyala metin={String(log.id)} etiket="log id" />
        </div>
      </div>
    </>
  );
}
