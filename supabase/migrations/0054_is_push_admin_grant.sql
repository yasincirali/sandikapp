-- 0054 — is_push_admin() istemciden çağrılabilir olsun.
--
-- 0021 fonksiyonu tanımlayıp public/anon'dan revoke etti ama authenticated'a
-- GRANT vermedi; istemci "ben admin miyim" sorusunu soramıyordu. Bu yüzden
-- Ayarlar ekranındaki "Push Teşhisi" tile'ı herkese görünüyor, admin olmayan
-- kullanıcı ekrana girince "Bu hesap admin değil" ile karşılaşıyordu.
--
-- Fonksiyon yalnızca ÇAĞIRANIN kendi admin bayrağını döndürür (auth.uid()
-- üzerinden); başka kullanıcı hakkında bilgi sızdırmaz. Teşhis RPC'lerinin
-- kendi is_push_admin() kontrolleri değişmedi.
grant execute on function public.is_push_admin() to authenticated;

comment on function public.is_push_admin() is
  'Çağıran hesap push teşhis admin''i mi. Ayarlar ekranı tile görünürlüğü '
  'için istemciden çağrılır; RPC''lerin kendi kontrolü ayrıca sürer.';
