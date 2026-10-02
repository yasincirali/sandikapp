import { useMemo, useState } from 'react';
import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { useRpc } from '../useRpc';
import type {
  HuniAdimSatiri,
  HuniGunluk,
  HuniHata,
  HuniKaynak,
  HuniKirilim,
  HuniYolculuk,
} from '../types';
import { Card, Empty, Hata, Kopyala, Pill, Yukleniyor } from '../ui';
import {
  fmtGecis,
  fmtNum,
  fmtRelative,
  fmtTs,
  fmtTsShort,
  kisaKimlik,
  kisalt,
  oran,
} from '../format';

/* Kayıt hunisi (migration 0097) — panelin ilk ekranı.
 *
 * Soru: "uygulamayı indirenlerin kaçı kayıt ekranına geliyor, kaçı kayıt
 * oluyor, kaçı ilk girişini yapıp ilk varlığını ekliyor — ve kaybettiklerimiz
 * nerede, neden kayboluyor?"
 *
 * Okuma sırası kasıtlı: önce huni (nerede kaybediyoruz), sonra ara adımlar
 * ve süre (adımın içinde ne oluyor), sonra hatalar (neden), en sonda kişi
 * kişi yolculuklar (kanıt). Sayı → yer → neden → kişi.
 *
 * İki kaynak, çünkü iki farklı soru:
 *   · Kurulumdan — bu dönemde BAŞLAYAN kurulumlar. Beş adımın hepsi ölçülür
 *     ama yalnızca 0097'li istemciden (yeni sürüm) gelenler var.
 *   · Hesaptan — bu dönemde AÇILAN hesaplar, tüm sürümler. Kayıt öncesi
 *     adımlar (indirme, kayıt ekranı) eski sürümde ölçülmediği için yok. */

type Adim = { kod: string; etiket: string; aciklama: string };

const ANA_ADIMLAR: Record<HuniKaynak, Adim[]> = {
  kurulum: [
    { kod: 'ilk_acilis', etiket: 'İndirip açtı', aciklama: 'Yeni kurulumun ilk açılışı' },
    { kod: 'kayit_ekrani', etiket: 'Kayıt ekranına geldi', aciklama: 'Giriş/kayıt ekranını gördü' },
    { kod: 'kayit', etiket: 'Kayıt oldu', aciklama: 'E-postası onaylı ya da Apple/Google hesabı' },
    { kod: 'ilk_giris', etiket: 'İlk girişini yaptı', aciklama: 'İlk oturum (GoTrue defteri)' },
    { kod: 'ilk_varlik', etiket: 'İlk varlığını ekledi', aciklama: 'Portföye ilk satır' },
  ],
  hesap: [
    { kod: 'yolculuk', etiket: 'Hesap açıldı', aciklama: 'auth.users satırı (onaysız dahil)' },
    { kod: 'kayit', etiket: 'Kayıt oldu', aciklama: 'E-postası onaylı ya da Apple/Google hesabı' },
    { kod: 'ilk_giris', etiket: 'İlk girişini yaptı', aciklama: 'İlk oturum (GoTrue defteri)' },
    { kod: 'ilk_varlik', etiket: 'İlk varlığını ekledi', aciklama: 'Portföye ilk satır' },
  ],
};

const ARA_ADIMLAR: Array<Adim & { sonra: string }> = [
  { kod: 'kayit_formu', etiket: 'Kayıt formunu açtı', aciklama: 'E-posta ile kayıt formu', sonra: 'kayit_ekrani' },
  { kod: 'otp_gonderildi', etiket: 'Kod gönderildi', aciklama: 'Form gönderildi, e-posta yola çıktı', sonra: 'kayit_ekrani' },
  { kod: 'otp_dogrulandi', etiket: 'Kodu doğruladı', aciklama: 'E-postadaki kod girildi', sonra: 'kayit_ekrani' },
  { kod: 'yasal_onay', etiket: 'Yasal onay', aciklama: 'Sorumluluk reddi kabul', sonra: 'ilk_giris' },
  { kod: 'kullanici_adi', etiket: 'Kullanıcı adı', aciklama: 'Ad seçildi', sonra: 'ilk_giris' },
  { kod: 'tur', etiket: 'Tanıtım turu bitti', aciklama: 'Tur tamamlandı', sonra: 'ilk_giris' },
  { kod: 'ana_ekran', etiket: 'Ana ekranı gördü', aciklama: 'Kapılar geçildi, portföy ekranı', sonra: 'ilk_giris' },
];

/* Renk adıma bağlı, sıraya değil (dataviz: renk varlığı izler). Palet
 * dataviz referansının koyu basamakları; panel yüzeyi #112e28'de
 * validate_palette.js ile geçti (CVD ΔE ≥ 8.4, kontrast ≥ 3:1). */
const RENK: Record<string, string> = {
  ilk_acilis: '#3987e5',
  kayit_ekrani: '#d95926',
  kayit: '#199e70',
  ilk_giris: '#c98500',
  ilk_varlik: '#9085e9',
};

const ADIM_ETIKETI: Record<string, string> = {
  ilk_acilis: 'İlk açılış',
  kayit_ekrani: 'Kayıt ekranı',
  kayit_formu: 'Kayıt formu',
  otp_gonderildi: 'Kod gönderildi',
  otp_dogrulandi: 'Kod doğrulandı',
  kayit: 'Kayıt',
  ilk_giris: 'İlk giriş',
  yasal_onay: 'Yasal onay',
  kullanici_adi: 'Kullanıcı adı',
  tur: 'Tur',
  ana_ekran: 'Ana ekran',
  ilk_varlik: 'İlk varlık',
  geri_donen: 'Mevcut hesapla döndü',
  hesap: 'Hesap (olay yok)',
};

/* Hata anahtarı "asama:kod" (HuniKaydi.hataDetayi). Bilinen GoTrue
 * kodları Türkçe okunur; bilinmeyen kod ham gösterilir — gizlenmez. */
const ASAMA: Record<string, string> = {
  kayit: 'Kayıt formu',
  otp: 'Kod doğrulama',
  otp_tekrar: 'Kodu yeniden iste',
  sosyal_google: 'Google ile',
  sosyal_apple: 'Apple ile',
};
const KOD: Record<string, string> = {
  auth_weak_password: 'Zayıf şifre',
  auth_otp_expired: 'Kodun süresi doldu / yanlış kod',
  auth_over_email_send_rate_limit: 'E-posta gönderim sınırı',
  auth_over_request_rate_limit: 'İstek sınırı',
  auth_429: 'Sınıra takıldı (429)',
  auth_user_already_exists: 'Hesap zaten var',
  auth_email_exists: 'E-posta zaten kayıtlı',
  auth_email_address_invalid: 'Geçersiz e-posta',
  auth_invalid_credentials: 'Hatalı e-posta/şifre',
  auth_validation_failed: 'Doğrulama reddedildi',
  auth_signup_disabled: 'Kayıt kapalı',
  ag: 'Bağlantı yok / ağ',
  zaman_asimi: 'Zaman aşımı',
  diger: 'Diğer',
};

function hataOku(anahtar: string): { asama: string; neden: string } {
  if (anahtar === 'gecersiz') return { asama: '—', neden: 'Biçimsiz kayıt (istemci dışı olabilir)' };
  const [a, k = ''] = anahtar.split(':');
  return { asama: ASAMA[a] ?? a, neden: KOD[k] ?? k };
}

const GUN_SECENEKLERI = [7, 30, 90, 365] as const;

type SonAdimFiltre = 'hepsi' | 'ilk_acilis' | 'kayit_ekrani' | 'kayit' | 'ilk_giris' | 'ilk_varlik' | 'geri_donen' | 'hesap';

export default function Huni({ kullaniciyaGit }: { kullaniciyaGit: (q: string) => void }) {
  const [gun, setGun] = useState<number>(30);
  const [kaynak, setKaynak] = useState<HuniKaynak>('kurulum');
  const [platform, setPlatform] = useState<string | null>(null);
  const [boyut, setBoyut] = useState<'platform' | 'surum' | 'saglayici'>('platform');
  const [sonAdim, setSonAdim] = useState<SonAdimFiltre>('hepsi');
  const [secili, setSecili] = useState<HuniYolculuk | null>(null);

  const ortak = { p_gun: gun, p_kaynak: kaynak };
  const ozet = useRpc<HuniAdimSatiri[]>('admin_huni_ozet', { ...ortak, p_platform: platform });
  const gunluk = useRpc<HuniGunluk[]>('admin_huni_gunluk', { ...ortak, p_platform: platform });
  const kirilim = useRpc<HuniKirilim[]>('admin_huni_kirilim', { ...ortak, p_boyut: boyut });
  const hatalar = useRpc<HuniHata[]>('admin_huni_hatalar', { p_gun: gun, p_limit: 30 });
  const yolculuklar = useRpc<HuniYolculuk[]>('admin_huni_yolculuklar', {
    ...ortak,
    p_platform: platform,
    p_son_adim: sonAdim === 'hepsi' ? null : sonAdim,
    p_limit: 300,
  });

  const satir = useMemo(() => {
    const m = new Map<string, HuniAdimSatiri>();
    for (const r of ozet.data ?? []) m.set(r.adim, r);
    return m;
  }, [ozet.data]);
  const adet = (k: string) => satir.get(k)?.adet ?? 0;

  const anaAdimlar = ANA_ADIMLAR[kaynak];
  const taban = adet(anaAdimlar[0].kod);
  const yukleniyor =
    ozet.loading || gunluk.loading || kirilim.loading || hatalar.loading || yolculuklar.loading;

  return (
    <>
      <div className="topbar">
        <h1>Kayıt hunisi</h1>
        <Yukleniyor görünür={yukleniyor} />
        <span className="spacer" />
        <Secici
          etiket="Kaynak"
          deger={kaynak}
          ayarla={(v) => setKaynak(v as HuniKaynak)}
          secenekler={[
            { v: 'kurulum', l: 'Kurulumdan' },
            { v: 'hesap', l: 'Hesaptan' },
          ]}
        />
        <Secici
          etiket="Platform"
          deger={platform ?? ''}
          ayarla={(v) => setPlatform(v || null)}
          secenekler={[
            { v: '', l: 'Tümü' },
            { v: 'android', l: 'Android' },
            { v: 'ios', l: 'iOS' },
          ]}
        />
        <Secici
          etiket="Dönem"
          deger={String(gun)}
          ayarla={(v) => setGun(Number(v))}
          secenekler={GUN_SECENEKLERI.map((g) => ({ v: String(g), l: g === 365 ? '1 yıl' : `${g}g` }))}
        />
      </div>

      <Hata mesaj={ozet.error ?? gunluk.error ?? kirilim.error ?? hatalar.error ?? yolculuklar.error} />

      <div className="banner info">
        {kaynak === 'kurulum' ? (
          <>
            <b>Kurulumdan:</b> son {gun} günde <b>başlayan</b> kurulumlar ve her birinin nereye
            kadar gittiği. Yalnızca huni kaydı olan sürümden (0097) itibaren dolar. Mağaza
            indirme sayısı App Store Connect / Play Console'dadır; buradaki ilk adım
            "indirip <b>en az bir kez açan</b>" kişidir. Mevcut hesabıyla yeniden kuranlar
            huniye girmez, aşağıda ayrı sayılır.
          </>
        ) : (
          <>
            <b>Hesaptan:</b> son {gun} günde <b>açılan</b> hesaplar, tüm uygulama sürümleri.
            Kayıt, ilk giriş ve ilk varlık sunucu kayıtlarından okunur; kayıt öncesi adımlar
            (indirme, kayıt ekranı) yalnızca yeni sürümle gelenlerde doludur.
          </>
        )}
      </div>

      {/* ── 1. Huni ─────────────────────────────────────────────────────── */}
      <Card
        title="Huni"
        action={
          <span className="dim mono" style={{ fontSize: 11 }}>
            oranlar ilk adıma göre · geçiş süresi medyan (p90)
          </span>
        }
      >
        {taban === 0 ? (
          <Empty>
            {kaynak === 'kurulum'
              ? 'Bu dönemde huni kaydı olan kurulum yok. Yeni sürüm yayılınca dolar — o zamana kadar "Hesaptan" görünümüne bak.'
              : 'Bu dönemde açılmış hesap yok.'}
          </Empty>
        ) : (
          <div className="huni">
            {anaAdimlar.map((a, i) => {
              const n = adet(a.kod);
              const onceki = i > 0 ? adet(anaAdimlar[i - 1].kod) : n;
              const kayip = onceki - n;
              const r = satir.get(a.kod);
              return (
                <div className="huni-satir" key={a.kod}>
                  <div className="huni-etiket">
                    <div>{a.etiket}</div>
                    <div className="dim" style={{ fontSize: 11 }}>{a.aciklama}</div>
                  </div>
                  <div className="huni-iz" title={`${fmtNum(n)} / ${fmtNum(taban)}`}>
                    <div
                      className="huni-dolgu"
                      style={{
                        width: `${taban > 0 ? Math.max((100 * n) / taban, n > 0 ? 0.8 : 0) : 0}%`,
                        background: RENK[a.kod] ?? 'var(--t36)',
                      }}
                    />
                  </div>
                  <div className="huni-sayi">
                    <div className="mono" style={{ fontSize: 18 }}>{fmtNum(n)}</div>
                    <div className="dim mono" style={{ fontSize: 11 }}>{oran(n, taban)}</div>
                  </div>
                  <div className="huni-gecis">
                    {i === 0 ? (
                      <span className="dim">taban</span>
                    ) : (
                      <>
                        <div className="mono">{oran(n, onceki)} geçti</div>
                        {kayip > 0 ? (
                          <div className="mono err-text" style={{ fontSize: 11 }}>
                            −{fmtNum(kayip)} kaldı
                          </div>
                        ) : null}
                      </>
                    )}
                  </div>
                  <div className="huni-sure mono">
                    {r?.p50_sn != null ? (
                      <>
                        <div>{fmtGecis(r.p50_sn)}</div>
                        <div className="dim" style={{ fontSize: 11 }}>
                          p90 {fmtGecis(r.p90_sn)} · n={fmtNum(r.olcum)}
                        </div>
                      </>
                    ) : (
                      <span className="dim">—</span>
                    )}
                  </div>
                </div>
              );
            })}
            <div className="huni-alt">
              {kaynak === 'kurulum' ? (
                <span>
                  <Pill tone="info">{fmtNum(adet('geri_donen'))}</Pill> kurulum mevcut hesabıyla
                  döndü (yeniden yükleme / yeni telefon) — yeni kullanıcı sayılmadı
                </span>
              ) : null}
              <span>
                <Pill tone={adet('kayit_hatasi') > 0 ? 'warn' : undefined}>
                  {fmtNum(adet('kayit_hatasi'))}
                </Pill>{' '}
                yolculukta kayıt sırasında en az bir hata görüldü
              </span>
            </div>
          </div>
        )}
      </Card>

      {/* ── 2. Ara adımlar + gün gün ────────────────────────────────────── */}
      <div className="grid cols-2 section-gap">
        <Card title="Ara adımlar">
          <p className="dim" style={{ margin: '0 0 8px', fontSize: 12 }}>
            Ana adımların arasında ne oluyor. Oran, adımın ait olduğu ana adıma göre; süre bir
            önceki ara adımdan.
          </p>
          <table>
            <thead>
              <tr>
                <th>Adım</th>
                <th className="num">Kişi</th>
                <th className="num">Oran</th>
                <th className="num">Medyan</th>
                <th className="num">p90</th>
              </tr>
            </thead>
            <tbody>
              {ARA_ADIMLAR.map((a, i) => {
                const r = satir.get(a.kod);
                const ust = adet(a.sonra);
                const bolumBasi = i === 0 || ARA_ADIMLAR[i - 1].sonra !== a.sonra;
                return (
                  <tr key={a.kod} style={bolumBasi && i > 0 ? { borderTop: '1px solid var(--t20)' } : undefined}>
                    <td>
                      {a.etiket}
                      <div className="dim" style={{ fontSize: 11 }}>
                        {a.aciklama}
                      </div>
                    </td>
                    <td className="num">{fmtNum(r?.adet ?? 0)}</td>
                    <td className="num">
                      {oran(r?.adet ?? 0, ust)}
                      <div className="dim" style={{ fontSize: 11 }}>
                        / {ADIM_ETIKETI[a.sonra].toLowerCase()}
                      </div>
                    </td>
                    <td className="num">{fmtGecis(r?.p50_sn)}</td>
                    <td className="num dim">{fmtGecis(r?.p90_sn)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          <p className="dim" style={{ margin: '8px 0 0', fontSize: 11 }}>
            Apple/Google ile kayıt olanlar form ve kod adımlarını atlar; o satırların düşük
            olması kayıp değildir. Kullanıcı adı e-posta kaydında formda seçilir.
          </p>
        </Card>

        <Card title="Gün gün">
          <GunGun veri={gunluk.data ?? []} gun={gun} adimlar={anaAdimlar} />
        </Card>
      </div>

      {/* ── 3. Neden + kırılım ──────────────────────────────────────────── */}
      <div className="grid cols-2 section-gap">
        <Card
          title="Neden düşüyor — hatalar"
          action={
            <span className="dim mono" style={{ fontSize: 11 }}>
              kaynak seçiminden bağımsız
            </span>
          }
        >
          {!hatalar.data || hatalar.data.length === 0 ? (
            <Empty>Bu dönemde kayıt sırasında ya da ilk 48 saatte hata yok.</Empty>
          ) : (
            <div className="scroll">
              <table>
                <thead>
                  <tr>
                    <th>Nerede</th>
                    <th className="wrapcell">Ne</th>
                    <th className="num">Adet</th>
                    <th className="num">Kişi</th>
                    <th className="nowrap">Son</th>
                  </tr>
                </thead>
                <tbody>
                  {hatalar.data.map((h, i) => {
                    const o = h.kaynak === 'kayit' ? hataOku(h.anahtar) : null;
                    return (
                      <tr key={i}>
                        <td className="nowrap">
                          <Pill tone={h.kaynak === 'kayit' ? 'warn' : 'err'}>
                            {h.kaynak === 'kayit' ? 'kayıtta' : 'ilk 48 sa'}
                          </Pill>
                          <div className="dim" style={{ fontSize: 11, marginTop: 2 }}>
                            {o ? o.asama : h.servis}
                          </div>
                        </td>
                        <td className="wrapcell">
                          {o ? (
                            <>
                              {o.neden}
                              <div className="dim mono" style={{ fontSize: 11 }}>{h.anahtar}</div>
                            </>
                          ) : (
                            <>
                              <span className="mono" style={{ fontSize: 12 }}>{h.anahtar}</span>
                              <div className="err-text mono" style={{ fontSize: 11 }} title={h.ornek ?? ''}>
                                {kisalt(h.ornek, 100)}
                              </div>
                            </>
                          )}
                        </td>
                        <td className="num">{fmtNum(h.adet)}</td>
                        <td className="num">{fmtNum(h.kisi)}</td>
                        <td className="nowrap dim">{fmtRelative(h.son)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
          <p className="dim" style={{ margin: '8px 0 0', fontSize: 11 }}>
            "Kayıtta": oturum açılmadan alınan hatalar (sınıf + kod; mesaj saklanmaz). "İlk 48
            sa": hesabı bu dönemde açılanların ilk iki gününde <code>db_logs</code>'a düşen hatalar.
          </p>
        </Card>

        <Card
          title="Kırılım"
          action={
            <Secici
              etiket="Boyut"
              deger={boyut}
              ayarla={(v) => setBoyut(v as typeof boyut)}
              secenekler={[
                { v: 'platform', l: 'Platform' },
                { v: 'surum', l: 'Sürüm' },
                { v: 'saglayici', l: 'Giriş yolu' },
              ]}
            />
          }
        >
          <Kirilim veri={kirilim.data ?? []} kaynak={kaynak} />
        </Card>
      </div>

      {/* ── 4. Yolculuklar ──────────────────────────────────────────────── */}
      <div className="section-gap">
        <Card
          title="Yolculuklar"
          action={
            <Secici
              etiket="Nerede kaldı"
              deger={sonAdim}
              ayarla={(v) => setSonAdim(v as SonAdimFiltre)}
              secenekler={[
                { v: 'hepsi', l: 'Hepsi' },
                ...(kaynak === 'kurulum'
                  ? [
                      { v: 'ilk_acilis', l: 'Açıp çıktı' },
                      { v: 'kayit_ekrani', l: 'Kayıt ekranında' },
                    ]
                  : [{ v: 'hesap', l: 'Onaysız' }]),
                { v: 'kayit', l: 'Giriş yok' },
                { v: 'ilk_giris', l: 'Varlık yok' },
                { v: 'ilk_varlik', l: 'Tamamladı' },
                ...(kaynak === 'kurulum' ? [{ v: 'geri_donen', l: 'Döndü' }] : []),
              ]}
            />
          }
        >
          <Yolculuklar veri={yolculuklar.data ?? []} sec={setSecili} kaynak={kaynak} />
        </Card>
      </div>

      {secili ? (
        <YolculukDetay y={secili} kapat={() => setSecili(null)} kullaniciyaGit={kullaniciyaGit} />
      ) : null}
    </>
  );
}

/* ── Parçalar ──────────────────────────────────────────────────────────── */

function Secici({
  etiket,
  deger,
  ayarla,
  secenekler,
}: {
  etiket: string;
  deger: string;
  ayarla: (v: string) => void;
  secenekler: Array<{ v: string; l: string }>;
}) {
  return (
    <div className="seg" role="group" aria-label={etiket}>
      {secenekler.map((o) => (
        <button key={o.v} type="button" className={deger === o.v ? 'on' : ''} onClick={() => ayarla(o.v)}>
          {o.l}
        </button>
      ))}
    </div>
  );
}

const gunEtiketi = new Intl.DateTimeFormat('tr-TR', { day: '2-digit', month: 'short' });

function GunGun({ veri, gun, adimlar }: { veri: HuniGunluk[]; gun: number; adimlar: Adim[] }) {
  // Boş günler sıfırla doldurulur: aksi halde çizgi boşluğu atlar ve "hiç
  // kayıt yok" günü görünmez olur — en çok bakılması gereken gün o.
  const seriler = adimlar.filter((a) => a.kod in RENK);
  const satirlar = useMemo(() => {
    const m = new Map<string, Record<string, number | string>>();
    const bugun = new Date();
    for (let i = gun - 1; i >= 0; i--) {
      const d = new Date(bugun.getTime() - i * 86400000);
      const k = d.toLocaleDateString('sv-SE', { timeZone: 'Europe/Istanbul' });
      m.set(k, { gun: k });
    }
    for (const r of veri) {
      const s = m.get(r.gun);
      if (s) s[r.adim] = r.adet;
    }
    return [...m.values()].map((s) => {
      for (const a of seriler) if (s[a.kod] === undefined) s[a.kod] = 0;
      return s;
    });
  }, [veri, gun, seriler]);

  if (veri.length === 0) return <Empty>Bu dönemde olay yok.</Empty>;
  return (
    <div style={{ height: 260 }}>
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={satirlar} margin={{ top: 8, right: 8, left: -18, bottom: 0 }}>
          <CartesianGrid stroke="rgba(255,255,255,0.06)" vertical={false} />
          <XAxis
            dataKey="gun"
            tickFormatter={(v) => gunEtiketi.format(new Date(String(v)))}
            stroke="rgba(255,255,255,0.35)"
            fontSize={11}
            tickLine={false}
            minTickGap={24}
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
            labelFormatter={(v) => gunEtiketi.format(new Date(String(v)))}
          />
          {/* Gösterge huni sırasında; recharts varsayılanı ada göre sıralar. */}
          <Legend wrapperStyle={{ fontSize: 11 }} itemSorter={null} />
          {seriler.map((a) => (
            <Line
              key={a.kod}
              type="monotone"
              dataKey={a.kod}
              name={ADIM_ETIKETI[a.kod]}
              stroke={RENK[a.kod]}
              strokeWidth={2}
              dot={gun <= 30 ? { r: 2.5 } : false}
              activeDot={{ r: 4 }}
              isAnimationActive={false}
            />
          ))}
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}

function Kirilim({ veri, kaynak }: { veri: HuniKirilim[]; kaynak: HuniKaynak }) {
  if (veri.length === 0) return <Empty>Bu dönemde veri yok.</Empty>;
  return (
    <div className="scroll">
      <table>
        <thead>
          <tr>
            <th>Değer</th>
            <th className="num">Yolculuk</th>
            {kaynak === 'kurulum' ? <th className="num">Kayıt ekr.</th> : null}
            <th className="num">Kayıt</th>
            <th className="num">İlk giriş</th>
            <th className="num">İlk varlık</th>
            <th className="num">Hata</th>
          </tr>
        </thead>
        <tbody>
          {veri.map((r) => (
            <tr key={r.deger}>
              <td className="mono">{r.deger}</td>
              <td className="num">{fmtNum(r.yolculuk)}</td>
              {kaynak === 'kurulum' ? (
                <td className="num">
                  {fmtNum(r.kayit_ekrani)}
                  <div className="dim">{oran(r.kayit_ekrani, r.yolculuk)}</div>
                </td>
              ) : null}
              <td className="num">
                {fmtNum(r.kayit)}
                <div className="dim">{oran(r.kayit, r.yolculuk)}</div>
              </td>
              <td className="num">
                {fmtNum(r.ilk_giris)}
                <div className="dim">{oran(r.ilk_giris, r.kayit)}</div>
              </td>
              <td className="num">
                {fmtNum(r.ilk_varlik)}
                <div className="dim">{oran(r.ilk_varlik, r.ilk_giris)}</div>
              </td>
              <td className="num">{r.hata > 0 ? <span className="err-text">{fmtNum(r.hata)}</span> : '0'}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="dim" style={{ margin: '8px 0 0', fontSize: 11 }}>
        Alt satırdaki oran bir önceki sütuna göre. Hesap görünümünde sürüm, yalnızca yeni sürümle
        gelen hesaplarda dolu.
      </p>
    </div>
  );
}

const SERIT: Array<keyof HuniYolculuk> = ['ilk_acilis', 'kayit_ekrani', 'kayit', 'ilk_giris', 'ilk_varlik'];

function Yolculuklar({
  veri,
  sec,
  kaynak,
}: {
  veri: HuniYolculuk[];
  sec: (y: HuniYolculuk) => void;
  kaynak: HuniKaynak;
}) {
  if (veri.length === 0) return <Empty>Bu filtrede yolculuk yok.</Empty>;
  return (
    <div className="scroll tall">
      <table>
        <thead>
          <tr>
            <th className="nowrap">Başladı</th>
            <th>Kim</th>
            <th>Cihaz</th>
            <th>Adımlar</th>
            <th>Son adım</th>
            <th className="num">Kayıt → varlık</th>
            <th>Son hata</th>
          </tr>
        </thead>
        <tbody>
          {veri.map((y) => (
            <tr
              key={`${y.kurulum_id ?? ''}${y.user_id ?? ''}`}
              className="clickable"
              onClick={() => sec(y)}
            >
              <td className="nowrap">
                {fmtTsShort(y.baslangic)}
                <div className="dim" style={{ fontSize: 11 }}>{fmtRelative(y.baslangic)}</div>
              </td>
              <td>
                {y.email ? (
                  <>
                    <div style={{ overflowWrap: 'anywhere' }}>{y.email}</div>
                    <div className="dim" style={{ fontSize: 11 }}>{y.saglayici ?? ''}</div>
                  </>
                ) : (
                  <span className="dim">
                    anonim kurulum <span className="mono">{kisaKimlik(y.kurulum_id)}</span>
                  </span>
                )}
              </td>
              <td className="mono nowrap dim">
                {y.platform}
                {y.surum ? ` · ${y.surum}` : ''}
              </td>
              <td>
                <div className="serit" aria-label="ulaşılan adımlar">
                  {SERIT.filter((k) => kaynak === 'kurulum' || (k !== 'ilk_acilis' && k !== 'kayit_ekrani')).map(
                    (k) => (
                      <span
                        key={k}
                        className={`serit-nokta${y[k] ? ' on' : ''}`}
                        style={y[k] ? { background: RENK[k] } : undefined}
                        title={`${ADIM_ETIKETI[k]}: ${y[k] ? fmtTs(y[k] as string) : '—'}`}
                      />
                    ),
                  )}
                </div>
              </td>
              <td className="nowrap">
                <Pill
                  tone={
                    y.son_adim === 'ilk_varlik'
                      ? 'ok'
                      : y.son_adim === 'geri_donen'
                        ? 'info'
                        : y.son_adim === 'ilk_acilis' || y.son_adim === 'kayit_ekrani' || y.son_adim === 'hesap'
                          ? 'warn'
                          : undefined
                  }
                >
                  {ADIM_ETIKETI[y.son_adim] ?? y.son_adim}
                </Pill>
              </td>
              <td className="num">
                {y.kayit && y.ilk_varlik ? (
                  <>
                    {fmtGecis((Date.parse(y.ilk_varlik) - Date.parse(y.kayit)) / 1000)}
                    {y.ilk_varlik_tahmini ? <div className="dim" style={{ fontSize: 11 }}>tahmini</div> : null}
                  </>
                ) : (
                  <span className="dim">—</span>
                )}
              </td>
              <td className="mono" style={{ fontSize: 11 }}>
                {y.son_hata ? (
                  <span className="err-text" title={y.son_hata}>
                    {hataOku(y.son_hata).neden}
                    {y.hata_sayisi > 1 ? ` (+${y.hata_sayisi - 1})` : ''}
                  </span>
                ) : (
                  <span className="dim">—</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* Tek yolculuğun zaman çizelgesi: her adım, saati ve bir önceki
 * GERÇEKLEŞEN adımdan geçen süre. Atlanan adım (ör. sosyal kayıtta form)
 * soluk durur — "yapmadı" ile "ölçülmedi" ayrı okunsun diye satır silinmez. */
function YolculukDetay({
  y,
  kapat,
  kullaniciyaGit,
}: {
  y: HuniYolculuk;
  kapat: () => void;
  kullaniciyaGit: (q: string) => void;
}) {
  const sira: Array<keyof HuniYolculuk> = [
    'ilk_acilis',
    'kayit_ekrani',
    'kayit_formu',
    'otp_gonderildi',
    'otp_dogrulandi',
    'kayit',
    'ilk_giris',
    'yasal_onay',
    'kullanici_adi',
    'tur',
    'ana_ekran',
    'ilk_varlik',
  ];
  let onceki: number | null = null;
  return (
    <>
      <div className="scrim" onClick={kapat} />
      <aside className="drawer" role="dialog" aria-label="Yolculuk">
        <div className="drawer-head">
          <div style={{ flex: 1 }}>
            <h2>{y.email ?? 'Anonim kurulum'}</h2>
            <div className="dim mono" style={{ fontSize: 12, marginTop: 4 }}>
              {y.platform}
              {y.surum ? ` · ${y.surum}` : ''}
              {y.saglayici ? ` · ${y.saglayici}` : ''}
            </div>
          </div>
          <button className="btn sm" onClick={kapat}>
            Kapat
          </button>
        </div>

        {y.geri_donen ? (
          <div className="banner info">
            Bu hesap kurulumdan önce açılmış: yeniden yükleme ya da yeni telefon. Yeni kullanıcı
            sayılmadı.
          </div>
        ) : null}

        <table>
          <tbody>
            {sira.map((k) => {
              const ts = y[k] as string | null;
              const t = ts ? Date.parse(ts) : null;
              const fark = t !== null && onceki !== null ? (t - onceki) / 1000 : null;
              if (t !== null) onceki = t;
              return (
                <tr key={k} style={ts ? undefined : { opacity: 0.4 }}>
                  <td className="nowrap">
                    <span
                      className={`serit-nokta${ts ? ' on' : ''}`}
                      style={{ marginRight: 8, ...(ts && RENK[k] ? { background: RENK[k] } : {}) }}
                    />
                    {ADIM_ETIKETI[k]}
                  </td>
                  <td className="mono nowrap">
                    {ts ? fmtTs(ts) : '—'}
                    {k === 'ilk_varlik' && y.ilk_varlik_tahmini ? <span className="dim"> (tahmini)</span> : null}
                  </td>
                  <td className="num dim">{fark !== null && fark >= 0 ? `+${fmtGecis(fark)}` : ''}</td>
                </tr>
              );
            })}
          </tbody>
        </table>

        <dl className="kv section-gap">
          <dt>Kayıtta hata</dt>
          <dd>
            {y.hata_sayisi > 0 ? (
              <span className="err-text">
                {y.hata_sayisi} farklı · son: {y.son_hata ? `${hataOku(y.son_hata).asama} — ${hataOku(y.son_hata).neden}` : '—'}
              </span>
            ) : (
              '—'
            )}
          </dd>
          <dt>Portföy satırı</dt>
          <dd>{fmtNum(y.varlik_sayisi)}</dd>
          <dt>Kurulum</dt>
          <dd>
            {y.kurulum_id ?? '—'} {y.kurulum_id ? <Kopyala metin={y.kurulum_id} /> : null}
          </dd>
          <dt>Kullanıcı</dt>
          <dd>
            {y.user_id ?? '—'} {y.user_id ? <Kopyala metin={y.user_id} /> : null}
          </dd>
        </dl>

        {y.email ? (
          <div className="section-gap">
            <button
              className="btn primary"
              onClick={() => {
                kapat();
                kullaniciyaGit(y.email ?? '');
              }}
            >
              Künyesine ve loglarına git
            </button>
          </div>
        ) : (
          <p className="dim section-gap" style={{ fontSize: 12 }}>
            Hesap açmamış kurulumun kişisel verisi yok; yalnızca adım zamanları ve hata kodları
            tutulur.
          </p>
        )}
      </aside>
    </>
  );
}
