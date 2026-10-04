-- 0104 — Kayıtta yatırım uyarısı: zorunlu okuma (2026-10-04)
--
-- ## İstek
-- Kullanıcı (2026-10-04): "Özeti değil hepsini okutmalıyız. Zorunlu okutup
-- en sonda onaylatarak ilerleyelim." Kapsam: TÜM onay metinleri.
--
-- ## Hata
-- E-posta kaydında yatırım uyarısının yalnız ÖZETİ (kayıt kutusundaki
-- "yatırım tavsiyesi değildir" maddesi) gösteriliyordu; OTP sonrası
-- `disclaimer_acceptances`'a TAM metnin (`disclaimerText`) hash'i
-- yazılıyordu — gösterilmeyen metne onay. `yasal_onaylar`'a ise kayıt
-- kanalında `yatirim_uyarisi` hiç yazılmıyordu (0102/0103'te `kayit`
-- kanalının tür listesinde yoktu).
--
-- ## Karar
-- Uygulama (bayrak `zorunlu_okuma`, varsayılan açık) kayıt ekranında
-- uyarının TAM metnini sonuna kadar okutup sonunda onaylatıyor; onay
-- OTP'den sonra `yasal_onay_kaydet(p_kanal => 'kayit')` ile diğer kayıt
-- metinleriyle AYNI çağrıda yazılır (degiskenler: belge_acildi +
-- sonuna_kadar_okundu). Bu migration yalnız `kayit` kanalının tür
-- listesine 'yatirim_uyarisi'yi ekler. Başka hiçbir kanal ve kural
-- değişmez: hash doğrulaması, oturum/silinmiş hesap kontrolü, öğe sınırı,
-- Zirve rızası şartı aynen. Kullanıcı zaten `yatirim_uyarisi_ekrani`
-- kanalıyla aynı metni yazabiliyordu → yetki genişlemesi yok; yalnız
-- kanal etiketi doğru yüzeyi söyler.
--
-- `sonuna_kadar_okundu` serbest `degiskenler` jsonb'sindedir (0102:
-- nesne, ≤ 2048 bayt) — şema değişikliği gerekmez.
--
-- ## Fonksiyon gövdesi
-- 0103'teki SON tanımla BİREBİR (0103 dosyasından makineyle kopyalandı);
-- tek fark `kayit` listesine eklenen 'yatirim_uyarisi' ve onu anlatan
-- yorum satırı. İmza ve dönüş aynı → create or replace, GRANT'lar korunur
-- (yine de aşağıda tekrar yazılır, doğrulama bloğu bakar).
--
-- ## Eski istemciler
-- Yalnız GENİŞLETİR: eski istemcinin gönderdiği her kombinasyon geçmeye
-- devam eder. Yeni istemci bu migration'dan ÖNCE yayına çıkarsa kayıt
-- çağrısı tümüyle reddedilir (tek işlem: "tur yatirim_uyarisi bu kanalda
-- kaydedilemez") — kayıt onayları yazılmaz ve yeniden onay kapısı bir
-- sonraki açılışta sorar. Bu yüzden sıra:
--
-- ## Dağıtım sırası
-- Bu migration İKİ sunucuya → `python tool/sema_esitlik.py` → ANCAK SONRA
-- zorunlu okumalı istemci (YAPMAN_GEREKENLER).

-- ── 1) RPC: kayit kanalına yatirim_uyarisi ──────────────────────────────────
-- p_ogeler: [{"tur","surum","dil","hash","degiskenler"?}, ...] (1..12).
-- Tümü ya yazılır ya hiçbiri (tek işlem): bir öğenin hash'i tutmuyorsa
-- istemci yanlış metin göstermiştir; o çağrının hiçbir parçası ispat değildir.
-- Dönüş: yeni yazılan satır sayısı (zaten etkin olanlar sayılmaz).
create or replace function public.yasal_onay_kaydet(
  p_ogeler jsonb,
  p_kanal text,
  p_app_version text default null,
  p_platform text default null,
  p_locale text default null
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_oge jsonb;
  v_degisken jsonb;
  v_metin_id bigint;
  v_metin_hash text;
  v_tur text;
  v_n integer;
  v_eklenen integer := 0;
begin
  if v_uid is null then
    raise exception 'oturum yok' using errcode = '42501';
  end if;
  -- Hesap silindikten sonra JWT bir süre geçerli kalır; silinmiş hesaba
  -- onay yazılmaz (damgasız satır saklama işinden kaçardı).
  if not exists (select 1 from auth.users u where u.id = v_uid) then
    raise exception 'oturum yok' using errcode = '42501';
  end if;
  if p_kanal is null or p_kanal not in ('kayit', 'yatirim_uyarisi_ekrani', 'zirve', 'yeniden_onay') then
    raise exception 'gecersiz kanal' using errcode = '22023';
  end if;
  if p_ogeler is null or jsonb_typeof(p_ogeler) <> 'array'
     or jsonb_array_length(p_ogeler) not between 1 and 12 then
    raise exception 'ogeler 1..12 elemanli dizi olmali' using errcode = '22023';
  end if;
  if length(p_app_version) > 64 or length(p_platform) > 16 or length(p_locale) > 35 then
    raise exception 'gecersiz cihaz bilgisi' using errcode = '22023';
  end if;

  for v_oge in select e from jsonb_array_elements(p_ogeler) as e loop
    if jsonb_typeof(v_oge) <> 'object' then
      raise exception 'oge nesne olmali' using errcode = '22023';
    end if;
    v_tur := v_oge->>'tur';
    -- Kanal yalnız kendi yüzeyinin metinlerini yazar. Yeniden onay kapısı
    -- kayıt formunun metinlerini (+ aynı ekranda gösterdiyse yatırım
    -- uyarısını) yazar; Zirve rızası yalnız kendi kartından.
    -- 0103: Açık Rıza Metni kayıt ve kapı kanallarında.
    -- 0104: yatırım uyarısı kayıt kanalında (zorunlu okuma: kayıt ekranı
    -- uyarının TAM metnini sonuna kadar okutup onaylatıyor).
    if not (
         (p_kanal = 'kayit' and v_tur in ('kayit_kutu_kosullar', 'kayit_kutu_riza',
            'kayit_tek_kutu', 'kosullar', 'gizlilik_politikasi', 'kvkk_aydinlatma',
            'acik_riza_metni', 'yatirim_uyarisi'))
      or (p_kanal = 'yeniden_onay' and v_tur in ('kayit_kutu_kosullar', 'kayit_kutu_riza',
            'kayit_tek_kutu', 'kosullar', 'gizlilik_politikasi', 'kvkk_aydinlatma',
            'acik_riza_metni', 'yatirim_uyarisi'))
      or (p_kanal = 'yatirim_uyarisi_ekrani' and v_tur = 'yatirim_uyarisi')
      or (p_kanal = 'zirve' and v_tur = 'zirve_riza')) then
      raise exception 'tur % bu kanalda kaydedilemez', v_tur using errcode = '22023';
    end if;
    -- Zirve onayı yalnız etkin rızanın kanıtıdır; rıza yoksa kayıt yalan olur.
    if v_tur = 'zirve_riza' and not exists (
         select 1 from public.zirve_rizalari r
          where r.user_id = v_uid and r.geri_cekildi_at is null) then
      raise exception 'etkin zirve rizasi yok' using errcode = '22023';
    end if;

    v_degisken := coalesce(v_oge->'degiskenler', '{}'::jsonb);
    if jsonb_typeof(v_degisken) <> 'object' or length(v_degisken::text) > 2048 then
      raise exception 'gecersiz degiskenler' using errcode = '22023';
    end if;

    select m.id, m.govde_hash
      into v_metin_id, v_metin_hash
      from public.yasal_metinler m
     where m.tur = v_tur
       and m.surum = v_oge->>'surum'
       and m.dil = v_oge->>'dil';
    if v_metin_id is null then
      raise exception 'yasal metin yok: %/%/%', v_tur, v_oge->>'surum', v_oge->>'dil'
        using errcode = 'P0002';
    end if;
    if v_metin_hash is distinct from (v_oge->>'hash') then
      raise exception 'yasal metin hash uyusmuyor: %/%/%', v_tur, v_oge->>'surum', v_oge->>'dil'
        using errcode = '22023';
    end if;

    insert into public.yasal_onaylar
      (user_id, metin_id, kanal, app_version, platform, locale, degiskenler)
    values
      (v_uid, v_metin_id, p_kanal, p_app_version, p_platform, p_locale, v_degisken)
    on conflict (user_id, metin_id) where geri_cekildi_at is null do nothing;
    get diagnostics v_n = row_count;
    v_eklenen := v_eklenen + v_n;
    v_metin_id := null;
  end loop;
  return v_eklenen;
end;
$$;
revoke all on function public.yasal_onay_kaydet(jsonb, text, text, text, text) from public, anon;
grant execute on function public.yasal_onay_kaydet(jsonb, text, text, text, text) to authenticated;

-- ── 2) Doğrulama ────────────────────────────────────────────────────────────
do $$
declare
  v_def text := pg_get_functiondef(
    'public.yasal_onay_kaydet(jsonb, text, text, text, text)'::regprocedure);
begin
  -- 0102'nin güvenlik zemini bozulmadı (RLS + GRANT).
  if not exists (select 1 from pg_class
                  where oid = 'public.yasal_metinler'::regclass
                    and relrowsecurity and relforcerowsecurity)
     or not exists (select 1 from pg_class
                  where oid = 'public.yasal_onaylar'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0104: yasal tablolarda RLS (enable + force) kapali';
  end if;
  if has_table_privilege('authenticated', 'public.yasal_metinler', 'INSERT')
     or has_table_privilege('authenticated', 'public.yasal_onaylar', 'INSERT')
     or has_table_privilege('anon', 'public.yasal_onaylar', 'SELECT') then
    raise exception '0104: yasal tablolar istemciden yazilabilir / anon okuyabilir';
  end if;

  -- RPC: GRANT + security definer + search_path.
  if not has_function_privilege('authenticated',
       'public.yasal_onay_kaydet(jsonb, text, text, text, text)', 'EXECUTE') then
    raise exception '0104: yasal_onay_kaydet authenticated icin EXECUTE eksik';
  end if;
  if has_function_privilege('anon',
       'public.yasal_onay_kaydet(jsonb, text, text, text, text)', 'EXECUTE') then
    raise exception '0104: anon yasal_onay_kaydet cagiramamali';
  end if;
  if not exists (select 1 from pg_proc
                  where oid = 'public.yasal_onay_kaydet(jsonb, text, text, text, text)'::regprocedure
                    and prosecdef
                    and proconfig is not null
                    and exists (select 1 from unnest(proconfig) c where c like 'search_path=%')) then
    raise exception '0104: yasal_onay_kaydet security definer + search_path olmali';
  end if;

  -- Yeni eşleme: kayit listesi yatirim_uyarisi'yi taşıyor; 0103'ün açık
  -- rıza eşlemesi ve Zirve kanalı kısıtı yerinde.
  -- Regex kayit listesinin İÇİNE bakar ([^)]* listenin kapanışında durur):
  -- yeniden_onay listesi de 'yatirim_uyarisi' ile bittiği için düz arama
  -- 0103'te de geçerdi.
  if v_def !~ $re$p_kanal = 'kayit' and v_tur in \([^)]*'yatirim_uyarisi'$re$ then
    raise exception '0104: kayit kanali yatirim_uyarisi turunu tanimiyor';
  end if;
  if position('acik_riza_metni' in v_def) = 0
     or position('(p_kanal = ''zirve'' and v_tur = ''zirve_riza'')' in v_def) = 0 then
    raise exception '0104: 0103 eslemesi kaybolmus';
  end if;

  -- Kayıt kanalının yazacağı metin var (0102, değişmez satır).
  if not exists (select 1 from public.yasal_metinler
                  where tur = 'yatirim_uyarisi' and surum = '1.0' and dil = 'tr') then
    raise exception '0104: yatirim_uyarisi/1.0/tr metni yok';
  end if;

  raise notice '0104 tamam: kayit kanali yatirim_uyarisi yazar.';
end $$;
