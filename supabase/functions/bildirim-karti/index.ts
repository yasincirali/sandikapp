// bildirim-karti — push bildiriminin görseli (GET, herkese açık, imzalı).
//
// Android FCM görselini kendisi, oturumsuz indirir; bu yüzden JWT doğrulaması
// KAPALI (`config.toml` → `[functions.bildirim-karti] verify_jwt = false`).
// Kapıyı JWT değil imza tutar: URL'yi yalnız token'ı `bildirim_surumu >= 2`
// olan cihaza push gönderen fonksiyonlar üretir (`_shared/bildirim_karti.ts`).
// İmzasız / bozuk istek 403 alır ve gövdesinde hiçbir ayrıntı dönmez.
//
// Görsel, verisi URL'de olduğu için değişmez: uzun önbellek güvenli.
// Çizim başarısız olursa 500 — bildirim yine metniyle görünür (Android
// görsel inemezse sessizce metne düşer), kullanıcı bir şey kaybetmez.

import { kartSvg, kartUrlCoz } from '../_shared/bildirim_karti.ts';
import { pngCiz } from './cizici.ts';

Deno.serve(async (request) => {
  if (request.method !== 'GET') {
    return new Response(null, { status: 405 });
  }
  const anahtar = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!anahtar) return new Response(null, { status: 500 });

  const url = new URL(request.url);
  const veri = await kartUrlCoz(anahtar, url.searchParams.get('d'), url.searchParams.get('s'));
  if (!veri) return new Response(null, { status: 403 });

  try {
    const png = await pngCiz(kartSvg(veri));
    return new Response(png, {
      headers: {
        'Content-Type': 'image/png',
        'Cache-Control': 'public, max-age=604800, immutable',
      },
    });
  } catch (e) {
    console.error('[bildirim-karti] cizilemedi:', e instanceof Error ? e.message : String(e));
    return new Response(null, { status: 500 });
  }
});
