-- 0133 — Çoklu portföy: `portfoyler` + `assets.portfoy_id` (2026-10-10)
--
-- ## Neden (yasin, olgun Premium setinin ertelenen 2. maddesi)
-- "Aile / emeklilik ayrı" isteyen kullanıcı bugün ortaklıkla yetiniyordu.
-- Portföy, kullanıcının KENDİ lotlarını adlandırılmış kümelere ayırır;
-- Premium'da sınırsız, ücretsizde yalnız Ana (istemci `portfoyLimitProvider`).
--
-- ## Tasarım — YALNIZ EKLER (eski sürümler etkilenmez)
--   · `portfoyler`: yalnız ad ve sıra. Değer/maliyet/getiri lotlardan
--     hesaplanır; tabloya toplam yazılmaz (iki kaynaklı toplam "Σ parça ==
--     bütün" değişmezini kırar).
--   · `assets.portfoy_id` NULL = **Ana portföy**. Göç YOK: bütün mevcut
--     satırlar ve eski sürümün yazdığı her satır Ana'da durur.
--   · Eski istemci sütunu bilmez. UPDATE'te yalnız gövdesindeki sütunları
--     yazar (portfoy_id'ye dokunmaz, silemez); INSERT'te NULL bırakır →
--     aşağıdaki tetikleyici lot bazlı satış/temettünün portföyünü referans
--     lottan miras alır. Pozisyondan satış (`ref_asset_id` NULL) Ana'ya
--     düşer — bilinçli v1 sınırı (TECHNICAL_DEBT.md).
--   · Portföy silinince lotları SİLİNMEZ, Ana'ya döner
--     (`on delete set null (portfoy_id)`) — veri kaybı yok.
--   · Sunucu fonksiyonları (yarış, zirve, widget/Live Activity push, yıl
--     özeti) `assets`'i AÇIK kolon listesiyle okur ve kullanıcı TOPLAMI
--     hesaplar; hiçbiri değişmez. `assets_giris_ani` (0095) kolon listesine
--     portfoy_id EKLENMEDİ: portföyler arası taşıma bir ekonomik olay
--     değildir, yarışın "giriş anı"nı yenilememeli.

-- ── 1) Portföyler ──────────────────────────────────────────────────────────
create table if not exists public.portfoyler (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
              references auth.users(id) on delete cascade,
  -- İstemci aynı sınırı form basmadan gösterir (`Portfoy.adAzami`).
  ad          text not null check (char_length(btrim(ad)) between 1 and 40),
  sira        integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- Bileşik FK hedefi: lot, portföye ANCAK aynı kullanıcıyla bağlanabilsin.
  -- FK denetimi RLS'e tabi değildir; tek başına `portfoy_id` FK'si
  -- başkasının portföy kimliğine bağlanmaya izin verirdi (0088 deseni).
  constraint portfoyler_id_user_uq unique (id, user_id)
);

create index if not exists portfoyler_user_idx on public.portfoyler(user_id);

-- Aynı kullanıcıda aynı ad iki kez olmasın (büyük/küçük harf ve kenar
-- boşluğu fark etmez): seçicide iki "Emeklilik" hangisinin hangisi olduğunu
-- söylemez. İstemci önce kendisi denetler; bu, yarışan iki cihaza karşı.
create unique index if not exists portfoyler_ad_tekil
  on public.portfoyler(user_id, lower(btrim(ad)));

-- ── 2) Lot → portföy bağı ──────────────────────────────────────────────────
alter table public.assets add column if not exists portfoy_id uuid;

-- `on delete set null (portfoy_id)`: PG15+ sütun listesi. Düz `set null`
-- bileşik FK'nin İKİ sütununu da boşaltır ve `user_id not null` patlardı.
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'assets_portfoy_fk') then
    alter table public.assets
      add constraint assets_portfoy_fk foreign key (portfoy_id, user_id)
      references public.portfoyler(id, user_id)
      on delete set null (portfoy_id);
  end if;
end $$;

-- FK'nin silme tarafı (portföy silinince lotları bulmak) ve "portföyün
-- lotları" okuması için. Kısmi: satırların çoğu Ana'da (NULL) kalır.
create index if not exists assets_portfoy_idx
  on public.assets(portfoy_id) where portfoy_id is not null;

-- ── 3) updated_at ──────────────────────────────────────────────────────────
create or replace function public.portfoyler_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists portfoyler_updated_at on public.portfoyler;
create trigger portfoyler_updated_at
  before update on public.portfoyler
  for each row execute function public.portfoyler_updated_at();

-- ── 4) Kullanıcı başına üst sınır (kötüye kullanım bendi) ──────────────────
-- Ücretsiz/Premium sınırı istemcide (ödeme kapısı); burada yalnız makul bir
-- tavan: bir hesabın binlerce satırla seçiciyi ve FK indeksini şişirmesini
-- önler. 50, en kalabalık gerçek kullanımın (aile + emeklilik + çocuklar +
-- denemeler) çok üstünde.
create or replace function public.portfoyler_tavan()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if (select count(*) from public.portfoyler where user_id = new.user_id) >= 50 then
    raise exception 'portfoy_tavan' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists portfoyler_tavan on public.portfoyler;
create trigger portfoyler_tavan
  before insert on public.portfoyler
  for each row execute function public.portfoyler_tavan();

-- ── 5) Eski istemcinin lot bazlı satış/temettüsü portföyünü miras alır ─────
-- SECURITY INVOKER (varsayılan): referans lot RLS altında okunur. Yalnız
-- AYNI kullanıcının lotundan miras: ortağın lotuna referans verilmiş bir
-- satır (olmamalı ama) ortağın portföy kimliğini alıp bileşik FK'de
-- reddedilmesin — o durumda Ana'da kalır.
create or replace function public.assets_portfoy_mirasi()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.portfoy_id is null and new.ref_asset_id is not null then
    select a.portfoy_id into new.portfoy_id
      from public.assets a
     where a.id = new.ref_asset_id
       and a.user_id = new.user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists assets_portfoy_mirasi on public.assets;
create trigger assets_portfoy_mirasi
  before insert on public.assets
  for each row execute function public.assets_portfoy_mirasi();

-- ── 6) RLS ─────────────────────────────────────────────────────────────────
-- Sahip her şeyi yapar; ortak yalnız OKUR (`assets_partner_read`,
-- `sozlesmeler_partner_read` ile aynı kural). Ortak zaten bütün lotları
-- (ve `portfoy_id`'yi) okuyor; ad yeni bir alıcıya gitmiyor.
alter table public.portfoyler enable row level security;
alter table public.portfoyler force row level security;

drop policy if exists "portfoyler_own" on public.portfoyler;
create policy "portfoyler_own" on public.portfoyler
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "portfoyler_partner_read" on public.portfoyler;
create policy "portfoyler_partner_read" on public.portfoyler
  for select using (
    exists (
      select 1 from public.partnerships p
      where p.active = true
        and ((p.user_id_1 = auth.uid() and p.user_id_2 = user_id)
          or (p.user_id_2 = auth.uid() and p.user_id_1 = user_id))
    )
  );

-- ── 7) GRANT ───────────────────────────────────────────────────────────────
-- RLS ile GRANT ayrı şeylerdir (0036/0042/0043): GRANT yoksa sorgu sessizce
-- 0 satır döner. anon hiçbir şey göremez.
revoke all on table public.portfoyler from anon;
grant select, insert, update, delete on table public.portfoyler to authenticated;

-- ── 8) Doğrulama ───────────────────────────────────────────────────────────
do $$
declare
  g int;
  p int;
begin
  select count(*) into g from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'portfoyler'
     and grantee = 'authenticated'
     and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');
  select count(*) into p from pg_policies
   where schemaname = 'public' and tablename = 'portfoyler';

  if g <> 4 then
    raise exception '0133: portfoyler GRANT eksik: % / 4', g;
  end if;
  if p <> 2 then
    raise exception '0133: portfoyler RLS politikasi eksik: % / 2', p;
  end if;
  if has_table_privilege('anon', 'public.portfoyler', 'SELECT') then
    raise exception '0133: anon portfoyler okuyabiliyor';
  end if;
  if not exists (
    select 1 from pg_class
     where oid = 'public.portfoyler'::regclass
       and relrowsecurity and relforcerowsecurity
  ) then
    raise exception '0133: portfoyler RLS zorunlu degil';
  end if;
  if not exists (select 1 from pg_constraint where conname = 'assets_portfoy_fk') then
    raise exception '0133: assets_portfoy_fk yok';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'assets'
       and column_name = 'portfoy_id' and is_nullable = 'YES'
  ) then
    raise exception '0133: assets.portfoy_id yok ya da NULL olamaz';
  end if;
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.assets'::regclass
       and tgname = 'assets_portfoy_mirasi' and not tgisinternal
  ) then
    raise exception '0133: assets_portfoy_mirasi tetikleyicisi yok';
  end if;
end $$;

comment on table public.portfoyler is
  'Kullanicinin adlandirdigi portfoyler (0133). Deger lotlardan hesaplanir; '
  'assets.portfoy_id NULL = Ana portfoy. Silinince lotlar Ana''ya doner.';
comment on column public.assets.portfoy_id is
  'Lotun portfoyu (0133). NULL = Ana portfoy. Eski istemci yazmaz; lot bazli '
  'satis/temettu referans lottan miras alir (assets_portfoy_mirasi).';
