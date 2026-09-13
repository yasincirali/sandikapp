// Cron çağrılarının yetkilendirmesi — FAIL-CLOSED.
//
// Eski biçim şuydu:
//   if (cronSecret) { if (authHeader !== `Bearer ${cronSecret}`) return 401; }
// Bu FAIL-OPEN: secret hiç set edilmemişse (isim hatası, proje restore'u
// sonrası kayıp, secret'tan önce deploy) blok atlanır ve fonksiyon herkese
// açık kalır. Aynı fonksiyonlar SUPABASE_URL eksikse throw ediyordu — yani
// yalnızca güvenlik sınırı sessizce düşüyordu. Bu yardımcı üç şeyi
// değiştirir:
//   1. Secret yoksa 503 döner (fonksiyon çalışmaz; log'a yazar).
//   2. Karşılaştırma sabit zamanlıdır (SHA-256 özetleri üzerinden).
//   3. Tek yer: yedi fonksiyon aynı kuralı paylaşır, ayrışamaz.
//
// Kullanım:
//   const denied = await requireCronSecret(request, 'DAILY_BRIEF_CRON_SECRET');
//   if (denied) return denied;

const encoder = new TextEncoder();

async function sha256(input: string): Promise<Uint8Array> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(input));
  return new Uint8Array(digest);
}

/// Sabit zamanlı eşitlik. Özetler eşit uzunlukta olduğundan uzunluk
/// bilgisi sızmaz; XOR toplamı erken çıkış yapmaz.
export async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const [ha, hb] = await Promise.all([sha256(a), sha256(b)]);
  let diff = 0;
  for (let i = 0; i < ha.length; i++) diff |= ha[i] ^ hb[i];
  return diff === 0;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

/// Secret yoksa 503, başlık uyuşmuyorsa 401, geçerliyse null döner.
export async function requireCronSecret(
  request: Request,
  envName: string,
): Promise<Response | null> {
  const secret = Deno.env.get(envName);
  if (!secret) {
    console.error(
      `${envName} tanimli degil — cron yetkilendirmesi yapilamiyor, istek reddedildi.`,
    );
    return json({ error: 'cron_secret_missing' }, 503);
  }
  const header = request.headers.get('Authorization') ?? '';
  const ok = header.startsWith('Bearer ')
    && (await timingSafeEqual(header.slice('Bearer '.length), secret));
  if (!ok) return json({ error: 'Yetkisiz cron cagrisi.' }, 401);
  return null;
}
