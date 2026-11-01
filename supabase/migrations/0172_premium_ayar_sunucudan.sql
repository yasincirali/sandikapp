-- 0172 — Paywall ayarları sunucudan, Remote Config'siz (yasin 2026-11-01:
-- "rc flagleriyle yönetmemeye çalışalım burayı")
--
-- ## Neden
-- Açılış dört elle adımdı: hediye SQL'i → RC `premium_hediye_kesim` → RC
-- `paywall_enabled` (sürüm koşulu) → `kapi_acik`. Üçü Remote Config'teydi ve
-- kesim ile hediye SQL'i iki ayrı yerde elle eşleniyordu; biri atlanınca ya
-- herkes kilit görüyor ya da ücretli içerik açıkta kalıyordu. App Store 2.3.1
-- kaygısı da RC'de koşullu açılan özellikten geliyordu. Artık:
-- - Paywall'ın "görünür mü" kararı KODDA (iOS'ta açık; Android RevenueCat
--   kurulunca), Remote Config okunmaz.
-- - Hediye kesimi `erken_kullanici_hediyesi_ver` çağrısıyla BURAYA yazılır;
--   uygulama onu `premium_ayarlari()` ile okur. Tek kaynak, elle eşleme yok.
-- - Acil kapatma da burada: `acil_kapali = true` → kilitler askıya alınır,
--   ödeyenin hakkı korunur (eski RC `premium_enabled=false` davranışı).
--
-- ## Eski sürümler
-- Yalnız ekleme: iki kolon, bir RPC, fonksiyonun gövdesine bir UPDATE.
-- 1.1.7 ve öncesi bu kolonları okumaz; onlar RC'den okumaya devam eder.
-- Konsoldaki RC anahtarları eski build'ler kullanımdan düşene kadar kalır.

alter table public.premium_ayar
  add column if not exists hediye_kesim timestamptz,
  add column if not exists acil_kapali boolean not null default false;

comment on column public.premium_ayar.hediye_kesim is
  'Erken kullanıcı hediyesinin kesimi; erken_kullanici_hediyesi_ver yazar, uygulama okur (0172).';
comment on column public.premium_ayar.acil_kapali is
  'true → uygulamada kilitler askıda (acil durum); ödeyenin hakkı korunur (0172).';

-- Hediye fonksiyonu kesimi de kaydeder (gövde 0160 ile aynı + tek UPDATE).
create or replace function public.erken_kullanici_hediyesi_ver(
  p_kesim timestamptz,
  p_gun integer default 90,
  p_yayilim_gun integer default 0
)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_sayi integer;
begin
  if p_kesim is null or p_kesim > now() then
    raise exception 'erken_kullanici_hediyesi_ver: kesim gelecekte olamaz' using errcode = '22023';
  end if;
  if p_gun is null or p_gun < 1 or p_gun > 366 then
    raise exception 'erken_kullanici_hediyesi_ver: gun 1-366 olmali' using errcode = '22023';
  end if;
  if p_yayilim_gun is null or p_yayilim_gun < 0 or p_yayilim_gun > 60 then
    raise exception 'erken_kullanici_hediyesi_ver: yayilim 0-60 olmali' using errcode = '22023';
  end if;

  insert into public.premium_haklari (user_id, kaynak, bitis)
  select u.id,
         'erken_kullanici',
         now()
           + make_interval(days => p_gun)
           + make_interval(days => mod(abs(hashtext(u.id::text)), p_yayilim_gun + 1))
    from auth.users u
   where u.created_at < p_kesim
     and u.deleted_at is null
  on conflict (user_id, kaynak) do nothing;
  get diagnostics v_sayi = row_count;

  -- Kesim tek yerde: uygulama bunu okur, elle RC'ye yazılmaz (0172).
  -- En büyük kesim kalır: ikinci bir çağrı daha eski bir kesimle kesimi geri
  -- çekemez (o arada hediye alanları "yeni hesap" saymamak için).
  update public.premium_ayar
     set hediye_kesim = greatest(coalesce(hediye_kesim, p_kesim), p_kesim),
         guncellendi = now()
   where tek;
  return v_sayi;
end;
$$;

-- Uygulamanın okuduğu ayarlar. Oturumlu herkese açık: değerler gizli değil
-- (kapı, kesim, acil durum); tablo RLS'yle kapalı kalır, yalnız bu RPC okur.
create or replace function public.premium_ayarlari()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'kapi_acik',    a.kapi_acik,
    'hediye_kesim', a.hediye_kesim,
    'acil_kapali',  a.acil_kapali)
    from public.premium_ayar a
   where a.tek;
$$;
revoke all on function public.premium_ayarlari() from public, anon;
grant execute on function public.premium_ayarlari() to authenticated, service_role;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'premium_ayar'
                    and column_name in ('hediye_kesim', 'acil_kapali')
                 having count(*) = 2) then
    raise exception '0172: premium_ayar.hediye_kesim / acil_kapali yok';
  end if;
  if not has_function_privilege('authenticated', 'public.premium_ayarlari()', 'EXECUTE') then
    raise exception '0172: premium_ayarlari() authenticated tarafından çağrılamıyor';
  end if;
  if has_function_privilege('anon', 'public.premium_ayarlari()', 'EXECUTE') then
    raise exception '0172: premium_ayarlari() anon''a açık olmamalı';
  end if;
  if has_function_privilege('authenticated',
       'public.erken_kullanici_hediyesi_ver(timestamptz, integer, integer)', 'EXECUTE') then
    raise exception '0172: erken_kullanici_hediyesi_ver istemciden cagrilabilir olmamali';
  end if;
  raise notice '0172 tamam: paywall ayarlari sunucudan (hediye_kesim, acil_kapali, premium_ayarlari()).';
end $$;
