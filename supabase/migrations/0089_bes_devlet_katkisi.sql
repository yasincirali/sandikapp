-- 0089 — BES devlet katkısı parametreleri: sunucuda, EGM'den otomatik (2026-10-01)
--
-- ## Neden
-- Yıllık devlet katkısı üst sınırı istemcide sabit tabloydu
-- (`BesHesabi.yillikSinirTablosu = {2026: 79272}`) ve her Ocak kullanıcının
-- elle yeni yılı eklemesi gerekiyordu. Kullanıcı (2026-10-01): "bunu bir
-- yerden otomatik alsak, ben elle tanımlamam mantıklı değil."
--
-- ## Kaynak: EGM (Emeklilik Gözetim Merkezi) resmî sayfası
-- https://www.egm.org.tr/bireysel-emeklilik/devlet-katkisi/ her yıl şu
-- cümleyi yayımlıyor (2026-10-01'de okundu):
--   "2026 yılı Devlet katkısı üst limitinden yararlanabilmek için ödenmesi
--    gereken katkı payı tutarı 396.360 TL'dir. Bu tutara karşılık ilgili
--    yılda alınabilecek maksimum Devlet katkısı tutarı 79.272 TL'dir."
-- ve oranı ("katkı paylarının %20'si"). `bes-parametre` edge function'ı
-- sayfayı günde bir kez okur, üç sayıyı ayrıştırır ve KENDİ İÇİNDE
-- DOĞRULAR: katkı × oran = azami (±1 TL). Tutmazsa yazmaz — uydurma sınır
-- yasağı (fiyat_kaynagi sözleşmesi) burada da geçerli; tabloda olmayan yıl
-- için istemci sınırı "bilinmiyor" sayar ve tutarı düzenlenebilir gösterir.
--
-- ## Neden günlük
-- Yeni yılın tutarı asgari ücretle birlikte Aralık/Ocak'ta belli olur ama
-- EGM sayfayı hangi gün güncelleyeceği belli değil; oran da yıl içinde
-- Cumhurbaşkanı kararıyla değişebiliyor (2026: %30 → %20, RG 2026-01-07).
-- Günde tek bir HTTP isteği; değişmemişse tabloya dokunulmaz.
--
-- ## Yetki: herkese açık referans verisi, yalnız OKU
-- Kişisel veri değil; oturum açmış her kullanıcı okur. Yazma yalnızca
-- service_role (edge function). anon okumaz: istemci zaten oturumla gelir,
-- ve bu tabloyu dışarıya açmanın bir faydası yok. GRANT ve RLS ayrı
-- katmanlardır (0036/0042/0043): ikisi de yazılır ve sonda doğrulanır.

-- ── 1) Tablo ────────────────────────────────────────────────────────────────
create table if not exists public.bes_devlet_katkisi (
  yil                   int primary key check (yil between 2013 and 2100),
  -- Devlet katkısından yararlanılabilecek yıllık katkı payı üst sınırı
  -- (o yılın brüt asgari ücret toplamı), TL.
  katki_ust_siniri      numeric not null check (katki_ust_siniri > 0),
  -- O yıl alınabilecek azami devlet katkısı, TL.
  azami_devlet_katkisi  numeric not null check (azami_devlet_katkisi > 0),
  -- Devlet katkısı yüzdesi (20 = %20).
  oran_yuzde            numeric not null check (oran_yuzde > 0 and oran_yuzde <= 100),
  -- 'egm' = bes-parametre çekti; 'tohum' = bu migration'ın ektiği bilinen değer.
  kaynak                text not null check (kaynak in ('egm', 'tohum')),
  guncellendi           timestamptz not null default now(),
  -- Üç sayı birbirini doğrulamalı; EGM sayfasındaki bir dizgi hatası ya da
  -- yanlış ayrıştırma tabloya giremesin (±1 TL yuvarlama payı).
  constraint bes_devlet_katkisi_tutarli check (
    abs(katki_ust_siniri * oran_yuzde / 100 - azami_devlet_katkisi) <= 1)
);

comment on table public.bes_devlet_katkisi is
  'BES devlet katkisi yillik parametreleri (0089). Kaynak EGM resmi sayfasi; '
  'yalniz bes-parametre (service_role) yazar, authenticated yalniz okur.';

-- Bilinen 2026 değeri (EGM, 2026-10-01'de okundu; istemci sabitiyle aynı).
-- Böylece fonksiyon ilk kez koşmadan da tablo boş değil.
insert into public.bes_devlet_katkisi
  (yil, katki_ust_siniri, azami_devlet_katkisi, oran_yuzde, kaynak)
values (2026, 396360, 79272, 20, 'tohum')
on conflict (yil) do nothing;

-- ── 2) RLS ──────────────────────────────────────────────────────────────────
alter table public.bes_devlet_katkisi enable row level security;
alter table public.bes_devlet_katkisi force row level security;

drop policy if exists bes_devlet_katkisi_select on public.bes_devlet_katkisi;
create policy bes_devlet_katkisi_select
  on public.bes_devlet_katkisi
  for select to authenticated
  -- Referans verisi: satır sahibi yok, her oturum okur.
  using (true);

-- INSERT/UPDATE/DELETE politikası BİLEREK yok: authenticated için GRANT de
-- yok. Kullanıcı sınırı yükseltip "devlet katkısı" şişiremesin.

-- ── 3) GRANT ────────────────────────────────────────────────────────────────
revoke all on table public.bes_devlet_katkisi from public, anon, authenticated;
grant select on table public.bes_devlet_katkisi to authenticated;
grant select, insert, update, delete on table public.bes_devlet_katkisi to service_role;

-- ── 4) Tetikleyici ──────────────────────────────────────────────────────────
-- 0076 deseni. Secret TÜFE çekimiyle PAYLAŞILIR (`inflation_fetch_cron_secret`
-- / `INFLATION_FETCH_CRON_SECRET`): ikisi de aynı sınıftan, herkese açık
-- resmî parametre çeken salt-okur işlerdir; yeni secret elle kurulum
-- gerektirirdi ve bu değişikliğin amacı elle adımı kaldırmak. Emsal: yıl
-- sonu anı (0087) `calendar_nudge_cron_secret`'ı paylaşır.
create or replace function public.trigger_bes_parametre()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('bes-parametre'),
    headers := public.cron_headers('inflation_fetch_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- Tek EGM isteği (20 sn zaman aşımı) + tek upsert.
    timeout_milliseconds := 45000
  );
end;
$$;

revoke all on function public.trigger_bes_parametre() from public, anon, authenticated;

-- ── 5) Zamanlama (pg_cron UTC; TR = UTC+3) ──────────────────────────────────
-- 10:40 TR = 07:40 UTC, her gün. TÜFE çekimi (07:05) ve takvim kancasıyla
-- (07:15) çakışmasın diye ayrı dakika.
select cron.unschedule(jobid) from cron.job where jobname = 'bes-parametre';
select cron.schedule('bes-parametre', '40 7 * * *',
  $$select public.trigger_bes_parametre()$$);

-- İki sunucu birebir: Frankfurt "tüm cron kapalı" kipindeyse yeni iş de
-- kapalı doğar (0086 gerekçesi; proje ref'i sabit yazılmaz).
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'bes-parametre')
     and not exists (select 1 from cron.job
                      where jobname <> 'bes-parametre' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'bes-parametre';
    raise notice '0089: projede tum cron isleri kapali — bes-parametre de kapali kuruldu.';
  end if;
end $$;

-- ── 6) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.bes_devlet_katkisi', 'SELECT') then
    raise exception '0089: authenticated icin bes_devlet_katkisi SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.bes_devlet_katkisi', 'INSERT')
     or has_table_privilege('authenticated', 'public.bes_devlet_katkisi', 'UPDATE')
     or has_table_privilege('authenticated', 'public.bes_devlet_katkisi', 'DELETE') then
    raise exception '0089: authenticated bes_devlet_katkisi tablosuna YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.bes_devlet_katkisi', 'SELECT') then
    raise exception '0089: anon bes_devlet_katkisi tablosunu okuyamamali';
  end if;
  if not has_table_privilege('service_role', 'public.bes_devlet_katkisi', 'INSERT') then
    raise exception '0089: service_role icin bes_devlet_katkisi INSERT GRANT eksik';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.bes_devlet_katkisi'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0089: bes_devlet_katkisi RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'bes_devlet_katkisi') <> 1
     or not exists (select 1 from pg_policies
                     where schemaname = 'public'
                       and tablename = 'bes_devlet_katkisi'
                       and policyname = 'bes_devlet_katkisi_select'
                       and cmd = 'SELECT') then
    raise exception '0089: bes_devlet_katkisi yalniz select politikasini tasimali';
  end if;
  if not exists (select 1 from public.bes_devlet_katkisi where yil = 2026) then
    raise exception '0089: 2026 tohumu eksik';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'bes-parametre' and schedule = '40 7 * * *') then
    raise exception '0089: bes-parametre cron isi kurulmadi';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_bes_parametre()', 'EXECUTE') then
    raise exception '0089: trigger_bes_parametre authenticated tarafindan cagrilabilir olmamali';
  end if;

  raise notice '0089 tamam: bes_devlet_katkisi + RLS + GRANT + cron yerinde.';
end $$;
