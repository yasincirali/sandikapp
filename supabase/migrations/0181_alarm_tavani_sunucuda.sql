-- 0181 — Ücretsiz alarm tavanı sunucuda da (yasin 2026-11-12: "alarm ekleme
-- kısmında sonsuz alarma gidebilecek bir bug var")
--
-- ## Neden
-- Ücretsiz planda aktif alarm tavanı (20; fiyat + yüzde + gösterge + çizgi
-- alarmı toplamı) yalnız istemcide denetleniyordu ve üç yerden deliniyordu:
-- yüklenmemiş liste 0 sayılıyordu, kontrol sayfa açılırken bir kez
-- yapılıyordu, Alarmlarım'daki "Geri al" hiç bakmıyordu. İstemci düzeltildi
-- (aynı dal); bu migration son bekçi: istemci eksik sayarsa ya da eski build
-- deliği kullanırsa yazma burada reddedilir. Paywall'ın satış kapısı veride
-- korunmuyorsa satılan şeyin ("sınırsız alarm") bir karşılığı yoktur.
--
-- ## Kural — istemciyle BİREBİR (priceAlertLimitProvider)
-- İstemci tavanı yalnız şu durumda uygular: paywall bu build'de görünür
-- (iOS'ta açık; Android'de RevenueCat anahtarı girince) VE kullanıcının
-- Premium erişimi yok (mağaza/sunucu hakkı/admin; acil kapatma
-- `acil_kapali` kilitleri askıya alır). Sunucunun karşılıkları:
--   * kapı:   premium_ayar.kapi_acik (0116) — kapalıysa tavan YOK.
--   * acil:   premium_ayar.acil_kapali (0172) — açıksa tavan YOK.
--   * Premium: premium_mi_kullanici(uid) (0116/0123; hak satırı + admin).
--   * platform: sunucu build'in paywall'ı açık mı bilemez. Android build'i
--     anahtarsızsa istemci sınırsızdır; sunucu orada keserse canlı
--     kullanıcı (ANA KURAL) haksız yere duvara çarpar. Bu yüzden tavan
--     yalnız hesabın AKTİF cihazı (0098 aktif_cihaz → kayitli_cihazlar)
--     iOS ise uygulanır; aktif cihazı bilinmeyen hesap (muafiyetli inceleme
--     hesabı dahil) için sunucu karışmaz, istemci kuralı yine geçerli.
--     Bu cihaz BİLGİSİ (platform), kurulum kaynağı değil: App Store 2.3.1
--     kuralına (inceleme ortamı tespiti yok) dokunmaz.
--   * tavan:  20 = RemoteConfigService `free_price_alert_limit` kod
--     varsayılanı (RC'den okunmuyor). İkisi ayrışırsa sayaç 20 derken sunucu
--     başka yerde keser — `alarm_tavani_test` iki sayıyı karşılaştırır.
--   * "aktif": model `isActive`'leriyle aynı (`alarm_satiri_aktif`).
-- Bilinen kalan fark: Premium'u yeni satın alan kişinin hakkı sunucuya
-- RevenueCat webhook'u ile gelir (saniyeler); o arada 21. alarm reddedilirse
-- istemci Premium uyarısını gösterir, kişi tekrar dener.
--
-- ## Etkilenmeyenler
--   * service_role / cron (check-price-alerts damgaları): auth.uid() boş →
--     tetikleyici hemen döner.
--   * Var olan fazla alarmlar SİLİNMEZ, düzenlenebilir: yalnız yeni bir
--     alarmı AKTİF yapan yazma (INSERT ya da pasif → aktif UPDATE: yeniden
--     kur) sayılır. Aktif satırı düzenlemek (hedef, ad) tavana bakmaz.
--   * Kapatma (aktif → pasif) ve silme serbest.
--
-- ## Hata
-- SQLSTATE 54000 (program_limit_exceeded; 0098 `cihaz_siniri` ile aynı
-- sınıf) + mesajda sabit `alarm_siniri` işareti. İstemci mesajdan tanır
-- (`alarmSiniriHatasiMi`) ve ortak sınır uyarısını gösterir; ham metin
-- kullanıcıya gitmez. Eski build'ler genel "işlem yapılamadı" görür.
--
-- ## Eski sürümler
-- Yalnız ekleme: iki fonksiyon + dört tetikleyici. Kolon/RPC/yanıt biçimi
-- değişmez. Eski iOS build'leri (paywall'ı açık olan 1.1.7+) zaten aynı
-- tavanı uygular. ⚠️ Paywall'ı RC'den kapalı alan eski iOS build'inde
-- (≤1.1.6) Premium'suz ve 20+ aktif alarmlı biri 21.'yi kuramaz
-- (YAPMAN_GEREKENLER'de not).
--
-- ## Eşzamanlılık
-- Aynı kullanıcının iki eşzamanlı yazması ikisi de 19 görüp 21 yapmasın:
-- sayım kullanıcıya özel işlem kilidi (pg_advisory_xact_lock) altında.

-- ── "Aktif" tanımı (istemci modelleriyle birebir) ───────────────────────────
-- price_alerts:      enabled && (tekrar || triggered_at == null)  (0171)
-- yuzde_alarmlari:   enabled                                       (0169)
-- gosterge/cizim:    enabled && triggered_at == null               (0170)
create or replace function public.alarm_satiri_aktif(p_tablo text, p_satir jsonb)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select case p_tablo
    when 'price_alerts' then
      coalesce((p_satir->>'enabled')::boolean, false)
      and (coalesce((p_satir->>'tekrar')::boolean, false)
           or p_satir->>'triggered_at' is null)
    when 'yuzde_alarmlari' then
      coalesce((p_satir->>'enabled')::boolean, false)
    when 'gosterge_alarmlari' then
      coalesce((p_satir->>'enabled')::boolean, false)
      and p_satir->>'triggered_at' is null
    when 'cizim_alarmlari' then
      coalesce((p_satir->>'enabled')::boolean, false)
      and p_satir->>'triggered_at' is null
    else false
  end;
$$;

revoke all on function public.alarm_satiri_aktif(text, jsonb) from public, anon, authenticated;

comment on function public.alarm_satiri_aktif(text, jsonb) is
  'Alarm satırı tavana sayılır mı (istemci isActive ile aynı; 0181).';

-- ── Tetikleyici ─────────────────────────────────────────────────────────────
-- SECURITY DEFINER: premium_ayar, premium_mi_kullanici ve cihaz tabloları
-- istemciye kapalı (RLS/GRANT); sayım da dört tablonun tamamında kullanıcının
-- satırlarını görmeli. search_path sabit; dışarıdan girdi yalnız NEW satırı.
create or replace function public.alarm_tavani_denetim()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- RemoteConfigService `free_price_alert_limit` ile aynı (alarm_tavani_test).
  v_tavan constant integer := 20;
  v_uid uuid := (select auth.uid());
  v_kapi boolean;
  v_acil boolean;
  v_toplam integer;
begin
  -- Sunucu/cron yazmaları (service_role, oturumsuz) muaf.
  if v_uid is null then
    return new;
  end if;

  -- Yalnız bir alarmı AKTİF YAPAN yazma sayılır.
  if not public.alarm_satiri_aktif(tg_table_name, to_jsonb(new)) then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and public.alarm_satiri_aktif(tg_table_name, to_jsonb(old)) then
    return new;
  end if;

  -- İstemcinin priceAlertLimitProvider kararı (yukarıdaki "Kural").
  select a.kapi_acik, a.acil_kapali
    into v_kapi, v_acil
    from public.premium_ayar a
   where a.tek;
  if not coalesce(v_kapi, false) or coalesce(v_acil, false) then
    return new;
  end if;
  if not exists (
    select 1
      from public.aktif_cihaz ac
      join public.kayitli_cihazlar k
        on k.user_id = ac.user_id and k.cihaz_id = ac.cihaz_id
     where ac.user_id = new.user_id
       and k.platform = 'ios'
  ) then
    return new;
  end if;
  if public.premium_mi_kullanici(new.user_id) then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('alarm_tavani:' || new.user_id::text, 0));

  -- UPDATE'te satırın eski (pasif) hâli sayıma girmez; INSERT'te yeni satır
  -- henüz tabloda değil. İkisinde de "bu yazmadan önceki aktif sayı".
  select
      (select count(*) from public.price_alerts p
        where p.user_id = new.user_id and p.enabled
          and (p.tekrar or p.triggered_at is null))
    + (select count(*) from public.yuzde_alarmlari y
        where y.user_id = new.user_id and y.enabled)
    + (select count(*) from public.gosterge_alarmlari g
        where g.user_id = new.user_id and g.enabled and g.triggered_at is null)
    + (select count(*) from public.cizim_alarmlari c
        where c.user_id = new.user_id and c.enabled and c.triggered_at is null)
    into v_toplam;

  if v_toplam >= v_tavan then
    raise exception 'alarm_siniri: ucretsiz planda en fazla % aktif alarm', v_tavan
      using errcode = '54000',
            hint = 'alarm_siniri';
  end if;
  return new;
end;
$$;

-- Tetikleyici fonksiyonu doğrudan çağrılamaz; tetiklenirken EXECUTE
-- yetkisi aranmaz. Yine de kimseye açık durmasın.
revoke all on function public.alarm_tavani_denetim() from public, anon, authenticated;

comment on function public.alarm_tavani_denetim() is
  'Ücretsiz aktif alarm tavanı (20; dört tablo toplamı), istemci '
  'priceAlertLimitProvider ile aynı kapılar; service_role muaf (0181).';

-- Ad `alarm_tavani`: BEFORE tetikleyicileri ad sırasıyla koşar; tavan
-- tablonun kendi `*_denetim`inden (değişmez alanlar, kaba 100 sınırı) önce
-- karar verir. İkisinin sırası sonucu değiştirmez.
drop trigger if exists alarm_tavani on public.price_alerts;
create trigger alarm_tavani
  before insert or update on public.price_alerts
  for each row execute function public.alarm_tavani_denetim();

drop trigger if exists alarm_tavani on public.yuzde_alarmlari;
create trigger alarm_tavani
  before insert or update on public.yuzde_alarmlari
  for each row execute function public.alarm_tavani_denetim();

drop trigger if exists alarm_tavani on public.gosterge_alarmlari;
create trigger alarm_tavani
  before insert or update on public.gosterge_alarmlari
  for each row execute function public.alarm_tavani_denetim();

drop trigger if exists alarm_tavani on public.cizim_alarmlari;
create trigger alarm_tavani
  before insert or update on public.cizim_alarmlari
  for each row execute function public.alarm_tavani_denetim();

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
declare
  v_tablo text;
begin
  foreach v_tablo in array array['price_alerts', 'yuzde_alarmlari',
                                 'gosterge_alarmlari', 'cizim_alarmlari'] loop
    if not exists (
      select 1 from pg_trigger t
       where t.tgrelid = ('public.' || v_tablo)::regclass
         and t.tgname = 'alarm_tavani'
         and not t.tgisinternal
         and t.tgenabled <> 'D') then
      raise exception '0181: % tablosunda alarm_tavani tetikleyicisi yok', v_tablo;
    end if;
  end loop;

  if not exists (
    select 1 from pg_proc p
     where p.oid = 'public.alarm_tavani_denetim()'::regprocedure
       and p.prosecdef
       and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')) then
    raise exception '0181: alarm_tavani_denetim SECURITY DEFINER + search_path olmali';
  end if;
  if has_function_privilege('authenticated', 'public.alarm_tavani_denetim()', 'EXECUTE')
     or has_function_privilege('anon', 'public.alarm_tavani_denetim()', 'EXECUTE') then
    raise exception '0181: alarm_tavani_denetim istemciye acik olmamali';
  end if;
  if has_function_privilege('authenticated', 'public.alarm_satiri_aktif(text, jsonb)', 'EXECUTE') then
    raise exception '0181: alarm_satiri_aktif istemciye acik olmamali';
  end if;

  -- "Aktif" tanımı istemci modelleriyle aynı mı (saf fonksiyon, veri yok).
  if not public.alarm_satiri_aktif('price_alerts', '{"enabled":true,"triggered_at":null}')
     or public.alarm_satiri_aktif('price_alerts', '{"enabled":true,"triggered_at":"2026-11-12T10:00:00Z"}')
     or not public.alarm_satiri_aktif('price_alerts', '{"enabled":true,"tekrar":true,"triggered_at":"2026-11-12T10:00:00Z"}')
     or public.alarm_satiri_aktif('price_alerts', '{"enabled":false,"tekrar":true}')
     or not public.alarm_satiri_aktif('yuzde_alarmlari', '{"enabled":true,"son_tetik_gunu":"2026-11-12"}')
     or public.alarm_satiri_aktif('yuzde_alarmlari', '{"enabled":false}')
     or not public.alarm_satiri_aktif('gosterge_alarmlari', '{"enabled":true,"triggered_at":null}')
     or public.alarm_satiri_aktif('cizim_alarmlari', '{"enabled":false,"triggered_at":"2026-11-12T10:00:00Z"}') then
    raise exception '0181: alarm_satiri_aktif istemci isActive ile ayrisiyor';
  end if;

  raise notice '0181 tamam: ucretsiz alarm tavani sunucuda (dort tablo, service_role muaf).';
end $$;
