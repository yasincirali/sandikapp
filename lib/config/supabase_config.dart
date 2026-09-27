/// Supabase proje bilgileri — değerler build zamanında --dart-define ile enjekte edilir.
///
/// Local geliştirme için proje kökünde .env.local oluştur (git'e eklenmez):
///   flutter run --dart-define-from-file=.env.local
///
/// CI/CD'de GitHub Secrets olarak tanımlanır ve workflow'da --dart-define ile geçilir.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Köprü sürümü (K1, 2026-09-27): ikinci proje — Frankfurt. Hangisine
/// bağlanılacağına Remote Config `sunucu` bayrağı karar verir
/// (`SunucuSecimi`). Boşsa derleme tek sunuculudur ve bayrak etkisizdir —
/// yerel yığın, CI ve geçiş sonrası (K5) derlemeleri böyle.
/// Plan: docs/SUPABASE_FRANKFURT_TASIMA.md.
const supabaseUrlEu = String.fromEnvironment('SUPABASE_URL_EU');
const supabaseAnonKeyEu = String.fromEnvironment('SUPABASE_ANON_KEY_EU');

/// Bilinen projeler: ref → verinin durduğu ülke. Rıza metni (KVKK 9) verinin
/// GERÇEK yerini söylemek zorunda; eskiden "ABD" yazıyordu, proje Japonya'daydı.
/// Bilinmeyen proje (yerel yığın, CI) için ülke UYDURULMAZ — `null` döner ve
/// metin genel ifadeye düşer.
const supabaseProjeUlkeleri = <String, ({String ad, String ulke, String ulkede})>{
  'ybdbzouzhzwthjgwlbmk': (ad: 'tokyo', ulke: 'Japonya', ulkede: "Japonya'da"),
  'ynwymnpdiwudrlxfrmuo': (ad: 'frankfurt', ulke: 'Almanya (AB)', ulkede: "Almanya'da (AB)"),
};

/// Google ile giriş — `google_sign_in` 7.x `serverClientId` olarak **Web**
/// istemci kimliğini ister; Supabase de ID token'ın `aud` alanını aynı
/// kimlikle doğrular (Dashboard → Auth → Providers → Google → Client IDs).
/// iOS'ta ayrıca iOS istemci kimliği gerekir (ve Info.plist'te ters URL
/// şeması). Boşsa Google düğmesi gösterilmez — çökme değil, yokluk.
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
