-- 0131 — Fon X-Ray, Katman B: TEFAS varlık sınıfı dağılımı (2026-10-10)
--
-- ## Neden
-- yasin (2026-10-10): Premium setine "Fon X-Ray" — "fonumun içinde ne var,
-- portföyümün gerçekte neye maruz olduğu". Araştırma:
-- tmp/arastirma/reports/Fon XRay veri kaynakları.md.
--
-- ## Kaynak kararı
-- TEFAS'ın açık JSON ucu `POST /api/funds/dagilimSiraliGetirT` fon başına
-- GÜNLÜK ~57 varlık sınıfı yüzdesi veriyor (YAT, EMK, BYF; doğrulandı
-- 2026-10-10). Fiyatı zaten aynı kaynaktan çekiyoruz: yeni sağlayıcı değil,
-- aynı kaynağın ikinci ucu. Kişisel veri ALMAZ (kamuya açık piyasa verisi) —
-- yasal metne dokunmaz (CLAUDE.md, kullanıcı kararı 2026-10-08).
--
-- ## Neden sunucuda, neden tüm evren
-- Tek fon istemciden çekilebilirdi ama TEFAS dakikada ~6 istek kabul ediyor
-- ve yanıt Java hata metni de olabiliyor; istemci her varlık ekranında
-- TEFAS'a gitseydi sınır kullanıcı sayısıyla büyürdü. Sunucu fon tipi
-- başına TEK istekle bütün evrenin son 5 gününü alır (YAT ≈ 1,5 MB/gün),
-- fon başına en yeni satırı yazar. İstemci yalnız kendi fonlarının satırını
-- okur (pk araması).
--
-- ## Uydurma sayı yok
-- `dagilim` kaynaktaki yüzdeleri AYNEN taşır ({kod: yüzde}; null/0 düşer).
-- Toplam 100 değilse fark hiçbir sınıfa uydurulmaz; kaba kova eşlemesi ve
-- "X-Ray dışı" payı istemcide (`lib/services/fon_dagilimi.dart`).
-- Kaynak boş/hatalı döndüğünde mevcut satırlar SİLİNMEZ; satır yalnız daha
-- yeni (ya da aynı) tarihli bir satırla güncellenir.
--
-- ## Premium
-- Okuma `premium_icerik_gorebilir()` (0116): sunucu kapısı kapalıyken her
-- oturumlu kullanıcı, açıkken yalnız Premium. İstemcide görünürlük ayrıca
-- `premiumOzellikleriGorunur` (paywall kapalıyken yalnız admin) — iki ayrı
-- anahtar 0116'daki gerekçeyle bilinçli.
--
-- ## Eski istemciler
-- Yalnız EKLER: bir tablo, bir tetikleyici, iki cron işi. Eski build bunları
-- hiç okumaz.
--
-- ## Dağıtım sırası
-- Bu migration (iki sunucu) → `fon-dagilim` fonksiyonu (iki sunucu) → ilk
-- tur elle: `select public.trigger_fon_dagilim();` → kontrol:
-- `select fon_tipi, count(*), max(tarih) from public.fon_dagilimlari group by 1;`

create table if not exists public.fon_dagilimlari (
  -- TEFAS fon kodu (AFT, AEA…). Uygulamadaki `fonKoduOf` ile aynı biçim.
  fon_kodu  text primary key check (fon_kodu ~ '^[A-Z0-9]{2,8}$'),
  -- Hangi TEFAS fon tipinden geldiği: YAT (yatırım), EMK (emeklilik/BES),
  -- BYF (borsa yatırım fonu).
  fon_tipi  text not null check (fon_tipi in ('YAT', 'EMK', 'BYF')),
  -- Satırın ait olduğu TEFAS günü (kaynaktaki `tarih`).
  tarih     date not null,
  -- {sınıf kodu: yüzde}, kaynaktan aynen. Boş nesne yazılmaz.
  dagilim   jsonb not null check (jsonb_typeof(dagilim) = 'object' and dagilim <> '{}'::jsonb),
  alindi    timestamptz not null default now()
);

comment on table public.fon_dagilimlari is
  'Fon X-Ray Katman B (0131): TEFAS dagilimSiraliGetirT, fon basina en yeni gunun varlik sinifi '
  'yuzdeleri (kaynaktan aynen). fon-dagilim (service_role) yazar; okuma premium_icerik_gorebilir().';

alter table public.fon_dagilimlari enable row level security;
alter table public.fon_dagilimlari force row level security;

drop policy if exists fon_dagilimlari_premium on public.fon_dagilimlari;
create policy fon_dagilimlari_premium
  on public.fon_dagilimlari
  for select to authenticated
  using ((select public.premium_icerik_gorebilir()));

revoke all on table public.fon_dagilimlari from public, anon, authenticated;
grant select on table public.fon_dagilimlari to authenticated;
grant select, insert, update, delete on table public.fon_dagilimlari to service_role;

-- ── Tetikleyici (0129 deseni: edge_function_url + cron_headers) ────────────
-- Ayrı secret açılmadı: TEFAS'tan kamu verisi okuyan öteki iş
-- (`observe-tefas-nav`, 0063) ile aynı sınıf risk; yeni secret yasin'in
-- Vault'a elle girmesini beklerdi (0124/0129 kararıyla aynı gerekçe).
create or replace function public.trigger_fon_dagilim()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('fon-dagilim'),
    headers := public.cron_headers('tefas_nav_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- 3 fon tipi, istekler arası ~11 sn (TEFAS ~6 istek/dk) + upsert.
    timeout_milliseconds := 120000
  );
end;
$$;

revoke all on function public.trigger_fon_dagilim() from public, anon, authenticated;

-- TEFAS günün dağılımını akşam yayımlıyor (gözlem 2026-10-10: 9 Ekim satırı
-- 10 Ekim sabahı vardı). Hafta içi TR 21:00 (18:00 UTC) ilk tur; ertesi
-- sabah TR 07:30 (04:30 UTC) yedek — akşam gecikirse ya da TEFAS hata
-- verirse kart bir gün bayat kalır, boşalmaz.
select cron.unschedule(jobid) from cron.job where jobname in ('fon-dagilim', 'fon-dagilim-yedek');
select cron.schedule('fon-dagilim', '0 18 * * 1-5',
  $$select public.trigger_fon_dagilim()$$);
select cron.schedule('fon-dagilim-yedek', '30 4 * * 2-6',
  $$select public.trigger_fon_dagilim()$$);

-- İki sunucu birebir; tek bilinçli fark cron `active` (0119 kuralı).
do $$
begin
  if exists (select 1 from cron.job where jobname not like 'fon-dagilim%')
     and not exists (select 1 from cron.job where jobname not like 'fon-dagilim%' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname like 'fon-dagilim%';
    raise notice '0131: projede tum cron isleri kapali — fon-dagilim isleri de kapali kuruldu.';
  end if;
end $$;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.fon_dagilimlari', 'SELECT') then
    raise exception '0131: authenticated icin fon_dagilimlari SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.fon_dagilimlari', 'INSERT')
     or has_table_privilege('authenticated', 'public.fon_dagilimlari', 'UPDATE')
     or has_table_privilege('authenticated', 'public.fon_dagilimlari', 'DELETE') then
    raise exception '0131: authenticated fon_dagilimlari tablosuna YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.fon_dagilimlari', 'SELECT') then
    raise exception '0131: anon fon_dagilimlari tablosunu okuyamamali';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.fon_dagilimlari'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0131: fon_dagilimlari RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'fon_dagilimlari') <> 1 then
    raise exception '0131: fon_dagilimlari yalniz Premium select politikasini tasimali';
  end if;
  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'fon_dagilimlari'
                    and cmd = 'SELECT' and qual like '%premium_icerik_gorebilir%') then
    raise exception '0131: fon_dagilimlari politikasi premium_icerik_gorebilir() sormuyor';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_fon_dagilim()', 'EXECUTE')
     or has_function_privilege('anon', 'public.trigger_fon_dagilim()', 'EXECUTE') then
    raise exception '0131: trigger_fon_dagilim istemciden cagrilabilir olmamali';
  end if;
  if not exists (select 1 from cron.job where jobname = 'fon-dagilim')
     or not exists (select 1 from cron.job where jobname = 'fon-dagilim-yedek') then
    raise exception '0131: fon-dagilim cron isleri kurulmadi';
  end if;
  raise notice '0131 tamam: fon_dagilimlari + trigger_fon_dagilim + cron kuruldu.';
end $$;
