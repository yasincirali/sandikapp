-- Live Activity oturumları — iOS kilit ekranı / Dynamic Island push hedefi.
--
-- NEDEN AYRI TABLO (user_push_tokens'a eklenmedi):
--   * Yaşam döngüsü tamamen farklı. Cihaz push token'ı aylarca yaşar;
--     Live Activity token'ı OTURUMA özeldir ve seans bitince (≤ 8 saat)
--     ölür. Aynı tabloda tutmak, ölü token'ların cihaz bildirimlerini de
--     kirletmesi demekti.
--   * Kanal farklı. Cihaz push'u FCM üzerinden gider; ActivityKit push'u
--     FCM ile GÖNDERİLEMEZ — doğrudan APNs ve özel bir topic gerekir
--     (`<bundle>.push-type.liveactivity`). İki kanal iki tablo.
--   * Kullanıcı başına birden çok eşzamanlı oturum olabilir (iki cihaz).

create table if not exists live_activity_sessions (
  -- APNs push token'ı (hex). Oturumu tekilleştiren doğal anahtar.
  token         text primary key,

  user_id       uuid references auth.users(id) on delete cascade not null,

  -- ActivityKit'in oturum kimliği. Aynı cihaz yeni oturum açtığında eski
  -- satırı bulup değiştirmek için tutulur.
  activity_id   text not null,

  -- Seansın planlanan bitişi. Bu andan sonra push GÖNDERİLMEZ: oturum
  -- zaten sistem tarafından kapatılmıştır ve ölü token'a yazmak APNs
  -- tarafında hata üretir.
  expires_at    timestamptz not null,

  -- Kullanıcının "kilit ekranında tutarı göster" tercihi.
  --
  -- Sunucuda tutulur çünkü push içeriğini sunucu üretir; istemci
  -- tercihini bilmeden tutar gönderirse kilit ekranında görünürdü.
  show_amounts  boolean not null default false,

  -- İstemcinin yazdığı son portföy özeti.
  --
  -- NEDEN SUNUCU HESAPLAMIYOR: portföy değeri lot toplama + döviz çevrimi
  -- + altın dönüşümü ister; bunların tamamı `HistoryService` içinde
  -- yaşıyor. Sunucuda ikinci bir implementasyon kurmak iki kopyanın
  -- ayrışması demekti — kullanıcı uygulamada bir rakam, kilit ekranında
  -- başka bir rakam görürdü. (Aynı sınıf hata bu projede ons→gram
  -- formülünün beş kopyasında yaşandı.)
  --
  -- Şekil: { totalText, changeText, changePctText, isPositive, sparkline[] }
  -- Tutar metinleri yalnızca `show_amounts` true iken push'a girer.
  summary       jsonb,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Push döngüsü "şu an aktif oturumlar" sorgusunu atar.
create index if not exists live_activity_sessions_active_idx
  on live_activity_sessions(expires_at)
  where expires_at > now();

create index if not exists live_activity_sessions_user_idx
  on live_activity_sessions(user_id);

alter table live_activity_sessions enable row level security;

-- Kullanıcı yalnızca kendi oturumunu yönetir.
-- (Edge function service_role ile bağlanır ve RLS'i bypass eder.)
drop policy if exists live_activity_sessions_own on live_activity_sessions;
create policy live_activity_sessions_own
  on live_activity_sessions
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Süresi dolmuş oturumları temizle.
--
-- Kendiliğinden birikirler: kullanıcı uygulamayı hiç açmasa da seans
-- akşam biter ve satır ölü kalır. Temizlik olmadan tablo her gün
-- kullanıcı sayısı kadar çöp satır büyür.
create or replace function cleanup_expired_live_activities()
returns void
language sql
security definer
set search_path = public
as $$
  delete from live_activity_sessions
  where expires_at < now() - interval '1 hour';
$$;

comment on table live_activity_sessions is
  'iOS Live Activity push hedefleri. Oturum başına bir satır; seans '
  'bitiminde ölür. FCM DEĞİL, doğrudan APNs kullanılır.';
