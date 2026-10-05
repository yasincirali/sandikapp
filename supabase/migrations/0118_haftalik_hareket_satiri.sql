-- 0118 — Pazartesi özetinde hareket satırı tercihi (Balina S19-A, 2026-10-05)
--
-- Haftalık bildirim (weekly-summary) tutulan varlıklardaki büyük para
-- giriş/çıkışı ve olağandışı hacmi tek cümleyle anar (`HAFTALIK_AKIS_SATIRI`).
-- Kullanıcı Ayarlar › Bildirimler'de bu satırı kapatabilmeli: yüzdeyi isteyip
-- radar cümlesini istemeyen olabilir. Tercih sunucuda, çünkü cümleyi kuran
-- sunucu.
--
-- Yalnız EKLER (eski sürümler bu kolonu okumaz, yazmaz): varsayılan true =
-- bugünkü davranış. Kullanıcı kendi satırını `profiles_update_own` RLS
-- politikasıyla günceller; ayrı GRANT gerekmez (tablo düzeyinde update
-- zaten açık, kolon düzeyi kısıt yok).

alter table public.profiles
  add column if not exists haftalik_hareket_satiri boolean not null default true;

comment on column public.profiles.haftalik_hareket_satiri is
  'Pazartesi ozetinde fon akisi / olagandisi hacim cumlesi (0118). false = cumle eklenmez.';

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'profiles'
       and column_name = 'haftalik_hareket_satiri'
  ) then
    raise exception '0118: profiles.haftalik_hareket_satiri yok';
  end if;
end $$;
