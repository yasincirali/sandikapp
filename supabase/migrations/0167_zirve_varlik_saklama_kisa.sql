-- 0167 — Zirve varlık ölçümlerinin saklaması 365 → 7 gün (2026-10-22)
--
-- ## Neden
-- yasin (2026-10-22): "database iyileştirme ve az alan kaplaması için
-- performanstan da ödün vermeyecek şekilde bir geliştirme". Boyut ölçümü
-- (db-boyut, 22 Eki) 82,5 MB / 500 MB ve düz; ileriye dönük tek büyüyen
-- kalem `zirve_allocation_snapshots`: her katılımcı için günde iki satır,
-- her satırda üç jsonb (allocation_pct, fon_detay 0084, varlik_detay 0158)
-- ve 365 gün saklanıyor. Oysa bu tabloyu okuyan HER yer yalnız son 24
-- saatin en yeni satırına bakar (0085, 0091, 0144, 0158 RPC'leri:
-- `created_at >= now() - interval '24 hours'`); leaderboard-snapshot
-- yalnız yazar, istemci tabloyu hiç görmez (RLS açık, politika yok).
-- Yani 24 saatten eski 364 günlük ayrıntı hiçbir ekranda görünmeyen ölü
-- veridir. 7 gün: hata ayıklama için bir haftalık geçmiş kalır.
--
-- ## Performans
-- Okuma yolu değişmez; tablo küçüldükçe `distinct on (user_id)` taraması
-- kısalır. Silme haftalık cron'da (0081 `leaderboard-snapshot-retention`,
-- Pazartesi 03:35) zaten çalışan fonksiyonun içinde; yeni cron yok. Boşalan
-- sayfaları autovacuum yeni satırlara verir, tablo bundan sonra büyümez.
-- Diske geri vermek için elle `vacuum full public.zirve_allocation_snapshots;`
-- (isteğe bağlı, SQL Editor'da tek komut).
--
-- ## Yasal metin
-- KVKK Aydınlatma Metni saklama tablosu "Zirve havuzu ölçümleri: son 365 gün
-- rolling" der; bu bir üst sınırdır, kısaltma metinle çelişmez. Getiri
-- ölçümleri (`zirve_roi_snapshots`, dar satırlar) ve yarış tabloları
-- (user_*; istemci `user_allocation_snapshots`'a yazar) 365 günde kalır.
--
-- Yalnız sunucu içi temizlik: eski sürümler etkilenmez, imza değişmez.

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
  -- Okuyucular yalnız son 24 saate bakar; 7 gün hata ayıklama payı (0167).
  delete from public.zirve_allocation_snapshots where created_at < now() - interval '7 days';
end;
$$;
revoke all on function public.cleanup_leaderboard_snapshots() from public, anon, authenticated;

-- İlk temizlik şimdi; sonrası mevcut haftalık cron.
select public.cleanup_leaderboard_snapshots();

do $$
declare
  tanim text := pg_get_functiondef('public.cleanup_leaderboard_snapshots()'::regprocedure);
begin
  if position('zirve_allocation_snapshots where created_at < now() - interval ''7 days''' in tanim) = 0 then
    raise exception '0167: zirve_allocation_snapshots 7 gun saklamasi yok';
  end if;
  if position('user_allocation_snapshots  where created_at < now() - interval ''365 days''' in tanim) = 0 then
    raise exception '0167: yaris saklamasi 365 gunden saptı';
  end if;
  if has_function_privilege('authenticated', 'public.cleanup_leaderboard_snapshots()', 'EXECUTE')
     or has_function_privilege('anon', 'public.cleanup_leaderboard_snapshots()', 'EXECUTE') then
    raise exception '0167: cleanup_leaderboard_snapshots istemciye acik';
  end if;
  if not exists (select 1 from cron.job where jobname = 'leaderboard-snapshot-retention') then
    raise exception '0167: leaderboard-snapshot-retention cron isi yok';
  end if;
  if exists (select 1 from public.zirve_allocation_snapshots
              where created_at < now() - interval '7 days') then
    raise exception '0167: 7 gunden eski zirve varlik olcumu kaldi';
  end if;
  raise notice '0167 tamam: zirve varlik olcumleri 7 gun, digerleri 365 gun.';
end $$;
