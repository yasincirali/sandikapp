-- `signal_state` üzerinde `authenticated` rolüne SELECT + DELETE yetkisi.
--
-- ## Neden 0035 yetmedi
-- 0035 RLS politikalarını ekledi ama tablo düzeyinde GRANT yoktu. Postgres
-- yetkiyi İKİ katmanda kontrol eder:
--
--   1. GRANT  — rol bu tabloya dokunabilir mi?
--   2. RLS    — dokunabiliyorsa HANGİ satırlara?
--
-- Birinci katman geçilemezse ikinci hiç değerlendirilmez. Politikalar
-- doğruydu ama istemci şu hatayı alıyordu:
--   permission denied for table signal_state (42501)
--
-- Tablo baştan yalnızca `service_role`'a açık kurulmuştu (`analyze-signals`
-- edge function'ı için) — kardeş tablo `signal_notifications` ise
-- `authenticated`'a tam yetkiliydi. Bu asimetri fark edilmemişti çünkü
-- istemci `signal_state`'e hiç dokunmuyordu.
--
-- ## Neden yalnızca SELECT + DELETE
-- 0035'teki gerekçenin aynısı: `signal_state` bir OTORİTE kaydıdır ("bu
-- varlık için en son şu sinyal gönderildi"). INSERT/UPDATE verilirse
-- uygulama hiç gönderilmemiş bir sinyali "gönderilmiş" işaretleyebilir ve o
-- varlığın push'u kalıcı olarak susar. Silme güvenlidir: en kötü ihtimalle
-- sinyaller bir kez daha gönderilir.
--
-- GRANT satır bazlı değildir; "kendi satırları" kısıtını 0035'teki RLS
-- politikaları sağlar. İkisi birlikte gerekir.

grant select, delete on table signal_state to authenticated;

-- Doğrulama: hem GRANT hem RLS yerinde mi?
--
-- Bu ikisinden biri eksikken tablo "çalışıyor" görünür ve yalnızca istemci
-- işlemleri patlar — tam olarak bu hatanın kaynağı buydu.
do $$
declare
  grant_sayisi int;
  policy_sayisi int;
begin
  select count(*) into grant_sayisi
  from information_schema.role_table_grants
  where table_name = 'signal_state'
    and grantee = 'authenticated'
    and privilege_type in ('SELECT', 'DELETE');

  select count(*) into policy_sayisi
  from pg_policies
  where tablename = 'signal_state'
    and policyname in ('signal_state_own_select', 'signal_state_own_delete');

  if grant_sayisi <> 2 then
    raise exception
      'signal_state GRANT eksik: % / 2 (SELECT+DELETE)', grant_sayisi;
  end if;

  if policy_sayisi <> 2 then
    raise exception
      'signal_state RLS politikasi eksik: % / 2 — 0035 uygulandi mi?',
      policy_sayisi;
  end if;
end $$;
