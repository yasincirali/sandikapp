-- 0115 — Balina Radarı F1'in eksik iki parçası (2026-10-05)
--
-- ## Neden
-- Gereksinim dokümanında olup PR #91'de yapılmayan iki şey:
--   1) G-03 "saatlik" kripto alıcı baskısı. Günlük mum (0108) dünü anlatır;
--      kartın "son 24 saat" bölümü saat saat net alımı gösterir. Kaynak aynı
--      Binance kline ucu, `interval=1h`.
--      Plandaki "büyük işlemler" listesi YAPILMADI (kullanıcıya 2026-10-05'te
--      bildirildi): Binance tek tek işlemleri (aggTrades) 1.000'erlik
--      parçalarla veriyor; BTC'de bu birkaç saniyeye denk geliyor, 24 saati
--      taramak coin başına binlerce istek. Eksik bir "büyük işlemler" listesi
--      yanıltıcı olurdu.
--   2) Fon kartının "kategoride akış sırası" bölümü. Aynı TEFAS kategorisi
--      (fon tipi + `fon_turu`, fon karnesiyle aynı kıyas grubu) içinde son
--      haftanın net akışına göre sıra.
--
-- ## Eski sürümler
-- Yalnızca EKLER: bir tablo, bir RPC, bir tetikleyici, bir cron. Mevcut hiçbir
-- kolona/RPC'ye dokunmaz; eski build'ler bunları hiç çağırmaz.
--
-- ## Yetki
-- Piyasa verisi, kişisel veri yok (0106–0108 deseni): oturum açmış kullanıcı
-- okur, yalnız service_role yazar, anon okumaz.

-- ── 1) Saatlik kripto hacmi ─────────────────────────────────────────────────
create table if not exists public.kripto_hacim_saatlik (
  -- Uygulamadaki ticker ile birebir: 'KRIPTO:BTC'.
  ticker      text not null check (ticker ~ '^KRIPTO:[A-Z0-9]{2,15}$'),
  -- Saatlik mumun AÇILIŞ anı (UTC). Yalnız KAPANMIŞ mumlar yazılır; yarım
  -- saat "o saatte az işlem oldu" diye yanlış okunurdu.
  saat        timestamptz not null,
  -- O saatin işlem hacmi, USDT.
  para_hacmi  numeric not null check (para_hacmi > 0),
  -- Taker alış hacmi / toplam (0–1). Net alım = (2 × pay − 1) × hacim;
  -- türetilen değer saklanmaz, tek kaynak bu iki sütun.
  alici_payi  numeric not null check (alici_payi >= 0 and alici_payi <= 1),
  primary key (ticker, saat)
);

create index if not exists kripto_hacim_saatlik_saat_idx
  on public.kripto_hacim_saatlik (saat);

comment on table public.kripto_hacim_saatlik is
  'Portfoylerde tutulan coinlerin saatlik Binance USDT hacmi ve alici payi (0115). '
  'Yalniz kripto-hacim-gozlem (mod saatlik, service_role) yazar, authenticated yalniz okur. 8 gun saklanir.';

alter table public.kripto_hacim_saatlik enable row level security;
alter table public.kripto_hacim_saatlik force row level security;

drop policy if exists kripto_hacim_saatlik_select on public.kripto_hacim_saatlik;
create policy kripto_hacim_saatlik_select
  on public.kripto_hacim_saatlik
  for select to authenticated
  using (true);

revoke all on table public.kripto_hacim_saatlik from public, anon, authenticated;
grant select on table public.kripto_hacim_saatlik to authenticated;
grant select, insert, update, delete on table public.kripto_hacim_saatlik to service_role;

-- ── 2) Kategoride akış sırası ───────────────────────────────────────────────
-- İstemci kendi "son hafta" aralığını verir (Pazartesi → veri tarihi;
-- `fon_akisi.dart`). Sıra aynı aralıktan hesaplanmazsa kartın üstündeki sayı
-- ile sıradaki sayı farklı haftayı anlatırdı.
--
-- Kıyas grubu = hedef fonun EN YENİ satırındaki fon tipi + `fon_turu`
-- (fon karnesiyle aynı). Yalnız hedef fonla AYNI sayıda günlük akışı olan
-- fonlar sıralanır: bir günü eksik fonun toplamı kısa kalır ve sıra
-- yanıltır. Türü bilinmeyen fon, akışı olmayan fon ya da tek fonlu kategori
-- → boş sonuç (kart bölümü gizlenir; "1 fondan 1." bilgi değildir).
--
-- Dönen satırlar: ilk 5 + (ilk 5'te değilse) hedef fonun kendisi.
-- SECURITY INVOKER: okuma yetkisi tablonun RLS'inden gelir; yetki kazanmaz.
create or replace function public.fon_kategori_akis_sirasi(
  p_fon_kodu text,
  p_baslangic date,
  p_bitis date
)
returns table (
  sira integer,
  fon_kodu text,
  net_akis numeric,
  kendi boolean,
  kategori text,
  fon_sayisi integer
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
  if p_fon_kodu is null or p_baslangic is null or p_bitis is null
     or p_bitis < p_baslangic or p_bitis - p_baslangic > 13 then
    raise exception 'fon_kategori_akis_sirasi: gecersiz aralik' using errcode = '22023';
  end if;

  return query
  with hedef as (
    select g.fon_tipi, g.fon_turu
      from fon_akis_gunluk g
     where g.fon_kodu = p_fon_kodu
       and g.tarih between p_baslangic and p_bitis
       and g.fon_turu is not null
     order by g.tarih desc
     limit 1
  ),
  hedef_gun as (
    select count(g.net_akis) as n
      from fon_akis_gunluk g
     where g.fon_kodu = p_fon_kodu
       and g.tarih between p_baslangic and p_bitis
  ),
  toplam as (
    select g.fon_kodu as kod, sum(g.net_akis) as net, count(g.net_akis) as n
      from fon_akis_gunluk g
      join hedef h on g.fon_tipi = h.fon_tipi and g.fon_turu = h.fon_turu
     where g.tarih between p_baslangic and p_bitis
     group by g.fon_kodu
  ),
  tam as (
    select t.kod, t.net
      from toplam t, hedef_gun hg
     where hg.n > 0 and t.n = hg.n
  ),
  sirali as (
    select row_number() over (order by t.net desc, t.kod)::integer as s,
           t.kod, t.net,
           (count(*) over ())::integer as adet
      from tam t
  )
  select s.s, s.kod, s.net, s.kod = p_fon_kodu, (select h.fon_turu from hedef h), s.adet
    from sirali s
   where s.adet >= 2
     and (s.s <= 5 or s.kod = p_fon_kodu)
     and exists (select 1 from sirali x where x.kod = p_fon_kodu)
   order by s.s;
end;
$$;

revoke all on function public.fon_kategori_akis_sirasi(text, date, date) from public, anon;
grant execute on function public.fon_kategori_akis_sirasi(text, date, date) to authenticated, service_role;

-- ── 3) Saatlik tetikleyici ──────────────────────────────────────────────────
-- Aynı function, `mod: saatlik` gövdesiyle; secret 0108 ile aynı
-- (`price_alerts_cron_secret`).
create or replace function public.trigger_kripto_hacim_saatlik()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('kripto-hacim-gozlem'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object('source', 'cron', 'mod', 'saatlik'),
    timeout_milliseconds := 140000
  );
end;
$$;

revoke all on function public.trigger_kripto_hacim_saatlik() from public, anon, authenticated;

-- ── 4) Zamanlama (pg_cron UTC) ──────────────────────────────────────────────
-- Her saatin 7. dakikası: saatlik mum 00. dakikada kapanır, Binance birkaç
-- saniye içinde yayınlar; 7 dakika fiyat alarmı (her 5 dk) ile çakışmasın.
select cron.unschedule(jobid) from cron.job where jobname = 'kripto-hacim-saatlik';
select cron.schedule('kripto-hacim-saatlik', '7 * * * *',
  $$select public.trigger_kripto_hacim_saatlik()$$);

-- Projede tüm cron'lar kapalıysa (Frankfurt, geçişe kadar) bu da kapalı doğar.
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'kripto-hacim-saatlik')
     and not exists (select 1 from cron.job
                      where jobname <> 'kripto-hacim-saatlik' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'kripto-hacim-saatlik';
    raise notice '0115: projede tum cron isleri kapali — kripto-hacim-saatlik de kapali kuruldu.';
  end if;
end $$;

-- ── 5) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.kripto_hacim_saatlik', 'SELECT') then
    raise exception '0115: authenticated icin kripto_hacim_saatlik SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.kripto_hacim_saatlik', 'INSERT')
     or has_table_privilege('authenticated', 'public.kripto_hacim_saatlik', 'UPDATE')
     or has_table_privilege('authenticated', 'public.kripto_hacim_saatlik', 'DELETE') then
    raise exception '0115: authenticated kripto_hacim_saatlik tablosuna YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.kripto_hacim_saatlik', 'SELECT') then
    raise exception '0115: anon kripto_hacim_saatlik tablosunu okuyamamali';
  end if;
  if not has_table_privilege('service_role', 'public.kripto_hacim_saatlik', 'INSERT')
     or not has_table_privilege('service_role', 'public.kripto_hacim_saatlik', 'DELETE') then
    raise exception '0115: service_role icin kripto_hacim_saatlik INSERT/DELETE GRANT eksik';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.kripto_hacim_saatlik'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0115: kripto_hacim_saatlik RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'kripto_hacim_saatlik') <> 1 then
    raise exception '0115: kripto_hacim_saatlik yalniz select politikasini tasimali';
  end if;
  if not has_function_privilege('authenticated',
       'public.fon_kategori_akis_sirasi(text, date, date)', 'EXECUTE') then
    raise exception '0115: fon_kategori_akis_sirasi authenticated EXECUTE eksik';
  end if;
  if has_function_privilege('anon',
       'public.fon_kategori_akis_sirasi(text, date, date)', 'EXECUTE') then
    raise exception '0115: fon_kategori_akis_sirasi anon tarafindan cagrilabilir olmamali';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_kripto_hacim_saatlik()', 'EXECUTE') then
    raise exception '0115: trigger_kripto_hacim_saatlik authenticated tarafindan cagrilabilir olmamali';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'kripto-hacim-saatlik' and schedule = '7 * * * *') then
    raise exception '0115: kripto-hacim-saatlik cron isi kurulmadi';
  end if;

  raise notice '0115 tamam: kripto_hacim_saatlik + fon_kategori_akis_sirasi + saatlik cron yerinde.';
end $$;
