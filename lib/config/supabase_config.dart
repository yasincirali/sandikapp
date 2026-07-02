/// Supabase proje bilgileri — değerler build zamanında --dart-define ile enjekte edilir.
///
/// Local geliştirme için proje kökünde .env.local oluştur (git'e eklenmez):
///   flutter run --dart-define-from-file=.env.local
///
/// CI/CD'de GitHub Secrets olarak tanımlanır ve workflow'da --dart-define ile geçilir.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
