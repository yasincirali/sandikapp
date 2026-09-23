/* Migration 0070'teki `returns table` imzalarının TypeScript karşılığı.
 * Sütun adları SQL ile birebir aynı tutulur — biri değişirse burada da
 * değişmeli; tip hatası derlemede yakalar. */

export type AdminUser = {
  user_id: string;
  email: string;
  display_name: string;
  created_at: string;
  last_sign_in_at: string | null;
  email_confirmed_at: string | null;
  banned_until: string | null;
  provider: string;
  asset_count: number;
  error_count_7d: number;
};

export type AdminLog = {
  id: number;
  ts: string;
  /** Istemcinin istegi attigi an. Eski surumlerde null. */
  requested_at: string | null;
  /** Yanitin dondugu an. Eski surumlerde null. */
  responded_at: string | null;
  /**
   * ts - requested_at. Buyuk deger = cihaz saati sunucudan sapmis;
   * OTP/token gibi zamana bagli akislarda ASIL sebep olabilir.
   */
  saat_farki_ms: number | null;
  source: string;
  table_name: string;
  op: string;
  event_kind: string | null;
  duration_ms: number;
  is_error: boolean;
  /** Dart hata sinifi: PostgrestException, TimeoutException… */
  error_type: string | null;
  /** SQLSTATE (42501), PostgREST (PGRST202) veya HTTP durumu. */
  error_code: string | null;
  /** Maskelenmis mesaj. Eski satirlarda response_json'dan dusulur. */
  error_message: string | null;
  /** Maskelenmis stack trace. */
  stack_trace: string | null;
  session_id: string | null;
  device_id: string | null;
  platform: string | null;
  os_version: string | null;
  app_version: string | null;
  device_model: string | null;
  request_json: unknown;
  response_json: unknown;
};

export type UserSession = {
  session_id: string;
  baslangic: string;
  bitis: string;
  sure_sn: number;
  olay: number;
  hata: number;
  ekran: number;
  device_id: string | null;
  platform: string | null;
  os_version: string | null;
  app_version: string | null;
  device_model: string | null;
  ilk_kaynak: string | null;
  son_hata: string | null;
};

export type SessionRow = {
  session_id: string;
  user_id: string | null;
  email: string | null;
  display_name: string | null;
  baslangic: string;
  bitis: string;
  sure_sn: number;
  olay: number;
  hata: number;
  device_id: string | null;
  platform: string | null;
  app_version: string | null;
  son_hata: string | null;
};

export type SessionEvent = {
  id: number;
  ts: string;
  requested_at: string | null;
  responded_at: string | null;
  /** Bir onceki olaydan kac sn sonra. Ilk satirda null. */
  onceki_bosluk_sn: number | null;
  user_id: string | null;
  email: string | null;
  source: string;
  table_name: string;
  op: string;
  event_kind: string | null;
  duration_ms: number;
  is_error: boolean;
  error_type: string | null;
  error_code: string | null;
  error_message: string | null;
  stack_trace: string | null;
  request_json: unknown;
  response_json: unknown;
};

export type DeviceRow = {
  device_id: string;
  platform: string | null;
  os_version: string | null;
  app_version: string | null;
  device_model: string | null;
  kullanici: number;
  emailler: string | null;
  seans: number;
  olay: number;
  hata: number;
  ilk_gorulme: string;
  son_gorulme: string;
};

export type VersionHealth = {
  app_version: string;
  platform: string;
  os_version: string;
  cihaz: number;
  kullanici: number;
  olay: number;
  hata: number;
  hata_orani: number | null;
  p95_ms: number;
  son_gorulme: string;
};

export type UserDevice = {
  device_id: string;
  platform: string | null;
  os_version: string | null;
  app_version: string | null;
  device_model: string | null;
  son_gorulme: string;
  hata: number;
};

export type ErrorCluster = {
  error_type: string;
  error_code: string;
  source: string;
  table_name: string;
  op: string;
  error_text: string;
  hits: number;
  affected_users: number;
  affected_devices: number;
  /** Bu hatanin gorulduğu uygulama surumleri, virgulle. */
  surumler: string | null;
  first_seen: string;
  last_seen: string;
  p95_ms: number;
  sample_request: unknown;
  sample_stack: string | null;
  /** Ornek satirin id'si: tek tikla tam kayda gitmek icin. */
  sample_log_id: number | null;
};

export type PushToken = {
  token: string;
  platform: string;
  device_id: string | null;
  updated_at: string;
  /** Son guncellemeden bu yana gecen gun. Bayat token = olu cihaz. */
  yas_gun: number;
};

/** admin_log_detail: tek satirin tamami + ayni seanstaki komsu olaylar. */
export type LogDetail = {
  id: number;
  ts: string;
  requested_at: string | null;
  responded_at: string | null;
  saat_farki_ms: number | null;
  duration_ms: number;
  user_id: string | null;
  /** profiles join'inden gelir; log satirinda DEGIL. */
  email: string | null;
  display_name: string | null;
  session_id: string | null;
  device_id: string | null;
  platform: string | null;
  os_version: string | null;
  app_version: string | null;
  device_model: string | null;
  sdk: string;
  source: string;
  table_name: string;
  op: string;
  event_kind: string | null;
  is_error: boolean;
  error_type: string | null;
  error_code: string | null;
  error_message: string | null;
  stack_trace: string | null;
  request_json: unknown;
  response_json: unknown;
  komsular: Array<{
    id: number;
    ts: string;
    source: string;
    table_name: string;
    is_error: boolean;
    error_type: string | null;
    duration_ms: number;
  }> | null;
};

export type ServiceHealth = {
  source: string;
  table_name: string;
  calls: number;
  errors: number;
  error_rate: number | null;
  p50_ms: number;
  p95_ms: number;
  max_ms: number;
  users: number;
  last_seen: string;
};

export type AuthEvent = {
  ts: string;
  kaynak: 'gotrue' | 'istemci';
  user_id: string | null;
  email: string | null;
  action: string;
  basarili: boolean;
  ip: string | null;
  user_agent: string | null;
  detay: string | null;
};

export type AuthAbuse = {
  user_id: string | null;
  email: string | null;
  display_name: string | null;
  action: string;
  basarisiz: number;
  ardisik_basarisiz: number;
  ilk_deneme: string;
  son_deneme: string;
  son_basarili: string | null;
  ornek_hata: string | null;
};

export type RateLimitRow = {
  subject: string;
  email: string | null;
  display_name: string | null;
  scope: string;
  deneme: number;
  pencere_icinde: number;
  ilk_deneme: string;
  son_deneme: string;
  kilitli_mi: boolean;
  kalan_saniye: number;
};

export type Overview = {
  pencere_saat: number;
  toplam_kullanici: number;
  yeni_kullanici: number;
  aktif_kullanici: number;
  istek: number;
  hata: number;
  hatali_kullanici: number;
  auth_hata: number;
  kilitli_subject: number;
  yavas_istek: number;
  en_eski_log: string | null;
  son_log: string | null;
};

export type TimelinePoint = {
  kova: string;
  istek: number;
  hata: number;
  auth_hata: number;
  kullanici: number;
};

export type UserDetail = {
  user_id: string;
  email: string;
  display_name: string;
  created_at: string;
  onboarding: boolean;
  last_sign_in_at: string | null;
  email_confirmed_at: string | null;
  banned_until: string | null;
  provider: string;
  asset_count: number;
  push_tokens: number;
  partner_count: number;
  log_24h: number;
  hata_24h: number;
  hata_7g: number;
  seans_7g: number;
  cihaz_sayisi: number;
  cihazlar: UserDevice[] | null;
  son_hata: {
    ts: string;
    source: string;
    table: string;
    error: string;
    session_id: string | null;
    app_version: string | null;
  } | null;
  son_gorulme: string | null;
};
