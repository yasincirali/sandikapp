import { useCallback, useEffect, useRef, useState } from 'react';
import { rpc } from './supabase';

/* Tek bir RPC'yi çeken hook.
 *
 * Neden kendi hook'u var (React Query yerine): panelin tek ihtiyacı
 * "çağır, yükleniyor göster, hata göster, elle yenile". Bir veri
 * kütüphanesinin cache invalidation'ı burada kazanç değil — canlı log
 * zaten her çağrıda değişiyor, önbellek istemiyoruz.
 *
 * `args` her render'da yeni bir nesne olur; bu yüzden bağımlılık dizisinde
 * nesnenin kendisi değil JSON'u kullanılıyor. Aksi halde sonsuz döngü. */
export function useRpc<T>(
  fn: string,
  args: Record<string, unknown>,
  opts: { enabled?: boolean } = {},
) {
  const enabled = opts.enabled ?? true;
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [nonce, setNonce] = useState(0);
  const argKey = JSON.stringify(args);

  // Yarış koruması: kullanıcı hızlıca filtre değiştirirse geç dönen eski
  // yanıt yeniyi ezmesin.
  const istekSayaci = useRef(0);

  useEffect(() => {
    if (!enabled) return;
    const benimSiram = ++istekSayaci.current;
    setLoading(true);
    setError(null);
    rpc<T>(fn, JSON.parse(argKey))
      .then((d) => {
        if (benimSiram === istekSayaci.current) setData(d);
      })
      .catch((e: unknown) => {
        if (benimSiram === istekSayaci.current) {
          setError(e instanceof Error ? e.message : String(e));
        }
      })
      .finally(() => {
        if (benimSiram === istekSayaci.current) setLoading(false);
      });
  }, [fn, argKey, enabled, nonce]);

  const yenile = useCallback(() => setNonce((n) => n + 1), []);

  return { data, loading, error, yenile };
}

/** Otomatik yenileme — "şu an ne bozuk" ekranı açıkken elle basmak istemezsin. */
export function useOtomatikYenile(yenile: () => void, saniye: number | null) {
  useEffect(() => {
    if (!saniye) return;
    const id = setInterval(yenile, saniye * 1000);
    return () => clearInterval(id);
  }, [yenile, saniye]);
}
