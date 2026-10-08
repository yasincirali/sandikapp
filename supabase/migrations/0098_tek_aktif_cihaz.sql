-- ============================================================
-- 0098 — Tek aktif cihaz + kayıtlı cihazlar + yeni cihazda e-posta kodu
-- (2026-10-03)
--
-- ## Kullanıcı kararı (2026-10-03)
-- "Aynı hesap aynı anda 2 cihazda açılamamalı, kayıtlı cihaz listesi
-- olmalı, onu da mail OTP ile kontrol ettirmeliyiz. Kayıtlı cihaz
-- listesini görüp oradan silme de yapabilmeli."
--
-- ## Model
--   * `kayitli_cihazlar` — e-posta koduyla doğrulanmış (güvenilen) cihazlar.
--     Kayıtlı cihazda girişte kod SORULMAZ; kayıtlı olmayan cihazda sorulur.
--   * `aktif_cihaz` — hesap başına TEK satır: şu an açık olan cihaz.
--     Yeni cihaz oturumu alınca satır değişir; eski cihaz Realtime'dan
--     (ya da öne dönüşte) bunu görür ve kendini kapatır. İstemci ayrıca
--     `signOut(scope: others)` ile diğer oturumların refresh token'larını
--     iptal eder — eski cihaz en geç access token ömrü dolunca (≤1 sa)
--     sunucuya da erişemez.
--
-- ## Yerinden edilen cihaz kendiliğinden geri alamaz
-- Atılan cihazın elindeki access token ≤1 saat daha geçerlidir. Soğuk
-- açılışta `oturum_al` çağırıp oturumu geri kapmasın diye kural SUNUCUDA:
-- çağıranın son kimlik doğrulama anı (JWT `amr[].timestamp` en büyüğü —
-- token tazelenince DEĞİŞMEZ, yalnız şifre/sosyal/kod ile girişte değişir)
-- aktif satırın değişim anından ESKİYSE `yerinden_edildi` hatası döner.
-- Yani oturumu yeniden almak için yeniden giriş şart.
--
-- ## Yeni cihaz = e-posta kodu (sunucu kanıtı)
-- `cihaz_kaydet` yalnızca JWT'de SON 15 DAKİKADA e-posta sahipliği kanıtı
-- varsa yazar: `amr` içinde `otp` / `magiclink` (giriş kodu), `email/signup`
-- (kayıt kodu) ya da `recovery` (şifre sıfırlama kodu). İstemci bu kontrolü
-- atlayamaz — kayıt çağrısı kodsuz oturumla reddedilir.
--
-- ⚠️ SINIR (bilinçli): Yeni cihaz kapısı İSTEMCİDEDİR. Şifreyi bilen biri
-- uygulama yerine ham API ile veri OKUYABİLİR — JWT cihaz kimliği
-- taşımadığı için RLS "kayıtlı cihaz mı" soramaz. Kapı hesabın uygulamada
-- paylaşılmasını ve sessiz ikinci oturumu önler; şifrenin yerine geçmez.
-- (Gerçek ikinci faktör: Supabase MFA aal2 — e-postayı desteklemiyor.)
--
-- ## İlk cihaz (geçiş)
-- Hiç kayıtlı cihazı olmayan hesabın ilk cihazı kodsuz kaydedilir (TOFU).
-- Aksi halde güncellemeyi alan HER mevcut kullanıcıya aynı anda e-posta
-- kodu sorulurdu. Bedel: geçiş penceresinde şifreyi bilen biri ilk cihaz
-- olabilir — gerçek sahip cihaz listesinde görür ve siler.
--
-- ## Muafiyet
-- `cihaz_kontrol_muafiyeti` — mağaza inceleme hesabı gibi e-postası
-- okunamayan, birden çok cihazda aynı anda açılan hesaplar. Yalnız
-- service_role yazar (SQL ile, iki sunucuda birden).
-- ============================================================

-- ── 1) Tablolar ─────────────────────────────────────────────────────────────
create table if not exists public.kayitli_cihazlar (
  user_id     uuid not null references auth.users(id) on delete cascade,
  -- İstemcinin ürettiği rastgele kimlik (16 bayt hex). Donanım kimliği
  -- DEĞİL; uygulama silinince kaybolur ve cihaz yeniden kod ister.
  cihaz_id    text not null check (cihaz_id ~ '^[0-9a-f]{32}$'),
  ad          text not null check (length(ad) between 1 and 80),
  platform    text not null check (platform in ('android', 'ios', 'unknown')),
  ilk_kayit   timestamptz not null default now(),
  son_gorulme timestamptz not null default now(),
  primary key (user_id, cihaz_id)
);

comment on table public.kayitli_cihazlar is
  'E-posta koduyla dogrulanmis cihazlar (0098). Yalniz cihaz_kaydet / '
  'cihaz_sil RPC yazar; kullanici yalniz kendi satirlarini okur.';

create table if not exists public.aktif_cihaz (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  cihaz_id text not null check (cihaz_id ~ '^[0-9a-f]{32}$'),
  degisim  timestamptz not null default now()
);

comment on table public.aktif_cihaz is
  'Hesabin su an acik oldugu TEK cihaz (0098). Yalniz oturum_al yazar. '
  'Realtime yayininda: eski cihaz degisimi aninda gorup kapanir.';

create table if not exists public.cihaz_kontrol_muafiyeti (
  user_id uuid primary key references auth.users(id) on delete cascade,
  neden   text not null check (length(neden) between 1 and 200),
  eklendi timestamptz not null default now()
);

comment on table public.cihaz_kontrol_muafiyeti is
  'Tek cihaz / yeni cihaz kodu kuralindan muaf hesaplar (0098): magaza '
  'inceleme hesabi vb. Yalniz service_role yazar.';

-- ── 2) RLS + GRANT (ayrı katmanlar — 0036/0042 dersi) ──────────────────────
alter table public.kayitli_cihazlar enable row level security;
alter table public.kayitli_cihazlar force row level security;
alter table public.aktif_cihaz enable row level security;
alter table public.aktif_cihaz force row level security;
alter table public.cihaz_kontrol_muafiyeti enable row level security;
alter table public.cihaz_kontrol_muafiyeti force row level security;

drop policy if exists kayitli_cihazlar_own_select on public.kayitli_cihazlar;
create policy kayitli_cihazlar_own_select
  on public.kayitli_cihazlar
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- Realtime `postgres_changes` RLS'e tabidir: eski cihazın değişimi
-- görebilmesi için kendi satırını SELECT edebilmesi şart.
drop policy if exists aktif_cihaz_own_select on public.aktif_cihaz;
create policy aktif_cihaz_own_select
  on public.aktif_cihaz
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- Muafiyet tablosunda istemciye politika YOK: kullanıcı muaf olup
-- olmadığını yalnız `cihaz_durumu` yanıtından öğrenir.

-- Yazma yalnız RPC üzerinden: kayıt e-posta kanıtı ister, oturum alma
-- yerinden edilme kuralını uygular; doğrudan INSERT/UPDATE ikisini atlardı.
revoke all on table public.kayitli_cihazlar from public, anon, authenticated;
revoke all on table public.aktif_cihaz from public, anon, authenticated;
revoke all on table public.cihaz_kontrol_muafiyeti from public, anon, authenticated;
grant select on table public.kayitli_cihazlar to authenticated;
grant select on table public.aktif_cihaz to authenticated;
grant select, insert, update, delete on table public.kayitli_cihazlar to service_role;
grant select, insert, update, delete on table public.aktif_cihaz to service_role;
grant select, insert, update, delete on table public.cihaz_kontrol_muafiyeti to service_role;

-- ── 3) Yardımcı: e-posta sahipliği kanıtı / son giriş anı ──────────────────
-- `amr` GoTrue'nun kimlik doğrulama yöntemleri listesidir:
-- [{"method":"password","timestamp":1696...}, ...]. Token tazelenince
-- korunur; yeni giriş/doğrulama yeni öğe ekler.
create or replace function public._amr_son_an(p_yontemler text[] default null)
returns timestamptz
language sql
stable
set search_path = public
as $$
  select to_timestamp(max((e ->> 'timestamp')::bigint))
    from jsonb_array_elements(
           case when jsonb_typeof(auth.jwt() -> 'amr') = 'array'
                then auth.jwt() -> 'amr' else '[]'::jsonb end) e
   where (e ->> 'timestamp') ~ '^\d+$'
     and (p_yontemler is null or (e ->> 'method') = any (p_yontemler));
$$;
revoke all on function public._amr_son_an(text[]) from public, anon, authenticated;

-- ── 4) RPC: cihaz_durumu ────────────────────────────────────────────────────
-- 'muaf' | 'kayitli' | 'ilk' (hiç kayıtlı cihaz yok) | 'yeni'
create or replace function public.cihaz_durumu(p_cihaz_id text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'cihaz_durumu: oturum yok' using errcode = '42501';
  end if;
  if exists (select 1 from public.cihaz_kontrol_muafiyeti where user_id = v_uid) then
    return 'muaf';
  end if;
  if exists (select 1 from public.kayitli_cihazlar
              where user_id = v_uid and cihaz_id = p_cihaz_id) then
    return 'kayitli';
  end if;
  if not exists (select 1 from public.kayitli_cihazlar where user_id = v_uid) then
    return 'ilk';
  end if;
  return 'yeni';
end;
$$;

-- ── 5) RPC: cihaz_kaydet ────────────────────────────────────────────────────
create or replace function public.cihaz_kaydet(
  p_cihaz_id text,
  p_ad       text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_ad   text := left(btrim(coalesce(p_ad, '')), 80);
begin
  if v_uid is null then
    raise exception 'cihaz_kaydet: oturum yok' using errcode = '42501';
  end if;
  if p_cihaz_id is null or p_cihaz_id !~ '^[0-9a-f]{32}$' then
    raise exception 'cihaz_kaydet: gecersiz cihaz' using errcode = '22023';
  end if;
  if p_platform is null or p_platform not in ('android', 'ios', 'unknown') then
    raise exception 'cihaz_kaydet: gecersiz platform' using errcode = '22023';
  end if;
  if v_ad = '' then v_ad := 'Cihaz'; end if;

  -- Zaten kayıtlıysa yalnız ad/görülme tazelenir — kanıt gerekmez.
  if not exists (select 1 from public.kayitli_cihazlar
                  where user_id = v_uid and cihaz_id = p_cihaz_id)
     -- İlk cihaz (TOFU) kanıtsız; sonrakiler son 15 dk'da e-posta kanıtı ister.
     and exists (select 1 from public.kayitli_cihazlar where user_id = v_uid)
     and coalesce(public._amr_son_an(
           array['otp', 'magiclink', 'email/signup', 'recovery']),
           '-infinity'::timestamptz) < now() - interval '15 minutes'
  then
    raise exception 'otp_gerekli' using errcode = '42501';
  end if;

  -- Kötüye kullanım tavanı: hesap başına 20 cihaz. Eskiyi silmeden yenisi
  -- eklenemez (liste ekranından silinir).
  if (select count(*) from public.kayitli_cihazlar where user_id = v_uid) >= 20
     and not exists (select 1 from public.kayitli_cihazlar
                      where user_id = v_uid and cihaz_id = p_cihaz_id) then
    raise exception 'cihaz_siniri' using errcode = '54000';
  end if;

  insert into public.kayitli_cihazlar (user_id, cihaz_id, ad, platform)
  values (v_uid, p_cihaz_id, v_ad, p_platform)
  on conflict (user_id, cihaz_id) do update
    set ad = excluded.ad,
        platform = excluded.platform,
        son_gorulme = now();
end;
$$;

-- ── 6) RPC: oturum_al ───────────────────────────────────────────────────────
-- Çağıran cihazı hesabın TEK aktif cihazı yapar. Diğer cihazların push
-- token'larını da düşürür: atılan cihaz kapalıyken (Realtime'ı duymadan)
-- hesabın sinyal/brifing push'larını almaya devam etmesin.
create or replace function public.oturum_al(
  p_cihaz_id      text,
  p_push_cihaz_id text default null,
  p_push_token    text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_aktif public.aktif_cihaz%rowtype;
  v_giris timestamptz := public._amr_son_an(null);
begin
  if v_uid is null then
    raise exception 'oturum_al: oturum yok' using errcode = '42501';
  end if;
  if p_cihaz_id is null or p_cihaz_id !~ '^[0-9a-f]{32}$' then
    raise exception 'oturum_al: gecersiz cihaz' using errcode = '22023';
  end if;
  -- Muaf hesapta tek cihaz kuralı yok.
  if exists (select 1 from public.cihaz_kontrol_muafiyeti where user_id = v_uid) then
    return;
  end if;
  if not exists (select 1 from public.kayitli_cihazlar
                  where user_id = v_uid and cihaz_id = p_cihaz_id) then
    raise exception 'otp_gerekli' using errcode = '42501';
  end if;

  select * into v_aktif from public.aktif_cihaz where user_id = v_uid for update;
  -- Yerinden edilme: başka cihaz bu oturumun girişinden SONRA aktif olduysa
  -- bu oturum eskidir — geri almak için yeniden giriş gerekir. `amr`
  -- okunamazsa (beklenmez) kural uygulanmaz; kapı yine kayıtlı cihazdır.
  if found and v_aktif.cihaz_id <> p_cihaz_id
     and v_giris is not null and v_giris < v_aktif.degisim then
    raise exception 'yerinden_edildi' using errcode = '42501';
  end if;

  insert into public.aktif_cihaz (user_id, cihaz_id, degisim)
  values (v_uid, p_cihaz_id, now())
  on conflict (user_id) do update
    set cihaz_id = excluded.cihaz_id,
        -- Aynı cihaz her açılışta çağırır: damga yalnız cihaz DEĞİŞİNCE
        -- ilerler, yoksa kendi eski oturumunu "yerinden edilmiş" sayardı.
        degisim = case when aktif_cihaz.cihaz_id = excluded.cihaz_id
                       then aktif_cihaz.degisim else now() end;

  update public.kayitli_cihazlar
     set son_gorulme = now()
   where user_id = v_uid and cihaz_id = p_cihaz_id;

  if p_push_cihaz_id is not null and p_push_cihaz_id <> '' then
    delete from public.user_push_tokens
     where user_id = v_uid
       and device_id is distinct from p_push_cihaz_id
       and token <> coalesce(p_push_token, '');
  end if;
end;
$$;

-- ── 7) RPC: cihaz_sil ───────────────────────────────────────────────────────
-- Aktif cihaz (yani çağıranın kendisi) silinemez: kendini listeden atan
-- cihaz bir sonraki açılışta kendi oturumunu kod sormadan sürdürürdü.
create or replace function public.cihaz_sil(p_cihaz_id text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_sayi  integer;
begin
  if v_uid is null then
    raise exception 'cihaz_sil: oturum yok' using errcode = '42501';
  end if;
  if exists (select 1 from public.aktif_cihaz
              where user_id = v_uid and cihaz_id = p_cihaz_id) then
    raise exception 'aktif_cihaz_silinemez' using errcode = '42501';
  end if;
  delete from public.kayitli_cihazlar
   where user_id = v_uid and cihaz_id = p_cihaz_id;
  get diagnostics v_sayi = row_count;
  return v_sayi;
end;
$$;

-- ── 8) Fonksiyon GRANT'ları — yalnız oturumlu ───────────────────────────────
revoke all on function public.cihaz_durumu(text) from public, anon;
revoke all on function public.cihaz_kaydet(text, text, text) from public, anon;
revoke all on function public.oturum_al(text, text, text) from public, anon;
revoke all on function public.cihaz_sil(text) from public, anon;
grant execute on function public.cihaz_durumu(text) to authenticated;
grant execute on function public.cihaz_kaydet(text, text, text) to authenticated;
grant execute on function public.oturum_al(text, text, text) to authenticated;
grant execute on function public.cihaz_sil(text) to authenticated;
-- `_amr_son_an` SECURITY INVOKER ve yalnız yukarıdaki definer fonksiyonların
-- içinden çağrılır (sahipleri postgres). Doğrudan çağrılmasına gerek yok.

-- ── 9) Realtime — eski cihaz değişimi anında duysun ─────────────────────────
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public' and tablename = 'aktif_cihaz')
  then
    execute 'alter publication supabase_realtime add table public.aktif_cihaz';
  end if;
end $$;

-- ── 10) Doğrulama — sessizce eksik kalmasın ────────────────────────────────
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.cihaz_durumu(text)',
    'public.cihaz_kaydet(text, text, text)',
    'public.oturum_al(text, text, text)',
    'public.cihaz_sil(text)'
  ] loop
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception '%: authenticated EXECUTE yetkisi yok', f;
    end if;
    if has_function_privilege('anon', f, 'execute') then
      raise exception '%: anon EXECUTE yetkisi olmamali', f;
    end if;
  end loop;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('cihaz_durumu', 'cihaz_kaydet', 'oturum_al', 'cihaz_sil')
       and not p.prosecdef
  ) then
    raise exception '0098: cihaz RPC''lerinden biri security definer degil';
  end if;
  if has_table_privilege('authenticated', 'public.kayitli_cihazlar', 'insert')
     or has_table_privilege('authenticated', 'public.aktif_cihaz', 'update')
     or has_table_privilege('authenticated', 'public.cihaz_kontrol_muafiyeti', 'select') then
    raise exception '0098: istemci tablolara dogrudan yazabiliyor/muafiyeti okuyabiliyor';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.aktif_cihaz'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.kayitli_cihazlar'::regclass) then
    raise exception '0098: RLS kapali';
  end if;
end $$;
