-- 0160 — Erken kullanıcı hediyesi: yayılmış bitiş (paywall incelemesi, 2026-10-20)
--
-- ## Neden
-- `erken_kullanici_hediyesi_ver(kesim, 90)` herkese `now() + 90 gün` yazar:
-- hediye hangi gün verildiyse HERKESİN hediyesi aynı gün biter. O gün bütün
-- kullanıcılar birden kilit görür, hatırlatma push'u (0142) aynı gün gider ve
-- destek/dönüşüm yükü tek güne yığılır. İsteğe bağlı üçüncü parametre
-- `p_yayilim_gun` bitişi kullanıcıya göre 0…p_yayilim_gun gün ileri kaydırır
-- (deterministik: `hashtext(user_id)`), bitişler bir pencereye yayılır.
-- Kimse 90 günden AZ almaz; en çok 90 + p_yayilim_gun.
--
-- ## Eski sürümler / DB
-- Yalnız fonksiyon tanımı değişir; yeni parametre varsayılan 0 = bugünkü
-- davranış birebir (`erken_kullanici_hediyesi_ver('…', 90)` çağrısı aynı
-- sonucu verir). Tablo/kolon/satır eklenmez. Önerilen açılış çağrısı
-- (/mnt/project-files/paywall/hediye_ve_magaza_metinleri_2026-10-19.md):
--   select public.erken_kullanici_hediyesi_ver('<kesim>', 90, 14);
--
-- Eski iki parametreli imza kalır (tek fonksiyon, varsayılanlı parametre).

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
           -- Kullanıcıya göre sabit, 0…p_yayilim_gun gün (yayılım 0 = kaydırma yok).
           + make_interval(days => mod(abs(hashtext(u.id::text)), p_yayilim_gun + 1))
    from auth.users u
   where u.created_at < p_kesim
     and u.deleted_at is null
  on conflict (user_id, kaynak) do nothing;
  get diagnostics v_sayi = row_count;
  return v_sayi;
end;
$$;

-- Eski imzanın GRANT'ı yeni imzaya taşınır (parametre listesi değişti).
drop function if exists public.erken_kullanici_hediyesi_ver(timestamptz, integer);
revoke all on function public.erken_kullanici_hediyesi_ver(timestamptz, integer, integer)
  from public, anon, authenticated;
grant execute on function public.erken_kullanici_hediyesi_ver(timestamptz, integer, integer)
  to service_role;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'erken_kullanici_hediyesi_ver'
       and p.pronargs = 3) then
    raise exception '0160: erken_kullanici_hediyesi_ver(3 parametre) yok';
  end if;
  if has_function_privilege('authenticated',
       'public.erken_kullanici_hediyesi_ver(timestamptz, integer, integer)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.erken_kullanici_hediyesi_ver(timestamptz, integer, integer)', 'EXECUTE') then
    raise exception '0160: erken_kullanici_hediyesi_ver istemciden cagrilabilir olmamali';
  end if;
  raise notice '0160 tamam: hediye bitisi yayilabilir (p_yayilim_gun).';
end $$;
