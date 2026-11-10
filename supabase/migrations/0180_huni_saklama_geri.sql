-- 0180 — Kayıt hunisi 400 gün saklama silmesi geri geldi (2026-11-10)
--
-- ## Neden
-- 0097 `huni_olaylari` satırlarını 400 gün sonra silmeyi `cleanup_db_logs`
-- (günlük `db-logs-retention` işi) içine ekledi. 0114 aynı fonksiyonu
-- yalnız `db_logs` için yeniden yazarken bu satırı düşürdü; o günden beri
-- hunideki adımları silen bir iş yok, satırlar süresiz kalıyor. Oysa
-- Gizlilik Politikası ve KVKK Aydınlatma Metni "Kayıt hunisi adımları |
-- 400 gün" diyor. Aykırılığı yeni `saklama_sureleri_test` buldu (yasal
-- metin ↔ migration karşılaştırması, Ar-Ge 22 Eki 17:15 #3).
--
-- Metin değişmez, kod metne uyar. Tablo 0097'de (Ekim 2026) geldiği için
-- bugün 400 günden eski satır yok: bu migration ilk satırı 2027 sonbaharında
-- siler, canlı veride bugün bir şey eksilmez.
--
-- ## Değişmeyen
-- `db_logs` kuralı 0114'teki gibi (hatalar 30 gün, başarılı satırlar 1 gün).
-- İş, yetkiler ve zamanlama aynı; istemci tarafı yok.

create or replace function public.cleanup_db_logs()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.db_logs
   where ts < now() - interval '30 days'
      or (not is_error and ts < now() - interval '1 day');
  delete from public.huni_olaylari where yazildi < now() - interval '400 days';
$$;

revoke all on function public.cleanup_db_logs() from public, anon, authenticated;

comment on function public.cleanup_db_logs() is
  'db_logs saklama: hatalar 30 gun (0056), basarili satirlar 1 gun (0114); '
  'huni_olaylari 400 gun (0097, 0180 geri getirdi).';

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
declare
  tanim text := pg_get_functiondef('public.cleanup_db_logs()'::regprocedure);
begin
  if position('1 day' in tanim) = 0 then
    raise exception '0180: cleanup_db_logs basarili satirlari 1 gunde silmeli';
  end if;
  if position('huni_olaylari' in tanim) = 0 or position('400 days' in tanim) = 0 then
    raise exception '0180: cleanup_db_logs huni_olaylari 400 gun silmesini icermeli';
  end if;
  if has_function_privilege('authenticated', 'public.cleanup_db_logs()', 'execute') then
    raise exception '0180: cleanup_db_logs authenticated tarafindan cagrilamamali';
  end if;
end $$;
