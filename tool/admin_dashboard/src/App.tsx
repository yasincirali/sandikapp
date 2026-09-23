import { useCallback, useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { configHatasi, rpc, supabase } from './supabase';
import Genel from './pages/Genel';
import Kullanicilar from './pages/Kullanicilar';
import Seanslar from './pages/Seanslar';
import Cihazlar from './pages/Cihazlar';
import Guvenlik from './pages/Guvenlik';
import Servisler from './pages/Servisler';
import type { Overview } from './types';
import { useRpc } from './useRpc';
import { fmtNum } from './format';

type Sekme = 'genel' | 'kullanicilar' | 'seanslar' | 'cihazlar' | 'guvenlik' | 'servisler';

export default function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [hazir, setHazir] = useState(false);
  const [adminMi, setAdminMi] = useState<boolean | null>(null);
  const [adminHata, setAdminHata] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setHazir(true);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);

  // Yetki kontrolü panelin kapısı DEĞİL — gerçek kapı her RPC'nin
  // gövdesindeki is_push_admin(). Bu çağrı sadece kullanıcıya doğru mesajı
  // göstermek için: yetkisiz biri boş tablolar yerine ne yapması
  // gerektiğini okusun.
  useEffect(() => {
    if (!session) {
      setAdminMi(null);
      return;
    }
    rpc<boolean>('is_push_admin')
      .then((v) => {
        setAdminMi(v);
        setAdminHata(null);
      })
      .catch((e: unknown) => {
        setAdminMi(false);
        setAdminHata(e instanceof Error ? e.message : String(e));
      });
  }, [session]);

  if (configHatasi) {
    return (
      <div className="login-wrap">
        <div className="login">
          <h1>Yapılandırma eksik</h1>
          <p>{configHatasi}</p>
        </div>
      </div>
    );
  }

  if (!hazir) {
    return (
      <div className="login-wrap">
        <span className="spin" />
      </div>
    );
  }

  if (!session) return <Giris />;

  if (adminMi === false) {
    return (
      <div className="login-wrap">
        <div className="login">
          <h1>Yetki yok</h1>
          <p>
            <b>{session.user.email}</b> yönetici listesinde değil. Supabase SQL Editor'da:
          </p>
          <pre className="json">
            {`insert into public.push_admins (user_id)\nselect id from auth.users\nwhere email = '${session.user.email}';`}
          </pre>
          {adminHata ? <p className="err-text">{adminHata}</p> : null}
          <button className="btn" onClick={() => void supabase.auth.signOut()}>
            Çıkış
          </button>
        </div>
      </div>
    );
  }

  if (adminMi === null) {
    return (
      <div className="login-wrap">
        <span className="spin" />
      </div>
    );
  }

  return <Panel email={session.user.email ?? ''} />;
}

/* ── Giriş ───────────────────────────────────────────────────────────── */

function Giris() {
  const [email, setEmail] = useState('');
  const [sifre, setSifre] = useState('');
  const [hata, setHata] = useState<string | null>(null);
  const [bekliyor, setBekliyor] = useState(false);

  async function gonder(e: React.FormEvent) {
    e.preventDefault();
    setBekliyor(true);
    setHata(null);
    const { error } = await supabase.auth.signInWithPassword({ email, password: sifre });
    if (error) setHata(error.message);
    setBekliyor(false);
  }

  return (
    <div className="login-wrap">
      <form className="login" onSubmit={gonder}>
        <div className="brand" style={{ padding: 0, marginBottom: 4 }}>
          <span className="dot" />
          <span>
            sandık
            <small>destek paneli</small>
          </span>
        </div>
        <p>
          Yönetici hesabınla giriş yap. Panelin yetkisi oturumdan gelir; hiçbir gizli
          anahtar saklanmaz.
        </p>
        <input
          className="input"
          type="email"
          placeholder="e-posta"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          autoComplete="username"
          required
          autoFocus
        />
        <input
          className="input"
          type="password"
          placeholder="şifre"
          value={sifre}
          onChange={(e) => setSifre(e.target.value)}
          autoComplete="current-password"
          required
        />
        {hata ? <div className="banner err" style={{ margin: 0 }}>{hata}</div> : null}
        <button className="btn primary" type="submit" disabled={bekliyor}>
          {bekliyor ? 'Giriş yapılıyor…' : 'Giriş'}
        </button>
      </form>
    </div>
  );
}

/* ── Panel kabuğu ────────────────────────────────────────────────────── */

function Panel({ email }: { email: string }) {
  const [sekme, setSekme] = useState<Sekme>('genel');
  const [saat, setSaat] = useState(24);
  const [kullaniciSorgu, setKullaniciSorgu] = useState('');

  // Kenar çubuğundaki rozetler: sekmeye girmeden "orada bir şey var mı".
  const ozet = useRpc<Overview>('admin_overview', { p_hours: saat });

  const kullaniciyaGit = useCallback((q: string) => {
    setKullaniciSorgu(q);
    setSekme('kullanicilar');
  }, []);

  const o = ozet.data;

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <span className="dot" />
          <span>
            sandık
            <small>destek paneli</small>
          </span>
        </div>

        <NavDugme
          aktif={sekme === 'genel'}
          tikla={() => setSekme('genel')}
          etiket="Genel durum"
          rozet={o?.hata ? fmtNum(o.hata) : undefined}
        />
        <NavDugme
          aktif={sekme === 'kullanicilar'}
          tikla={() => setSekme('kullanicilar')}
          etiket="Kullanıcılar"
          rozet={o?.hatali_kullanici ? fmtNum(o.hatali_kullanici) : undefined}
        />
        <NavDugme
          aktif={sekme === 'seanslar'}
          tikla={() => setSekme('seanslar')}
          etiket="Seanslar"
        />
        <NavDugme
          aktif={sekme === 'cihazlar'}
          tikla={() => setSekme('cihazlar')}
          etiket="Cihazlar"
        />
        <NavDugme
          aktif={sekme === 'guvenlik'}
          tikla={() => setSekme('guvenlik')}
          etiket="Güvenlik"
          rozet={
            (o?.auth_hata ?? 0) + (o?.kilitli_subject ?? 0) > 0
              ? fmtNum((o?.auth_hata ?? 0) + (o?.kilitli_subject ?? 0))
              : undefined
          }
        />
        <NavDugme
          aktif={sekme === 'servisler'}
          tikla={() => setSekme('servisler')}
          etiket="Servisler"
          rozet={o?.yavas_istek ? fmtNum(o.yavas_istek) : undefined}
          sakin
        />

        <div style={{ flex: 1 }} />

        <div className="dim" style={{ fontSize: 11, padding: '0 8px', overflowWrap: 'anywhere' }}>
          {email}
        </div>
        <button className="nav-item" onClick={() => void supabase.auth.signOut()}>
          Çıkış
        </button>
      </aside>

      <main className="main">
        {sekme === 'genel' && (
          <Genel saat={saat} saatAyarla={setSaat} kullaniciyaGit={kullaniciyaGit} />
        )}
        {sekme === 'kullanicilar' && <Kullanicilar ilkSorgu={kullaniciSorgu} />}
        {sekme === 'seanslar' && (
          <Seanslar saat={saat} saatAyarla={setSaat} kullaniciyaGit={kullaniciyaGit} />
        )}
        {sekme === 'cihazlar' && (
          <Cihazlar saat={saat} saatAyarla={setSaat} kullaniciyaGit={kullaniciyaGit} />
        )}
        {sekme === 'guvenlik' && (
          <Guvenlik saat={saat} saatAyarla={setSaat} kullaniciyaGit={kullaniciyaGit} />
        )}
        {sekme === 'servisler' && <Servisler saat={saat} saatAyarla={setSaat} />}
      </main>
    </div>
  );
}

function NavDugme({
  aktif,
  tikla,
  etiket,
  rozet,
  sakin,
}: {
  aktif: boolean;
  tikla: () => void;
  etiket: string;
  rozet?: string;
  sakin?: boolean;
}) {
  return (
    <button className={`nav-item${aktif ? ' active' : ''}`} onClick={tikla}>
      <span>{etiket}</span>
      {rozet ? <span className={`badge${sakin ? ' quiet' : ''}`}>{rozet}</span> : null}
    </button>
  );
}
