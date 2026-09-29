-- 0087 — Takvim kancasına yeni an: "yıl sonu özetin hazır" (2026-09-29)
--
-- ## Neden
-- Yıllık "sandık Özeti" kodu var (`RecapService.isYearlyWindow`: 26 Aralık –
-- 10 Ocak) ama kimse haber vermiyordu: özet Profil'deki bir afişte, yılda
-- 16 gün görünür ve kullanıcı o sayfaya o günlerde uğramazsa hiç görmez.
-- Yıl sonu, TÜFE günü gibi ülkenin ZATEN baktığı bir an (herkes "yılım
-- nasıl geçti" diye bakıyor); `calendar-nudge` deseninin ikinci anı olur
-- (docs/BUYUME_OZELLIKLERI_TEKNIK_PLAN_2026_09.md §F9).
--
-- ## Neden AYRI tetikleyici
-- `trigger_calendar_nudge()` imzası ve gövdesi (TÜFE günü, `'{}'` gövde)
-- DEĞİŞMEZ — var olan RPC'ye dokunulmaz (plan §2). Yeni fonksiyon aynı
-- edge function'a `{"occasion":"year_end_recap"}` gövdesiyle gider; fonksiyon
-- anı gövdeden seçer, gövdesiz çağrı eskisi gibi TÜFE günüdür.
--
-- ## Zamanlama
-- 26 Aralık 20:00 TR = 17:00 UTC (TR sabit UTC+3). Pencerenin İLK günü:
-- afiş o gün açılıyor; akşam saati "günün işi bitti, yıla bakayım" anı.
-- Tek atış — fonksiyon `calendar_nudge_log(occasion='year_end_recap',
-- period='<yıl>-12-01')` defterine yazar, elle ikinci tetik ikinci
-- bildirim göndermez. Fonksiyon ayrıca TR tarihinin pencere içinde
-- olduğunu kendisi denetler (elle yanlış günde tetiklenirse susar).

-- ── 1) Tetikleyici (0054/0076 deseni) ───────────────────────────────────────
-- Adres Vault `project_url` (0076), secret `x-cron-secret`'ta
-- (`cron_headers`; Authorization gateway'e ait — 0054). TÜFE günüyle AYNI
-- secret: aynı fonksiyon, aynı env (`CALENDAR_NUDGE_CRON_SECRET`).
create or replace function public.trigger_calendar_nudge_yil_sonu()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('calendar-nudge'),
    headers := public.cron_headers('calendar_nudge_cron_secret'),
    body := jsonb_build_object('occasion', 'year_end_recap'),
    -- Herkese tek push + çan kaydı; TÜFE günüyle aynı bütçe (0054).
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_calendar_nudge_yil_sonu() from public, anon, authenticated;

-- ── 2) Zamanlama ────────────────────────────────────────────────────────────
select cron.unschedule(jobid) from cron.job where jobname = 'calendar-nudge-year-end';
select cron.schedule('calendar-nudge-year-end', '0 17 26 12 *',
  $$select public.trigger_calendar_nudge_yil_sonu()$$);

-- İki sunucu birebir (CLAUDE.md, 2026-09-28): tek bilinçli fark cron
-- `active`. Frankfurt'ta geçişe kadar TÜM işler kapalı; `cron.schedule` yeni
-- işi AÇIK doğurur ve Aralık'ta iki sunucu aynı kişiye iki push atardı.
-- Proje ref'i sabit yazılmaz — 0086 ile aynı kural: başka iş var ve hiçbiri
-- açık değilse proje "cron kapalı" kipindedir, yeni iş de ona uyar.
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'calendar-nudge-year-end')
     and not exists (select 1 from cron.job
                      where jobname <> 'calendar-nudge-year-end' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'calendar-nudge-year-end';
    raise notice '0087: projede tum cron isleri kapali — calendar-nudge-year-end da kapali kuruldu.';
  end if;
end $$;

-- ── 3) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from cron.job
                  where jobname = 'calendar-nudge-year-end'
                    and schedule = '0 17 26 12 *') then
    raise exception '0087: calendar-nudge-year-end cron isi kurulmadi';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_calendar_nudge_yil_sonu()', 'EXECUTE')
     or has_function_privilege('anon', 'public.trigger_calendar_nudge_yil_sonu()', 'EXECUTE') then
    raise exception '0087: trigger_calendar_nudge_yil_sonu istemciden cagrilabilir olmamali';
  end if;
  raise notice '0087 tamam: yil sonu ani (26 Aralik 20:00 TR) kuruldu.';
end $$;
