// Premium hakkı — SAF yardımcılar (0116, 2026-10-05).
//
// ── Neden olaydan değil RevenueCat API'sinden ───────────────────────────────
// RevenueCat webhook olayları sırasız ve tekrarlı gelebilir (yenileme ile
// iptal yer değiştirir, ağ hatasında aynı olay yeniden gönderilir). Olayın
// alanlarından durum kurmak, sırayı doğru varsaymayı gerektirirdi. Bunun
// yerine olay yalnızca "bu kullanıcılara bak" sinyalidir: her kullanıcı için
// RevenueCat'in `GET /v1/subscribers/{id}` yanıtı okunur ve `premium` hakkının
// GÜNCEL hâli yazılır. Aynı olay iki kez gelse de sonuç aynıdır (idempotent).
//
// ── Kimlik ──────────────────────────────────────────────────────────────────
// İstemci RevenueCat'e Supabase kullanıcı kimliğiyle (`auth.uid()`) giriş
// yapar. UUID olmayan kimlik (`$RCAnonymousID:…`, oturum açmadan önceki
// satın alma) tabloya yazılmaz; RevenueCat giriş anında o satın almayı
// kullanıcıya aktarır ve TRANSFER olayı gelir.

/// RevenueCat panelinde tanımlı tek hak kimliği.
export const PREMIUM_HAK = 'premium';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function uuidMi(s: unknown): s is string {
  return typeof s === 'string' && UUID.test(s);
}

/// Webhook gövdesinden durumu yeniden okunacak kullanıcı kimlikleri: olayın
/// sahibi, takma adları ve TRANSFER'in iki ucu. Yalnız UUID'ler, tekil.
export function etkilenenKullanicilar(body: unknown): string[] {
  const olay = (body as { event?: Record<string, unknown> } | null)?.event;
  if (!olay || typeof olay !== 'object') return [];
  const adaylar: unknown[] = [
    olay.app_user_id,
    olay.original_app_user_id,
    ...(Array.isArray(olay.aliases) ? olay.aliases : []),
    ...(Array.isArray(olay.transferred_from) ? olay.transferred_from : []),
    ...(Array.isArray(olay.transferred_to) ? olay.transferred_to : []),
  ];
  return [...new Set(adaylar.filter(uuidMi).map((s) => s.toLowerCase()))].sort();
}

/// `premium_haklari` satırının RevenueCat'ten gelen kısmı. `null` = kullanıcının
/// RevenueCat'te bu hakkı hiç olmamış (satır yazılmaz, varsa dokunulmaz).
export type RevenueCatHakki = {
  urun: string | null;
  magaza: string | null;
  bitis: string; // ISO
  iptal_edildi: boolean;
  sandbox: boolean;
};

/// `GET /v1/subscribers/{id}` yanıtı → hak satırı.
///
/// Süresiz hak (`expires_date: null`, ömür boyu satın alma) bu üründe yok;
/// gelirse uydurma bir bitiş yazmak yerine yok sayılır ve log'a düşer
/// (çağıran). Bitmiş hak da yazılır: "Premium'du, bitti" bilgisi raporda
/// gerekli ve `premium_mi` zaten `bitis > now()` sorar.
export function revenueCatHakki(yanit: unknown): RevenueCatHakki | null {
  const abone = (yanit as { subscriber?: Record<string, unknown> } | null)?.subscriber;
  if (!abone || typeof abone !== 'object') return null;
  const haklar = abone.entitlements as Record<string, Record<string, unknown>> | undefined;
  const hak = haklar?.[PREMIUM_HAK];
  if (!hak || typeof hak !== 'object') return null;

  const bitis = typeof hak.expires_date === 'string' ? hak.expires_date : null;
  if (bitis === null || Number.isNaN(Date.parse(bitis))) return null;
  const urun = typeof hak.product_identifier === 'string' ? hak.product_identifier : null;

  // Ürünün abonelik kaydı: mağaza, sandbox, iptal (otomatik yenileme kapalı).
  const abonelikler = abone.subscriptions as Record<string, Record<string, unknown>> | undefined;
  const ab = urun !== null ? abonelikler?.[urun] : undefined;
  const magaza = typeof ab?.store === 'string' ? ab.store : null;
  const sandbox = ab?.is_sandbox === true;
  const iptal = typeof ab?.unsubscribe_detected_at === 'string' ||
    typeof ab?.refunded_at === 'string';

  // İade edilen satın almada hak iade anında biter; RevenueCat `expires_date`'i
  // zaten öne çeker, yine de daha erken olanı al.
  let bitisIso = new Date(bitis).toISOString();
  if (typeof ab?.refunded_at === 'string' && !Number.isNaN(Date.parse(ab.refunded_at))) {
    const iade = new Date(ab.refunded_at).toISOString();
    if (iade < bitisIso) bitisIso = iade;
  }

  return { urun, magaza, bitis: bitisIso, iptal_edildi: iptal, sandbox };
}
