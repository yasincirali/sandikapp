-- 0063 — TEFAS NAV yayın anı GÖZLEMİ: fonun gün içi basamağı gerçek saate çapalanır
-- ============================================================
--
-- ── Sorun ───────────────────────────────────────────────────────────────────
-- TEFAS yanıtı NAV'ın TARİHİNİ taşır, yayımlandığı ANI değil. Gün içi seride
-- fonun günlük NAV değişimi bir basamak olarak çiziliyor ve basamak sabit
-- 10:00'a (`tefasNavYayinSaati`) çapalıydı — "TEFAS zaman damgası vermiyor"
-- diye ertelenmişti (TECHNICAL_DEBT.md "Fonun gün içi NAV basamağı SABİT bir
-- saate çapalı").
--
-- ── Çözüm: damgayı TEFAS'tan istemek yerine KENDİMİZ ÜRETİYORUZ ─────────────
-- `observe-tefas-nav` edge function'ı iş günlerinde yarım saatte bir, portföy-
-- lerde tutulan her fon kodu için TEFAS'ın son NAV satırını çeker. Bir fon
-- için daha önce görülmemiş bir (kod, NAV tarihi) çifti ilk kez göründüğünde
-- buraya `ilk_gorulme = now()` ile yazılır; `onceki_kontrol` bir önceki turun
-- zamanıdır (o turda henüz yoktu). Yani yayın anı [onceki_kontrol, ilk_gorulme]
-- aralığında — cron sıklığı kadar (30 dk) belirsiz, ama GERÇEK bir gözlem.
--
-- İstemci (`HistoryService`) çizdiği gün için bu satırı okur: NAV tarihi o
-- günse ve ilk görülme o güne düşüyorsa basamak `ilk_gorulme` slotuna
-- konur; satır yoksa (fonksiyon henüz dağıtılmadı, TEFAS o tur yanıt
-- vermedi, hafta sonu) eski davranış aynen: 10:00.
--
-- ── Neden ayrı tablo, neden `price_history_cache` değil ─────────────────────
-- `price_history_cache` seri saklar ve 12 saatlik TTL ile yazılır; bir NAV
-- tarihinin İLK görülme anını korumaz (üzerine yazılır). Buradaki satır bir
-- kez yazılır, değiştirilmez (`on conflict do nothing`).
--
-- ── Erişim ──────────────────────────────────────────────────────────────────
-- Piyasa verisi, kişisel değil: oturumlu her kullanıcı okuyabilir. Yazan
-- yalnızca edge function (service_role, RLS'i geçer). anon'a hiçbir şey yok.
-- GRANT ve RLS ayrı şeylerdir; ikisi de aşağıda ve doğrulanır.

create table if not exists public.tefas_nav_gozlem (
  fon_kodu        text        not null,
  nav_tarihi      date        not null,
  ilk_gorulme     timestamptz not null default now(),
  -- Bir önceki turun zamanı (o turda bu NAV tarihi HENÜZ yoktu). Fonksiyon
  -- ilk turunda ya da bir önceki tur başarısızsa NULL: gözlem yalnızca üst
  -- sınır demektir.
  onceki_kontrol  timestamptz,
  -- Gözlemlenen NAV (teşhis için; istemci fiyatı buradan OKUMAZ).
  nav             double precision,
  primary key (fon_kodu, nav_tarihi)
);

comment on table public.tefas_nav_gozlem is
  'TEFAS NAV tarihinin sunucuda ILK gorulme ani (observe-tefas-nav). Gun ici fon basamagi bu ana capalanir.';

-- Bir fonun en son gözlemi tek indeks dokunuşuyla gelsin.
create index if not exists tefas_nav_gozlem_kod_tarih_idx
  on public.tefas_nav_gozlem (fon_kodu, nav_tarihi desc);

alter table public.tefas_nav_gozlem enable row level security;
alter table public.tefas_nav_gozlem force  row level security;

drop policy if exists tefas_nav_gozlem_select on public.tefas_nav_gozlem;
create policy tefas_nav_gozlem_select on public.tefas_nav_gozlem
  for select to authenticated using (true);
-- INSERT/UPDATE/DELETE politikası YOK: istemci yazamaz (varsayılan red).

-- Supabase'in varsayılan ayrıcalıkları yeni tabloda authenticated'a ALL
-- verir; önce hepsi geri alınır, sonra yalnız SELECT.
revoke all on public.tefas_nav_gozlem from public, anon, authenticated;
grant select on public.tefas_nav_gozlem to authenticated;
grant all    on public.tefas_nav_gozlem to service_role;

-- GRANT + RLS doğrulaması (0036/0042 deseni): sessizce eksik kalmasın.
do $$
begin
  if not has_table_privilege('authenticated', 'public.tefas_nav_gozlem', 'select') then
    raise exception 'tefas_nav_gozlem: authenticated SELECT grant eksik';
  end if;
  if has_table_privilege('authenticated', 'public.tefas_nav_gozlem', 'insert') then
    raise exception 'tefas_nav_gozlem: authenticated INSERT verilmemeli';
  end if;
  if has_table_privilege('anon', 'public.tefas_nav_gozlem', 'select') then
    raise exception 'tefas_nav_gozlem: anon SELECT verilmemeli';
  end if;
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'tefas_nav_gozlem'
      and c.relrowsecurity and c.relforcerowsecurity
  ) then
    raise exception 'tefas_nav_gozlem: RLS/FORCE RLS acik degil';
  end if;
end $$;

-- ── Tur defteri: tek satır, son turun zamanı ────────────────────────────────
-- `onceki_kontrol` için: fonksiyon başlarken bir önceki turun zamanını buradan
-- okur, biterken kendi zamanını yazar. Önceki tur 45 dakikadan eskiyse
-- (atlanmış/başarısız tur, günün ilk turu) aralık bilinmiyor → NULL yazılır.
-- Yalnız service_role dokunur.
create table if not exists public.tefas_nav_tur (
  tek      boolean primary key default true check (tek),
  son_tur  timestamptz not null
);
alter table public.tefas_nav_tur enable row level security;
alter table public.tefas_nav_tur force  row level security;
revoke all on public.tefas_nav_tur from public, anon, authenticated;
grant all on public.tefas_nav_tur to service_role;

-- ── Temizlik: gözlem 60 günden eski olunca silinir ──────────────────────────
-- İstemci yalnızca çizilen günün satırına bakar; geçmiş yalnızca teşhis
-- (yayın saatinin fon bazında dağılımı) için tutulur.
create or replace function public.cleanup_tefas_nav_gozlem()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.tefas_nav_gozlem
   where nav_tarihi < (now() at time zone 'Europe/Istanbul')::date - 60;
$$;

revoke all on function public.cleanup_tefas_nav_gozlem() from public, anon, authenticated;

-- ── Tetikleyici (0054 `cron_headers` deseni) ────────────────────────────────
create or replace function public.trigger_observe_tefas_nav()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/observe-tefas-nav',
    headers := public.cron_headers('tefas_nav_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- Kod sayısı kadar TEFAS isteği (4'lü paralel); 5 sn yetmez
    -- (bkz. 0040_cron_http_timeout.sql).
    timeout_milliseconds := 90000
  );
end;
$$;

revoke all on function public.trigger_observe_tefas_nav() from public, anon, authenticated;

-- ── Zamanlama ───────────────────────────────────────────────────────────────
select cron.unschedule(jobid) from cron.job
 where jobname in ('observe-tefas-nav', 'tefas-nav-gozlem-cleanup');

-- pg_cron UTC. `*/30 3-18 * * 1-5` = TR 06:00–21:30, iş günleri, yarım
-- saatte bir. Pencere alarm cron'undan (05-18) iki saat erken başlar: bazı
-- fonların NAV'ı sabah erken görünüyor; ilk turda görülen tarih yalnızca
-- ÜST sınır verir, o sınırı olabildiğince erkene çekmek istiyoruz.
--
-- Maliyet: bir fonun BUGÜN tarihli NAV'ı bir kez görülünce o kod gün
-- boyu bir daha SORULMAZ (fonksiyon süzüyor). Yayın öncesi turlar kod
-- sayısı kadar istek atar; kod sayısı üst sınırlı (fonksiyonda 150).
select cron.schedule('observe-tefas-nav', '*/30 3-18 * * 1-5',
  $$select public.trigger_observe_tefas_nav()$$);

select cron.schedule('tefas-nav-gozlem-cleanup', '50 22 * * 0',
  $$select public.cleanup_tefas_nav_gozlem()$$);
