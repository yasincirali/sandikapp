-- ============================================================
-- 0069 — Push token'ı cihazı elinde tutan hesap devralır (2026-09-21)
--
-- ## Arıza
-- `user_push_tokens` birincil anahtarı `token`; FCM token'ı CİHAZA bağlıdır,
-- hesaba değil. Aynı telefonda A çıkıp B girince B'nin `upsert`'i
-- `on conflict (token) do update` yoluna düşer ve UPDATE politikasının
-- USING ifadesi MEVCUT satıra (A'nın satırı) bakar → `42501 new row violates
-- row-level security policy (USING expression)`. Canlıda ölçüldü
-- (db_logs 664946, iOS, 2026-09-21 10:27 UTC).
--
-- Sonucu iki yönlü:
--   · B'nin token'ı hiç yazılmaz → B'ye push GİTMEZ ("pushlar çalışmıyor").
--   · A'nın satırı durur → A'nın brifingi/sinyali B'nin elindeki telefona
--     düşer: B, A'nın portföy haberini görür (gizlilik).
--
-- İstemcideki çıkış temizliği (`RemotePushService.stop` → delete) bunu
-- ÖNLEYEMEZ: yalnızca bellekteki `_currentToken` doluysa çalışır; upsert
-- zaman aşımına uğradıysa (db_logs 653096) ya da oturum istemci dışında
-- düştüyse (süresi dolan refresh token → SIGNED_OUT → silme isteği
-- oturumsuz gider, RLS sessizce 0 satır) satır kalır. Kalıcı çözüm sunucuda.
--
-- ## Karar
-- Token'ı sunan hesap onun sahibidir: token cihaz dışında bilinmez
-- (~160 karakter rastgele), sunabilmek cihazı elinde tutmak demektir.
-- Bu, mevcut modelle aynı güven varsayımıdır (kullanıcı zaten kendi adına
-- istediği token'ı yazabiliyordu); yeni olan tek şey başka hesabın
-- satırının düşmesi. `security definer` RLS'i geçer, bu yüzden fonksiyon
-- yalnızca ÜÇ şey yapar ve hepsi çağıranın kendi cihazına dokunur:
--   1) aynı token başka hesaptaysa o satır silinir (devralma),
--   2) aynı hesabın aynı cihazdaki bayat token'ları silinir
--      (istemcide `upsertPushToken` öncesi yapılan temizlik buraya taşındı;
--      `user_push_tokens_user_device_uidx` kısıtı bu sayede takılmaz),
--   3) satır çağıranın adına yazılır.
-- Fonksiyon `auth.uid()` dışında hiçbir user_id kabul etmez.
-- ============================================================

create or replace function public.claim_push_token(
  p_token     text,
  p_platform  text,
  p_device_id text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_devralinan integer := 0;
begin
  if v_uid is null then
    raise exception 'claim_push_token: oturum yok' using errcode = '42501';
  end if;
  -- FCM token'ları uzun ve rastgeledir; kısa/boş değer istemci hatasıdır.
  if p_token is null or length(p_token) < 20 or length(p_token) > 4096 then
    raise exception 'claim_push_token: gecersiz token' using errcode = '22023';
  end if;
  if p_platform is null or p_platform not in ('android', 'ios', 'unknown') then
    raise exception 'claim_push_token: gecersiz platform' using errcode = '22023';
  end if;

  -- 1) Devralma: token başka hesaba kayıtlıysa o satır düşer.
  delete from public.user_push_tokens
   where token = p_token and user_id <> v_uid;
  get diagnostics v_devralinan = row_count;

  -- 2) Aynı cihazın bayat token'ları (rotasyon sonrası kalanlar).
  if p_device_id is not null and p_device_id <> '' then
    delete from public.user_push_tokens
     where user_id = v_uid and device_id = p_device_id and token <> p_token;
  end if;

  -- 3) Çağıranın adına yaz. Cihaz kimliği gelmediyse eskisi korunur.
  insert into public.user_push_tokens (token, user_id, platform, device_id, updated_at)
  values (p_token, v_uid, p_platform, nullif(p_device_id, ''), now())
  on conflict (token) do update
    set user_id    = excluded.user_id,
        platform   = excluded.platform,
        device_id  = coalesce(excluded.device_id, user_push_tokens.device_id),
        updated_at = now();

  return v_devralinan;
end;
$$;

comment on function public.claim_push_token(text, text, text) is
  'Push token''ini cagiran hesaba yazar; token baska hesaptaysa devralir '
  '(token cihaza baglidir, cihazi elinde tutan sahibidir). Ayni cihazin '
  'bayat token''larini temizler. Donus: baska hesaptan devralinan satir sayisi.';

-- GRANT: RLS'ten bağımsız, ayrı katman (0036/0042 dersi). Yalnızca oturumlu.
revoke all on function public.claim_push_token(text, text, text) from public, anon;
grant execute on function public.claim_push_token(text, text, text) to authenticated;

-- ── Aynı kural tabloda: eski istemci de düzelsin ───────────────────────────
-- Yayındaki uygulama (RPC'den önceki build) `user_push_tokens`'a doğrudan
-- upsert eder. `on conflict do update` çakışmayı bulmadan ÖNCE `before insert`
-- tetikleyicileri koşar; tetikleyici başka hesabın aynı token satırını
-- düşürürse çakışma kalmaz, RLS'in USING ifadesi hiç değerlendirilmez ve
-- düz insert geçer. Böylece 0069 canlıya alındığı an eski build'ler de
-- token yazabilir; RPC'yi bekleyen tek şey bayat cihaz temizliği.
-- Tetikleyici fonksiyonu SECURITY DEFINER: silme RLS'in altında olsaydı
-- (auth.uid() ≠ satır sahibi) sessizce 0 satır etkilerdi — 0069'un tam da
-- çözdüğü sorun.
create or replace function public.push_token_devral()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.user_push_tokens
   where token = new.token and user_id <> new.user_id;
  return new;
end;
$$;
revoke all on function public.push_token_devral() from public, anon, authenticated;

drop trigger if exists user_push_tokens_devral on public.user_push_tokens;
create trigger user_push_tokens_devral
  before insert on public.user_push_tokens
  for each row execute function public.push_token_devral();

-- ── Doğrulama — sessizce eksik kalmasın ────────────────────────────────────
do $$
begin
  if not has_function_privilege('authenticated', 'public.claim_push_token(text, text, text)', 'execute') then
    raise exception 'claim_push_token: authenticated EXECUTE yetkisi yok';
  end if;
  if has_function_privilege('anon', 'public.claim_push_token(text, text, text)', 'execute') then
    raise exception 'claim_push_token: anon EXECUTE yetkisi olmamali';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'claim_push_token' and p.prosecdef
  ) then
    raise exception 'claim_push_token: security definer degil';
  end if;
  if not exists (
    select 1 from pg_trigger where tgname = 'user_push_tokens_devral' and not tgisinternal
  ) then
    raise exception 'user_push_tokens_devral tetikleyicisi yok';
  end if;
  if has_function_privilege('authenticated', 'public.push_token_devral()', 'execute') then
    raise exception 'push_token_devral: dogrudan cagrilamamali';
  end if;
end $$;
