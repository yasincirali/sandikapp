-- 0092 — Push token'ında bildirim biçimi sürümü (2026-10-01)
--
-- ## Neden
-- Bildirimler "C · Kart" tasarımına geçiyor: açılınca markalı bir görsel
-- (yön halkası + rakam). Kullanıcı kuralı (2026-10-01): "store
-- kullanıcılarını etkilemesin, yeni versiyondan güncellenmiş olsun." Sunucu
-- hangi cihazın yeni biçimi anladığını bilmeli; FCM token'ı bunu söylemez.
--
-- ## Sözleşme
-- `bildirim_surumu` NULL → eski istemci: FCM gövdesi birebir eskisi gibi.
-- `>= 2` → kart görseli eklenir (`_shared/bildirim_karti.ts`, KART_SURUMU).
-- Değeri YALNIZ yeni istemci, token kaydından sonra kendi satırına yazar
-- (`SupabaseService.setPushBildirimSurumu`); mevcut `own_update` RLS
-- politikası (0016) bunu zaten kapsar, yeni GRANT gerekmez.
--
-- ## Geriye uyum
-- Yalnız sütun ekleniyor; varsayılan NULL, mevcut satırlar ve eski
-- istemcinin `claim_push_token` çağrısı değişmez. Token başka hesaba
-- devredilirse (0069) satır silinip yeniden yazılır → NULL; yeni istemci
-- açılışta yeniden yazar. Gönderen fonksiyonlar sütun YOKSA eski seçime
-- düşer (`tokenSatirlariniOku`), dağıtım sırası bildirimi düşürmez.
--
-- İki sunucu birebir: Frankfurt → Tokyo, `supabase-deploy.yml` (hedef `ikisi`).

alter table public.user_push_tokens
  add column if not exists bildirim_surumu smallint;

alter table public.user_push_tokens
  drop constraint if exists user_push_tokens_bildirim_surumu_aralik;
alter table public.user_push_tokens
  add constraint user_push_tokens_bildirim_surumu_aralik
  check (bildirim_surumu is null or bildirim_surumu between 1 and 100);

comment on column public.user_push_tokens.bildirim_surumu is
  'İstemcinin anladığı bildirim biçimi. NULL = eski sürüm (düz metin). '
  '>= 2 = bildirim kartı görseli (_shared/bildirim_karti.ts KART_SURUMU). '
  'Yalnız yeni istemci yazar; eski sürümlere giden gövde değişmez (0092).';
