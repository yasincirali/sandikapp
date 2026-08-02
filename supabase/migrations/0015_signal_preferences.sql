-- Sinyal tercihleri: kullanıcının varlık türü başına seçtiği güven eşiği ve
-- aktif göstergeler.
--
-- Neden gerekli: bu tercihler yalnızca cihazdaki SharedPreferences'ta
-- tutuluyordu. Sunucu taraflı analiz (analyze-signals edge function)
-- "bu kullanıcının eşiği 85" bilgisine erişemediği için hangi sinyalin
-- push edileceğine karar veremiyordu. Artık tek doğruluk kaynağı burası;
-- client yazar, sunucu okur.
--
-- Tasarım: kullanıcı × varlık türü başına tek satır. Türü olmayan
-- (henüz dokunulmamış) kombinasyonlar için sunucu varsayılanı kullanır
-- (eşik 70, temel 5 gösterge) — satır yokluğu "varsayılan" demektir,
-- bu yüzden onboarding'de toplu satır yazmaya gerek yok.

create table if not exists signal_preferences (
  user_id     uuid references auth.users(id) on delete cascade not null,
  asset_type  text not null,

  -- Güven eşiği (0-100). Bu değerin ALTINDA kalan sinyaller push edilmez.
  -- Client 50/70/85 sunuyor ama sunucu aralığı geniş tutar: ileride
  -- kaydırmalı seçici gelirse migration gerekmesin.
  threshold   int  not null default 70 check (threshold between 0 and 100),

  -- Aktif gösterge id'leri ('rsi','macd','bollinger','ema','stochastic',
  -- 'adx','williams_r','cci'). Boş dizi = bu tür için sinyal üretme.
  indicators  text[] not null default array['rsi','macd','bollinger','ema','stochastic'],

  -- Nötr sinyaller de bildirilsin mi (varsayılan: hayır — gürültü olur).
  neutral_push boolean not null default false,

  updated_at  timestamptz not null default now(),

  primary key (user_id, asset_type)
);

-- Edge function kullanıcı başına toplu okur.
create index if not exists signal_preferences_user_idx
  on signal_preferences(user_id);

alter table signal_preferences enable row level security;

-- Kullanıcı yalnızca kendi tercihlerini görür/yazar.
-- (Edge function service_role ile bağlanır, RLS'i bypass eder.)
drop policy if exists "signal_preferences_own_select" on signal_preferences;
create policy "signal_preferences_own_select"
  on signal_preferences for select
  using (auth.uid() = user_id);

drop policy if exists "signal_preferences_own_upsert" on signal_preferences;
create policy "signal_preferences_own_upsert"
  on signal_preferences for insert
  with check (auth.uid() = user_id);

drop policy if exists "signal_preferences_own_update" on signal_preferences;
create policy "signal_preferences_own_update"
  on signal_preferences for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "signal_preferences_own_delete" on signal_preferences;
create policy "signal_preferences_own_delete"
  on signal_preferences for delete
  using (auth.uid() = user_id);


-- ── Fiyat geçmişi cache ─────────────────────────────────────────────────────
--
-- Maliyet/performans kritik: edge function her kullanıcı için ayrı ayrı
-- Yahoo'ya gitseydi aynı sembol (THYAO, GC=F, USDTRY=X) yüzlerce kez
-- çekilirdi — hem rate-limit yer hem function süresi (= ücretli
-- invocation süresi) uzardı.
--
-- Bunun yerine sembol başına TEK çekim yapılır ve buraya yazılır; aynı
-- cron turundaki tüm kullanıcılar aynı satırı okur. `fetched_at` ile
-- tazelik kontrolü yapılır (gün içi tekrar çağrılarda yeniden çekilmez).
create table if not exists price_history_cache (
  symbol     text primary key,

  -- Kapanış fiyatları, eski→yeni sıralı. Teknik göstergeler için yeterli
  -- (OHLC gerekmiyor — mevcut Dart implementasyonu da sadece close kullanır).
  closes     double precision[] not null,

  fetched_at timestamptz not null default now()
);

alter table price_history_cache enable row level security;

-- Cache'i yalnızca service_role (edge function) yazar/okur.
-- Client'ın bu tabloya erişmesine gerek yok; policy tanımlanmadığı için
-- RLS altında normal kullanıcılara kapalıdır.
