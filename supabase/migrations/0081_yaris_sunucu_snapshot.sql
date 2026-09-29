-- 0081 — Yarış snapshot'ları sunucuda: opt-in sütunu + günlük cron (2026-09-28)
--
-- Sorun: `user_roi_snapshots` / `user_allocation_snapshots` yalnızca
-- İSTEMCİDEN yazılıyordu (opt-in kullanıcı Profil kartını ya da Yarış
-- ekranını açınca). Küresel havuzun uygunluk kuralı (0059: son 30 günde ≥5
-- farklı gün ROI snapshot'ı + son 24 saatte dağılım snapshot'ı) ve zirve
-- portföyler eşiği (k_min=8) bu yüzden dolmuyordu: onlarca portföy, 2 uygun
-- kullanıcı. Kullanıcı kararı: snapshot'ı sunucu her gün atar.
--
-- Bu migration:
--   1. `profiles.leaderboard_opt_in` — opt-in artık SUNUCUDA bilinir.
--      Eskiden yalnız cihaz tercihiydi; sunucu "kim yarışta" bilmeden kimin
--      snapshot'ını atacağını seçemez. İstemci tercihi değişince yazar
--      (`SupabaseService.yarisOptInYaz`); geri doldurma: daha önce snapshot
--      atmış herkes opt-in demişti.
--   2. `trigger_leaderboard_snapshot()` → edge function `leaderboard-snapshot`
--      (adres Vault `project_url`, 0076; secret `leaderboard_snapshot_cron_secret`,
--      0054 kalıbı). Günlük 18:40 TR = 15:40 UTC, her gün: altın/kripto hafta
--      sonu da oynar; uygunluk kuralı FARKLI GÜN sayar.
--   3. Snapshot tablolarına saklama: 400 gün. RPC'ler en fazla son 24 saati
--      ve uygunluk son 30 günü okur; 365 günlük dönem satırı bile bugünün
--      satırıdır (period_days sütunu). Sınırsız büyüme = 4 satır/kullanıcı/gün.
--
-- İstemci ROI'si ile sunucu ROI'si aynı tanımdır (miktar sabit, yalnız fiyat
-- etkisi) ama fiyat kaynağı farklı olabilir (altın: truncgil vs GC=F). Oran
-- hesabında fark iki uca da uygulandığı için küçüktür; kendi satırının
-- istemci hesabıyla gösterilmesi TECHNICAL_DEBT'te kayıtlı.

-- ── 1) Opt-in sütunu ───────────────────────────────────────────────────────
alter table public.profiles
  add column if not exists leaderboard_opt_in boolean not null default false;

comment on column public.profiles.leaderboard_opt_in is
  'Yarisa katilim (0081). Istemci tercihi degisince yazar; gunluk snapshot cronu yalnizca true olanlari hesaplar.';

-- Geri doldurma: istemciden snapshot atmış olan herkes opt-in yapmıştı.
update public.profiles p
   set leaderboard_opt_in = true
 where p.leaderboard_opt_in = false
   and exists (select 1 from public.user_roi_snapshots s where s.user_id = p.id);

-- ── 2) Tetikleyici ─────────────────────────────────────────────────────────
create or replace function public.trigger_leaderboard_snapshot()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('leaderboard-snapshot'),
    headers := public.cron_headers('leaderboard_snapshot_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    timeout_milliseconds := 120000
  );
end;
$$;
revoke all on function public.trigger_leaderboard_snapshot() from public, anon, authenticated;

-- ── 3) Saklama ─────────────────────────────────────────────────────────────
create or replace function public.cleanup_leaderboard_snapshots()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.user_roi_snapshots        where created_at < now() - interval '400 days';
  delete from public.user_allocation_snapshots where created_at < now() - interval '400 days';
end;
$$;
revoke all on function public.cleanup_leaderboard_snapshots() from public, anon, authenticated;

-- ── 4) Zamanlama (pg_cron UTC; TR = UTC+3) ─────────────────────────────────
select cron.unschedule(jobid) from cron.job
 where jobname in ('leaderboard-snapshot', 'leaderboard-snapshot-retention');

-- BIST kapanış 18:10, TEFAS günlük fiyat akşam; 18:40 TR = 15:40 UTC, HER gün.
select cron.schedule('leaderboard-snapshot', '40 15 * * *',
  $$select public.trigger_leaderboard_snapshot()$$);
-- Pazartesi 06:35 TR.
select cron.schedule('leaderboard-snapshot-retention', '35 3 * * 1',
  $$select public.cleanup_leaderboard_snapshots()$$);

-- ── 5) Doğrulama ───────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'profiles'
       and column_name = 'leaderboard_opt_in'
  ) then
    raise exception 'profiles.leaderboard_opt_in eksik';
  end if;
  -- İstemci kendi satırını güncelleyebilmeli (RLS profiles_update_own +
  -- tablo GRANT'ı). GRANT ve RLS ayrı şeylerdir; ikisi de yerinde mi?
  if not has_column_privilege('authenticated', 'public.profiles', 'leaderboard_opt_in', 'UPDATE') then
    raise exception 'authenticated icin profiles.leaderboard_opt_in UPDATE GRANT eksik';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                   and tablename = 'profiles' and policyname = 'profiles_update_own') then
    raise exception 'profiles_update_own RLS politikasi yok';
  end if;
  if not exists (select 1 from cron.job where jobname = 'leaderboard-snapshot'
                   and schedule = '40 15 * * *') then
    raise exception 'leaderboard-snapshot cron isi kurulmadi';
  end if;
  if not exists (select 1 from cron.job where jobname = 'leaderboard-snapshot-retention') then
    raise exception 'leaderboard-snapshot-retention cron isi kurulmadi';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_leaderboard_snapshot()', 'EXECUTE') then
    raise exception 'trigger_leaderboard_snapshot authenticated tarafindan cagrilabilir olmamali';
  end if;
end $$;
