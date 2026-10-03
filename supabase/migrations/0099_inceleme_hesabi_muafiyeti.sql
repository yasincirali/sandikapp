-- ============================================================
-- 0099 — Mağaza inceleme / test hesabı tek cihaz kuralından muaf (2026-10-03)
--
-- 0098 yeni cihazda e-posta kodu ister ve hesabı tek cihazda tutar.
-- App Store / TestFlight harici / Play incelemesi demo hesapla, kendi
-- cihazlarından ve çoğu zaman AYNI ANDA birden çok cihazdan girer; demo
-- hesabın e-postasını okuyamaz. Muafiyet olmadan inceleyici kod ekranında
-- kalır ("giriş yapılamıyor" reddi). Kullanıcı kararı (2026-10-03):
-- test.sandikapp@gmail.com muaf.
--
-- Veri değişikliği ama migration'da: iki sunucu birebir kuralı (CLAUDE.md)
-- — panelden tek projede yazılırsa diğerinde unutulur. Hesap o sunucuda
-- yoksa (taze yerel yığın, CI) satır eklenmez, hata da vermez.
-- Muafiyeti kaldırmak: `delete from public.cihaz_kontrol_muafiyeti
-- where neden like 'magaza inceleme%'` (yeni migration ile).
-- ============================================================

insert into public.cihaz_kontrol_muafiyeti (user_id, neden)
select u.id, 'magaza inceleme / test hesabi'
  from auth.users u
 where lower(u.email) = 'test.sandikapp@gmail.com'
on conflict (user_id) do nothing;

-- Doğrulama: hesap bu sunucuda VARSA muaf olmalı.
do $$
begin
  if exists (select 1 from auth.users where lower(email) = 'test.sandikapp@gmail.com')
     and not exists (
       select 1 from public.cihaz_kontrol_muafiyeti m
         join auth.users u on u.id = m.user_id
        where lower(u.email) = 'test.sandikapp@gmail.com')
  then
    raise exception '0099: test hesabi muafiyete yazilamadi';
  end if;
end $$;
