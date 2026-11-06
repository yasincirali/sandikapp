-- 0173 — TCMB haftalık TL mevduat faizi GEÇMİŞİ (kıyas kartı "Mevduatta" satırı).
--
-- ── Neden yeni tablo ────────────────────────────────────────────────────────
-- "Başka yere koysaydın" kartı aynı nakit akışını aynı günlerde mevduata
-- koysaydın ne olurdu sorusunu yanıtlar (Ar-Ge 2026-11-07 madde 1). Bunun
-- için dönem boyunca HER HAFTANIN faizi gerekir; 0129'daki
-- `mevduat_faiz_ortalama` vade dilimi başına yalnız SON haftayı tutar ve
-- her tur üzerine yazar. Geçmiş başka yerde saklanmıyordu.
--
-- ── Eski sürümler etkilenmez ────────────────────────────────────────────────
-- Yalnız EKLEME: yeni tablo; 0129 tablosuna, RPC'ye, cron'a dokunulmaz.
-- `mevduat-faiz` fonksiyonu aynı turda bu tabloya da upsert eder (yanıt
-- biçimi değişmez). Tablo boşken yeni istemci satırı çizmez, hata göstermez.
--
-- ── İzin (0161 sonrası açık GRANT) ──────────────────────────────────────────
-- Kamuya açık piyasa verisi ama giriş sonrası okunur: authenticated SELECT,
-- yazan yalnız service_role (edge function). anon'a izin YOK.

create table if not exists public.mevduat_faiz_gecmisi (
  -- 0129 ile aynı dilim adları; kıyas bugün yalnız 'ay1' okur.
  vade_dilimi  text not null
               check (vade_dilimi in ('ay1', 'ay3', 'ay6', 'yil1', 'yil1_ustu')),
  -- EVDS "Tarih" (haftanın tarihi).
  hafta        date not null,
  -- Yıllık brüt (%) — 0129 ile aynı tanım ve aralık. Bilinmeyen hafta
  -- SATIR OLARAK YOKTUR; NULL/varsayılan yazılmaz.
  yillik_faiz  double precision not null check (yillik_faiz > 0 and yillik_faiz < 300),
  guncellendi  timestamptz not null default now(),
  primary key (vade_dilimi, hafta)
);

comment on table public.mevduat_faiz_gecmisi is
  'TCMB EVDS haftalik akim agirlikli ortalama TL mevduat faizi gecmisi (mevduat-faiz, 0173). Kiyas karti Mevduatta satiri.';

alter table public.mevduat_faiz_gecmisi enable row level security;
alter table public.mevduat_faiz_gecmisi force  row level security;

drop policy if exists mevduat_faiz_gecmisi_select on public.mevduat_faiz_gecmisi;
create policy mevduat_faiz_gecmisi_select on public.mevduat_faiz_gecmisi
  for select to authenticated using (true);

revoke all on table public.mevduat_faiz_gecmisi from public, anon, authenticated;
grant select on table public.mevduat_faiz_gecmisi to authenticated;
grant all on table public.mevduat_faiz_gecmisi to service_role;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.mevduat_faiz_gecmisi', 'select') then
    raise exception '0173: authenticated SELECT grant eksik';
  end if;
  if has_table_privilege('authenticated', 'public.mevduat_faiz_gecmisi', 'insert')
     or has_table_privilege('authenticated', 'public.mevduat_faiz_gecmisi', 'update')
     or has_table_privilege('authenticated', 'public.mevduat_faiz_gecmisi', 'delete') then
    raise exception '0173: authenticated yazma yetkisi verilmemeli';
  end if;
  if has_table_privilege('anon', 'public.mevduat_faiz_gecmisi', 'select') then
    raise exception '0173: anon okumamali';
  end if;
  if not has_table_privilege('service_role', 'public.mevduat_faiz_gecmisi', 'insert') then
    raise exception '0173: service_role yazma grant eksik';
  end if;
  if not exists (select 1 from pg_class where oid = 'public.mevduat_faiz_gecmisi'::regclass
                 and relrowsecurity and relforcerowsecurity) then
    raise exception '0173: RLS kapali';
  end if;
end $$;
