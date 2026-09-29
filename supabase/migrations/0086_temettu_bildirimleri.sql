-- 0086 — Temettü yakalama: bildirim defteri + günlük cron (2026-09-29)
--
-- ## Neden
-- Temettü kaydı tamamen kullanıcıya kalmıştı: hisse temettü dağıttığında
-- uygulama bunu bilmiyor, kullanıcı hatırlamazsa getirisi eksik görünüyor.
-- Yahoo chart API'si GERÇEKLEŞMİŞ (hak kullanımı yapılmış) temettüleri
-- `events.dividends` içinde TL/pay olarak veriyor. `temettu-yakala` edge
-- function'ı her akşam son 30 günün olaylarını çekip hak tarihinde lot'u
-- olan kullanıcıya ÖNERİ gönderir (push + çan).
--
-- ## Bu tablo bir KAYIT DEĞİL, bir DEFTERDİR
-- Temettünün kendisi yine `assets` tablosuna `kind='dividend'` satırı
-- olarak, istemcinin `addDividend` yolundan ve kullanıcı onayıyla yazılır
-- (temettü miktara girmez değişmezi dokunulmadan kalır). Buradaki satır
-- yalnızca "bu kullanıcıya bu olay için öneri GÖNDERİLDİ" demektir: aynı
-- olay ertesi akşam (30 günlük pencere boyunca her gün görünür) ikinci kez
-- gönderilmesin. Anahtar (user_id, ticker, hak_tarihi) — bir hisse aynı
-- gün iki kez temettü dağıtmaz.
--
-- `tutar_pay` / `lot` öneri anındaki değerlerdir (teşhis için: "bana 100
-- lot yazdı, oysa 80 lotum vardı" sorusunun cevabı). Brüttür; stopaj
-- istemcide Remote Config'ten uygulanır (bilinmiyorsa uydurulmaz).
--
-- ## Yetki: yalnız OKU
-- İstemci kendi satırını okuyabilir (ileride "önerildi" rozeti için);
-- yazma yalnızca service_role. İstemciye INSERT verilseydi kullanıcı
-- satırı önceden yazıp bildirimi kalıcı susturabilirdi — zararsız ama
-- anlamsız bir yüzey; 0035/0036 `signal_state` gerekçesinin aynısı.
-- GRANT ve RLS ayrı katmanlardır (0036/0042/0043): ikisi de burada yazılır
-- ve sonda doğrulanır.

-- ── 1) Tablo ────────────────────────────────────────────────────────────────
create table if not exists public.temettu_bildirimleri (
  user_id     uuid not null references auth.users(id) on delete cascade,
  -- Yahoo sembolü (`THYAO.IS`) — `assets.ticker` ile aynı yazım.
  ticker      text not null,
  -- Hak kullanım (ex-dividend) günü, TR takvimi.
  hak_tarihi  date not null,
  -- TL/pay, brüt (Yahoo `amount`).
  tutar_pay   numeric not null check (tutar_pay > 0),
  -- Hak tarihinden önceki günün kapanışındaki net lot.
  lot         numeric not null check (lot > 0),
  created_at  timestamptz not null default now(),
  primary key (user_id, ticker, hak_tarihi)
);

-- `temettu-yakala` defteri pencereyle okur (`hak_tarihi >= bugün − 31`);
-- PK `user_id` ile başladığı için o sorguya yaramaz. Tablo küçük kalır ama
-- silinmez (teşhis kaydı), yıllar içinde tam taramaya dönmesin.
create index if not exists temettu_bildirimleri_hak_tarihi_idx
  on public.temettu_bildirimleri (hak_tarihi);

comment on table public.temettu_bildirimleri is
  'Temettu onerisi gonderim defteri (0086). Temettu KAYDI degildir: kayit '
  'assets.kind=dividend satiri olarak istemciden, kullanici onayiyla yazilir. '
  'Satiri yalniz temettu-yakala (service_role) yazar; kullanici kendi '
  'satirini yalniz okur.';

-- ── 2) RLS ──────────────────────────────────────────────────────────────────
alter table public.temettu_bildirimleri enable row level security;
-- 0056: sahip rol de politikaya tabi olsun (derinlemesine savunma).
alter table public.temettu_bildirimleri force row level security;

drop policy if exists temettu_bildirimleri_own_select on public.temettu_bildirimleri;
create policy temettu_bildirimleri_own_select
  on public.temettu_bildirimleri
  for select to authenticated
  -- `(select auth.uid())`: satır başına değil sorgu başına bir kez (0077).
  using ((select auth.uid()) = user_id);

-- INSERT/UPDATE/DELETE politikası BİLEREK yok: authenticated için GRANT de
-- yok, iki katman birlikte kapalı. service_role RLS'yi baypas eder.

-- ── 3) GRANT ────────────────────────────────────────────────────────────────
-- Supabase `public` şemasında yeni tabloya anon/authenticated için geniş
-- varsayılan yetki verir; önce hepsi geri alınır, sonra yalnız SELECT.
revoke all on table public.temettu_bildirimleri from public, anon, authenticated;
grant select on table public.temettu_bildirimleri to authenticated;
grant select, insert, update, delete on table public.temettu_bildirimleri to service_role;

-- ── 4) Çan kaydı türü ───────────────────────────────────────────────────────
-- `app_notifications.type` CHECK kısıtı (0066 → 0067 → 0068) yeni türle
-- GENİŞLETİLİR; var olan türlerin hiçbiri çıkmaz.
alter table public.app_notifications
  drop constraint if exists app_notifications_type_check;
alter table public.app_notifications
  add constraint app_notifications_type_check check (type in (
    'partner_invite', 'daily_brief', 'weekly_summary', 'monthly_summary',
    'watchlist_move', 'inflation_day', 'calendar_nudge', 'temettu'));

-- ── 5) Tetikleyici ──────────────────────────────────────────────────────────
-- 0076 deseni: adres Vault `project_url`, başlıklar `cron_headers`
-- (secret `x-cron-secret`'ta; Authorization gateway'e ait — 0054).
-- Vault'ta `temettu_yakala_cron_secret` yoksa çağrı anında `cron_secret_of`
-- patlar ve iş `cron.job_run_details`'ta "failed" görünür (fail-closed);
-- yer tutucu tohum EKİLMEZ (0076 gerekçesi).
create or replace function public.trigger_temettu_yakala()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('temettu-yakala'),
    headers := public.cron_headers('temettu_yakala_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- Sembol başına bir Yahoo isteği + kullanıcı başına push: 5 sn yetmez (0040).
    timeout_milliseconds := 120000
  );
end;
$$;

revoke all on function public.trigger_temettu_yakala() from public, anon, authenticated;

-- ── 6) Zamanlama (pg_cron UTC; TR = UTC+3, DST yok) ─────────────────────────
-- 19:00 TR = 16:00 UTC, HER gün. BIST kapanışı 18:10; Yahoo hak kullanım
-- olayını gün içinde yazar. Hafta sonu da koşar: Cuma olayı Cumartesi
-- ikinci kez görünür ama defter tekrar önler.
select cron.unschedule(jobid) from cron.job where jobname = 'temettu-yakala';
select cron.schedule('temettu-yakala', '0 16 * * *',
  $$select public.trigger_temettu_yakala()$$);

-- İki sunucu birebir (CLAUDE.md, 2026-09-28): şema iki projede aynı, tek
-- bilinçli fark cron `active` bayrağı — geçişe kadar Frankfurt'ta TÜM işler
-- kapalı (iki sunucu aynı kişiye iki push atmasın). `cron.schedule` yeni
-- işi AÇIK doğurur; Frankfurt'ta bu, ilk akşam çift bildirim demek.
-- Proje ref'i SABİT yazılmaz: projede başka iş var ve HİÇBİRİ açık değilse
-- proje "cron kapalı" kipindedir, yeni iş de ona uyar. Tokyo'da (işler
-- açık) iş açık kalır. Geçişte `alter_job(active := true)` bunu da açar.
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'temettu-yakala')
     and not exists (select 1 from cron.job
                      where jobname <> 'temettu-yakala' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'temettu-yakala';
    raise notice '0086: projede tum cron isleri kapali — temettu-yakala da kapali kuruldu.';
  end if;
end $$;

-- ── 7) Doğrulama ────────────────────────────────────────────────────────────
-- GRANT ve RLS ayrı şeylerdir; biri eksikken tablo "çalışıyor" görünür
-- (0035/0036). Migration kendini denetler.
do $$
begin
  if not has_table_privilege('authenticated', 'public.temettu_bildirimleri', 'SELECT') then
    raise exception '0086: authenticated icin temettu_bildirimleri SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.temettu_bildirimleri', 'INSERT')
     or has_table_privilege('authenticated', 'public.temettu_bildirimleri', 'UPDATE')
     or has_table_privilege('authenticated', 'public.temettu_bildirimleri', 'DELETE') then
    raise exception '0086: authenticated temettu_bildirimleri tablosuna YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.temettu_bildirimleri', 'SELECT') then
    raise exception '0086: anon temettu_bildirimleri tablosunu okuyamamali';
  end if;
  if not has_table_privilege('service_role', 'public.temettu_bildirimleri', 'INSERT') then
    raise exception '0086: service_role icin temettu_bildirimleri INSERT GRANT eksik';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.temettu_bildirimleri'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0086: temettu_bildirimleri RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'temettu_bildirimleri') <> 1
     or not exists (select 1 from pg_policies
                     where schemaname = 'public'
                       and tablename = 'temettu_bildirimleri'
                       and policyname = 'temettu_bildirimleri_own_select'
                       and cmd = 'SELECT') then
    raise exception '0086: temettu_bildirimleri yalniz own_select politikasini tasimali';
  end if;
  if not exists (select 1 from pg_constraint
                  where conname = 'app_notifications_type_check'
                    and pg_get_constraintdef(oid) like '%temettu%') then
    raise exception '0086: app_notifications_type_check temettu turunu tanimiyor';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'temettu-yakala' and schedule = '0 16 * * *') then
    raise exception '0086: temettu-yakala cron isi kurulmadi';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_temettu_yakala()', 'EXECUTE') then
    raise exception '0086: trigger_temettu_yakala authenticated tarafindan cagrilabilir olmamali';
  end if;

  raise notice '0086 tamam: temettu_bildirimleri + RLS + GRANT + cron yerinde.';
end $$;
