-- 0097_kayit_hunisi.sql
-- ============================================================
-- Kayıt hunisi: kurulumdan ilk varlığa kadar her adım panelde.
--
-- ── Neden ───────────────────────────────────────────────────────────────────
-- Kullanıcı isteği (2026-10-02): kontrol panelinde "uygulamayı indiren →
-- kayıt ekranına gelen → kayıt olan → ilk girişini yapan → ilk varlığını
-- ekleyen" kişilerin sayısını ve kayıtlarını görmek.
--
-- Bugün bu sorunun yarısı sunucuda hiç yok:
--   · Kayıt ÖNCESİ adımlar (ilk açılış, kayıt ekranı, form, OTP) yalnızca
--     Firebase Analytics'e `signup_step` olarak gidiyor; panel Firebase'i
--     okuyamaz.
--   · `db_logs` oturumsuz satır yazmaz (RLS + DbLogger 2026-09-29 kararı),
--     yani kayıt sırasında alınan hatalar (zayıf şifre, OTP süresi, ağ) iz
--     bırakmıyor — huninin tam düştüğü yer karanlık.
--
-- "İlk varlığını ne zaman ekledi" için `assets.created_at` kullanılır —
-- 0095 (Yarış TWR) ekledi, tetikleyiciyle sunucu yazar. İki tuzağı var ve
-- yolculuk tablosu ikisini de "tahmini" diye işaretler:
--   · 0095 öncesi satırlara ALIŞ tarihi (`added_date`) dolduruldu, giriş
--     anı değil. Eşik: 0095'in iki sunucuya dağıtıldığı gün (2026-10-01).
--   · Tetikleyici, miktar/tarih düzeltmesinde damgayı yeniler. Kişinin İLK
--     varlığı için tüm satırların en küçüğü alınır; ilk satırını sonradan
--     düzelten kişide değer biraz ileri kayar (kabul edildi: yön doğru,
--     sapma küçük).
--
-- ── Ne eklendi ──────────────────────────────────────────────────────────────
--  1. `huni_olaylari` — kurulum başına adım defteri. Kimlik, cihazda
--     rastgele üretilen `kurulum_id`'dir (cihaz kimliği, reklam kimliği,
--     e-posta YOK). Oturum açılınca satırlar `user_id`'ye bağlanır.
--  2. `huni_kaydet(...)` — tek yazma yolu; oturumsuz (anon) çağrılabilir.
--  3. `admin_huni_*` — panelin okuma yüzeyi (0070 güvenlik sözleşmesi).
--
-- ── Sunucu doğrusu önce gelir ───────────────────────────────────────────────
-- Kayıt, ilk giriş ve ilk varlık İSTEMCİ olayından değil sunucu
-- kayıtlarından okunur (`auth.users`, `auth.audit_log_entries`,
-- `assets.created_at`). Böylece bu sürümü almamış istemcilerin kullanıcıları
-- da sayılır ve olay kaybı (çevrimdışı, uygulama öldürüldü) sayıyı
-- düşürmez. İstemci olayları yalnızca sunucunun GÖREMEDİĞİ adımlar için:
-- kayıt öncesi her şey ve oturum sonrası ara ekranlar.
--
-- ── İki sunucu ──────────────────────────────────────────────────────────────
-- CLAUDE.md "iki sunucu birebir": Frankfurt → Tokyo birlikte. Cron EKLENMEDİ
-- (Frankfurt'ta cron'lar kapalı, yeni bir iş farkı büyütürdü); saklama
-- süresi var olan `cleanup_db_logs` işine eklendi.
-- ============================================================

-- ── 1. huni_olaylari ───────────────────────────────────────────────────────
-- Adım listesi istemcideki `HuniAdimi` ile birebir (lib/services/huni_kaydi.dart).
-- `kayit`, `ilk_varlik` burada YOK: onları sunucu kendi kayıtlarından bilir.
create table if not exists public.huni_olaylari (
  id          bigserial primary key,
  kurulum_id  uuid not null,
  adim        text not null,
  -- Yalnızca `kayit_hatasi` için: "asama:kod" (ör. kayit:auth_weak_password).
  -- Serbest metin DEĞİL — biçim kısıtı e-posta/alan adı sızmasını yapısal
  -- olarak engeller: @, nokta, boşluk, büyük harf giremez. Karakter süzmek
  -- YETMEZ (yerel sınama: "Ali@Ornek.com" süzülünce "aliornek.com" kaldı);
  -- biçime uymayan girdi bütünüyle 'gecersiz' olur.
  detay       text not null default '',
  user_id     uuid references auth.users(id) on delete set null,
  platform    text not null default 'diger',
  surum       text,
  -- İstemcinin olayı yaşadığı an (çevrimdışı kuyruk sonradan gönderir;
  -- sıralama bozulmasın). Sunucuda [now-7g, now] aralığına kıstırılır.
  ts          timestamptz not null,
  -- Sunucuya yazıldığı an: taşma sınırı ve saklama bu eksende.
  yazildi     timestamptz not null default now(),
  constraint huni_olaylari_adim_chk check (adim in (
    'ilk_acilis', 'kayit_ekrani', 'kayit_formu', 'otp_gonderildi',
    'otp_dogrulandi', 'kayit_hatasi', 'ilk_giris', 'yasal_onay',
    'kullanici_adi', 'tur', 'ana_ekran')),
  constraint huni_olaylari_detay_chk check (
    detay ~ '^([a-z0-9_]{1,24}:[a-z0-9_]{1,40})?$' or detay = 'gecersiz'),
  constraint huni_olaylari_platform_chk check (platform in ('android', 'ios', 'diger')),
  constraint huni_olaylari_surum_chk check (surum is null or surum ~ '^[0-9A-Za-z.+-]{1,24}$')
);

-- Her adım kurulum başına BİR kez (hata: her farklı kod bir kez). Tekrar
-- gönderim (yeniden deneme kuyruğu) sayıyı şişiremez.
create unique index if not exists huni_olaylari_tekil
  on public.huni_olaylari (kurulum_id, adim, detay);
create index if not exists huni_olaylari_ts_idx on public.huni_olaylari (ts);
create index if not exists huni_olaylari_yazildi_idx on public.huni_olaylari (yazildi);
create index if not exists huni_olaylari_user_idx
  on public.huni_olaylari (user_id) where user_id is not null;

-- Kimse doğrudan okuyamaz/yazamaz: yazma `huni_kaydet`, okuma `admin_huni_*`.
-- Supabase'in public şemadaki varsayılan GRANT'ları açıkça geri alınır.
alter table public.huni_olaylari enable row level security;
alter table public.huni_olaylari force row level security;
revoke all on table public.huni_olaylari from public, anon, authenticated;
revoke all on sequence public.huni_olaylari_id_seq from public, anon, authenticated;

comment on table public.huni_olaylari is
  'Kayıt hunisi adım defteri (0097). Kurulum başına rastgele kimlik; PII yok. Yazma: huni_kaydet. Okuma: admin_huni_*.';

-- ── 2. huni_kaydet ─────────────────────────────────────────────────────────
-- Oturumsuz çağrılır: huninin üst yarısı (ilk açılış, kayıt ekranı) tanımı
-- gereği giriş ÖNCESİDİR. anon anahtarı uygulama ikilisinde taşındığı için
-- bu uç herkese açıktır; tehdit modeli ve karşılığı:
--
--   · user_id taklidi  → istemci user_id GÖNDEREMEZ, `auth.uid()`'den alınır.
--   · Çöp adım/metin   → adım beyaz listede, detay/sürüm biçim kısıtlı
--                        (detay biçime uymazsa 'gecersiz', süzülmez);
--                        geçersiz girdi hata DEĞİL sessiz no-op (istemci
--                        hata ekranı görmesin, saldırgan geri bildirim almasın).
--   · Tablo şişirme    → kurulum başına 40 satır, sunucu geneli dakikada
--                        300 satır. Gerçek trafik bunun çok altında; sınır
--                        aşılırsa sayım eksik kalır, veritabanı büyümez.
--   · Okuma            → fonksiyon hiçbir şey döndürmez; var olan bir
--                        kurulum_id'yi doğrulamak bile mümkün değil.
--
-- Kalan risk (bilinçli): anahtarı ikiliden söken biri dakikada 300 sahte
-- satıra kadar huni sayılarını kirletebilir. Bunun karşılığı kimlik
-- doğrulaması olurdu — ama doğrulanacak bir kimlik yok, ölçtüğümüz şey
-- kimliksiz ziyaretçi.
create or replace function public.huni_kaydet(
  p_kurulum  uuid,
  p_adim     text,
  p_detay    text        default '',
  p_platform text        default null,
  p_surum    text        default null,
  p_ts       timestamptz default null
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_detay text := '';
begin
  if p_kurulum is null or p_adim is null or p_adim not in (
    'ilk_acilis', 'kayit_ekrani', 'kayit_formu', 'otp_gonderildi',
    'otp_dogrulandi', 'kayit_hatasi', 'ilk_giris', 'yasal_onay',
    'kullanici_adi', 'tur', 'ana_ekran') then
    return;
  end if;

  if p_adim = 'kayit_hatasi' then
    v_detay := case when p_detay ~ '^[a-z0-9_]{1,24}:[a-z0-9_]{1,40}$'
                    then p_detay else 'gecersiz' end;
  end if;

  if (select count(*) from public.huni_olaylari h where h.kurulum_id = p_kurulum) >= 40 then
    return;
  end if;
  if (select count(*) from public.huni_olaylari h
      where h.yazildi > now() - interval '1 minute') >= 300 then
    return;
  end if;

  insert into public.huni_olaylari (kurulum_id, adim, detay, user_id, platform, surum, ts)
  values (
    p_kurulum,
    p_adim,
    v_detay,
    v_uid,
    case when p_platform in ('android', 'ios') then p_platform else 'diger' end,
    case when p_surum ~ '^[0-9A-Za-z.+-]{1,24}$' then p_surum end,
    least(now(), greatest(coalesce(p_ts, now()), now() - interval '7 days'))
  )
  on conflict (kurulum_id, adim, detay) do nothing;

  -- Oturum açıldıysa bu kurulumun oturumsuz satırları kişiye bağlanır:
  -- "kayıt ekranına gelen" ile "kayıt olan" aynı yolculuk olarak okunsun.
  -- Yalnızca boş olanlar — aynı cihazda ikinci hesap ilk kişinin
  -- geçmişini devralmaz.
  if v_uid is not null then
    update public.huni_olaylari h
       set user_id = v_uid
     where h.kurulum_id = p_kurulum
       and h.user_id is null;
  end if;
end;
$$;

revoke all on function public.huni_kaydet(uuid, text, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.huni_kaydet(uuid, text, text, text, text, timestamptz)
  to anon, authenticated;

-- Saklama: 400 gün (yıllık kıyas + pay). Ayrı cron yerine db_logs'un
-- günlük işine eklendi (gerekçe: dosya başı, "İki sunucu").
create or replace function public.cleanup_db_logs()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.db_logs where ts < now() - interval '30 days';
  delete from public.huni_olaylari where yazildi < now() - interval '400 days';
$$;
revoke all on function public.cleanup_db_logs() from public, anon, authenticated;

-- ── 3. Yolculuk tablosu (iç) ───────────────────────────────────────────────
-- Panelin bütün sayıları buradan türer: bir satır = bir yolculuk.
--
-- p_kaynak = 'kurulum' → bu dönemde BAŞLAYAN kurulumlar (yalnızca bu
--   sürümle gelen istemciler; huninin beş adımının hepsi ölçülür).
-- p_kaynak = 'hesap'   → bu dönemde AÇILAN hesaplar (tüm sürümler; kayıt
--   öncesi adımlar yalnızca yeni sürümde dolu).
--
-- `geri_donen`: kuruluma bağlanan hesap kurulumdan önce açılmış — yeniden
-- yükleme ya da yeni telefon. Yeni kullanıcı değildir; panel onları
-- huniden çıkarıp ayrı sayar, yoksa "kayıt" sayısı şişer.
create or replace function public.huni_yolculuklar_ic(
  p_bas      timestamptz,
  p_kaynak   text,
  p_platform text default null
)
returns table (
  kurulum_id         uuid,
  user_id            uuid,
  platform           text,
  surum              text,
  saglayici          text,
  baslangic          timestamptz,
  hesap_acilis       timestamptz,
  geri_donen         boolean,
  ilk_acilis         timestamptz,
  kayit_ekrani       timestamptz,
  kayit_formu        timestamptz,
  otp_gonderildi     timestamptz,
  otp_dogrulandi     timestamptz,
  kayit              timestamptz,
  ilk_giris          timestamptz,
  yasal_onay         timestamptz,
  kullanici_adi      timestamptz,
  tur                timestamptz,
  ana_ekran          timestamptz,
  ilk_varlik         timestamptz,
  ilk_varlik_tahmini boolean,
  hata_sayisi        integer,
  son_hata           text,
  varlik_sayisi      integer
)
language sql
stable
security definer
set search_path = public, auth
as $$
  with
  h as (
    select
      k.kurulum_id,
      min(k.ts) as ilk_ts,
      min(k.ts) filter (where k.adim = 'ilk_acilis')     as ilk_acilis,
      min(k.ts) filter (where k.adim = 'kayit_ekrani')   as kayit_ekrani,
      min(k.ts) filter (where k.adim = 'kayit_formu')    as kayit_formu,
      min(k.ts) filter (where k.adim = 'otp_gonderildi') as otp_gonderildi,
      min(k.ts) filter (where k.adim = 'otp_dogrulandi') as otp_dogrulandi,
      min(k.ts) filter (where k.adim = 'ilk_giris')      as ilk_giris,
      min(k.ts) filter (where k.adim = 'yasal_onay')     as yasal_onay,
      min(k.ts) filter (where k.adim = 'kullanici_adi')  as kullanici_adi,
      min(k.ts) filter (where k.adim = 'tur')            as tur,
      min(k.ts) filter (where k.adim = 'ana_ekran')      as ana_ekran,
      (count(*) filter (where k.adim = 'kayit_hatasi'))::int as hata_sayisi,
      (array_agg(k.detay order by k.ts desc) filter (where k.adim = 'kayit_hatasi'))[1] as son_hata,
      (array_agg(k.user_id order by k.ts) filter (where k.user_id is not null))[1] as user_id,
      (array_agg(k.platform order by k.ts))[1] as platform,
      (array_agg(k.surum order by k.ts desc) filter (where k.surum is not null))[1] as surum
    from public.huni_olaylari k
    where k.kurulum_id in (
      select distinct k2.kurulum_id from public.huni_olaylari k2
      where k2.ts >= p_bas - interval '1 day')
    group by k.kurulum_id
  ),
  u as (
    select
      au.id as user_id,
      au.created_at,
      au.email_confirmed_at,
      au.last_sign_in_at,
      coalesce(au.raw_app_meta_data->>'provider', 'email') as saglayici
    from auth.users au
    where au.created_at >= p_bas
       or au.id in (select h.user_id from h where h.user_id is not null)
  ),
  -- İlk giriş: GoTrue defteri. `user_signedup` e-posta onayında (OTP)
  -- oturum da açtığı için ilk giriş sayılır. payload `json` (jsonb değil)
  -- ve actor_id bazı satırlarda boş — uuid'e çevirmeden önce süzülür.
  g as (
    select (a.payload->>'actor_id')::uuid as user_id, min(a.created_at) as ilk_giris
    from auth.audit_log_entries a
    where a.created_at >= p_bas - interval '1 day'
      and a.payload->>'action' in ('login', 'user_signedup')
      and a.payload->>'actor_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    group by 1
  ),
  v as (
    select
      a.user_id,
      min(a.created_at) as ilk_damga,
      (count(*) filter (where a.deleted_at is null))::int as varlik_sayisi
    from public.assets a
    where a.user_id in (select u.user_id from u)
    group by a.user_id
  ),
  pt as (
    select distinct on (t.user_id) t.user_id, t.platform
    from public.user_push_tokens t
    where t.user_id in (select u.user_id from u)
      and t.platform in ('android', 'ios')
    order by t.user_id, t.updated_at desc
  ),
  j0 as (
    select
      h.kurulum_id,
      coalesce(h.user_id, u.user_id) as user_id,
      coalesce(nullif(h.platform, 'diger'), pt.platform, 'diger') as platform,
      h.surum,
      u.saglayici,
      coalesce(h.ilk_ts, u.created_at) as baslangic,
      u.created_at as hesap_acilis,
      (h.kurulum_id is not null and u.created_at is not null
        and u.created_at < h.ilk_ts - interval '10 minutes') as geri_donen,
      h.ilk_acilis, h.kayit_ekrani, h.kayit_formu,
      -- PG'de least/greatest NULL'u yok sayar: hangi kaynak varsa o.
      least(h.otp_gonderildi,
            case when u.saglayici = 'email' then u.created_at end) as otp_gonderildi,
      least(h.otp_dogrulandi,
            case when u.saglayici = 'email' then u.email_confirmed_at end) as otp_dogrulandi,
      case when u.user_id is null then null
           when u.saglayici = 'email' then u.email_confirmed_at
           else u.created_at end as kayit,
      coalesce(least(h.ilk_giris, g.ilk_giris), u.last_sign_in_at) as ilk_giris,
      h.yasal_onay, h.kullanici_adi, h.tur, h.ana_ekran,
      -- Damga hesaptan önceyse ya da 0095 dolgusuysa (alış tarihi) giriş
      -- anı değildir: hesap açılışına kıstırılır ve tahmin diye işaretlenir.
      -- `case` şart: greatest NULL'u yok sayar, varlıksız kişiye hesap
      -- açılışını "ilk varlık" diye yazardı.
      case when v.ilk_damga is not null
           then greatest(v.ilk_damga, u.created_at) end as ilk_varlik,
      coalesce(v.ilk_damga < u.created_at
               or v.ilk_damga < timestamptz '2026-10-01 00:00+03', false)
        as ilk_varlik_tahmini,
      coalesce(h.hata_sayisi, 0) as hata_sayisi,
      h.son_hata,
      coalesce(v.varlik_sayisi, 0) as varlik_sayisi
    from h
    full outer join u on u.user_id = h.user_id
    left join g  on g.user_id  = coalesce(h.user_id, u.user_id)
    left join v  on v.user_id  = coalesce(h.user_id, u.user_id)
    left join pt on pt.user_id = coalesce(h.user_id, u.user_id)
  ),
  j as (
    select * from j0
    where p_platform is null or j0.platform = p_platform
  )
  (
    select j.kurulum_id, j.user_id, j.platform, j.surum, j.saglayici, j.baslangic,
           j.hesap_acilis, j.geri_donen, j.ilk_acilis, j.kayit_ekrani, j.kayit_formu,
           j.otp_gonderildi, j.otp_dogrulandi, j.kayit, j.ilk_giris, j.yasal_onay,
           j.kullanici_adi, j.tur, j.ana_ekran, j.ilk_varlik, j.ilk_varlik_tahmini,
           j.hata_sayisi, j.son_hata, j.varlik_sayisi
    from j
    where p_kaynak = 'kurulum'
      and j.kurulum_id is not null
      -- İstemci kuyruğu sıralı ve ilk elemanı hep ilk_acilis: onsuz bir
      -- kurulum ya istemci dışından (çöp) gelmiştir ya da yarımdır.
      -- Yerel sınamada tek bir sahte hata satırı "yolculuk" sayılıyordu.
      and j.ilk_acilis is not null
      and j.baslangic >= p_bas
  )
  union all
  (
    -- Hesap görünümünde kişi başına TEK satır: aynı hesap iki cihazda
    -- kurulduysa ilk kurulum yolculuğu temsil eder.
    select distinct on (j.user_id)
           j.kurulum_id, j.user_id, j.platform, j.surum, j.saglayici, j.baslangic,
           j.hesap_acilis, false, j.ilk_acilis, j.kayit_ekrani, j.kayit_formu,
           j.otp_gonderildi, j.otp_dogrulandi, j.kayit, j.ilk_giris, j.yasal_onay,
           j.kullanici_adi, j.tur, j.ana_ekran, j.ilk_varlik, j.ilk_varlik_tahmini,
           j.hata_sayisi, j.son_hata, j.varlik_sayisi
    from j
    where p_kaynak = 'hesap'
      and j.user_id is not null
      and j.hesap_acilis >= p_bas
    order by j.user_id, j.geri_donen, j.baslangic
  );
$$;

-- İç fonksiyon: yönetici kapısı YOK, bu yüzden hiçbir rol çağıramaz.
-- Yalnızca aşağıdaki admin_huni_* (definer, sahibi postgres) çağırır.
revoke all on function public.huni_yolculuklar_ic(timestamptz, text, text)
  from public, anon, authenticated;

-- ── 4. admin_huni_ozet: huninin adımları ───────────────────────────────────
-- Satır başına bir adım: kaç yolculuk ulaştı + bir ÖNCEKİ adımdan bu
-- adıma geçen sürenin medyanı ve p90'ı. Süre yalnızca iki ucu da ölçülmüş
-- ve sırası doğru yolculuklardan; tahmini ilk varlık süreye girmez.
--
-- Ek satırlar: `yolculuk` (taban), `geri_donen` (huniden çıkarılan),
-- `kayit_hatasi` (kayıtta en az bir hata gören yolculuk).
create or replace function public.admin_huni_ozet(
  p_gun      int  default 30,
  p_kaynak   text default 'kurulum',
  p_platform text default null
)
returns table (
  adim   text,
  sira   int,
  ana    boolean,
  adet   bigint,
  olcum  bigint,
  p50_sn int,
  p90_sn int
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_bas timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_gun, 30), 365)));
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;
  if p_kaynak not in ('kurulum', 'hesap') then
    raise exception 'p_kaynak kurulum|hesap olmali';
  end if;

  return query
  with j as (
    select * from public.huni_yolculuklar_ic(v_bas, p_kaynak, p_platform)
  ),
  yeni as (select * from j where not j.geri_donen),
  s as (
    select x.adim, x.sira, x.ana, x.ts, x.onceki, x.tahmini
    from yeni
    cross join lateral (values
      ('ilk_acilis',      1, true,  yeni.ilk_acilis,     null::timestamptz,  false),
      ('kayit_ekrani',    2, true,  yeni.kayit_ekrani,   yeni.ilk_acilis,    false),
      ('kayit_formu',     3, false, yeni.kayit_formu,    yeni.kayit_ekrani,  false),
      ('otp_gonderildi',  4, false, yeni.otp_gonderildi, yeni.kayit_formu,   false),
      ('otp_dogrulandi',  5, false, yeni.otp_dogrulandi, yeni.otp_gonderildi, false),
      ('kayit',           6, true,  yeni.kayit,
         coalesce(yeni.kayit_ekrani, yeni.otp_gonderildi), false),
      ('ilk_giris',       7, true,  yeni.ilk_giris,      yeni.kayit,         false),
      ('yasal_onay',      8, false, yeni.yasal_onay,     yeni.ilk_giris,     false),
      ('kullanici_adi',   9, false, yeni.kullanici_adi,
         coalesce(yeni.yasal_onay, yeni.ilk_giris), false),
      ('tur',            10, false, yeni.tur,
         coalesce(yeni.kullanici_adi, yeni.yasal_onay, yeni.ilk_giris), false),
      ('ana_ekran',      11, false, yeni.ana_ekran,
         coalesce(yeni.tur, yeni.kullanici_adi, yeni.yasal_onay, yeni.ilk_giris), false),
      ('ilk_varlik',     12, true,  yeni.ilk_varlik,     yeni.ilk_giris,     yeni.ilk_varlik_tahmini)
    ) as x(adim, sira, ana, ts, onceki, tahmini)
  )
  select s.adim, s.sira, s.ana,
         count(s.ts),
         count(*) filter (where s.ts >= s.onceki and not s.tahmini),
         (percentile_cont(0.5) within group (order by extract(epoch from s.ts - s.onceki)::float8)
            filter (where s.ts >= s.onceki and not s.tahmini))::int,
         (percentile_cont(0.9) within group (order by extract(epoch from s.ts - s.onceki)::float8)
            filter (where s.ts >= s.onceki and not s.tahmini))::int
  from s
  group by s.adim, s.sira, s.ana
  union all
  select 'yolculuk', 0, false, (select count(*) from yeni), 0::bigint, null::int, null::int
  union all
  select 'geri_donen', 98, false, (select count(*) from j where j.geri_donen), 0::bigint, null::int, null::int
  union all
  select 'kayit_hatasi', 99, false,
         (select count(*) from yeni where yeni.hata_sayisi > 0), 0::bigint, null::int, null::int
  order by 2;
end;
$$;

-- ── 5. admin_huni_gunluk: gün gün ana adımlar ──────────────────────────────
-- Olay GÜNÜNE göre (İstanbul takvimi): "dün kaç kayıt oldu". Kohort
-- dönüşümü özet kartında; bu eğri hacmin ritmini gösterir.
create or replace function public.admin_huni_gunluk(
  p_gun      int  default 30,
  p_kaynak   text default 'kurulum',
  p_platform text default null
)
returns table (
  gun  date,
  adim text,
  adet bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_bas timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_gun, 30), 365)));
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;
  if p_kaynak not in ('kurulum', 'hesap') then
    raise exception 'p_kaynak kurulum|hesap olmali';
  end if;

  return query
  select (x.ts at time zone 'Europe/Istanbul')::date, x.adim, count(*)
  from public.huni_yolculuklar_ic(v_bas, p_kaynak, p_platform) j
  cross join lateral (values
    ('ilk_acilis', j.ilk_acilis),
    ('kayit_ekrani', j.kayit_ekrani),
    ('kayit', j.kayit),
    ('ilk_giris', j.ilk_giris),
    ('ilk_varlik', j.ilk_varlik)
  ) as x(adim, ts)
  where not j.geri_donen
    and x.ts is not null
    and x.ts >= v_bas
  group by 1, 2
  order by 1, 2;
end;
$$;

-- ── 6. admin_huni_kirilim: platform / sürüm / sağlayıcı ────────────────────
-- "Android'de kayıt ekranından kayda geçiş iOS'un yarısı" gibi farklar
-- toplam huni içinde kaybolur; kırılım onları ayırır.
create or replace function public.admin_huni_kirilim(
  p_gun    int  default 30,
  p_kaynak text default 'kurulum',
  p_boyut  text default 'platform'
)
returns table (
  deger        text,
  yolculuk     bigint,
  ilk_acilis   bigint,
  kayit_ekrani bigint,
  kayit        bigint,
  ilk_giris    bigint,
  ilk_varlik   bigint,
  hata         bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_bas timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_gun, 30), 365)));
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;
  if p_kaynak not in ('kurulum', 'hesap') then
    raise exception 'p_kaynak kurulum|hesap olmali';
  end if;
  if p_boyut not in ('platform', 'surum', 'saglayici') then
    raise exception 'p_boyut platform|surum|saglayici olmali';
  end if;

  return query
  select
    coalesce(case p_boyut
               when 'platform'  then j.platform
               when 'surum'     then j.surum
               else j.saglayici
             end, '—') as deger,
    count(*),
    count(j.ilk_acilis),
    count(j.kayit_ekrani),
    count(j.kayit),
    count(j.ilk_giris),
    count(j.ilk_varlik),
    count(*) filter (where j.hata_sayisi > 0)
  from public.huni_yolculuklar_ic(v_bas, p_kaynak, null) j
  where not j.geri_donen
  group by 1
  order by 2 desc;
end;
$$;

-- ── 7. admin_huni_yolculuklar: kişi kişi ───────────────────────────────────
-- Sayıların arkasındaki satırlar. `p_son_adim` ile "kayıt ekranında
-- kalanlar" gibi tek bir düşüş noktası listelenir. E-posta `profiles`
-- join'inden (0070 PII kararı: panel e-postayı açık gösterir).
create or replace function public.admin_huni_yolculuklar(
  p_gun      int  default 30,
  p_kaynak   text default 'kurulum',
  p_platform text default null,
  p_son_adim text default null,
  p_limit    int  default 200
)
returns table (
  kurulum_id         uuid,
  user_id            uuid,
  email              text,
  display_name       text,
  platform           text,
  surum              text,
  saglayici          text,
  baslangic          timestamptz,
  geri_donen         boolean,
  son_adim           text,
  ilk_acilis         timestamptz,
  kayit_ekrani       timestamptz,
  kayit_formu        timestamptz,
  otp_gonderildi     timestamptz,
  otp_dogrulandi     timestamptz,
  kayit              timestamptz,
  ilk_giris          timestamptz,
  yasal_onay         timestamptz,
  kullanici_adi      timestamptz,
  tur                timestamptz,
  ana_ekran          timestamptz,
  ilk_varlik         timestamptz,
  ilk_varlik_tahmini boolean,
  hata_sayisi        integer,
  son_hata           text,
  varlik_sayisi      integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_bas timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_gun, 30), 365)));
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;
  if p_kaynak not in ('kurulum', 'hesap') then
    raise exception 'p_kaynak kurulum|hesap olmali';
  end if;

  return query
  with j as (
    select
      y.*,
      case
        when y.geri_donen               then 'geri_donen'
        when y.ilk_varlik     is not null then 'ilk_varlik'
        when y.ilk_giris      is not null then 'ilk_giris'
        when y.kayit          is not null then 'kayit'
        when y.kayit_ekrani   is not null then 'kayit_ekrani'
        when y.ilk_acilis     is not null then 'ilk_acilis'
        else 'hesap'
      end as son
    from public.huni_yolculuklar_ic(v_bas, p_kaynak, p_platform) y
  )
  select
    j.kurulum_id, j.user_id, p.email, p.display_name, j.platform, j.surum,
    j.saglayici, j.baslangic, j.geri_donen, j.son,
    j.ilk_acilis, j.kayit_ekrani, j.kayit_formu, j.otp_gonderildi, j.otp_dogrulandi,
    j.kayit, j.ilk_giris, j.yasal_onay, j.kullanici_adi, j.tur, j.ana_ekran,
    j.ilk_varlik, j.ilk_varlik_tahmini, j.hata_sayisi, j.son_hata, j.varlik_sayisi
  from j
  left join public.profiles p on p.id = j.user_id
  where p_son_adim is null or j.son = p_son_adim
  order by j.baslangic desc
  limit least(coalesce(p_limit, 200), 1000);
end;
$$;

-- ── 8. admin_huni_hatalar: huni neden düşüyor ──────────────────────────────
-- İki kaynak, tek tablo:
--   'kayit'   → huni_olaylari.kayit_hatasi: OTURUMSUZ hatalar (db_logs'a
--               hiç düşmeyenler). Anahtar "asama:kod".
--   'ilk_gun' → db_logs: hesabı bu dönemde açılan kişilerin ilk 48
--               saatindeki hataları. Yeni kullanıcıyı kaçıran arıza budur.
create or replace function public.admin_huni_hatalar(
  p_gun   int default 30,
  p_limit int default 50
)
returns table (
  kaynak   text,
  anahtar  text,
  servis   text,
  ornek    text,
  adet     bigint,
  kisi     bigint,
  son      timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_bas timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_gun, 30), 365)));
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  (
    select 'kayit'::text, k.detay, null::text, null::text,
           count(*), count(distinct k.kurulum_id), max(k.ts)
    from public.huni_olaylari k
    where k.adim = 'kayit_hatasi' and k.ts >= v_bas
    group by k.detay
  )
  union all
  (
    select 'ilk_gun'::text,
           coalesce(d.error_type, '?') || coalesce(':' || nullif(d.error_code, ''), ''),
           d.source,
           left(coalesce(d.error_message, d.response_json->>'error', '(mesajsız)'), 160),
           count(*), count(distinct d.user_id), max(d.ts)
    from public.db_logs d
    join auth.users au on au.id = d.user_id
    where d.is_error
      and au.created_at >= v_bas
      and d.ts >= v_bas
      and d.ts < au.created_at + interval '48 hours'
    group by 2, 3, 4
  )
  order by 5 desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.admin_huni_ozet(int, text, text)',
    'public.admin_huni_gunluk(int, text, text)',
    'public.admin_huni_kirilim(int, text, text)',
    'public.admin_huni_yolculuklar(int, text, text, text, int)',
    'public.admin_huni_hatalar(int, int)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ── Doğrulama: sözleşme bozulursa migration patlasın ───────────────────────
-- CLAUDE.md: "GRANT ve RLS ayrı şeylerdir; eksikse raise exception ile
-- doğrula" (0036/0042/0043/0070 örnek).
do $$
declare
  v_kotu text;
begin
  -- (a) admin_huni_*: authenticated çağırır, anon ÇAĞIRAMAZ, definer + search_path.
  select string_agg(p.proname, ', ') into v_kotu
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname like 'admin\_huni\_%'
    and (not has_function_privilege('authenticated', p.oid, 'execute')
         or has_function_privilege('anon', p.oid, 'execute')
         or not p.prosecdef
         or p.proconfig is null
         or not exists (select 1 from unnest(p.proconfig) c where c like 'search\_path=%'));
  if v_kotu is not null then
    raise exception 'admin_huni_* sozlesmesi bozuk: %', v_kotu;
  end if;

  -- (b) İç fonksiyonun yönetici kapısı yok: hiçbir istemci rolü çağıramamalı.
  if has_function_privilege('anon', 'public.huni_yolculuklar_ic(timestamptz, text, text)', 'execute')
     or has_function_privilege('authenticated', 'public.huni_yolculuklar_ic(timestamptz, text, text)', 'execute') then
    raise exception 'huni_yolculuklar_ic istemciye acik';
  end if;

  -- (c) Tablo doğrudan okunamaz/yazılamaz — tek yol huni_kaydet.
  if has_table_privilege('anon', 'public.huni_olaylari', 'select')
     or has_table_privilege('anon', 'public.huni_olaylari', 'insert')
     or has_table_privilege('authenticated', 'public.huni_olaylari', 'select')
     or has_table_privilege('authenticated', 'public.huni_olaylari', 'insert')
     or has_table_privilege('authenticated', 'public.huni_olaylari', 'update') then
    raise exception 'huni_olaylari istemciye dogrudan acik';
  end if;

  -- (d) Yazma yolu oturumsuz da çalışmalı — yoksa huninin üst yarısı boş kalır.
  if not has_function_privilege('anon', 'public.huni_kaydet(uuid, text, text, text, text, timestamptz)', 'execute') then
    raise exception 'huni_kaydet anon icin kapali; kayit oncesi adimlar yazilamaz';
  end if;

  -- (e) PII sözleşmesi: e-posta / ad / token / IP sütunu eklenirse patla.
  select string_agg(c.column_name, ', ') into v_kotu
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'huni_olaylari'
    and c.column_name not in ('id', 'kurulum_id', 'adim', 'detay', 'user_id',
                              'platform', 'surum', 'ts', 'yazildi');
  if v_kotu is not null then
    raise exception 'huni_olaylari beklenmeyen sutun (PII sozlesmesi): %', v_kotu;
  end if;
end $$;

comment on function public.huni_kaydet(uuid, text, text, text, text, timestamptz) is
  'Kayıt hunisi adımı yazar (0097). Oturumsuz çağrılabilir; user_id auth.uid()''den. Sınırlar: kurulum başına 40, dakikada 300 satır.';
comment on function public.admin_huni_ozet(int, text, text) is
  'Admin paneli: huni adımları, adet ve önceki adımdan geçiş süresi (p50/p90).';
comment on function public.admin_huni_gunluk(int, text, text) is
  'Admin paneli: ana huni adımları gün gün (İstanbul takvimi).';
comment on function public.admin_huni_kirilim(int, text, text) is
  'Admin paneli: huni platform / sürüm / giriş sağlayıcısı kırılımı.';
comment on function public.admin_huni_yolculuklar(int, text, text, text, int) is
  'Admin paneli: yolculuk başına adım zamanları; p_son_adim ile düşüş noktası süzülür.';
comment on function public.admin_huni_hatalar(int, int) is
  'Admin paneli: kayıt sırasında (oturumsuz) ve ilk 48 saatte alınan hatalar.';
