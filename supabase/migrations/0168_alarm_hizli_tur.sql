-- 0168 — altın, döviz ve kripto alarmları 5 dakikada (2026-10-24)
--
-- ## İstek
-- Ar-ge fikri 2026-10-24 §2, rapor 13:15 §1 (YAP). `check-price-alerts`
-- yarım saatte bir koşuyordu (0046 `*/30 5-18`), oysa altın/döviz 5
-- dakikada (`yurt-ici-kotasyon`, 0101), kripto 2 dakikada (`kripto-fiyat`)
-- tazeleniyor. 10:02'de hedefe değen gram altın alarmı 10:30'da geliyordu;
-- arada fiyat geri dönebiliyordu ("alarm geç geldi / hiç gelmedi").
--
-- ## Karar: İKİ iş, tek fonksiyon
-- * `check-price-alerts` OLDUĞU GİBİ kalır: `*/30 5-18`, gövde `{}`, her tür.
--   Dokunulmuyor ki eski davranış (ve gövdesiz elle çağrı) birebir sürsün.
-- * Yeni `check-price-alerts-hizli`: `5-25/5,35-55/5 5-18` — yarım saatlerin
--   ARASINDAKİ 5 dakikalar, gövde `{"turler":["altin","doviz","kripto"]}`.
--   Dakikalar ayrık: :00/:30'da yalnız eski iş koşar, iki tur aynı alarmı
--   aynı anda değerlendirmez. (Yine de çakışırsa fonksiyon damgayı atamayan
--   turda push göndermez — 0168 ile `alarmiSondur`.)
-- * Neden tek */5 iş + fonksiyonda "hisse/fon yalnız :00/:30" filtresi DEĞİL:
--   o, kararı fonksiyonun saat okumasına bağlardı (pg_net gecikmesi :00'ı
--   :01 yapınca hisse alarmı o turu kaçırır) ve eski işin anlamını
--   değiştirirdi. İki işte ritim cron tablosunda okunur, fonksiyon saat
--   bilmez.
-- * BIST ve fon 30 dakikada kalır: kaynakları gecikmeli (Yahoo) ya da günlük
--   (TEFAS NAV); 5 dakikada sormak boşa istek. Emtia/eurobond da öyle.
--
-- ## Pencere
-- Aynı: TR 08:00–21:30. Cron ifadesi "18'de yalnız :30'a kadar" diyemediği
-- için 18:35–18:55 UTC turları sarmalayıcıda (`trigger_...hizli`) erken
-- döner; son hızlı tur 18:25 UTC = TR 21:25, son tur yine eski işin 18:30'u.
-- Gece bildirimi rahatsız eder; kripto için gece ayrı karar, ayrı bayrak.
--
-- ## İki sunucu
-- Yeni iş `check-price-alerts`'in `active` durumunu ALIR: Frankfurt'ta
-- (geçişe kadar tüm cron kapalı) kapalı, Tokyo'da açık doğar. Var olan işin
-- `active` bayrağına dokunulmaz. Sarmalayıcı 0076 deseni: URL ve başlıklar
-- `edge_function_url` / `cron_headers` (Vault), secret aynı
-- `price_alerts_cron_secret`.
--
-- ## Eski sürümler
-- İstemci değişmez; `price_alerts` şeması aynı. Yalnız EKLER (yeni iş + yeni
-- fonksiyon). Geri almak: `select cron.unschedule('check-price-alerts-hizli')`.
--
-- ## cron.job_run_details
-- Yeni iş günde 140 satır ekler (~1.900'e karşı, %7). 0112 saklaması (7 gün,
-- günlük 03:35 UTC) iş adından bağımsız; ek tedbir gerekmez.
--
-- Tablo yaratılmıyor; GRANT gerekmez (0161 kuralı tablo/görünüm içindir).

create or replace function public.trigger_check_price_alerts_hizli()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  -- Pencere sonu TR 21:30 (= 18:30 UTC); cron saati UTC (pg_cron varsayılanı).
  if (now() at time zone 'utc')::time > time '18:30' then
    return;
  end if;
  perform net.http_post(
    url := public.edge_function_url('check-price-alerts'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object(
      'source', 'cron',
      'turler', jsonb_build_array('altin', 'doviz', 'kripto')
    ),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_check_price_alerts_hizli() from public, anon, authenticated;

comment on function public.trigger_check_price_alerts_hizli() is
  'Altin/doviz/kripto alarmlari 5 dk (yarim saatlerin arasi); 18:30 UTC sonrasi '
  'erken doner. Hisse/fon 30 dk isinde (check-price-alerts) kalir (0168).';

select cron.unschedule(jobid) from cron.job where jobname = 'check-price-alerts-hizli';
select cron.schedule('check-price-alerts-hizli', '5-25/5,35-55/5 5-18 * * *',
  $$select public.trigger_check_price_alerts_hizli()$$);

-- Yeni iş, alarm işinin açık/kapalı durumunu birebir alır (iki sunucu farkı
-- yalnız `active` bayrağında; bkz. CLAUDE.md "İki sunucu birebir").
do $$
declare
  v_aktif boolean;
begin
  select j.active into v_aktif from cron.job j where j.jobname = 'check-price-alerts';
  if v_aktif is not null and not v_aktif then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job
      where jobname = 'check-price-alerts-hizli';
    raise notice '0168: check-price-alerts kapali — hizli is de kapali kuruldu.';
  end if;
end $$;

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from cron.job
                  where jobname = 'check-price-alerts-hizli'
                    and schedule = '5-25/5,35-55/5 5-18 * * *') then
    raise exception '0168: check-price-alerts-hizli 5-25/5,35-55/5 5-18 * * * ile kurulmali';
  end if;
  -- Eski işe bu migration dokunmaz; ritmi beklenenden farklıysa dağıtımı
  -- durdurmak yerine uyarır (hızlı turun dakikaları :00/:30'u dışarıda
  -- bırakacak biçimde seçildi, eski iş başka ritimdeyse elle bakılmalı).
  if not exists (select 1 from cron.job
                  where jobname = 'check-price-alerts'
                    and schedule = '*/30 5-18 * * *') then
    raise warning '0168: check-price-alerts beklenen */30 5-18 * * * ritminde degil — kontrol et';
  end if;
  if (select count(distinct active) from cron.job
       where jobname in ('check-price-alerts', 'check-price-alerts-hizli')) > 1 then
    raise exception '0168: iki alarm isinin active durumu ayni olmali';
  end if;
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'trigger_check_price_alerts_hizli'
      and p.prosecdef
      and p.proconfig @> array['search_path=public, vault, net']
  ) then
    raise exception '0168: trigger_check_price_alerts_hizli SECURITY DEFINER + search_path olmali';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_check_price_alerts_hizli()', 'execute')
     or has_function_privilege('anon', 'public.trigger_check_price_alerts_hizli()', 'execute') then
    raise exception '0168: trigger_check_price_alerts_hizli istemciye acik';
  end if;
  raise notice '0168 tamam: altin/doviz/kripto alarmlari 5 dk, digerleri 30 dk.';
end $$;
