-- 0117 — Haftalık varlık notu ve aylık rapor (Balina Radarı F2, 2026-10-05)
--
-- ## Neden
-- Gereksinim G-05…G-08, G-11, G-12, N-04, N-08. Her Pazar gecesi portföylerde
-- tutulan her varlık için BİR not üretilir (kullanıcı başına değil — maliyet
-- varlık çeşidiyle büyür, kişisel veri modele gitmez: N-07). Üretim
-- `analiz-hazirla` (Anthropic Message Batches), toplama `analiz-topla`.
-- Not yayınlanmadan önce iki kapıdan geçer (`_shared/analiz.ts`): metindeki
-- her sayı girdide olmalı; al/sat/hedef/kesin dili reddedilir. Geçmeyen not
-- `reddedildi` olarak saklanır (oran ölçülür) ama kimse okuyamaz.
--
-- ## Eski sürümler
-- Yalnızca EKLER. Eski build'ler bu tabloları hiç okumaz.
--
-- ## Yetki
--   · `varlik_analizi`: tam satır yalnız `yayinda` ve
--     `premium_icerik_gorebilir()` (0116) — kapı kapalıyken herkes, açıkken
--     yalnız Premium. Ücretsiz katmanın gördüğü tek şey başlık cümlesi:
--     `analiz_ozetleri` RPC'si (SECURITY DEFINER, yalnız yayındaki başlık).
--   · `analiz_batch`: yalnız service_role.
--   · `not_geri_bildirim`: kullanıcı kendi satırını okur/yazar.

-- ── 1) Notlar ───────────────────────────────────────────────────────────────
create table if not exists public.varlik_analizi (
  -- Uygulamadaki ticker: 'TEFAS:TTE', 'THYAO.IS', 'KRIPTO:BTC'.
  ticker        text not null check (length(ticker) between 3 and 40),
  tur           text not null check (tur in ('haftalik', 'aylik')),
  -- Haftalık: anlatılan haftanın Pazartesi'si. Aylık: ayın 1'i.
  donem         date not null,
  durum         text not null check (durum in ('yayinda', 'reddedildi', 'hata')),
  -- Tek cümle; ücretsiz katmanda görünen kısım.
  baslik        text check (baslik is null or length(baslik) <= 300),
  -- [{ "metin": "...", "kanit": ["olcum_anahtari", ...] }], en çok 4.
  maddeler      jsonb not null default '[]'::jsonb check (jsonb_typeof(maddeler) = 'array'),
  -- 'buyuk_giris' | 'buyuk_cikis' | 'olagandisi_hacim' | 'alici_istekli' |
  -- 'satici_istekli' | 'sakin'. Rozet modelden değil VERİDEN gelir.
  rozet         text check (rozet is null or rozet in ('buyuk_giris', 'buyuk_cikis',
                  'olagandisi_hacim', 'alici_istekli', 'satici_istekli', 'sakin')),
  -- Modele giden paket: ölçümler (anahtar → değer, gösterim, kaynak, tarih).
  -- Kanıt çipi buradan çizilir; sayı kapısı da bunu kullanır.
  girdi         jsonb not null default '{}'::jsonb,
  -- Haber bağlantıları (G-07): [{ "baslik": "...", "url": "..." }].
  kaynaklar     jsonb not null default '[]'::jsonb check (jsonb_typeof(kaynaklar) = 'array'),
  -- Gözlemlenebilirlik (N-08).
  model         text,
  girdi_token   integer,
  cikti_token   integer,
  maliyet_usd   numeric(10, 5),
  red_nedeni    text check (red_nedeni is null or length(red_nedeni) <= 500),
  batch_id      text,
  olusturuldu   timestamptz not null default now(),
  primary key (ticker, tur, donem),
  constraint varlik_analizi_yayinda_dolu
    check (durum <> 'yayinda' or (baslik is not null and rozet is not null))
);

create index if not exists varlik_analizi_donem_idx
  on public.varlik_analizi (tur, donem desc);

comment on table public.varlik_analizi is
  'Varlik basina yapay zeka notu (0117). analiz-topla (service_role) yazar; '
  'yayindaki tam satir premium_icerik_gorebilir() ile okunur, baslik analiz_ozetleri ile herkese.';

alter table public.varlik_analizi enable row level security;
alter table public.varlik_analizi force row level security;

drop policy if exists varlik_analizi_okuma on public.varlik_analizi;
create policy varlik_analizi_okuma
  on public.varlik_analizi
  for select to authenticated
  using (durum = 'yayinda' and public.premium_icerik_gorebilir());

revoke all on table public.varlik_analizi from public, anon, authenticated;
grant select on table public.varlik_analizi to authenticated;
grant select, insert, update, delete on table public.varlik_analizi to service_role;

-- ── 2) Ücretsiz katman: başlık cümlesi ──────────────────────────────────────
-- Verilen ticker'ların en yeni YAYINDAKİ notunun başlığı, rozeti ve madde
-- sayısı. Madde metni, girdi ve kaynak DÖNMEZ — onlar Premium.
create or replace function public.analiz_ozetleri(p_tickerlar text[], p_tur text default 'haftalik')
returns table (
  ticker text,
  donem date,
  baslik text,
  rozet text,
  madde_sayisi integer
)
language sql
stable
security definer
set search_path = public
as $$
  select distinct on (v.ticker)
         v.ticker, v.donem, v.baslik, v.rozet, jsonb_array_length(v.maddeler)
    from public.varlik_analizi v
   where (select auth.uid()) is not null
     and v.durum = 'yayinda'
     and v.tur = p_tur
     and v.ticker = any (p_tickerlar[1:200])
     -- Bayat not gösterilmez: haftalıkta 3, aylıkta 2 dönemden eski değil.
     and v.donem >= case when p_tur = 'aylik'
                         then (date_trunc('month', now()) - interval '2 months')::date
                         else (current_date - 21) end
   order by v.ticker, v.donem desc;
$$;

revoke all on function public.analiz_ozetleri(text[], text) from public, anon;
grant execute on function public.analiz_ozetleri(text[], text) to authenticated;

-- ── 3) Batch defteri ────────────────────────────────────────────────────────
create table if not exists public.analiz_batch (
  -- Anthropic batch kimliği ('msgbatch_…').
  id            text primary key check (length(id) between 5 and 100),
  tur           text not null check (tur in ('haftalik', 'aylik')),
  donem         date not null,
  durum         text not null default 'gonderildi'
                  check (durum in ('gonderildi', 'bitti', 'hata')),
  istek_sayisi  integer not null check (istek_sayisi >= 0),
  -- Batch'e giden her isteğin girdisi (custom_id → paket); topla bunu
  -- kapıda kullanır. Not satırına da kopyalanır.
  girdiler      jsonb not null default '{}'::jsonb,
  model         text not null,
  olusturuldu   timestamptz not null default now(),
  bitti         timestamptz
);

alter table public.analiz_batch enable row level security;
alter table public.analiz_batch force row level security;
revoke all on table public.analiz_batch from public, anon, authenticated;
grant select, insert, update, delete on table public.analiz_batch to service_role;

-- ── 4) Geri bildirim (açılış kapısı: "yanlış dediğin not 0") ────────────────
create table if not exists public.not_geri_bildirim (
  user_id      uuid not null references auth.users (id) on delete cascade,
  ticker       text not null check (length(ticker) between 3 and 40),
  tur          text not null check (tur in ('haftalik', 'aylik')),
  donem        date not null,
  -- 1 işe yaradı, -1 yaramadı, NULL oy yok.
  oy           smallint check (oy is null or oy in (-1, 1)),
  yanlis_sayi  boolean not null default false,
  aciklama     text check (aciklama is null or length(aciklama) <= 500),
  olusturuldu  timestamptz not null default now(),
  primary key (user_id, ticker, tur, donem)
);

alter table public.not_geri_bildirim enable row level security;
alter table public.not_geri_bildirim force row level security;

drop policy if exists not_geri_bildirim_oku on public.not_geri_bildirim;
create policy not_geri_bildirim_oku on public.not_geri_bildirim
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists not_geri_bildirim_ekle on public.not_geri_bildirim;
create policy not_geri_bildirim_ekle on public.not_geri_bildirim
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists not_geri_bildirim_guncelle on public.not_geri_bildirim;
create policy not_geri_bildirim_guncelle on public.not_geri_bildirim
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

revoke all on table public.not_geri_bildirim from public, anon, authenticated;
grant select, insert, update on table public.not_geri_bildirim to authenticated;
grant select, insert, update, delete on table public.not_geri_bildirim to service_role;

-- ── 5) Tetikleyiciler ve zamanlama ──────────────────────────────────────────
-- Secret fiyat alarmıyla PAYLAŞILIR (`price_alerts_cron_secret`, emsal 0107):
-- yeni Vault değeri istemez. Anthropic anahtarı `ANTHROPIC_API_KEY` function
-- secret'ıdır; tanımsızsa `analiz-hazirla` hiçbir şey göndermez (503).
create or replace function public.trigger_analiz_hazirla(p_tur text default 'haftalik')
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  if p_tur not in ('haftalik', 'aylik') then
    raise exception 'trigger_analiz_hazirla: tur gecersiz' using errcode = '22023';
  end if;
  perform net.http_post(
    url := public.edge_function_url('analiz-hazirla'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object('source', 'cron', 'tur', p_tur),
    timeout_milliseconds := 140000
  );
end;
$$;

create or replace function public.trigger_analiz_topla()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('analiz-topla'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    timeout_milliseconds := 140000
  );
end;
$$;

revoke all on function public.trigger_analiz_hazirla(text) from public, anon, authenticated;
revoke all on function public.trigger_analiz_topla() from public, anon, authenticated;

-- pg_cron UTC. Haftalık: Pazar 20:00 TR (17:00 UTC) — Cuma'nın fon verisi
-- Cumartesi sabahı tamamlanır. Aylık: ayın 1'i 06:00 TR (03:00 UTC).
-- Toplama: saatte bir, :25 (Batch çoğunlukla 1 saatte biter; Pazartesi
-- 10:30'daki haftalık özetten önce yayında olsun).
select cron.unschedule(jobid) from cron.job
 where jobname in ('analiz-hazirla-haftalik', 'analiz-hazirla-aylik', 'analiz-topla');
select cron.schedule('analiz-hazirla-haftalik', '0 17 * * 0',
  $$select public.trigger_analiz_hazirla('haftalik')$$);
select cron.schedule('analiz-hazirla-aylik', '0 3 1 * *',
  $$select public.trigger_analiz_hazirla('aylik')$$);
select cron.schedule('analiz-topla', '25 * * * *',
  $$select public.trigger_analiz_topla()$$);

do $$
begin
  if exists (select 1 from cron.job
              where jobname not in ('analiz-hazirla-haftalik', 'analiz-hazirla-aylik', 'analiz-topla'))
     and not exists (select 1 from cron.job
                      where jobname not in ('analiz-hazirla-haftalik', 'analiz-hazirla-aylik', 'analiz-topla')
                        and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job
      where jobname in ('analiz-hazirla-haftalik', 'analiz-hazirla-aylik', 'analiz-topla');
    raise notice '0117: projede tum cron isleri kapali — analiz isleri de kapali kuruldu.';
  end if;
end $$;

-- ── 6) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.varlik_analizi', 'SELECT') then
    raise exception '0117: authenticated icin varlik_analizi SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.varlik_analizi', 'INSERT')
     or has_table_privilege('authenticated', 'public.varlik_analizi', 'UPDATE')
     or has_table_privilege('authenticated', 'public.varlik_analizi', 'DELETE') then
    raise exception '0117: authenticated varlik_analizi tablosuna YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.varlik_analizi', 'SELECT') then
    raise exception '0117: anon varlik_analizi okuyamamali';
  end if;
  if has_table_privilege('authenticated', 'public.analiz_batch', 'SELECT') then
    raise exception '0117: analiz_batch istemciye kapali olmali';
  end if;
  if has_table_privilege('authenticated', 'public.not_geri_bildirim', 'DELETE') then
    raise exception '0117: not_geri_bildirim DELETE istemciye verilmemeli';
  end if;
  if not exists (select 1 from pg_class
                  where oid in ('public.varlik_analizi'::regclass,
                                'public.analiz_batch'::regclass,
                                'public.not_geri_bildirim'::regclass)
                    and relrowsecurity and relforcerowsecurity
                 having count(*) = 3) then
    raise exception '0117: RLS (enable + force) eksik';
  end if;
  if not has_function_privilege('authenticated', 'public.analiz_ozetleri(text[], text)', 'EXECUTE') then
    raise exception '0117: analiz_ozetleri authenticated EXECUTE eksik';
  end if;
  if has_function_privilege('anon', 'public.analiz_ozetleri(text[], text)', 'EXECUTE') then
    raise exception '0117: analiz_ozetleri anon tarafindan cagrilabilir olmamali';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_analiz_hazirla(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.trigger_analiz_topla()', 'EXECUTE') then
    raise exception '0117: analiz tetikleyicileri authenticated tarafindan cagrilabilir olmamali';
  end if;
  if (select count(*) from cron.job
       where jobname in ('analiz-hazirla-haftalik', 'analiz-hazirla-aylik', 'analiz-topla')) <> 3 then
    raise exception '0117: analiz cron isleri kurulmadi';
  end if;

  raise notice '0117 tamam: varlik_analizi + analiz_ozetleri + analiz_batch + not_geri_bildirim + cron yerinde.';
end $$;
