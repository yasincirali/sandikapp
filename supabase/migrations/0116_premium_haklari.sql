-- 0116 — Premium hakkı sunucuda (Balina Radarı G-11, 2026-10-05)
--
-- ## Neden
-- Premium bugün yalnız cihazdaki bir ayar (`premiumUnlockedProvider`,
-- SharedPreferences). Ücretli içerik — Balina F2'nin haftalık notları —
-- sunucuda korunacaksa "bu kullanıcı Premium mu" sorusunun cevabı sunucuda
-- olmalı. Kaynaklar:
--   · `revenuecat`: mağaza aboneliği. Yalnız `revenuecat-webhook` edge
--     function'ı yazar; o da RevenueCat'in kendi API'sinden doğrular.
--   · `erken_kullanici`: Premium planı (2026-10-04) — paywall açıldığı gün
--     mevcut kullanıcılara 90 gün. Toplu yazımı `erken_kullanici_hediyesi_ver`
--     yapar; yasin paywall açılışında bir kez çağırır (YAPMAN_GEREKENLER).
--   · `manuel`: destek / test hesabı.
-- Kullanıcı başına kaynak başına bir satır: hediye ile abonelik birbirini
-- ezmez; Premium = herhangi bir satır geçerli.
--
-- ## Eski sürümler
-- Yalnızca EKLER. Hiçbir eski istemci bu tabloyu okumaz; `paywall_enabled`
-- kapalıyken yeni istemci de kilit göstermez (bkz. `effectivePremiumProvider`).
--
-- ## Yetki
-- Kişisel veri: kullanıcı yalnız KENDİ satırlarını okur (RLS). Yazma yalnız
-- service_role. anon hiçbir şey. `premium_mi()` yalnız çağıranın kendi
-- durumunu söyler; başkasını sormak `premium_mi_kullanici` ile ve yalnız
-- service_role'a (edge function'lar) açık.

create table if not exists public.premium_haklari (
  user_id      uuid not null references auth.users (id) on delete cascade,
  kaynak       text not null check (kaynak in ('revenuecat', 'erken_kullanici', 'manuel')),
  -- Mağaza ürün kimliği ('sandik_premium_aylik'); hediye/manuel'de NULL.
  urun         text check (urun is null or length(urun) <= 120),
  -- 'app_store' | 'play_store' | 'promotional' …  (RevenueCat `store`).
  magaza       text check (magaza is null or length(magaza) <= 40),
  -- Hakkın bittiği an. NULL = süresiz (yalnız `manuel`).
  bitis        timestamptz,
  -- Otomatik yenileme kapatıldı; hak `bitis`'e kadar sürer.
  iptal_edildi boolean not null default false,
  -- RevenueCat sandbox satın alımı (test). Premium sayılır; raporda ayrılır.
  sandbox      boolean not null default false,
  baslangic    timestamptz not null default now(),
  guncellendi  timestamptz not null default now(),
  primary key (user_id, kaynak),
  constraint premium_haklari_suresiz_yalniz_manuel
    check (bitis is not null or kaynak = 'manuel')
);

create index if not exists premium_haklari_bitis_idx
  on public.premium_haklari (bitis);

comment on table public.premium_haklari is
  'Kullanicinin Premium haklari (0116). revenuecat-webhook ve erken_kullanici_hediyesi_ver '
  '(service_role) yazar; kullanici yalniz kendi satirini okur.';

alter table public.premium_haklari enable row level security;
alter table public.premium_haklari force row level security;

drop policy if exists premium_haklari_kendi on public.premium_haklari;
create policy premium_haklari_kendi
  on public.premium_haklari
  for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.premium_haklari from public, anon, authenticated;
grant select on table public.premium_haklari to authenticated;
grant select, insert, update, delete on table public.premium_haklari to service_role;

-- ── premium_mi ──────────────────────────────────────────────────────────────
-- Tek tanım: geçerli (bitmemiş) en az bir satır. RLS politikaları (0117
-- `varlik_analizi`) ve istemci aynı fonksiyonu sorar.
create or replace function public.premium_mi_kullanici(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.premium_haklari h
     where h.user_id = p_user_id
       and (h.bitis is null or h.bitis > now())
  );
$$;

revoke all on function public.premium_mi_kullanici(uuid) from public, anon, authenticated;
grant execute on function public.premium_mi_kullanici(uuid) to service_role;

-- Çağıranın kendisi. Oturum yoksa false.
create or replace function public.premium_mi()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.premium_mi_kullanici((select auth.uid())), false);
$$;

revoke all on function public.premium_mi() from public, anon;
grant execute on function public.premium_mi() to authenticated, service_role;

-- ── Erken kullanıcı hediyesi ────────────────────────────────────────────────
-- Paywall açılış günü yasin bir kez çağırır:
--   select public.erken_kullanici_hediyesi_ver('2026-11-01T00:00:00+03', 90);
-- [p_kesim]'den önce kaydolmuş, henüz `erken_kullanici` satırı olmayan herkese
-- şimdiden itibaren [p_gun] gün. Tekrar çağrılırsa var olan hediyeyi UZATMAZ
-- (idempotent). Dönen: yeni yazılan satır sayısı.
create or replace function public.erken_kullanici_hediyesi_ver(
  p_kesim timestamptz,
  p_gun integer default 90
)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_sayi integer;
begin
  if p_kesim is null or p_kesim > now() then
    raise exception 'erken_kullanici_hediyesi_ver: kesim gelecekte olamaz' using errcode = '22023';
  end if;
  if p_gun is null or p_gun < 1 or p_gun > 366 then
    raise exception 'erken_kullanici_hediyesi_ver: gun 1-366 olmali' using errcode = '22023';
  end if;

  insert into public.premium_haklari (user_id, kaynak, bitis)
  select u.id, 'erken_kullanici', now() + make_interval(days => p_gun)
    from auth.users u
   where u.created_at < p_kesim
     and u.deleted_at is null
  on conflict (user_id, kaynak) do nothing;
  get diagnostics v_sayi = row_count;
  return v_sayi;
end;
$$;

revoke all on function public.erken_kullanici_hediyesi_ver(timestamptz, integer)
  from public, anon, authenticated;
grant execute on function public.erken_kullanici_hediyesi_ver(timestamptz, integer) to service_role;


-- ── Sunucu tarafı kapı: Premium içerik ne zaman kilitlenir ──────────────────
-- İstemcide `paywall_enabled` (Remote Config) kapalıyken Premium sistemi yok
-- sayılır, kilit hiç çizilmez. Sunucu da aynı kuralı izlemeli: kapı kapalıyken
-- Premium içerik (0117 `varlik_analizi`) herkese açık, açıkken yalnız
-- Premium'a. Tek satırlık ayar; paywall açılış günü yasin, erken kullanıcı
-- hediyesiyle aynı anda çevirir:
--   update public.premium_ayar set kapi_acik = true;
-- İki ayrı anahtar (istemci + sunucu) bilinçli: istemci bayrağı eski build'leri
-- etkilemez, sunucu kapısı ise veriyi korur; biri diğerini beklemeden geri
-- alınabilir.
create table if not exists public.premium_ayar (
  tek        boolean primary key default true check (tek),
  kapi_acik  boolean not null default false,
  guncellendi timestamptz not null default now()
);
insert into public.premium_ayar (tek) values (true) on conflict (tek) do nothing;

alter table public.premium_ayar enable row level security;
alter table public.premium_ayar force row level security;
revoke all on table public.premium_ayar from public, anon, authenticated;
grant select, update on table public.premium_ayar to service_role;

-- Çağıran Premium içeriği görebilir mi: kapı kapalıysa herkes (oturumlu),
-- açıksa yalnız Premium.
create or replace function public.premium_icerik_gorebilir()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (select auth.uid()) is not null
     and (not coalesce((select a.kapi_acik from public.premium_ayar a where a.tek), false)
          or public.premium_mi());
$$;

revoke all on function public.premium_icerik_gorebilir() from public, anon;
grant execute on function public.premium_icerik_gorebilir() to authenticated, service_role;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.premium_haklari', 'SELECT') then
    raise exception '0116: authenticated icin premium_haklari SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.premium_haklari', 'INSERT')
     or has_table_privilege('authenticated', 'public.premium_haklari', 'UPDATE')
     or has_table_privilege('authenticated', 'public.premium_haklari', 'DELETE') then
    raise exception '0116: authenticated premium_haklari tablosuna YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.premium_haklari', 'SELECT') then
    raise exception '0116: anon premium_haklari tablosunu okuyamamali';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.premium_haklari'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0116: premium_haklari RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'premium_haklari') <> 1 then
    raise exception '0116: premium_haklari yalniz kendi-satir select politikasini tasimali';
  end if;
  if has_function_privilege('authenticated', 'public.premium_mi_kullanici(uuid)', 'EXECUTE') then
    raise exception '0116: premium_mi_kullanici authenticated tarafindan cagrilabilir olmamali (baskasini sorar)';
  end if;
  if not has_function_privilege('authenticated', 'public.premium_mi()', 'EXECUTE') then
    raise exception '0116: premium_mi authenticated EXECUTE eksik';
  end if;
  if has_function_privilege('anon', 'public.premium_mi()', 'EXECUTE') then
    raise exception '0116: premium_mi anon tarafindan cagrilabilir olmamali';
  end if;
  if has_function_privilege('authenticated',
       'public.erken_kullanici_hediyesi_ver(timestamptz, integer)', 'EXECUTE') then
    raise exception '0116: erken_kullanici_hediyesi_ver yalniz service_role olmali';
  end if;

  if has_table_privilege('authenticated', 'public.premium_ayar', 'SELECT') then
    raise exception '0116: premium_ayar istemciye kapali olmali';
  end if;
  if not has_function_privilege('authenticated', 'public.premium_icerik_gorebilir()', 'EXECUTE') then
    raise exception '0116: premium_icerik_gorebilir authenticated EXECUTE eksik';
  end if;

  raise notice '0116 tamam: premium_haklari + premium_mi + erken_kullanici_hediyesi_ver yerinde.';
end $$;
