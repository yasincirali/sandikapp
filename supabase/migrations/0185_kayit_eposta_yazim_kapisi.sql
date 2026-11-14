-- 0185 — Kayıtta açık yazım hatalı e-posta alan adını sunucuda reddet
-- (yasin 2026-11-14: "sunucu kapısını yaz").
--
-- Neden: 14 Kasım sabahı mağazadaki sürümden "…@gmail.con" ile iki kayıt
-- geldi; kod e-postası geri döndü, kullanıcı hiç gelmeyen kodu bekledi.
-- İstemcideki öneri (#374/#376, `lib/utils/eposta_onerisi.dart`) yalnız yeni
-- build'de; telefonlarda haftalarca eski sürüm çalışır. Bu kapı ESKİ
-- istemciyi de korur: GoTrue "Before User Created" kancası kullanıcı
-- yaratılmadan önce bu fonksiyonu çağırır, ret mesajı kayıt ekranına döner.
--
-- Kapsam bilerek DAR: yalnız (1) `.com` son ekinin açık yazım hataları
-- (.con, .cmo…) ve (2) büyük sağlayıcıların bilinen yazım hataları
-- (gmial.com…). Benzerlik tahmini (mesafe) sunucuda YOK — gerçek ama az
-- bilinen bir alan adını reddetmek kaydı tamamen keserdi; istemci orada
-- yalnız öneri gösterir. Liste istemciyle tutarlı:
-- `test/eposta_sunucu_kapisi_parite_test.dart` buradaki her çift için
-- istemcinin aynı düzeltmeyi önerdiğini doğrular.
--
-- Mesaj İngilizce "Email address … invalid" ifadesini taşır: eski
-- istemcilerin `friendlyError`'u bunu "E-posta adresi geçersiz. Yazımını
-- kontrol et." diye gösterir (Türkçe serbest metin genel "işlem
-- tamamlanamadı"ya düşerdi). Sonuna önerilen alan adı eklenir.
--
-- Ekleyici: kanca panelde açılana kadar hiçbir şey değişmez (Authentication
-- → Hooks → Before User Created → Postgres → public.hook_before_user_created).
-- Kapatmak = paneldeki anahtarı kapatmak; fonksiyon kalabilir.
-- Sosyal giriş (Apple/Google) de aynı kancadan geçer; sağlayıcıdan gelen
-- doğrulanmış adreslerde bu hatalar olmaz. İnceleme hesabı etkilenmez.

create or replace function public.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  eposta text := lower(trim(coalesce(event #>> '{user,email}', '')));
  alan text;
  dogru text;
  -- Sağlayıcı yazım hataları → doğrusu. İstemci paritesi testi bu bloğu
  -- 'yanlis' => 'dogru' satırlarından okur; biçimi koru.
  harita constant jsonb := jsonb_build_object(
    'gmial.com', 'gmail.com',
    'gmai.com', 'gmail.com',
    'gmal.com', 'gmail.com',
    'gamil.com', 'gmail.com',
    'gnail.com', 'gmail.com',
    'gmaill.com', 'gmail.com',
    'gmali.com', 'gmail.com',
    'gmil.com', 'gmail.com',
    'gmail.co', 'gmail.com',
    'gmail.cm', 'gmail.com',
    'gmail.om', 'gmail.com',
    'hotmial.com', 'hotmail.com',
    'hotmai.com', 'hotmail.com',
    'hotmal.com', 'hotmail.com',
    'hotamil.com', 'hotmail.com',
    'hotmil.com', 'hotmail.com',
    'hotmail.co', 'hotmail.com',
    'hotmail.cm', 'hotmail.com',
    'hotmail.com.t', 'hotmail.com.tr',
    'hotmial.com.tr', 'hotmail.com.tr',
    'outlok.com', 'outlook.com',
    'outllok.com', 'outlook.com',
    'otlook.com', 'outlook.com',
    'outlook.co', 'outlook.com',
    'yahooo.com', 'yahoo.com',
    'yaho.com', 'yahoo.com',
    'iclod.com', 'icloud.com',
    'icoud.com', 'icloud.com',
    'icloud.co', 'icloud.com',
    'icloud.cm', 'icloud.com'
  );
begin
  if position('@' in eposta) = 0 then
    return '{}'::jsonb;  -- Telefonla kayıt vb.; e-posta yoksa karışma.
  end if;
  alan := substring(eposta from '@([^@]+)$');
  if alan is null then
    return '{}'::jsonb;
  end if;

  dogru := harita ->> alan;
  if dogru is null and alan ~ '\.(con|cmo|cpm|vom|xom|cim|comm|coom|ocm)$' then
    dogru := regexp_replace(alan, '\.[a-z]+$', '.com');
    dogru := coalesce(harita ->> dogru, dogru);  -- gmial.con → gmail.com
  elsif dogru is null and alan ~ '\.comtr$' then
    dogru := regexp_replace(alan, '\.comtr$', '.com.tr');
  end if;

  if dogru is null then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'http_code', 400,
    'message', format(
      'Email address domain looks invalid (typo): %s. Did you mean %s?',
      alan, dogru)));
end;
$$;

-- Yalnız GoTrue çağırır. İstemci rolleri bu fonksiyonu göremez.
revoke all on function public.hook_before_user_created(jsonb)
  from public, anon, authenticated;
grant execute on function public.hook_before_user_created(jsonb)
  to supabase_auth_admin;
grant usage on schema public to supabase_auth_admin;

-- Doğrulama (0036/0042 deseni): izinler beklenen gibi değilse göç durur.
do $$
begin
  if not has_function_privilege('supabase_auth_admin',
      'public.hook_before_user_created(jsonb)', 'execute') then
    raise exception '0185: supabase_auth_admin çağıramıyor';
  end if;
  if has_function_privilege('anon',
      'public.hook_before_user_created(jsonb)', 'execute')
     or has_function_privilege('authenticated',
      'public.hook_before_user_created(jsonb)', 'execute') then
    raise exception '0185: istemci rolleri kancayı çağırabiliyor';
  end if;
  if not (public.hook_before_user_created(
       '{"user":{"email":"a@gmail.con"}}'::jsonb) ? 'error') then
    raise exception '0185: gmail.con reddedilmedi';
  end if;
  if public.hook_before_user_created(
       '{"user":{"email":"a@gmail.com"}}'::jsonb) <> '{}'::jsonb then
    raise exception '0185: gmail.com reddedildi';
  end if;
  if public.hook_before_user_created(
       '{"user":{"email":"a@sirket.co"}}'::jsonb) <> '{}'::jsonb then
    raise exception '0185: gerçek .co uzantısı reddedildi';
  end if;
end $$;
