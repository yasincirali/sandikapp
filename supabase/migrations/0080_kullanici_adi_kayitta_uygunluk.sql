-- 0080 — Kayıt formunda anonim kullanıcı adı uygunluk denetimi (2026-09-28)
--
-- 0079 `kullanici_adi_uygun_mu`'yu oturumsuz çağrıya kapattı ("ad taraması
-- kayıt ekranından anonim yapılamasın"). Kullanıcı kararı (2026-09-28) bunu
-- tersine çevirdi: adını kayıt formunda veren kullanıcıya giriş kapısı bir
-- daha sorulmamalı; bunun için alınmış adın FORMDA — yani henüz oturum yokken
-- — görünmesi gerekir. Mevcut RPC'ye dokunulmaz (oturumlu ad ekranı onu
-- kullanmaya devam eder); anonim yüzey için ayrı, daha dar bir RPC açılır:
--   · 'ayrilmis' ile 'alinmis' ayrımı verilmez — anonim çağıran hangi adların
--     gerçek hesap olduğunu ayırt edemez (tarama yüzeyi daralır);
--   · tanınmayan kod da 'alinmis'e katlanır; anon tarafa yalnız
--     ok / bicim / uygunsuz / alinmis sızar.
-- `kullanici_adi_denetle` oturumsuz da doğru çalışır: `id is distinct from
-- auth.uid()` null ile her satıra true verir → her mevcut ad "alınmış".
-- Kalan risk: uygunluk sorgusu oran sınırsız, kayıt formu dışından da
-- çağrılabilir. Kabul edildi — kayıt uygunluğu her uygulamada anonim bir
-- sorudur; gerekirse gateway'de IP başına oran sınırı.

create or replace function public.kullanici_adi_kayitta_uygun_mu(p_ad text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  kod text := kullanici_adi_denetle(p_ad);
begin
  return case kod
    when 'ok' then 'ok'
    when 'bicim' then 'bicim'
    when 'uygunsuz' then 'uygunsuz'
    else 'alinmis'
  end;
end;
$$;

revoke all on function public.kullanici_adi_kayitta_uygun_mu(text) from public;
grant execute on function public.kullanici_adi_kayitta_uygun_mu(text) to anon, authenticated;

-- ── Doğrulama ──────────────────────────────────────────────────────────────
-- Anon yeni RPC'yi çağırabilmeli; iç denetleyici ve oturumlu RPC anon'a
-- KAPALI kalmalı (0079'un GRANT'ları bu migration'la gevşememeli).
do $$
begin
  if not has_function_privilege('anon',
      'public.kullanici_adi_kayitta_uygun_mu(text)', 'EXECUTE') then
    raise exception 'kullanici_adi_kayitta_uygun_mu: anon EXECUTE eksik';
  end if;
  if has_function_privilege('anon',
      'public.kullanici_adi_denetle(text)', 'EXECUTE') then
    raise exception 'kullanici_adi_denetle anon''a acik olmamali';
  end if;
  if has_function_privilege('anon',
      'public.kullanici_adi_uygun_mu(text)', 'EXECUTE') then
    raise exception 'kullanici_adi_uygun_mu (oturumlu) anon''a acik olmamali';
  end if;
end $$;
