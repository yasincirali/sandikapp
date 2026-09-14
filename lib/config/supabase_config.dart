/// Supabase proje bilgileri — değerler build zamanında --dart-define ile enjekte edilir.
///
/// Local geliştirme için proje kökünde .env.local oluştur (git'e eklenmez):
///   flutter run --dart-define-from-file=.env.local
///
/// CI/CD'de GitHub Secrets olarak tanımlanır ve workflow'da --dart-define ile geçilir.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Google ile giriş — `google_sign_in` 7.x `serverClientId` olarak **Web**
/// istemci kimliğini ister; Supabase de ID token'ın `aud` alanını aynı
/// kimlikle doğrular (Dashboard → Auth → Providers → Google → Client IDs).
/// iOS'ta ayrıca iOS istemci kimliği gerekir (ve Info.plist'te ters URL
/// şeması). Boşsa Google düğmesi gösterilmez — çökme değil, yokluk.
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
