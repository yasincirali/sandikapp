import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/* Panelin Supabase geçidi.
 *
 * Tek istemci, anon key ile. Yetki anon key'den GELMEZ: her admin_* RPC'si
 * gövdesinin ilk satırında is_push_admin() kontrol eder (migration 0070).
 * Yani bu dosyada saklanacak bir sır yok — service_role anahtarı buraya
 * bilerek konmadı, RLS'yi bypass ederdi. */

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const configHatasi =
  !url || !anonKey
    ? 'VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY tanımlı değil. ' +
      '.env.example dosyasını .env.local olarak kopyalayıp doldur, sonra dev sunucusunu yeniden başlat.'
    : null;

export const supabase: SupabaseClient = createClient(
  url ?? 'https://placeholder.invalid',
  anonKey ?? 'placeholder',
  {
    auth: {
      // Panel yerel bir araç; oturumu sakla ki her yenilemede tekrar
      // giriş yapılmasın. localStorage yeterli — token zaten kullanıcının
      // kendi oturumu, mobil uygulamadakiyle aynı sınıfta.
      persistSession: true,
      autoRefreshToken: true,
      // URL'de token arama: bu panel e-posta bağlantısıyla açılmaz.
      detectSessionInUrl: false,
    },
  },
);

/* RPC sarmalayıcı.
 *
 * Neden ham `supabase.rpc` kullanılmıyor: `is_push_admin()` duvarına çarpan
 * her çağrı Postgres'ten `Yetkisiz` diye döner ve supabase-js bunu ham
 * PostgrestError olarak verir. Panelde her çağrı yerinde bunu ayrıştırmak
 * yerine burada tek bir anlaşılır mesaja çeviriyoruz. */
export async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) {
    if (/yetkisiz/i.test(error.message)) {
      throw new Error(
        'Bu hesap yönetici değil. Supabase SQL Editor: ' +
          "insert into public.push_admins (user_id) select id from auth.users where email = '<e-posta>';",
      );
    }
    if (error.code === 'PGRST202') {
      throw new Error(
        `\`${fn}\` sunucuda yok. Migration 0070 uygulanmamış olabilir: supabase db push`,
      );
    }
    throw new Error(error.message);
  }
  return data as T;
}
