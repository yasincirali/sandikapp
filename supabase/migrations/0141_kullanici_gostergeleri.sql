-- 0141 — Kendi göstergeni yaz: kullanıcı gösterge betikleri (2026-10-10)
--
-- ## Neden
-- yasin (2026-10-10): "traderlar TradingView'e kendi kodlarını ekleyerek kendi
-- generic göstergelerini kullanabiliyorlar … bunu paywall arkasına ekleyelim."
-- Kullanıcı Pine Script (TradingView) kodunu yapıştırır ya da yazar
-- (`lib/services/gosterge_betigi/betik.dart`); betik CİHAZDA çalışır. Sunucu
-- yalnız METNİ saklar ki gösterge kullanıcının bütün cihazlarında aynı olsun.
-- Sunucuda kod ÇALIŞTIRILMAZ: `kod` sütunu düz metindir, hiçbir fonksiyon onu
-- yorumlamaz.
--
-- ## Kişisel veri
-- Kullanıcının kendi yazdığı gösterge formülü ve adı; portföy/kimlik bilgisi
-- değil, üçüncü tarafa gitmez. Hesap silinince `on delete cascade` ile gider.
-- Yeni amaç, alıcı ya da saklama eklemez ("ilgili özelliklerin çalışması",
-- hesap silinene kadar); portföy adları (0133) gibi kullanıcının kendi
-- kurduğu ayar sayılır ve yasal metne dokunmaz (CLAUDE.md "Yasal metin tek
-- kaynak").
--
-- ## Premium
-- Yazma (INSERT/UPDATE) `premium_icerik_gorebilir()` (0116) ister: sunucu
-- kapısı kapalıyken her oturumlu kullanıcı, açıkken yalnız Premium. Okuma ve
-- silme her zaman sahibine açık: aboneliği biten kullanıcı kodunu kaybetmez,
-- silebilir (istemci zaten kilitli gösterir). İstemcide görünürlük ayrıca
-- `premiumOzellikleriGorunur` (paywall kapalıyken yalnız admin).
--
-- ## Sınırlar
-- Kod 20000 karakter (istemcideki `kBetikAzamiKarakter` ile aynı; TradingView
-- topluluk göstergeleri çoğunlukla 2-15 bin karakter), ad 40,
-- kullanıcı başına 20 gösterge. Sayı sınırı tetikleyiciyle: RLS satır sayamaz.
--
-- ## Eski istemciler
-- Yalnız EKLER (bir tablo, bir tetikleyici). Eski build bu tabloyu hiç okumaz.

create table if not exists public.kullanici_gostergeleri (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
              references auth.users(id) on delete cascade,
  ad          text not null check (char_length(btrim(ad)) between 1 and 40),
  kod         text not null check (char_length(kod) between 1 and 20000),
  -- Grafikte açık mı (çip sayfasındaki anahtar). Cihazlar arası aynı kalsın
  -- diye sunucuda.
  grafikte    boolean not null default true,
  olusturuldu timestamptz not null default now(),
  guncellendi timestamptz not null default now()
);

create index if not exists kullanici_gostergeleri_user_idx
  on public.kullanici_gostergeleri (user_id, olusturuldu);

alter table public.kullanici_gostergeleri enable row level security;
alter table public.kullanici_gostergeleri force row level security;

drop policy if exists kullanici_gostergeleri_oku on public.kullanici_gostergeleri;
create policy kullanici_gostergeleri_oku on public.kullanici_gostergeleri
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists kullanici_gostergeleri_ekle on public.kullanici_gostergeleri;
create policy kullanici_gostergeleri_ekle on public.kullanici_gostergeleri
  for insert to authenticated
  with check ((select auth.uid()) = user_id
              and public.premium_icerik_gorebilir());

drop policy if exists kullanici_gostergeleri_guncelle on public.kullanici_gostergeleri;
create policy kullanici_gostergeleri_guncelle on public.kullanici_gostergeleri
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id
              and public.premium_icerik_gorebilir());

drop policy if exists kullanici_gostergeleri_sil on public.kullanici_gostergeleri;
create policy kullanici_gostergeleri_sil on public.kullanici_gostergeleri
  for delete to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.kullanici_gostergeleri from public, anon;
grant select, insert, update, delete on table public.kullanici_gostergeleri
  to authenticated;
grant all on table public.kullanici_gostergeleri to service_role;

-- Sayı sınırı + `guncellendi` damgası. SECURITY INVOKER: sayım çağıranın RLS'i
-- altında yalnız kendi satırlarını görür, bu da tam istenen.
create or replace function public.kullanici_gostergeleri_denetim()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if (select count(*) from public.kullanici_gostergeleri g
         where g.user_id = new.user_id) >= 20 then
      raise exception 'kullanici_gostergeleri: en fazla 20 gosterge'
        using errcode = 'P0001';
    end if;
  else
    new.user_id := old.user_id;
    new.olusturuldu := old.olusturuldu;
  end if;
  new.guncellendi := now();
  return new;
end;
$$;

drop trigger if exists kullanici_gostergeleri_denetim on public.kullanici_gostergeleri;
create trigger kullanici_gostergeleri_denetim
  before insert or update on public.kullanici_gostergeleri
  for each row execute function public.kullanici_gostergeleri_denetim();

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if has_table_privilege('anon', 'public.kullanici_gostergeleri', 'SELECT') then
    raise exception '0141: anon kullanici_gostergeleri okuyamamali';
  end if;
  if not has_table_privilege('authenticated', 'public.kullanici_gostergeleri', 'INSERT') then
    raise exception '0141: authenticated INSERT GRANT eksik';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.kullanici_gostergeleri'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0141: kullanici_gostergeleri RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'kullanici_gostergeleri') <> 4 then
    raise exception '0141: kullanici_gostergeleri dort politika bekleniyordu';
  end if;
end $$;
