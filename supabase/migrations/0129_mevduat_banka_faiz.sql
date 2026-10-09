-- 0129 — Mevduat: banka listesi + TCMB haftalık faiz ortalaması (2026-10-09)
--
-- ## Neden
-- yasin (2026-10-09): "Vadeli mevduat kısmında banka listesi yasal yollardan
-- ve ücretsiz bir API'den performansı da etkilemeyecek şekilde çekilip
-- seçilen bankanın aylık/yıllık brüt faizi varsayılan yazılsın; müşteriye
-- özel oran verildiyse değiştirebilsin." Bayrak `mevduat_banka_secici`.
--
-- ## Kaynak kararı (ölçüldü, GitHub runner, 2026-10-09)
-- * Bankaya özel "tabela" faizini yasal + ücretsiz veren kaynak YOK. Banka
--   siteleri ancak kazınarak okunur (kullanım koşulları, kırılganlık);
--   karşılaştırma siteleri izin vermiyor.
-- * TCMB "fiilen uygulanan AZAMİ faiz" (aylık): o ay HERHANGİ bir müşteriye
--   ödenen en yüksek basit faiz, bir ay gecikmeli. Varsayılan olarak çoğu
--   kullanıcıya şişkin sayı gösterir — kullanılmadı.
-- * TCMB "ağırlıklı ortalama mevduat faizi (akım, haftalık)": vade dilimine
--   göre sektör ortalaması, EVDS'de, kaynak gösterilerek serbest. SEÇİLEN
--   bu. Bankaya özel değil; uygulama etiketi bunu açıkça söyler.
--
-- ## Banka listesi neden sunucuda, neden elle
-- Mevduat bankası listesi yılda bir-iki kez değişir; BDDK/TBB sayfaları
-- makine okunur API sunmuyor (BDDK sertifika zinciri eksik, TBB tarih formu).
-- Liste burada tutulur: yeni banka/marka uygulama sürümü beklemeden bir
-- migration'la eklenir. Ad kullanımı tanımlayıcıdır (paranın durduğu
-- banka); LOGO YOK — marka/tasarım hakkı ve App Review 5.2. Uygulama harf
-- rozeti çizer.
--
-- ## Performans
-- İstemci iki küçük tabloyu (≈35 + 5 satır) yalnız mevduat formu açılınca
-- okur ve oturum boyunca bellekte tutar. Dış kaynağa istemci hiç gitmez;
-- EVDS'yi haftada bir sunucu okur.
--
-- ## Eski istemciler
-- Yalnız EKLER: iki yeni tablo, bir tetikleyici, bir cron işi. Eski build
-- bunları hiç okumaz.
--
-- ## Dağıtım sırası
-- Bu migration (iki sunucu) → `mevduat-faiz` fonksiyonu → ilk tur elle:
-- `select public.trigger_mevduat_faiz();` → kontrol:
-- `select vade_dilimi, seri_kodu, yillik_faiz, veri_tarihi, durum from public.mevduat_faiz_ortalama;`

-- ── 1) Banka listesi ────────────────────────────────────────────────────────
create table if not exists public.mevduat_bankalari (
  kod     text    primary key check (kod ~ '^[a-z0-9_]{2,32}$'),
  ad      text    not null check (length(ad) between 2 and 60),
  -- 'mevduat' = faiz; 'katilim' = kâr payı (önceden belli oran yok →
  -- istemci faiz varsayılanı YAZMAZ).
  tur     text    not null check (tur in ('mevduat', 'katilim')),
  -- Arama için ek adlar (eski ad, marka): "denizbank" → "Denizbank".
  diger_adlar text[] not null default '{}',
  sira    integer not null default 100,
  aktif   boolean not null default true
);

comment on table public.mevduat_bankalari is
  'Mevduat formundaki banka secici (bayrak mevduat_banka_secici). Logo yok; istemci harf rozeti cizer.';

-- Sıra: önce en çok kullanılanlar (kamu + büyük özel), sonra alfabetik.
insert into public.mevduat_bankalari (kod, ad, tur, diger_adlar, sira) values
  ('ziraat',        'Ziraat Bankası',      'mevduat', '{"TC Ziraat"}',            10),
  ('isbank',        'İş Bankası',          'mevduat', '{"Türkiye İş Bankası","İşbank"}', 11),
  ('garanti',       'Garanti BBVA',        'mevduat', '{"Garanti"}',              12),
  ('akbank',        'Akbank',              'mevduat', '{}',                       13),
  ('yapikredi',     'Yapı Kredi',          'mevduat', '{"YKB"}',                  14),
  ('vakifbank',     'VakıfBank',           'mevduat', '{"Vakıflar Bankası"}',     15),
  ('halkbank',      'Halkbank',            'mevduat', '{"Halk Bankası"}',         16),
  ('qnb',           'QNB',                 'mevduat', '{"QNB Finansbank","Finansbank"}', 17),
  ('enpara',        'Enpara',              'mevduat', '{"Enpara.com"}',           18),
  ('denizbank',     'DenizBank',           'mevduat', '{}',                       19),
  ('teb',           'TEB',                 'mevduat', '{"Türk Ekonomi Bankası","CEPTETEB"}', 20),
  ('ing',           'ING',                 'mevduat', '{"ING Bank"}',             21),
  ('alternatif',    'Alternatif Bank',     'mevduat', '{"ABank"}',                100),
  ('anadolubank',   'Anadolubank',         'mevduat', '{}',                       100),
  ('burgan',        'Burgan Bank',         'mevduat', '{"ON Dijital"}',           100),
  ('colendi',       'Colendi Bank',        'mevduat', '{}',                       100),
  ('fibabanka',     'Fibabanka',           'mevduat', '{}',                       100),
  ('hsbc',          'HSBC',                'mevduat', '{"HSBC Bank"}',            100),
  ('icbc',          'ICBC Turkey',         'mevduat', '{}',                       100),
  ('odeabank',      'Odeabank',            'mevduat', '{"Odea"}',                 100),
  ('sekerbank',     'Şekerbank',           'mevduat', '{}',                       100),
  ('turkishbank',   'Turkish Bank',        'mevduat', '{}',                       100),
  ('albaraka',      'Albaraka Türk',       'katilim', '{"Albaraka"}',             200),
  ('dunyakatilim',  'Dünya Katılım',       'katilim', '{}',                       200),
  ('emlakkatilim',  'Emlak Katılım',       'katilim', '{}',                       200),
  ('hayatfinans',   'Hayat Finans',        'katilim', '{}',                       200),
  ('kuveytturk',    'Kuveyt Türk',         'katilim', '{}',                       200),
  ('tomkatilim',    'TOM Katılım',         'katilim', '{}',                       200),
  ('turkiyefinans', 'Türkiye Finans',      'katilim', '{}',                       200),
  ('vakifkatilim',  'Vakıf Katılım',       'katilim', '{}',                       200),
  ('ziraatkatilim', 'Ziraat Katılım',      'katilim', '{}',                       200)
on conflict (kod) do nothing;

-- ── 2) TCMB haftalık ağırlıklı ortalama (vade dilimi başına tek satır) ─────
create table if not exists public.mevduat_faiz_ortalama (
  -- 'ay1' ≤ 1 ay (32 gün dahil: TCMB dilimi "1 aya kadar", bankaların
  -- 32 günlük ürünü burada raporlanır), 'ay3', 'ay6', 'yil1', 'yil1_ustu'.
  vade_dilimi  text primary key
               check (vade_dilimi in ('ay1', 'ay3', 'ay6', 'yil1', 'yil1_ustu')),
  -- EVDS seri kodu. Fonksiyon kodu buradan okur: TCMB kodu değiştirirse
  -- deploy değil tek UPDATE yeter.
  seri_kodu    text not null check (seri_kodu ~ '^[A-Z0-9._]{3,64}$'),
  -- Yıllık brüt (%), bileşik — TCMB tanımı. Bilinmiyorsa NULL; uydurulmaz.
  yillik_faiz  double precision check (yillik_faiz is null or (yillik_faiz > 0 and yillik_faiz < 300)),
  -- Verinin ait olduğu hafta (EVDS "Tarih").
  veri_tarihi  date,
  -- Son turun sonucu: 'ok' | 'seri_bos' | 'evds_hata' | 'bekliyor'.
  durum        text not null default 'bekliyor' check (length(durum) <= 32),
  guncellendi  timestamptz not null default now()
);

comment on table public.mevduat_faiz_ortalama is
  'TCMB EVDS haftalik akim agirlikli ortalama TL mevduat faizi, vade dilimi basina (mevduat-faiz). Bankaya ozel DEGIL.';

-- Aday seri kodları (TCMB "TL mevduat, akım, haftalık"). İlk tur `durum`
-- sütununda doğrular; boş gelen dilim 'seri_bos' olur ve istemci o dilimde
-- varsayılan yazmaz (bugünkü davranış).
insert into public.mevduat_faiz_ortalama (vade_dilimi, seri_kodu) values
  ('ay1',       'TP.TRY.MT02'),
  ('ay3',       'TP.TRY.MT03'),
  ('ay6',       'TP.TRY.MT04'),
  ('yil1',      'TP.TRY.MT05'),
  ('yil1_ustu', 'TP.TRY.MT06')
on conflict (vade_dilimi) do nothing;

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.mevduat_bankalari     enable row level security;
alter table public.mevduat_bankalari     force  row level security;
alter table public.mevduat_faiz_ortalama enable row level security;
alter table public.mevduat_faiz_ortalama force  row level security;

drop policy if exists mevduat_bankalari_select on public.mevduat_bankalari;
create policy mevduat_bankalari_select on public.mevduat_bankalari
  for select to authenticated using (aktif);

drop policy if exists mevduat_faiz_ortalama_select on public.mevduat_faiz_ortalama;
create policy mevduat_faiz_ortalama_select on public.mevduat_faiz_ortalama
  for select to authenticated using (true);

-- ── GRANT ───────────────────────────────────────────────────────────────────
revoke all on public.mevduat_bankalari     from public, anon, authenticated;
revoke all on public.mevduat_faiz_ortalama from public, anon, authenticated;
grant select on public.mevduat_bankalari     to authenticated;
grant select on public.mevduat_faiz_ortalama to authenticated;
grant all on public.mevduat_bankalari     to service_role;
grant all on public.mevduat_faiz_ortalama to service_role;

-- ── 3) Tetikleyici (0076 edge_function_url + cron_headers deseni) ──────────
-- Ayrı secret açılmadı: EVDS işi TÜFE çekimiyle aynı secret'ı kullanır
-- (0124'ün kripto/eurobond kararıyla aynı gerekçe — yeni secret yasin'in
-- elle girmesini beklerdi, risk aynı sınıfta: kamu verisi okuyan cron).
create or replace function public.trigger_mevduat_faiz()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('mevduat-faiz'),
    headers := public.cron_headers('inflation_fetch_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- 5 EVDS isteği (sıralı, 20 sn zaman aşımı) + tek upsert.
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_mevduat_faiz() from public, anon, authenticated;

-- TCMB haftalık akım faizini perşembe 14:30'da (önceki hafta) yayımlıyor;
-- cuma TR 10:15 (07:15 UTC) ilk tur, pazartesi ikinci tur (gecikme/tatil).
select cron.unschedule(jobid) from cron.job where jobname in ('mevduat-faiz', 'mevduat-faiz-yedek');
select cron.schedule('mevduat-faiz', '15 7 * * 5',
  $$select public.trigger_mevduat_faiz()$$);
select cron.schedule('mevduat-faiz-yedek', '15 7 * * 1',
  $$select public.trigger_mevduat_faiz()$$);

-- İki sunucu birebir; tek bilinçli fark cron `active` (0119 kuralı).
do $$
begin
  if exists (select 1 from cron.job where jobname not like 'mevduat-faiz%')
     and not exists (select 1 from cron.job where jobname not like 'mevduat-faiz%' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname like 'mevduat-faiz%';
    raise notice '0129: projede tum cron isleri kapali — mevduat-faiz isleri de kapali kuruldu.';
  end if;
end $$;

-- ── 4) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.mevduat_bankalari', 'select')
     or not has_table_privilege('authenticated', 'public.mevduat_faiz_ortalama', 'select') then
    raise exception '0129: authenticated SELECT grant eksik';
  end if;
  if has_table_privilege('authenticated', 'public.mevduat_bankalari', 'insert')
     or has_table_privilege('authenticated', 'public.mevduat_bankalari', 'update')
     or has_table_privilege('authenticated', 'public.mevduat_faiz_ortalama', 'insert')
     or has_table_privilege('authenticated', 'public.mevduat_faiz_ortalama', 'update') then
    raise exception '0129: authenticated yazma yetkisi verilmemeli';
  end if;
  if has_table_privilege('anon', 'public.mevduat_bankalari', 'select')
     or has_table_privilege('anon', 'public.mevduat_faiz_ortalama', 'select') then
    raise exception '0129: anon erisimi olmamali';
  end if;
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relname in ('mevduat_bankalari', 'mevduat_faiz_ortalama')
         and c.relrowsecurity and c.relforcerowsecurity) <> 2 then
    raise exception '0129: RLS/FORCE RLS acik degil';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_mevduat_faiz()', 'EXECUTE')
     or has_function_privilege('anon', 'public.trigger_mevduat_faiz()', 'EXECUTE') then
    raise exception '0129: trigger_mevduat_faiz istemciden cagrilabilir olmamali';
  end if;
  if not exists (select 1 from cron.job where jobname = 'mevduat-faiz') then
    raise exception '0129: mevduat-faiz cron isi kurulmadi';
  end if;
  raise notice '0129 tamam: banka listesi, faiz ortalamasi ve cron kuruldu.';
end $$;
