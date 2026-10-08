-- 0126 — Ücretsiz planın tek sinyal varlığı (2026-10-08, Premium planı)
--
-- ## Neden
-- yasin kararı (2026-10-08): ücretsiz planda teknik sinyal bildirimi
-- yalnız TEK varlık için çalışır; ikinci varlığın sinyali Premium ister.
-- Kullanıcı hangi varlığı seçtiğini bu tabloya yazar; `analyze-signals`
-- ücretsiz kullanıcının lotlarını bu satıra göre süzer.
--
-- ## Yalnız ekleme; canlıda davranış değişmez
-- Kapı edge function'da `SINYAL_UCRETSIZ_VARLIK` secret'ı > 0 iken açılır
-- (paywall ile birlikte konur). Secret yokken bu tablo HİÇ okunmaz ve
-- bildirimler birebir eskisi gibi gider. Eski istemci tabloyu bilmez;
-- satırı olmayan ücretsiz kullanıcı için sunucu kendi seçer (en eski
-- eklenen analiz edilebilir varlık) — eski build'de kimse bildirimsiz kalmaz.
-- Seçilen varlık satıldıysa/silindiyse de aynı yedek uygulanır; satır
-- değiştirilmez, varlık geri alınınca seçim geri gelir.
--
-- ## Neden kullanıcı başına TEK satır (PK = user_id)
-- Plan "bir varlık" diyor; birincil anahtar bunu şemada zorlar. Seçimi
-- değiştirmek upsert'tür, iki satır birikip "hangisi geçerli" sorusu doğmaz.
-- Premium alınca satır silinmez: plan düşerse seçim kaldığı yerden döner.
--
-- ## Eşleşme anahtarı
-- (asset_type, upper(btrim(ticker))). Lot tablosundaki ticker'lar elle
-- girilmiş olabilir ("thyao ", "THYAO"); karşılaştırma iki tarafta da
-- aynı normalize edilir (bkz. `ucretsizVarlikFiltresi`). Lot id'si değil
-- pozisyon anahtarı tutulur: aynı varlığa yeni alım eklemek ya da ilk lotu
-- silmek seçimi bozmamalı.
--
-- ## Hesap silme / yasal metin
-- `on delete cascade` ile hesapla gider. Yeni veri kategorisi değil —
-- portföydeki bir varlığın bildirim tercihi (bildirim tercihleri zaten
-- kapsamda); yasal metin değişmez.

create table if not exists public.sinyal_varlik_secimi (
  user_id uuid primary key references auth.users(id) on delete cascade,
  -- `assets.type` ile aynı sözlük ('hisse', 'fon', 'altin', ...).
  asset_type text not null,
  ticker text not null check (length(btrim(ticker)) > 0),
  guncellendi timestamptz not null default now()
);

comment on table public.sinyal_varlik_secimi is
  'Ucretsiz planin tek sinyal varligi (kullanici basina bir satir). '
  'analyze-signals SINYAL_UCRETSIZ_VARLIK > 0 iken premium olmayan kullanicinin '
  'lotlarini (asset_type, upper(btrim(ticker))) eslesmesiyle bu satira suzer; '
  'satir yoksa ya da secilen varlik artik acik lotlarda yoksa en eski eklenen '
  'analiz edilebilir varlik secilir.';

-- ── RLS: yalnız kendi satırı ───────────────────────────────────────────────
-- Edge function service role ile okur (RLS'i aşar); istemci yalnız kendi
-- seçimini görür ve değiştirir. GRANT ile RLS ayrı katmanlardır — ikisi de
-- yazılır (CLAUDE.md sunucu kuralı).
alter table public.sinyal_varlik_secimi enable row level security;

drop policy if exists sinyal_varlik_secimi_select on public.sinyal_varlik_secimi;
create policy sinyal_varlik_secimi_select on public.sinyal_varlik_secimi
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists sinyal_varlik_secimi_insert on public.sinyal_varlik_secimi;
create policy sinyal_varlik_secimi_insert on public.sinyal_varlik_secimi
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists sinyal_varlik_secimi_update on public.sinyal_varlik_secimi;
create policy sinyal_varlik_secimi_update on public.sinyal_varlik_secimi
  for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists sinyal_varlik_secimi_delete on public.sinyal_varlik_secimi;
create policy sinyal_varlik_secimi_delete on public.sinyal_varlik_secimi
  for delete to authenticated using (auth.uid() = user_id);

revoke all on table public.sinyal_varlik_secimi from anon;
grant select, insert, update, delete on table public.sinyal_varlik_secimi to authenticated;

-- ── Doğrulama ──────────────────────────────────────────────────────────────
-- Sessizce eksik kalmasın: migration'ın kendisi kontrol eder (0036/0042/0043).
do $$
declare
  grant_sayisi int;
  politika_sayisi int;
begin
  if not (select relrowsecurity from pg_class
           where oid = 'public.sinyal_varlik_secimi'::regclass) then
    raise exception '0126: sinyal_varlik_secimi RLS kapali';
  end if;

  select count(*) into grant_sayisi
    from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name = 'sinyal_varlik_secimi'
     and grantee = 'authenticated'
     and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');
  if grant_sayisi <> 4 then
    raise exception '0126: authenticated GRANT eksik (% / 4)', grant_sayisi;
  end if;

  if has_table_privilege('anon', 'public.sinyal_varlik_secimi', 'SELECT')
     or has_table_privilege('anon', 'public.sinyal_varlik_secimi', 'INSERT') then
    raise exception '0126: sinyal_varlik_secimi anon''a acik olmamali';
  end if;

  select count(*) into politika_sayisi
    from pg_policies
   where schemaname = 'public' and tablename = 'sinyal_varlik_secimi';
  if politika_sayisi <> 4 then
    raise exception '0126: sinyal_varlik_secimi politikalari eksik (% / 4)', politika_sayisi;
  end if;

  raise notice '0126 tamam: sinyal_varlik_secimi (ucretsiz planin tek sinyal varligi) kuruldu.';
end $$;
