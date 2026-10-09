-- ============================================================
-- 0128 — Sıralamanın asgari ölçüm süresi AYARLANABİLİR (2026-10-09)
-- ============================================================
--
-- Kullanıcı kararı (yasin, 2026-10-09, thread "Zirve havuzu"): "Bu 30 günü
-- parametrik yapalım, ve 30 gün eklenen ilk varlığının ekleme tarihi olsun
-- (uygulamaya değil varlığı elde ediş tarihi)."
--
-- 1) Süre bu tek satırlık tablodan okunur (önce `leaderboard-snapshot`'ta
--    ve istemcide sabit `ASGARI_OLCUM_GUN = 30` idi, 0095). Değiştirmek:
--      update public.siralama_ayar set asgari_olcum_gun = 14, guncellendi = now();
--    Kanıt (Tokyo, 2026-10-09): rıza veren 6 kişinin 2'si yalnız bu şart
--    yüzünden Zirve havuzunun dışındaydı.
--
-- 2) Sayaç artık ilk varlığın EDİNME tarihinden (`added_date`) başlar —
--    kod tarafında (`leaderboard-snapshot` › `donemTwr`, istemci
--    `secim_getirisi.dart`). Getirinin ÖLÇÜLDÜĞÜ aralık değişmedi: 3 günden
--    fazla geriye tarihli kayıt anonim sıralamada girildiği gün sayılır
--    (0095 hile kuralı). Yani içe aktarılan geçmiş kapıyı hemen açar ama
--    getiri yalnız uygulamaya girildiği günden beri ölçülür.
--
-- Eski sürümle uyum: yalnız EKLER. Tablo yoksa ya da okunamazsa fonksiyon
-- ve istemci 30'a düşer (eski davranış).
-- ============================================================

create table if not exists public.siralama_ayar (
  tek              boolean primary key default true check (tek),
  asgari_olcum_gun integer not null default 30
                     check (asgari_olcum_gun between 0 and 365),
  guncellendi      timestamptz not null default now()
);
insert into public.siralama_ayar (tek) values (true) on conflict (tek) do nothing;

comment on table public.siralama_ayar is
  'Siralama (Zirve, genel, Yaris) ayarlari (0128). Tek satir; yalniz '
  'service_role okur/yazar, istemci siralama_asgari_olcum_gun() ile okur.';

alter table public.siralama_ayar enable row level security;
alter table public.siralama_ayar force row level security;
revoke all on table public.siralama_ayar from public, anon, authenticated;
grant select, update on table public.siralama_ayar to service_role;

-- İstemci ekran metni ve cihazda ölçülen Yarış aynı süreyi kullansın diye.
-- Bir sayı döner; kimseye ait veri yok.
create or replace function public.siralama_asgari_olcum_gun()
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select a.asgari_olcum_gun from public.siralama_ayar a where a.tek), 30);
$$;
revoke all on function public.siralama_asgari_olcum_gun() from public, anon;
grant execute on function public.siralama_asgari_olcum_gun() to authenticated, service_role;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if has_table_privilege('authenticated', 'public.siralama_ayar', 'SELECT')
     or has_table_privilege('anon', 'public.siralama_ayar', 'SELECT') then
    raise exception '0128: siralama_ayar istemciye kapali olmali';
  end if;
  if not has_table_privilege('service_role', 'public.siralama_ayar', 'SELECT') then
    raise exception '0128: service_role siralama_ayar SELECT GRANT eksik';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.siralama_ayar'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0128: siralama_ayar RLS (enable + force) kapali';
  end if;
  if not has_function_privilege('authenticated', 'public.siralama_asgari_olcum_gun()', 'execute') then
    raise exception '0128: siralama_asgari_olcum_gun authenticated EXECUTE eksik';
  end if;
  if has_function_privilege('anon', 'public.siralama_asgari_olcum_gun()', 'execute') then
    raise exception '0128: siralama_asgari_olcum_gun anon tarafindan cagrilabilir olmamali';
  end if;
  if (select count(*) from public.siralama_ayar) <> 1 then
    raise exception '0128: siralama_ayar tek satir olmali';
  end if;
end $$;
