-- 0090 — Yarış snapshot saklaması 400 → 365 gün (2026-10-01)
--
-- ## Neden
-- Kullanıcı sorusu (2026-10-01): "Yarış verisi neden 400 gün saklanır, max
-- 365 günlük hesaplanmıyor mu?" Haklı — 400 günün işlevsel karşılığı yok:
--   * RPC'ler en fazla son 24 saati okur (0081 notu),
--   * uygunluk kuralı son 30 günde FARKLI gün sayar (0059),
--   * 365 günlük dönem getirisi bir yıl önceki satırdan DEĞİL, bugünkü
--     satırın `period_days = 365` kaydından okunur.
-- 400 yalnızca "biraz pay bırakalım" sezgisiydi ve Gizlilik Politikası /
-- KVKK Aydınlatma Metni "son 365 gün" diyor — metin ile uygulama ayrışıyordu.
-- Veri minimizasyonu (KVKK m.4/2-ç) gereği kısa olan doğru olandır; bütün
-- snapshot tabloları 365 günde hizalanır.
--
-- Mevcut haftalık cron (0081, `leaderboard-snapshot-retention`) aynı
-- fonksiyonu çağırır; yeni cron yok. İlk koşuda 365–400 gün arası satırlar
-- silinir (geri alınamaz, ama hiçbir okuyucu onlara bakmıyordu).

create or replace function public.cleanup_leaderboard_snapshots()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.user_roi_snapshots         where created_at < now() - interval '365 days';
  delete from public.user_allocation_snapshots  where created_at < now() - interval '365 days';
  delete from public.zirve_roi_snapshots        where created_at < now() - interval '365 days';
  delete from public.zirve_allocation_snapshots where created_at < now() - interval '365 days';
end;
$$;
revoke all on function public.cleanup_leaderboard_snapshots() from public, anon, authenticated;

do $$
begin
  if position('400 days' in pg_get_functiondef('public.cleanup_leaderboard_snapshots()'::regprocedure)) > 0 then
    raise exception '0090: cleanup_leaderboard_snapshots hala 400 gun iceriyor';
  end if;
  if has_function_privilege('authenticated', 'public.cleanup_leaderboard_snapshots()', 'EXECUTE') then
    raise exception '0090: cleanup_leaderboard_snapshots authenticated tarafindan cagrilabilir olmamali';
  end if;
  raise notice '0090 tamam: yaris + zirve snapshot saklamasi 365 gun.';
end $$;
