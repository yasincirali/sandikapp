import { useState } from 'react';
import { useOtomatikYenile, useRpc } from '../useRpc';
import type { AuthAbuse, AuthEvent, RateLimitRow } from '../types';
import { Card, Empty, Hata, Kopyala, Pill, SaatSecici, Stat, Yukleniyor } from '../ui';
import { fmtDuration, fmtNum, fmtRelative, fmtTs, kisalt } from '../format';

/* Güvenlik ekranı — "kim zorlanıyor, kim zorluyor".
 *
 * Üç blok, üç ayrı soru:
 *   · Kötüye kullanım  → ardışık başarısız şifre/OTP (brute force)
 *   · Rate limit       → kilitli mi, ne zaman açılır (davet kodu vb.)
 *   · Auth akışı       → GoTrue + istemci olayları tek zaman ekseninde
 *
 * `ardisik_basarisiz` kasıtlı olarak `basarisiz`in önünde gösterilir:
 * toplam sayı geçmişi taşır, ardışık sayı ŞU ANKİ durumu söyler. Dün 8
 * deneyip bugün giren hesap kırmızı olmamalı. */

const ESIK_UYARI = 5;
const ESIK_KRITIK = 10;

export default function Guvenlik({
  saat,
  saatAyarla,
  kullaniciyaGit,
}: {
  saat: number;
  saatAyarla: (v: number) => void;
  kullaniciyaGit: (q: string) => void;
}) {
  const [minDeneme, setMinDeneme] = useState(3);
  const [authQ, setAuthQ] = useState('');
  const [authAranan, setAuthAranan] = useState('');

  const abuse = useRpc<AuthAbuse[]>('admin_auth_abuse', {
    p_hours: saat,
    p_min_hits: minDeneme,
    p_limit: 100,
  });

  const limits = useRpc<RateLimitRow[]>('admin_rate_limits', {
    p_hours: saat,
    p_limit: 100,
  });

  const events = useRpc<AuthEvent[]>('admin_auth_events', {
    p_q: authAranan || null,
    p_hours: saat,
    p_limit: 300,
  });

  useOtomatikYenile(() => {
    abuse.yenile();
    limits.yenile();
    events.yenile();
  }, 60);

  const kritik = (abuse.data ?? []).filter((a) => a.ardisik_basarisiz >= ESIK_KRITIK).length;
  const uyari = (abuse.data ?? []).filter(
    (a) => a.ardisik_basarisiz >= ESIK_UYARI && a.ardisik_basarisiz < ESIK_KRITIK,
  ).length;
  const kilitli = (limits.data ?? []).filter((r) => r.kilitli_mi).length;

  return (
    <>
      <div className="topbar">
        <h1>Güvenlik</h1>
        <Yukleniyor görünür={abuse.loading || limits.loading || events.loading} />
        <span className="spacer" />
        <SaatSecici deger={saat} ayarla={saatAyarla} />
      </div>

      <Hata mesaj={abuse.error ?? limits.error ?? events.error} />

      <div className="grid cols-4">
        <Stat
          label={`≥ ${ESIK_KRITIK} ardışık hata`}
          value={fmtNum(kritik)}
          sub="brute force şüphesi"
          tone={kritik > 0 ? 'bad' : 'good'}
        />
        <Stat
          label={`${ESIK_UYARI}–${ESIK_KRITIK - 1} ardışık hata`}
          value={fmtNum(uyari)}
          sub="takipte tut"
          tone={uyari > 0 ? 'warn' : undefined}
        />
        <Stat
          label="Kilitli hesap"
          value={fmtNum(kilitli)}
          sub="rate limit penceresi açık"
          tone={kilitli > 0 ? 'warn' : undefined}
        />
        <Stat
          label="Auth olayı"
          value={fmtNum(events.data?.length ?? 0)}
          sub={`son ${saat} saat`}
        />
      </div>

      {/* ── Şifre / OTP kötüye kullanımı ─────────────────────────────── */}
      <div className="section-gap">
        <Card
          title="Başarısız giriş ve OTP denemeleri"
          action={
            <label className="check">
              en az
              <input
                className="input"
                type="number"
                min={1}
                max={100}
                value={minDeneme}
                onChange={(e) => setMinDeneme(Math.max(1, Number(e.target.value) || 1))}
                style={{ width: 64 }}
              />
              deneme
            </label>
          }
        >
          {!abuse.data || abuse.data.length === 0 ? (
            <Empty>Eşiği aşan deneme yok.</Empty>
          ) : (
            <div className="scroll">
              <table>
                <thead>
                  <tr>
                    <th>Kullanıcı</th>
                    <th>Akış</th>
                    <th className="num" title="Son başarılı girişten bu yana">
                      Ardışık
                    </th>
                    <th className="num">Toplam</th>
                    <th className="nowrap">İlk</th>
                    <th className="nowrap">Son</th>
                    <th className="nowrap">Son başarılı</th>
                    <th className="wrapcell">Örnek hata</th>
                  </tr>
                </thead>
                <tbody>
                  {abuse.data.map((a, i) => (
                    <tr key={i}>
                      <td>
                        {a.email ? (
                          <button
                            className="btn sm ghost mono"
                            onClick={() => kullaniciyaGit(a.email!)}
                            title="Kullanıcı ekranında aç"
                          >
                            {a.email}
                          </button>
                        ) : (
                          <span className="dim">oturumsuz</span>
                        )}
                        {a.display_name ? (
                          <div className="dim" style={{ fontSize: 11 }}>
                            {a.display_name}
                          </div>
                        ) : null}
                      </td>
                      <td className="mono nowrap">{akisAdi(a.action)}</td>
                      <td className="num">
                        <Pill tone={tonu(a.ardisik_basarisiz)}>
                          {fmtNum(a.ardisik_basarisiz)}
                        </Pill>
                      </td>
                      <td className="num dim">{fmtNum(a.basarisiz)}</td>
                      <td className="nowrap dim">{fmtRelative(a.ilk_deneme)}</td>
                      <td className="nowrap">{fmtRelative(a.son_deneme)}</td>
                      <td className="nowrap dim">
                        {a.son_basarili ? (
                          <span className="gain-text">{fmtRelative(a.son_basarili)}</span>
                        ) : (
                          <span className="err-text">hiç</span>
                        )}
                      </td>
                      <td className="wrapcell mono dim" title={a.ornek_hata ?? ''}>
                        {kisalt(a.ornek_hata, 80)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="banner warn" style={{ marginTop: 12, marginBottom: 0 }}>
            Kaynak <code>db_logs</code>'taki <code>auth/*</code> hatalarıdır — yani
            <b> uygulamadan geçen</b> denemeler. Doğrudan GoTrue API'sine atılan istekler
            burada görünmez; onlar Supabase Dashboard → Auth → Logs'ta. Supabase'in
            kendi giriş rate limit'i de ayrıca çalışır.
          </div>
        </Card>
      </div>

      {/* ── Rate limit ───────────────────────────────────────────────── */}
      <div className="section-gap">
        <Card title="Rate limit sayaçları">
          {!limits.data || limits.data.length === 0 ? (
            <Empty>
              Bu aralıkta kayıt yok. <code>rate_limit_attempts</code> yalnızca davet kodu
              gibi sunucu taraflı akışlarda yazılır (migration 0028/0030).
            </Empty>
          ) : (
            <div className="scroll">
              <table>
                <thead>
                  <tr>
                    <th>Hedef</th>
                    <th>Akış</th>
                    <th className="num">Pencerede</th>
                    <th className="num">Toplam</th>
                    <th className="nowrap">Son deneme</th>
                    <th>Durum</th>
                  </tr>
                </thead>
                <tbody>
                  {limits.data.map((r, i) => (
                    <tr key={i}>
                      <td>
                        {r.email ? (
                          <button
                            className="btn sm ghost mono"
                            onClick={() => kullaniciyaGit(r.email!)}
                          >
                            {r.email}
                          </button>
                        ) : (
                          <span className="mono dim" title={r.subject}>
                            {kisalt(r.subject, 24)}
                          </span>
                        )}
                      </td>
                      <td className="mono">{r.scope}</td>
                      <td className="num">{fmtNum(r.pencere_icinde)}</td>
                      <td className="num dim">{fmtNum(r.deneme)}</td>
                      <td className="nowrap dim">{fmtRelative(r.son_deneme)}</td>
                      <td className="nowrap">
                        {r.kilitli_mi ? (
                          <Pill tone="err">kilitli · {fmtDuration(r.kalan_saniye)}</Pill>
                        ) : (
                          <Pill tone="ok">açık</Pill>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="banner warn" style={{ marginTop: 12, marginBottom: 0 }}>
            <b>Kilit durumu tahminidir:</b> 5 deneme / 10 dakika varsayılanına göre
            hesaplanır (0028). Çağıran Edge Function farklı bir limit geçiyorsa gerçek
            kilit farklı olur — kesin cevap <code>peek_rate_limit</code>'tedir ve yalnızca
            service-role çağırabilir.
          </div>
        </Card>
      </div>

      {/* ── Auth olay akışı ──────────────────────────────────────────── */}
      <div className="section-gap">
        <Card
          title="Auth olay akışı"
          action={
            <form
              onSubmit={(e) => {
                e.preventDefault();
                setAuthAranan(authQ);
              }}
              style={{ display: 'flex', gap: 8 }}
            >
              <input
                className="input"
                style={{ width: 240 }}
                placeholder="e-posta veya user_id ile daralt…"
                value={authQ}
                onChange={(e) => setAuthQ(e.target.value)}
              />
              <button className="btn sm" type="submit">
                filtrele
              </button>
            </form>
          }
        >
          {!events.data || events.data.length === 0 ? (
            <Empty>Bu aralıkta auth olayı yok.</Empty>
          ) : (
            <div className="scroll tall">
              <table>
                <thead>
                  <tr>
                    <th className="nowrap">Zaman</th>
                    <th>Kaynak</th>
                    <th>Kullanıcı</th>
                    <th>Eylem</th>
                    <th>Sonuç</th>
                    <th>IP</th>
                    <th className="wrapcell">Detay</th>
                  </tr>
                </thead>
                <tbody>
                  {events.data.map((e, i) => (
                    <tr key={i}>
                      <td className="nowrap mono dim" title={fmtTs(e.ts)}>
                        {fmtRelative(e.ts)}
                      </td>
                      <td>
                        <Pill tone={e.kaynak === 'gotrue' ? 'info' : undefined}>
                          {e.kaynak}
                        </Pill>
                      </td>
                      <td className="mono">
                        {e.email ? (
                          <button
                            className="btn sm ghost mono"
                            onClick={() => kullaniciyaGit(e.email!)}
                          >
                            {e.email}
                          </button>
                        ) : (
                          <span className="dim">—</span>
                        )}
                      </td>
                      <td className="mono nowrap">{akisAdi(e.action)}</td>
                      <td>
                        {e.basarili ? <Pill tone="ok">ok</Pill> : <Pill tone="err">hata</Pill>}
                      </td>
                      <td className="mono dim nowrap">
                        {e.ip ? (
                          <>
                            {e.ip} <Kopyala metin={e.ip} etiket="⧉" />
                          </>
                        ) : (
                          '—'
                        )}
                      </td>
                      <td
                        className={`wrapcell mono ${e.basarili ? 'dim' : 'err-text'}`}
                        title={e.detay ?? ''}
                      >
                        {kisalt(e.detay, 100)}
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

function tonu(n: number): 'err' | 'warn' | undefined {
  if (n >= ESIK_KRITIK) return 'err';
  if (n >= ESIK_UYARI) return 'warn';
  return undefined;
}

/** `auth/sign-in-with-password` gibi teknik adları okunur hale getir. */
function akisAdi(a: string): string {
  const harita: Record<string, string> = {
    'auth/sign-in-with-password': 'şifreyle giriş',
    'auth/sign-in-with-id-token': 'sosyal giriş',
    'auth/sign-up': 'kayıt',
    'auth/verify-otp': 'OTP doğrulama',
    'auth/resend': 'OTP yeniden gönder',
    'auth/reset-password-for-email': 'şifre sıfırlama isteği',
    'auth/update-user': 'kullanıcı güncelleme',
    'auth/sign-out': 'çıkış',
    login: 'giriş (gotrue)',
    logout: 'çıkış (gotrue)',
    token_refreshed: 'token yenileme',
    user_recovery_requested: 'kurtarma isteği',
    user_updated: 'kullanıcı güncellendi',
    user_signedup: 'kayıt (gotrue)',
  };
  return harita[a] ?? a;
}
