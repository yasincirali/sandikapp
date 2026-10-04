-- 0102 — Yasal metinler ve kimin hangisini onayladığı (2026-10-04)
--
-- ## İstek
-- Kullanıcı (2026-10-04): "bu metinleri de db de tutup her müşteri
-- hangilerini onaylamış takip edilebilir olmalı." Bağlam: kayıt ekranındaki
-- onay kutuları (iki kutu; bayrak `tek_onay_kutusu` açıkken tek kutu),
-- bağladıkları belgeler (Kullanım Koşulları, Gizlilik Politikası, KVKK
-- Aydınlatma Metni), yatırım uyarısı ve Zirve açık rıza metni.
--
-- ## Bugüne kadar
-- Yalnız yatırım uyarısı kaydediliyordu (`disclaimer_acceptances`, 0000:
-- sürüm + sha256). Kayıt kutuları yalnız istemcide bir kapıydı; koşullar,
-- KVKK ve yurt dışı aktarım açık rızası için sunucuda HİÇBİR iz yoktu.
-- Metinlerin kendisi de yalnız uygulama kodunda duruyordu.
--
-- ## Karar
-- 1. `yasal_metinler`: her metin (tür, sürüm, dil) ile bir kez ve TAM
--    hâliyle girer; `govde_hash` gövdenin sha256'sıdır (check ile
--    zorlanır). Satırlar DEĞİŞMEZ (tetikleyici): yeni metin = yeni sürüm =
--    yeni satır. Gövde ŞABLON hâlidir (`{SUPABASE_ULKE}` doldurulmadan);
--    gösterimde doldurulan değer onay satırının `degiskenler`'inde durur.
--    Metinler herkese açık belgeler → anon + authenticated okur.
-- 2. `yasal_onaylar`: kullanıcı × metin × an. Yalnız `yasal_onay_kaydet`
--    RPC'si yazar; RPC istemcinin gönderdiği hash'i sunucudaki metinle
--    KARŞILAŞTIRIR — eşit değilse reddeder. İstemcinin gösterdiği metin
--    sunucudakiyle aynı değilse kayıt yanlış ispat olurdu.
-- 3. Tekillik `(user_id, metin_id)` yalnız ETKİN satırlarda (kısmi indeks):
--    ilk onay anı korunur (tekrar gönderim hiçbir şey yapmaz), ama geri
--    çekilip yeniden verilen rıza (Zirve) yeni satır olur ve geçmiş
--    silinmez. Tam `unique(user_id, metin_id)` yeniden rızayı ya hiç
--    kaydetmez ya da ilk anı ezerdi.
-- 4. Satırda değişebilen tek şey `geri_cekildi_at`, bir kez (tetikleyici).
-- 5. `zirve_rizasi_ayarla` geri çekmede `zirve_riza` onaylarını da damgalar
--    (gövde 0094 ile birebir + o tek UPDATE).
-- 6. `yasal_onay_durumu` (yalnız service_role): kullanıcı × tür için son
--    onaylanan sürüm, güncel sürüm, güncel mi, geri çekildi mi —
--    "her müşteri hangilerini onaylamış" sorusunun cevabı.
--
-- ## Geri doldurma — yalnız kanıtı olan
--   * Yatırım uyarısı: `disclaimer_acceptances` satırı sürüm + hash taşıyor;
--     hash'i `yasal_metinler`'deki metinle EŞİT olanlar taşınır
--     (onay_at = accepted_at, kanal `aktarim`, kaynak `degiskenler`'de).
--     ⚠️ Bu satırların çoğu e-posta kaydında OTP sonrası yazıldı ve o yolda
--     `disclaimerText` ekranda GÖSTERİLMİYOR (kutunun "yatırım tavsiyesi
--     değildir" maddesi gösteriliyor). Satır olduğu gibi taşınır, kaynağı
--     yazılır; avukat sorusu YAPMAN'da.
--   * Zirve rızası: `zirve_rizalari` metin sürümünü saklıyor (0091) ve kart
--     metni o sürümden beri değişmedi → sürümü eşleşenler taşınır (geri
--     çekilmişse damgasıyla). 0091 yeniden rızada `verildi_at`'i ezdiği
--     için taşınan an SON veriliş anıdır.
--   * Koşullar / KVKK / Gizlilik / kayıt kutuları: eski kullanıcılar için
--     kanıt YOK → onay UYDURULMAZ. Yeniden onay gerekip gerekmediği avukat
--     sorusu (YAPMAN).
--
-- ## Eski istemciler
-- Yalnız EKLER: yeni tablolar, yeni RPC; `zirve_rizasi_ayarla` imzası ve
-- dönüşü aynı. İstemci kaydı Remote Config `yasal_onay_kaydi` arkasında
-- (varsayılan KAPALI) — bu migration iki sunucuya gitmeden açılmaz.
--
-- ## Metin ekleme
-- INSERT'ler `tool/yasal_metin_uret_test.dart` çıktısıdır (katalog:
-- `lib/services/yasal_metin_katalogu.dart`). `test/yasal_metin_kilidi_test`
-- katalogdaki her (tür, sürüm, dil, hash) dörtlüsünün migration'larda
-- bulunduğunu doğrular. Metin değişirse: sürümü artır → üreteci koş → YENİ
-- migration. Bu dosyadaki gövdelere elle dokunma (hash check'i tutmaz).

-- ── 1) Metinler ─────────────────────────────────────────────────────────────
create table if not exists public.yasal_metinler (
  id              bigint generated always as identity primary key,
  tur             text not null
    constraint yasal_metinler_tur_check check (tur in ('kosullar', 'gizlilik_politikasi', 'kvkk_aydinlatma', 'yatirim_uyarisi', 'kayit_kutu_kosullar', 'kayit_kutu_riza', 'kayit_tek_kutu', 'zirve_riza')),
  surum           text not null check (length(surum) between 1 and 32),
  dil             text not null check (dil ~ '^[a-z]{2}$'),
  baslik          text not null check (length(baslik) between 1 and 200),
  -- Gösterilen metnin şablon hâli (yer tutucular doldurulmadan), kanonik
  -- düz metin — üretim kuralı `YasalMetinKatalogu.bloklardanMetin`.
  govde           text not null check (length(govde) > 0),
  govde_hash      text not null,
  -- Metnin KENDİSİNDE yazan yürürlük tarihi; yazmıyorsa null (uydurulmaz).
  yururluk_tarihi date,
  eklendi_at      timestamptz not null default now(),
  constraint yasal_metinler_kimlik unique (tur, surum, dil),
  constraint yasal_metinler_hash_govde
    check (govde_hash = encode(sha256(convert_to(govde, 'UTF8')), 'hex'))
);

comment on table public.yasal_metinler is
  'Kullaniciya onaylatilan yasal metinler (0102). Satirlar degismez; yeni '
  'metin = yeni surum = yeni satir. Yalniz migration yazar.';

-- Değişmezlik: UPDATE/DELETE/TRUNCATE kimse için yok (service_role ve
-- postgres dahil). Bir yazım hatası bile yeni sürümdür — onaylanmış bir
-- metnin gövdesi sonradan değişirse eski onaylar başka bir metni gösterir.
create or replace function public.yasal_metinler_degismez()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception 'yasal_metinler degismez: yeni metin yeni surumle eklenir (0102)'
    using errcode = '42501';
end;
$$;
revoke all on function public.yasal_metinler_degismez() from public, anon, authenticated;

drop trigger if exists yasal_metinler_degismez on public.yasal_metinler;
create trigger yasal_metinler_degismez
  before update or delete on public.yasal_metinler
  for each row execute function public.yasal_metinler_degismez();
drop trigger if exists yasal_metinler_degismez_truncate on public.yasal_metinler;
create trigger yasal_metinler_degismez_truncate
  before truncate on public.yasal_metinler
  for each statement execute function public.yasal_metinler_degismez();

alter table public.yasal_metinler enable row level security;
alter table public.yasal_metinler force row level security;

drop policy if exists yasal_metinler_herkes_okur on public.yasal_metinler;
create policy yasal_metinler_herkes_okur
  on public.yasal_metinler
  for select to anon, authenticated
  using (true);

revoke all on table public.yasal_metinler from public, anon, authenticated, service_role;
grant select on table public.yasal_metinler to anon, authenticated, service_role;

-- ── 2) Onaylar ──────────────────────────────────────────────────────────────
create table if not exists public.yasal_onaylar (
  id              bigint generated always as identity primary key,
  -- Hesap silinince onaylar da gider (diğer kişisel verilerle aynı). ⚠️
  -- Gizlilik Politikası "onay logu silmeden sonra 3 yıl" diyor; bugün
  -- `disclaimer_acceptances` da cascade ile siliniyor — avukat sorusu.
  user_id         uuid not null references auth.users(id) on delete cascade,
  metin_id        bigint not null references public.yasal_metinler(id) on delete restrict,
  onay_at         timestamptz not null default now(),
  -- Onayın alındığı yüzey. `aktarim` = bu migration'ın geri doldurması.
  kanal           text not null
    constraint yasal_onaylar_kanal_check check (kanal in ('kayit', 'yatirim_uyarisi_ekrani', 'zirve', 'aktarim')),
  app_version     text check (length(app_version) <= 64),
  platform        text check (length(platform) <= 16),
  locale          text check (length(locale) <= 35),
  -- Gösterimde doldurulan yer tutucular (ör. {"SUPABASE_ULKE": "Almanya
  -- (AB)"}) ve kanıt notları (ör. "belge_acildi").
  degiskenler     jsonb not null default '{}'::jsonb
    check (jsonb_typeof(degiskenler) = 'object'),
  geri_cekildi_at timestamptz,
  constraint yasal_onaylar_geri_cekme_sirasi
    check (geri_cekildi_at is null or geri_cekildi_at >= onay_at)
);

comment on table public.yasal_onaylar is
  'Kullanicinin hangi yasal metni (yasal_metinler) ne zaman onayladigi '
  '(0102). Yalniz yasal_onay_kaydet RPC yazar; kullanici yalniz kendi '
  'satirini okur.';

create unique index if not exists yasal_onaylar_etkin_tekil
  on public.yasal_onaylar (user_id, metin_id)
  where geri_cekildi_at is null;
create index if not exists yasal_onaylar_user_idx
  on public.yasal_onaylar (user_id, onay_at desc);
create index if not exists yasal_onaylar_metin_idx
  on public.yasal_onaylar (metin_id);

-- Satırda değişebilen tek şey: `geri_cekildi_at`, null → dolu, bir kez.
-- (DELETE yalnız hesap silinince cascade ile; istemcide DELETE yetkisi yok.)
create or replace function public.yasal_onaylar_yalniz_geri_cekme()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.geri_cekildi_at is not null
     or new.geri_cekildi_at is null
     or (new.id, new.user_id, new.metin_id, new.onay_at, new.kanal,
         new.app_version, new.platform, new.locale, new.degiskenler)
        is distinct from
        (old.id, old.user_id, old.metin_id, old.onay_at, old.kanal,
         old.app_version, old.platform, old.locale, old.degiskenler) then
    raise exception 'yasal_onaylar: yalniz geri_cekildi_at bir kez damgalanabilir (0102)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.yasal_onaylar_yalniz_geri_cekme() from public, anon, authenticated;

drop trigger if exists yasal_onaylar_yalniz_geri_cekme on public.yasal_onaylar;
create trigger yasal_onaylar_yalniz_geri_cekme
  before update on public.yasal_onaylar
  for each row execute function public.yasal_onaylar_yalniz_geri_cekme();

alter table public.yasal_onaylar enable row level security;
alter table public.yasal_onaylar force row level security;

drop policy if exists yasal_onaylar_own_select on public.yasal_onaylar;
create policy yasal_onaylar_own_select
  on public.yasal_onaylar
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- Doğrudan yazma yok: hash karşılaştırması RPC'de; doğrudan INSERT onu
-- atlatırdı.
revoke all on table public.yasal_onaylar from public, anon, authenticated, service_role;
grant select on table public.yasal_onaylar to authenticated, service_role;

-- ── 3) RPC: onay kaydet ─────────────────────────────────────────────────────
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
  if p_kanal is null or p_kanal not in ('kayit', 'yatirim_uyarisi_ekrani', 'zirve') then
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
    -- Kanal yalnız kendi yüzeyinin metinlerini yazar.
    if not (
         (p_kanal = 'kayit' and v_tur in ('kayit_kutu_kosullar', 'kayit_kutu_riza',
            'kayit_tek_kutu', 'kosullar', 'gizlilik_politikasi', 'kvkk_aydinlatma'))
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

-- ── 4) Zirve rızası geri çekilince onay da damgalanır ──────────────────────
-- Gövde 0094 ile BİREBİR; tek ek geri çekme kolundaki `yasal_onaylar`
-- UPDATE'i. İmza ve dönüş aynı → create or replace, GRANT'lar korunur
-- (yine de aşağıda tekrar yazılır, doğrulama bloğu bakar).
create or replace function public.zirve_rizasi_ayarla(p_ver boolean, p_metin_surumu text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_onceki_verildi timestamptz;
  v_onceki_cekildi timestamptz;
  v_satir_var boolean := false;
begin
  if v_uid is null then
    raise exception 'oturum yok' using errcode = '42501';
  end if;
  if p_ver then
    if p_metin_surumu is null or length(p_metin_surumu) not between 1 and 32 then
      raise exception 'gecersiz metin surumu' using errcode = '22023';
    end if;
    select r.verildi_at, r.geri_cekildi_at, true
      into v_onceki_verildi, v_onceki_cekildi, v_satir_var
      from public.zirve_rizalari r
     where r.user_id = v_uid
     for update;
    insert into public.zirve_rizalari (user_id, verildi_at, metin_surumu, geri_cekildi_at)
    values (v_uid, now(), p_metin_surumu, null)
    on conflict (user_id) do update
      set verildi_at = now(),
          metin_surumu = excluded.metin_surumu,
          geri_cekildi_at = null;
    -- Anında ölçüm: yalnız "yok → var" geçişinde ve 10 dk sınırıyla.
    if not coalesce(v_satir_var, false)
       or (v_onceki_cekildi is not null
           and v_onceki_verildi < now() - interval '10 minutes') then
      begin
        perform public.zirve_tek_olcum(v_uid);
      exception when others then
        raise warning 'zirve anlik olcum kuyruga alinamadi: %', sqlerrm;
      end;
    end if;
  else
    update public.zirve_rizalari
       set geri_cekildi_at = now()
     where user_id = v_uid and geri_cekildi_at is null;
    -- Geri çekme = havuzdan çıkış + ölçümlerin silinmesi, aynı işlemde.
    delete from public.zirve_roi_snapshots        where user_id = v_uid;
    delete from public.zirve_allocation_snapshots where user_id = v_uid;
    -- 0102: rıza metninin onay kaydı da aynı anda geri çekilmiş sayılır.
    update public.yasal_onaylar o
       set geri_cekildi_at = now()
      from public.yasal_metinler m
     where m.id = o.metin_id
       and m.tur = 'zirve_riza'
       and o.user_id = v_uid
       and o.geri_cekildi_at is null;
  end if;
end;
$$;
revoke all on function public.zirve_rizasi_ayarla(boolean, text) from public, anon;
grant execute on function public.zirve_rizasi_ayarla(boolean, text) to authenticated;

-- ── 5) Metinler (tool/yasal_metin_uret_test.dart çıktısı) ───────────────────
-- kosullar/1.0/tr  (Kullanım Koşulları)
insert into public.yasal_metinler
  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)
values ('kosullar', '1.0', 'tr', 'Kullanım Koşulları', date '2026-05-11',
  '14012525a90672cbd7148ccacc29284b9515d3556eab659f301ee186338584b7',
  replace($yasal$# Kullanım Koşulları

> Yürürlük tarihi: 11 Mayıs 2026  ·  Sürüm: 1.0

---

## 1. Taraflar ve Kabul

Bu Kullanım Koşulları ("Koşullar"), Yasin Cirali (Bireysel Geliştirici) ("Geliştirici", "biz") tarafından sunulan sandık mobil uygulaması ("Uygulama") ile uygulamayı kullanan gerçek kişi ("Kullanıcı", "siz") arasındaki sözleşmedir.

Uygulamayı indirip hesap oluşturarak bu Koşulları, Gizlilik Politikası'nı ve KVKK Aydınlatma Metni'ni okuduğunuzu, anladığınızı ve kabul ettiğinizi beyan edersiniz.

## 2. Hizmetin Tanımı

sandık, kullanıcıların aşağıdaki varlık türlerini takip edebileceği bir kişisel portföy izleme aracıdır:

· BIST hisse senetleri
· TEFAS yatırım fonları
· Döviz (USD, EUR, GBP, vb.)
· Kıymetli madenler (altın)

Uygulama; portföy değerini, dağılımını, performansını ve isteğe bağlı olarak teknik analiz sinyallerini gösterir. Çoklu kullanıcı ortaklığı özelliğiyle iki kullanıcı portföylerini paylaşabilir.

Zirvedeki Portföyler (isteğe bağlı): uygulama içinde açık rıza verirseniz dönemsel getiriniz ve varlık türü paylarınız anonim bir karşılaştırma havuzunda değerlendirilir (portföy 5 günden eski, en az 2 farklı varlık); en çok kazanan portföylerin yalnızca sırası, getirisi, tür payları ve fonların TEFAS kodu ile payları, kimlik ve tutar olmadan diğer katılımcılara gösterilir; karşılığında siz de katılımcıların aynı anonim bilgilerini görürsünüz (ayrıntı: Gizlilik Politikası 5.1). İstediğiniz an ayrılabilirsiniz; katılmamak başka hiçbir özelliği etkilemez.

## 3. ÖNEMLİ UYARI — Yatırım Tavsiyesi Reddi

sandık BİR YATIRIM DANIŞMANI, ARACI KURUM VEYA PORTFÖY YÖNETİM ŞİRKETİ DEĞİLDİR.

· Geliştirici, Sermaye Piyasası Kurulu (SPK) tarafından lisanslı bir kurum değildir.
· Uygulamada gösterilen fiyatlar, performans rakamları, sinyal ve grafikler yalnızca bilgilendirme amaçlıdır.
· Hiçbir içerik yatırım tavsiyesi, alım-satım önerisi veya finansal danışmanlık niteliği taşımaz.
· Verilerin doğruluğu için garanti verilmez; üçüncü taraf veri sağlayıcılarının verileri olduğu gibi sunulur.
· Yatırım kararlarınızı SPK lisanslı bir danışmana danışarak veriniz.
· Uygulamada görüntülenen verilere dayanarak verdiğiniz yatırım kararlarından doğan hiçbir kâr/zarardan Geliştirici sorumlu tutulamaz.

## 4. Hesap

### 4.1 Hesap Açma

· 18 yaşından büyük olmalısınız.
· Geçerli bir e-posta adresi sağlamalısınız.
· Doğru ve güncel bilgi vermelisiniz.

### 4.2 Hesap Güvenliği

· Şifrenizi kimseyle paylaşmayın.
· Şifrenizin güvenliğinden siz sorumlusunuz.
· Yetkisiz erişim şüphesinde derhal şifrenizi değiştirin ve bizi bilgilendirin.
· Hesap üzerinden gerçekleştirilen tüm işlemler size ait sayılır.

## 5. Ortaklık Özelliği

Uygulamada bir başka kullanıcıyı "ortak" olarak ekleyebilirsiniz. Bu özellik aktive edildiğinde:

· Ortağınız sizin portföyünüzdeki varlıkları görebilir.
· Siz de ortağınızın portföyünü görebilirsiniz.
· Bu paylaşım iki tarafın da onayıyla başlar (davet kodu sistemi).
· İstediğiniz zaman ortaklığı sonlandırabilirsiniz.

Davet kodunuzu yalnızca güvendiğiniz kişiyle paylaşın.

## 6. Kabul Edilebilir Kullanım

Uygulamayı kullanırken yapılmaması gerekenler:

1. Yasalara aykırı amaçlarla kullanmak
2. Başkasının hesabına yetkisiz erişim sağlamaya çalışmak
3. Uygulamayı tersine mühendislik, decompile veya hack etmek
4. Otomatik scraping, bot veya zararlı yazılım kullanmak
5. Altyapıya aşırı yük bindiren talepler göndermek (DoS)
6. Sahte veya yanıltıcı bilgi girmek
7. Kara para aklama veya terör finansmanı amacıyla kullanmak

Bu kuralların ihlali halinde hesabınız bildirimsiz kapatılabilir.

## 7. Üçüncü Taraf Servisleri

Uygulama; Supabase (backend), Firebase (bildirim), Yahoo Finance / TEFAS (fiyat verisi) gibi üçüncü taraf servisleri kullanır. Bu servislerin kesintileri veya hataları nedeniyle oluşacak sorunlardan Geliştirici sorumlu değildir.

## 8. Fikri Mülkiyet

Uygulamanın tasarımı, kodu, logosu, marka ismi ve içeriği Geliştiriciye aittir. "sandık" markası, logo ve görsel kimliği telif hakkı ve marka koruması altındadır. Kendi girdiğiniz veriler (varlık kayıtlarınız) size aittir.

## 9. Hizmet Değişiklikleri ve Sona Erdirme

· Uygulamayı güncelleme, özellik kaldırma veya ekleme hakkı saklıdır.
· Hizmeti tamamen sonlandırma kararı alınırsa en az 30 gün önceden bildirim yapılır.
· İstediğiniz zaman hesabınızı silebilirsiniz (Profil → Ayarlar → Hesabımı Sil).
· Koşulları ihlal ettiğiniz tespit edilirse hesabınız bildirimsiz askıya alınabilir.

## 10. Sorumluluğun Sınırlandırılması

Uygulama "olduğu gibi" (as-is) sunulur; her türlü açık veya zımni garanti reddedilir. Geliştiricinin toplam sorumluluğu, son 12 ayda ödenen toplam tutarla sınırlıdır (ücretsiz kullanımda sıfır TL). Dolaylı, arızi veya cezai zararlardan sorumlu tutulamayız.

İstisna: Kasıtlı kusur veya ağır ihmalden doğan zararlar; tüketici hukuku kapsamındaki devredilemez haklar bu sınırlamadan etkilenmez.

## 11. Tüketici Hakları

6502 sayılı Tüketicinin Korunması Hakkında Kanun (TKHK) kapsamındaki devredilemez haklarınız bu Koşullarla sınırlandırılamaz. Tüketici Hakem Heyeti veya Tüketici Mahkemesi'ne başvuru hakkınız saklıdır.

## 12. Uygulanacak Hukuk

Uygulanacak hukuk: Türkiye Cumhuriyeti hukuku.
AB üyesi tüketiciler için Roma I Tüzüğü uyarınca yerleşim yeri ülkesinin zorunlu tüketici koruma hükümleri saklıdır.

## 13. Koşullarda Değişiklik

Değişiklik yapılırsa en az 30 gün önceden uygulama içi bildirim ve e-posta ile haber verilir. Değişikliği kabul etmiyorsanız hesabınızı silme hakkınız vardır.

## 14. İletişim

E-posta: sandikapp.destek@gmail.com
Web: yasincirali.github.io/sandikapp

---

> Bu Koşullar Türkçe ve İngilizce olarak sunulmaktadır.
Yorum farklılığında Türkçe versiyon esastır.$yasal$, chr(13), ''))
on conflict (tur, surum, dil) do nothing;

-- gizlilik_politikasi/1.0/tr  (Gizlilik Politikası)
insert into public.yasal_metinler
  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)
values ('gizlilik_politikasi', '1.0', 'tr', 'Gizlilik Politikası', date '2026-05-11',
  '6b64f07684c0892a2db04bca05f1e948b8b2be1635444c58a5a8e3932c4c310e',
  replace($yasal$# Gizlilik Politikası

> Yürürlük tarihi: 11 Mayıs 2026  ·  Sürüm: 1.0

---

## 1. Veri Sorumlusu

Bu uygulamayı (sandık) Yasin Cirali (Bireysel Geliştirici) ("biz", "geliştirici") işletmektedir.

| Bilgi | Detay |
| --- | --- |

| E-posta | sandikapp.destek@gmail.com |

| Web | yasincirali.github.io/sandikapp |

| Adres | Türkiye |

KVKK Madde 3(1)(ı) uyarınca veri sorumlusu sıfatıyla hareket ediyoruz.

## 2. Bu Politikanın Kapsamı

Bu politika; Uygulamayı indirip kullandığınızda hangi kişisel verilerinizi topladığımızı, neden topladığımızı, kimlerle paylaştığımızı, ne kadar sakladığımızı ve yasal haklarınızı açıklar. Politika; KVKK (6698 sayılı Kanun), GDPR (EU 2016/679), Apple App Store Privacy Guidelines ve Google Play Data Safety gerekliliklerini karşılayacak şekilde hazırlanmıştır.

## 3. Topladığımız Veriler

### 3.1 Hesap Verileri (zorunlu)

| Veri | Amaç | Hukuki Dayanak |
| --- | --- | --- |

| E-posta adresi | Hesap oluşturma, oturum açma, şifre sıfırlama | KVKK 5(2)(c) — sözleşme |

| Şifre (hash) | Kimlik doğrulama | KVKK 5(2)(c) |

| Görünen ad | Ortaklık özelliğinde isim göstermek | KVKK 5(2)(c) |

### 3.2 Uygulama İçeriği Verileri

| Veri | Amaç |
| --- | --- |

| Varlık kayıtları (sembol, miktar, alış fiyatı, tarih, not) | Portföy takibi |

| Portföy snapshot geçmişi | Performans grafikleri |

| Dönemsel getiri (%), varlık türü payları (%) ve fon kodu bazında paylar (%) — sunucuda hesaplanır | Zirvedeki Portföyler (anonim karşılaştırma, bkz. 5.1) |

| Ortaklık davet kodları ve bağlantılar | Çoklu kullanıcı paylaşımı |

### 3.3 Cihaz ve Bildirim Verileri

| Veri | Amaç |
| --- | --- |

| Push bildirim token'ı (FCM) | Ortaklık daveti ve sinyal bildirimleri |

| Cihaz modeli, OS sürümü, uygulama sürümü | Hata teşhisi |

| Yerel ayar (locale) | Dil / tarih formatı |

### 3.4 Toplamadığımız Veriler

Konum · Telefon defteri · Fotoğraf / kamera · Reklam tanımlayıcısı · Üçüncü taraf reklam ağı izleme verisi · Banka hesap bilgileri.

## 4. Verilerin Kullanım Amaçları

1. Hesabınızı oluşturmak ve oturumunuzu sürdürmek
2. Portföyünüzü yerel cihazınızda ve sunucularımızda saklamak
3. Performans grafiklerinizi hesaplamak
4. Ortaklık davetlerinizi diğer kullanıcılara iletmek
5. Bildirim göndermek (yalnızca açıkça izin verdiyseniz)
6. Yasal yükümlülüklerimizi yerine getirmek
7. Hata teşhisi ve servis kalitesinin iyileştirilmesi
8. Zirvedeki Portföyler: dönemin en çok kazanan portföylerinin getirisini ve varlık türü dağılımını, açık rıza veren katılımcılar arasında anonim olarak göstermek (KVKK 5(1))

## 5. Üçüncü Taraflarla Paylaşım

| Hizmet | Sağlayıcı | Amaç | Yer |
| --- | --- | --- | --- |

| Backend & veritabanı | Supabase Inc. | Saklama, kimlik doğrulama | {SUPABASE_ULKE} (AWS) |

| Push bildirimi | Google Firebase (FCM) | Bildirim teslimi | Küresel |

| Hata raporu | Firebase Crashlytics | Çökme teşhisi | Küresel |

| Fiyat verisi | Yahoo Finance, TEFAS | Fiyat çekme (kişisel veri aktarılmaz) | Küresel |

Bu sağlayıcılar yalnızca veri işleyen (data processor) sıfatıyla, talimatlarımız doğrultusunda hareket eder.

### 5.1 Diğer Kullanıcılarla Anonim Paylaşım (Zirvedeki Portföyler)

Zirvedeki Portföyler isteğe bağlıdır ve yalnızca uygulama içinde açık rıza veren kullanıcıları kapsar. Rıza verdiğinizde, portföyünüz 5 günden, hesabınız 7 günden eskiyse ve portföyünüzde en az 2 farklı varlık bulunuyorsa dönemsel getiriniz (haftalık, aylık, altı aylık, yıllık) ve varlık türü paylarınız (ör. "altın %56, fon %28") günde iki kez sunucuda hesaplanır ve anonim bir karşılaştırma havuzunda tutulur. Havuzda en az 8 portföy varsa, en çok kazanan en fazla 4 portföyün yalnızca sırası, getiri yüzdesi, tür payları ve fon türündeki yatırımların kamuya açık TEFAS fon kodu ile portföy içindeki payı (payı %1'in altındaki ya da kodsuz fonlar toplu olarak) havuza katılan diğer kullanıcılara gösterilir; fon adları resmi TEFAS listesinden gelir. Karşılığında siz de katılan kullanıcıların hangi varlık türlerini hangi oranlarda tuttuğunu ve getirilerini aynı anonim biçimde görürsünüz; bu karşılaştırma hizmeti yalnızca katılanlara açıktır. Ad, e-posta, kullanıcı adı, tutar, miktar, hisse ve diğer varlıkların adı veya sembolü ile varlıklarınıza verdiğiniz ad ve notlar hiçbir koşulda paylaşılmaz; gösterilen bilgi kimliğinizi ortaya koyacak bir veri içermez. Rıza vermezseniz getiriniz bu amaçla hesaplanmaz ve saklanmaz; uygulamanın diğer özellikleri etkilenmez. Rızanızı istediğiniz an Zirvedeki Portföyler ekranından geri alabilirsiniz; geri aldığınızda havuzdaki ölçümleriniz anında silinir. Rızanın verildiği tarih ve size gösterilen metnin sürümü, rızanın ispatı için kayıt altında tutulur. Hesabınızı sildiğinizde bu kayıtlar ve havuzdaki ölçümleriniz de silinir.

## 6. Yurt Dışına Veri Aktarımı

Supabase verileri {SUPABASE_ULKEDE}, Firebase verileri ABD'de barındırıldığından verileriniz Türkiye dışına aktarılır. Bu ülkeler KVK Kurulu'nun "yeterli korumaya sahip ülkeler" listesinde olmadığından aktarım KVKK Madde 9(1) kapsamında açık rızanıza dayanmaktadır.

## 7. Veri Saklama Süreleri

| Veri | Süre |
| --- | --- |

| Hesap verileri | Hesap silinene kadar |

| Varlık kayıtları | Hesap silinene kadar |

| Snapshot geçmişi | Son 365 gün (rolling) |

| Zirve havuzu ölçümleri (getiri %, tür payı %) | Son 365 gün (rolling); rıza geri alınınca ya da hesap silinince hemen |

| Disclaimer onay logu | Hesap silindikten sonra 3 yıl (TBK 146) |

| Push token | Logout / uninstall'a kadar |

| Hata logları | 90 gün |

Hesabınızı sildiğinizde, yukarıda özel saklama süresi belirtilenlerin haricindeki tüm verileriniz 30 gün içinde kalıcı olarak silinir.

## 8. Haklarınız (KVKK Madde 11 / GDPR Madde 15-22)

Bilgi alma · Erişim · Düzeltme · Silme (right to erasure) · Taşınabilirlik (GDPR) · İşlemeye itiraz (GDPR) · Açık rızayı geri çekme haklarına sahipsiniz.

Başvuru: sandikapp.destek@gmail.com adresine veya Profil → Ayarlar → "Hesabımı Sil" üzerinden.
KVKK Madde 13(2) uyarınca taleplerinize 30 gün içinde yanıt veririz.

Şikayet: Kişisel Verileri Koruma Kurumu — kvkk.gov.tr

## 9. Veri Güvenliği

TLS 1.2+ aktarım şifrelemesi · AES-256 at-rest şifreleme · Bcrypt şifre hash · Row-Level Security (RLS) erişim kontrolü · Rate limiting · 10 dk idle session timeout · PII maskeleme (üretim logları).

Veri ihlali tespiti halinde 72 saat içinde KVK Kurulu'na ve etkilenen kullanıcılara bildirim yapılır.

## 10. Yatırım Tavsiyesi Reddi

sandık bir portföy takip aracıdır. SPK lisanslı bir yatırım danışmanı veya aracı kurum DEĞİLDİR. Uygulamada gösterilen fiyat, performans, sinyal ve grafikler bilgilendirme amaçlıdır ve yatırım tavsiyesi niteliği taşımaz.

## 11. İletişim

E-posta: sandikapp.destek@gmail.com
Web: yasincirali.github.io/sandikapp

---

> Bu politika Türkçe ve İngilizce dillerinde sunulmaktadır.
Yorum farklılığında Türkçe versiyon esastır.$yasal$, chr(13), ''))
on conflict (tur, surum, dil) do nothing;

-- kvkk_aydinlatma/1.0/tr  (KVKK Aydınlatma Metni)
insert into public.yasal_metinler
  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)
values ('kvkk_aydinlatma', '1.0', 'tr', 'KVKK Aydınlatma Metni', date '2026-05-11',
  'e0af55df0a0ef92c107c51dd75235b24ac2d840c105fc5a89e99712b425494ed',
  replace($yasal$# KVKK Aydınlatma Metni

> Yürürlük tarihi: 11 Mayıs 2026  ·  Sürüm: 1.0

---

## 1. Veri Sorumlusunun Kimliği

6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") Madde 10 uyarınca, kişisel verilerinizin işlenmesine ilişkin olarak veri sorumlusu sıfatıyla aşağıdaki bilgilendirmeyi yaparız.

| Bilgi | Detay |
| --- | --- |

| Veri Sorumlusu | Yasin Cirali (Bireysel Geliştirici) |

| E-posta | sandikapp.destek@gmail.com |

| Web | yasincirali.github.io/sandikapp |

| Adres | Türkiye |

## 2. İşlenen Kişisel Veri Kategorileri

### 2.1 Kimlik Verisi

· E-posta adresi
· Görünen ad (display name)

### 2.2 İletişim Verisi

· Push bildirim için kayıtlı cihaz token'ı

### 2.3 Müşteri İşlem Verisi

· Portföy varlık kayıtları
· Snapshot geçmişi
· Ortaklık bağlantıları ve davet kodları
· Dönemsel getiri yüzdesi, varlık türü payları ve fon kodu bazında paylar (Zirvedeki Portföyler anonim havuzu)

### 2.4 İşlem Güvenliği Verisi

· Şifre (bcrypt hash — geri çevrilemez)
· Oturum tokenı (JWT)
· Cihaz IP adresi (oturum açma anında)
· Cihaz modeli, OS sürümü, uygulama sürümü

### 2.5 Hukuki İşlem Verisi

· Disclaimer onay zamanı, sürümü, platformu, IP'si

## 3. Kişisel Verilerin İşlenme Amaçları

| Amaç | Veri Kategorileri |
| --- | --- |

| Hesap oluşturma ve oturum yönetimi | 2.1, 2.4 |

| Portföy takibi (uygulamanın ana işlevi) | 2.3 |

| Zirvedeki Portföyler — anonim karşılaştırma | 2.3 |

| Performans grafiklerinin hesaplanması | 2.3 |

| Ortaklık özelliği | 2.1, 2.3 |

| Push bildirim gönderimi | 2.2 |

| Yasal yükümlülüklerin yerine getirilmesi | 2.5, 2.4 |

| Hata teşhisi ve uygulama güvenliği | 2.4 |

Zirvedeki Portföyler: Zirvedeki Portföyler isteğe bağlıdır ve yalnızca uygulama içinde açık rıza veren kullanıcıları kapsar. Rıza verdiğinizde, portföyünüz 5 günden, hesabınız 7 günden eskiyse ve portföyünüzde en az 2 farklı varlık bulunuyorsa dönemsel getiriniz (haftalık, aylık, altı aylık, yıllık) ve varlık türü paylarınız (ör. "altın %56, fon %28") günde iki kez sunucuda hesaplanır ve anonim bir karşılaştırma havuzunda tutulur. Havuzda en az 8 portföy varsa, en çok kazanan en fazla 4 portföyün yalnızca sırası, getiri yüzdesi, tür payları ve fon türündeki yatırımların kamuya açık TEFAS fon kodu ile portföy içindeki payı (payı %1'in altındaki ya da kodsuz fonlar toplu olarak) havuza katılan diğer kullanıcılara gösterilir; fon adları resmi TEFAS listesinden gelir. Karşılığında siz de katılan kullanıcıların hangi varlık türlerini hangi oranlarda tuttuğunu ve getirilerini aynı anonim biçimde görürsünüz; bu karşılaştırma hizmeti yalnızca katılanlara açıktır. Ad, e-posta, kullanıcı adı, tutar, miktar, hisse ve diğer varlıkların adı veya sembolü ile varlıklarınıza verdiğiniz ad ve notlar hiçbir koşulda paylaşılmaz; gösterilen bilgi kimliğinizi ortaya koyacak bir veri içermez. Rıza vermezseniz getiriniz bu amaçla hesaplanmaz ve saklanmaz; uygulamanın diğer özellikleri etkilenmez. Rızanızı istediğiniz an Zirvedeki Portföyler ekranından geri alabilirsiniz; geri aldığınızda havuzdaki ölçümleriniz anında silinir. Rızanın verildiği tarih ve size gösterilen metnin sürümü, rızanın ispatı için kayıt altında tutulur. Hesabınızı sildiğinizde bu kayıtlar ve havuzdaki ölçümleriniz de silinir.

## 4. Hukuki Dayanak

| Veri | Hukuki Sebep |
| --- | --- |

| E-posta, şifre, display name | KVKK 5(2)(c) — sözleşmenin ifası |

| Portföy verileri | KVKK 5(2)(c) — sözleşmenin ifası |

| Zirve havuzu ölçümleri (getiri %, tür payı %) | KVKK 5(1) — açık rıza (uygulama içinde, isteğe bağlı) |

| Push token | KVKK 5(1) — açık rıza |

| IP, cihaz bilgisi | KVKK 5(2)(f) — meşru menfaat (güvenlik) |

| Disclaimer onayı | KVKK 5(2)(a) — kanunlarda öngörülmesi |

| Yurt dışı aktarımı | KVKK 5(1) ve 9(1) — açık rıza |

## 5. Yurt Dışına Veri Aktarımı

| Alıcı | Ülke | Amaç | Hukuki Sebep |
| --- | --- | --- | --- |

| Supabase Inc. | {SUPABASE_ULKE} | Veritabanı ve kimlik doğrulama | KVKK 9(1) — açık rıza |

| Google LLC (Firebase) | ABD / Küresel | Push bildirim teslimi | KVKK 9(1) — açık rıza |

| Google LLC (Crashlytics) | ABD / Küresel | Çökme teşhisi | KVKK 9(1) — açık rıza |

Bu ülkeler KVK Kurulu'nun "yeterli korumaya sahip ülkeler" listesinde bulunmamaktadır. Yurt dışı aktarımı KVKK Madde 9(1) kapsamında açık rızanıza dayanmaktadır.

## 6. Veri Saklama Süreleri

| Veri | Süre | Dayanak |
| --- | --- | --- |

| Hesap verileri | Hesap silinene kadar | Sözleşme süresi |

| Portföy varlık kayıtları | Hesap silinene kadar | Sözleşme süresi |

| Snapshot geçmişi | Son 365 gün rolling | Servis ihtiyacı |

| Zirve havuzu ölçümleri | Son 365 gün rolling; rıza geri alınınca ya da hesap silinince hemen | Servis ihtiyacı |

| Push token | Logout / uninstall'a kadar | Sözleşme süresi |

| Disclaimer onay logu | Hesap silinmesinden sonra 3 yıl | TBK Madde 146 |

| Oturum logları (IP, cihaz) | 90 gün | KVKK 5(2)(f) meşru menfaat |

| Hata logları | 30 gün | KVKK 5(2)(f) meşru menfaat |

## 7. KVKK Madde 11 Kapsamındaki Haklarınız

a) Kişisel verilerinizin işlenip işlenmediğini öğrenme
b) İşlenmişse buna ilişkin bilgi talep etme
c) İşlenme amacını ve amacına uygun kullanılıp kullanılmadığını öğrenme
ç) Yurt içinde veya yurt dışında aktarıldığı üçüncü kişileri bilme
d) Eksik veya yanlış işlenmişse düzeltilmesini isteme
e) KVKK Madde 7 kapsamında silinmesini veya yok edilmesini isteme
f) Yapılan işlemlerin üçüncü kişilere bildirilmesini isteme
g) Münhasıran otomatik sistemlerle aleyhinize sonuç çıkmasına itiraz etme
ğ) Kanuna aykırı işleme sebebiyle zararın giderilmesini talep etme

### 7.1 Başvuru Yöntemi

KVKK Madde 13 uyarınca taleplerinizi şu yöntemlerden biriyle iletebilirsiniz:

1. Uygulama içi: Profil → Ayarlar → "Hesabımı Sil" / "Verilerimi İndir"
2. E-posta: sandikapp.destek@gmail.com adresine kimlik bilgilerinizle yazılı başvuru

Başvurunuza 30 gün içinde ücretsiz olarak yanıt veririz.

### 7.2 KVK Kurulu'na Şikayet

Yanıttan memnun kalmazsanız Kişisel Verileri Koruma Kurulu'na şikayet edebilirsiniz.

Kişisel Verileri Koruma Kurumu
Nasuh Akar Mah. Ziyabey Cad. 1407. Sok. No:4, 06520 Balgat / Ankara
Web: www.kvkk.gov.tr

## 8. Veri Güvenliği

Teknik Önlemler: TLS 1.2+ aktarım şifrelemesi · AES-256 at-rest şifreleme · Bcrypt şifre hash · Row-Level Security (RLS) · Rate limiting · 10 dk idle session timeout · PII maskeleme (üretim logları)

İdari Önlemler: Supabase ve Firebase ile yazılı DPA sözleşmeleri · Least-privilege erişim prensibi · Veri ihlali yönetimi süreci

Veri ihlali tespiti halinde 72 saat içinde KVK Kurulu'na ve etkilenen kullanıcılara bildirim yapılır.

## 9. Politikada Değişiklikler

Bu Aydınlatma Metni'nde değişiklik yapıldığında yeni sürüm uygulama içinde gösterilir, "Sürüm" numarası artırılır ve önemli değişikliklerde tekrar onay istenir.

## 10. İletişim

Veri korumayla ilgili tüm soru, talep ve şikayetler için:
E-posta: sandikapp.destek@gmail.com
Web: yasincirali.github.io/sandikapp

---

> Bu Aydınlatma Metni'ni okuyup anladığınızı, kayıt sırasında ilgili onay kutusunu işaretleyerek beyan etmektesiniz.$yasal$, chr(13), ''))
on conflict (tur, surum, dil) do nothing;

-- yatirim_uyarisi/1.0/tr  (Yasal Uyarı)
insert into public.yasal_metinler
  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)
values ('yatirim_uyarisi', '1.0', 'tr', 'Yasal Uyarı', null,
  '7b13f0c10a6ae24642c3cde6750292b8c7bec974b1a4287e73aeebb1c24c061b',
  replace($yasal$Bu uygulama yalnızca kişisel portföy takibi ve bilgilendirme amacıyla sunulmaktadır. Gösterilen fiyat verileri, teknik analizler ve sinyaller kesinlikle yatırım tavsiyesi, alım-satım önerisi veya finansal danışmanlık niteliği taşımaz. Yatırım kararlarınızı yetkili ve lisanslı bir finansal danışmana danışarak veriniz. Geçmiş performans ve teknik göstergeler gelecekteki sonuçları garanti etmez. Uygulamayı kullanarak bu koşulları okuduğunuzu ve kabul ettiğinizi onaylıyorsunuz.$yasal$, chr(13), ''))
on conflict (tur, surum, dil) do nothing;

-- kayit_kutu_kosullar/1.0/tr  (Yasal Koşullar)
insert into public.yasal_metinler
  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)
values ('kayit_kutu_kosullar', '1.0', 'tr', 'Yasal Koşullar', null,
  '814daa288fcb4da6e03b5a574101d4c953ccd30801c012ed3e1fef52c1a64ab5',
  replace($yasal$Yasal Koşullar

• 18 yaşından büyük olduğunu beyan edersin.
• Uygulama yatırım tavsiyesi değildir; gösterilen fiyatlar ve teknik analiz bilgi amaçlıdır.
• Kayıt ile Kullanım Koşulları, KVKK Aydınlatma Metni ve Gizlilik Politikası'nı kabul etmiş sayılırsın.

Yasal Koşulları, KVKK Aydınlatma Metni'ni ve 18+ olduğumu kabul ediyorum.$yasal$, chr(13), ''))
on conflict (tur, surum, dil) do nothing;

-- kayit_kutu_riza/1.0/tr  (Açık Rıza: Yurt Dışı Veri Aktarımı)
insert into public.yasal_metinler
  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)
values ('kayit_kutu_riza', '1.0', 'tr', 'Açık Rıza: Yurt Dışı Veri Aktarımı', null,
  '3eec733edea1270fd02837a4778d04db06d12b37b39a5d6f3e556e5bdc1f84cd',
  replace($yasal$Açık Rıza: Yurt Dışı Veri Aktarımı

Verilerin Supabase ({SUPABASE_ULKE}) ve Firebase (ABD/Küresel) üzerinde saklanacak. KVKK Madde 9(1) gereği açık rıza gerekir. İstediğin zaman geri çekebilirsin (hesap silme).

Verilerimin yurt dışına aktarılmasına açık rıza veriyorum.$yasal$, chr(13), ''))
on conflict (tur, surum, dil) do nothing;

-- kayit_tek_kutu/1.0/tr  (Yasal Koşullar)
insert into public.yasal_metinler
  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)
values ('kayit_tek_kutu', '1.0', 'tr', 'Yasal Koşullar', null,
  'ef73c2510462498f030be6403456e505638779529395e3aff0a32bae88e91e04',
  replace($yasal$Yasal Koşullar

Uygulama yatırım tavsiyesi değildir; gösterilen fiyatlar ve teknik analiz bilgi amaçlıdır. Verilerin Supabase ({SUPABASE_ULKE}) ve Firebase (ABD/Küresel) üzerinde saklanır; açık rızanı istediğin zaman geri çekebilirsin (hesap silme).

Yasal Koşulları, KVKK Aydınlatma Metni'ni ve 18+ olduğumu kabul ediyorum; verilerimin yurt dışına aktarılmasına açık rıza veriyorum.$yasal$, chr(13), ''))
on conflict (tur, surum, dil) do nothing;

-- kayit_tek_kutu/1.0/en  (Legal Terms)
insert into public.yasal_metinler
  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)
values ('kayit_tek_kutu', '1.0', 'en', 'Legal Terms', null,
  'dc44cd147f90a1c00b9710f4de4b51678c1101685fe120d05fc8edf591d15a23',
  replace($yasal$Legal Terms

The app is not investment advice; prices and technical analysis are for information only. Your data is stored on Supabase ({SUPABASE_ULKE}) and Firebase (USA/global); you can withdraw your explicit consent at any time (account deletion).

I accept the Legal Terms and KVKK Privacy Notice and confirm I am 18+; I give my explicit consent to the transfer of my data abroad.$yasal$, chr(13), ''))
on conflict (tur, surum, dil) do nothing;

-- zirve_riza/2026-10-01/tr  (Zirvedeki Portföyler'e katıl)
insert into public.yasal_metinler
  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)
values ('zirve_riza', '2026-10-01', 'tr', 'Zirvedeki Portföyler''e katıl', null,
  '53a15a1f8c9d7137a82139ab7faa8f73ccfdf1f087a2b3e5f42f1ba3f202a4dc',
  replace($yasal$Zirvedeki Portföyler'e katıl

Katılanların portföyleri anonim olarak yan yana konur; en çok kazandıranların neye yatırdığını görürsün.

Ne paylaşılır
Seçilen dönemdeki getiri yüzden ve portföyünün tür dağılımı (ör. %40 hisse, %35 altın). Fonlarda TEFAS fon kodu ve portföy içindeki payı.

Ne paylaşılmaz
Adın, e-postan, kullanıcı adın, TL tutarların, adetlerin ve hangi hisseleri tuttuğun. Hiçbir yerde kim olduğun yazmaz.

Nasıl görünür
Tamamen anonim: portföyün yalnız en az 8 kişilik havuzda, sıra numarasıyla ("2. portföy") görünebilir.

Karşılığında
Katılan diğer kullanıcıların hangi varlıkları hangi oranlarda tuttuğunu ve getirilerini yine anonim olarak görür, kendi portföyünle kıyaslarsın. Bu hizmet yalnız katılanlara açıktır.

Geri çekme
İstediğin an bu ekrandan ayrılabilirsin; ölçümlerin hemen silinir. Katılmaman uygulamanın başka hiçbir özelliğini etkilemez.

KVKK m.5/1 kapsamında açık rızana dayanır. Ayrıntı: Gizlilik Politikası §5.1 ve KVKK Aydınlatma Metni §5.3.

Katılıyorum$yasal$, chr(13), ''))
on conflict (tur, surum, dil) do nothing;

-- ── 6) Geri doldurma ────────────────────────────────────────────────────────
-- Kaynak tablolar FORCE RLS altında (0008, 0091). Migration rolü RLS'yi
-- aşamıyorsa aşağıdaki SELECT'ler sessizce BOŞ döner ve geri doldurma hiç
-- olmamış gibi görünür — sessiz eksik yerine dur.
do $$
begin
  if not exists (select 1 from pg_roles
                  where rolname = current_user and (rolsuper or rolbypassrls)) then
    raise exception '0102: % rolu RLS asamiyor; geri doldurma bos kalirdi', current_user;
  end if;
end $$;

-- Yatırım uyarısı: yalnız hash'i bu metinle EŞİT olan eski onaylar.
insert into public.yasal_onaylar
  (user_id, metin_id, onay_at, kanal, app_version, platform, locale, degiskenler)
select d.user_id, m.id, d.accepted_at, 'aktarim', d.app_version, d.platform, d.locale,
       jsonb_build_object(
         'kaynak', 'disclaimer_acceptances',
         'kaynak_id', d.id,
         'not', 'OTP sonrasi kayit yolunda metin ekranda gosterilmeden yazilmis olabilir')
  from public.disclaimer_acceptances d
  join public.yasal_metinler m
    on m.tur = 'yatirim_uyarisi'
   and m.surum = d.disclaimer_version
   and m.dil = 'tr'
   and m.govde_hash = d.disclaimer_hash
on conflict (user_id, metin_id) where geri_cekildi_at is null do nothing;

-- Zirve rızası: 0091 metin sürümünü saklıyor; geri çekilmişse damgasıyla.
-- Geri çekilmiş satır kısmi indekse girmez, çakışmaz.
insert into public.yasal_onaylar
  (user_id, metin_id, onay_at, kanal, degiskenler, geri_cekildi_at)
select r.user_id, m.id, r.verildi_at, 'aktarim',
       jsonb_build_object(
         'kaynak', 'zirve_rizalari',
         'not', 'onay_at son verilis ani; 0091 yeniden rizada ilk ani ezdi'),
       r.geri_cekildi_at
  from public.zirve_rizalari r
  join public.yasal_metinler m
    on m.tur = 'zirve_riza'
   and m.surum = r.metin_surumu
   and m.dil = 'tr'
on conflict (user_id, metin_id) where geri_cekildi_at is null do nothing;

-- ── 7) Yönetici görünümü ────────────────────────────────────────────────────
-- Kullanıcı × tür: son onay (geri çekilmiş olabilir) ve güncel sürüm.
-- "Güncel" = o türün en son EKLENEN sürümü. İki kayıt düzeni birbirinin
-- alternatifidir (iki kutu / tek kutu): biri boşsa öteki doludur.
-- security_invoker: okuyanın yetkisiyle çalışır; yalnız service_role'e
-- (ve SQL Editor'daki postgres'e) açık.
create or replace view public.yasal_onay_durumu
with (security_invoker = true) as
with guncel as (
  select distinct on (m.tur) m.tur, m.surum as guncel_surum
    from public.yasal_metinler m
   order by m.tur, m.eklendi_at desc, m.id desc
),
son_onay as (
  select distinct on (o.user_id, m.tur)
         o.user_id, m.tur, m.surum, m.dil, o.onay_at, o.kanal, o.geri_cekildi_at
    from public.yasal_onaylar o
    join public.yasal_metinler m on m.id = o.metin_id
   order by o.user_id, m.tur, o.onay_at desc, o.id desc
)
select p.id                                   as user_id,
       g.tur,
       s.surum                                as onaylanan_surum,
       s.dil                                  as onaylanan_dil,
       g.guncel_surum,
       coalesce(s.surum = g.guncel_surum and s.geri_cekildi_at is null, false)
                                              as guncel_mi,
       s.onay_at,
       s.kanal,
       (s.geri_cekildi_at is not null)        as geri_cekildi,
       s.geri_cekildi_at
  from public.profiles p
 cross join guncel g
  left join son_onay s on s.user_id = p.id and s.tur = g.tur;

comment on view public.yasal_onay_durumu is
  'Kullanici x yasal metin turu: son onaylanan surum, guncel surum, guncel '
  'mi, geri cekildi mi (0102). Yalniz service_role.';

revoke all on table public.yasal_onay_durumu from public, anon, authenticated;
grant select on table public.yasal_onay_durumu to service_role;

-- ── 8) Doğrulama ────────────────────────────────────────────────────────────
do $$
declare
  v_tur text;
begin
  -- RLS
  if not exists (select 1 from pg_class
                  where oid = 'public.yasal_metinler'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0102: yasal_metinler RLS (enable + force) kapali';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.yasal_onaylar'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0102: yasal_onaylar RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'yasal_metinler') <> 1
     or (select count(*) from pg_policies
          where schemaname = 'public' and tablename = 'yasal_onaylar') <> 1 then
    raise exception '0102: her tablo yalniz tek SELECT politikasini tasimali';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public'
                and tablename in ('yasal_metinler', 'yasal_onaylar')
                and cmd <> 'SELECT') then
    raise exception '0102: yasal tablolarda yazma politikasi olmamali';
  end if;

  -- GRANT: metinler herkese okunur, kimse yazamaz
  if not has_table_privilege('anon', 'public.yasal_metinler', 'SELECT')
     or not has_table_privilege('authenticated', 'public.yasal_metinler', 'SELECT') then
    raise exception '0102: yasal_metinler anon/authenticated SELECT GRANT eksik';
  end if;
  if has_table_privilege('anon', 'public.yasal_metinler', 'INSERT')
     or has_table_privilege('authenticated', 'public.yasal_metinler', 'INSERT')
     or has_table_privilege('authenticated', 'public.yasal_metinler', 'UPDATE')
     or has_table_privilege('authenticated', 'public.yasal_metinler', 'DELETE')
     or has_table_privilege('service_role', 'public.yasal_metinler', 'INSERT')
     or has_table_privilege('service_role', 'public.yasal_metinler', 'UPDATE') then
    raise exception '0102: yasal_metinler istemciden/servisten yazilamamali';
  end if;

  -- GRANT: onaylar yalnız okunur (RLS: kendi satırı), yazma RPC'de
  if not has_table_privilege('authenticated', 'public.yasal_onaylar', 'SELECT') then
    raise exception '0102: authenticated icin yasal_onaylar SELECT GRANT eksik';
  end if;
  if has_table_privilege('anon', 'public.yasal_onaylar', 'SELECT')
     or has_table_privilege('authenticated', 'public.yasal_onaylar', 'INSERT')
     or has_table_privilege('authenticated', 'public.yasal_onaylar', 'UPDATE')
     or has_table_privilege('authenticated', 'public.yasal_onaylar', 'DELETE') then
    raise exception '0102: yasal_onaylar istemciden dogrudan yazilamamali / anon okuyamamali';
  end if;

  -- RPC
  if not has_function_privilege('authenticated',
       'public.yasal_onay_kaydet(jsonb, text, text, text, text)', 'EXECUTE') then
    raise exception '0102: yasal_onay_kaydet authenticated icin EXECUTE eksik';
  end if;
  if has_function_privilege('anon',
       'public.yasal_onay_kaydet(jsonb, text, text, text, text)', 'EXECUTE') then
    raise exception '0102: anon yasal_onay_kaydet cagiramamali';
  end if;
  if not exists (select 1 from pg_proc
                  where oid = 'public.yasal_onay_kaydet(jsonb, text, text, text, text)'::regprocedure
                    and prosecdef
                    and proconfig is not null
                    and exists (select 1 from unnest(proconfig) c where c like 'search_path=%')) then
    raise exception '0102: yasal_onay_kaydet security definer + search_path olmali';
  end if;

  -- Zirve fonksiyonu: 0094 davranışı korunmuş + yeni damga
  if not has_function_privilege('authenticated', 'public.zirve_rizasi_ayarla(boolean, text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.zirve_rizasi_ayarla(boolean, text)', 'EXECUTE') then
    raise exception '0102: zirve_rizasi_ayarla GRANT bozuldu';
  end if;
  if position('zirve_tek_olcum' in pg_get_functiondef('public.zirve_rizasi_ayarla(boolean, text)'::regprocedure)) = 0
     or position('zirve_roi_snapshots' in pg_get_functiondef('public.zirve_rizasi_ayarla(boolean, text)'::regprocedure)) = 0
     or position('yasal_onaylar' in pg_get_functiondef('public.zirve_rizasi_ayarla(boolean, text)'::regprocedure)) = 0 then
    raise exception '0102: zirve_rizasi_ayarla govdesi eksik (anlik olcum / olcum silme / onay damgasi)';
  end if;

  -- Görünüm yalnız service_role
  if has_table_privilege('anon', 'public.yasal_onay_durumu', 'SELECT')
     or has_table_privilege('authenticated', 'public.yasal_onay_durumu', 'SELECT') then
    raise exception '0102: yasal_onay_durumu istemciye acik olmamali';
  end if;
  if not has_table_privilege('service_role', 'public.yasal_onay_durumu', 'SELECT') then
    raise exception '0102: yasal_onay_durumu service_role icin SELECT eksik';
  end if;

  -- Her türden en az bir metin
  foreach v_tur in array array['kosullar', 'gizlilik_politikasi', 'kvkk_aydinlatma',
      'yatirim_uyarisi', 'kayit_kutu_kosullar', 'kayit_kutu_riza', 'kayit_tek_kutu',
      'zirve_riza'] loop
    if not exists (select 1 from public.yasal_metinler where tur = v_tur) then
      raise exception '0102: % turunde metin yok', v_tur;
    end if;
  end loop;

  raise notice '0102 tamam: yasal_metinler (%) + yasal_onaylar (% aktarim) + RPC + gorunum.',
    (select count(*) from public.yasal_metinler),
    (select count(*) from public.yasal_onaylar where kanal = 'aktarim');
end $$;
