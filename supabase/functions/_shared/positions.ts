// Lot → AÇIK POZİSYON indirgemesi — sunucu tarafı.
//
// ## Neden gerekli
// `assets` bir **lot** (hareket) tablosudur, bir portföy görünümü değil.
// Satış, alım satırını silmez: `kind='sell'` olan AYRI bir satır yazılır ve
// pozisyonun net miktarı `Σ buy.qty − Σ sell.qty` ile hesaplanır
// (bkz. 0009_asset_kind_audit_trail).
//
// İstemci bunu biliyor: `aggregatePositions` net miktar 0'a inen pozisyonu
// listeden tamamen düşürür — kullanıcı o varlığı "portföyümde yok" olarak
// görür. Sunucudaki push işleri ise yalnızca `kind='buy'` satırlarını
// filtreliyor, satışları HİÇ okumuyordu. Sonuç: tamamı satılmış bir hisse
// için bildirim gelmeye devam ediyordu.
//
// Belirtisi (2026-09-07, kullanıcı bildirimi): "AVOD ve AGHOL varlıklarımda
// olmamasına rağmen push'ları geliyor." İki hisse de tamamen satılmıştı;
// alım lot'ları ledger'da duruyor, `deleted_at` null (silinmediler, SATILDILAR)
// ve sunucu onları hâlâ açık pozisyon sanıyordu.
//
// ## Değişmez
// Sunucunun "hangi varlıklar için bildirim gider" cevabı, istemcinin
// "hangi varlıklar portföyde görünür" cevabıyla AYNI olmalıdır. Bu dosya o
// eşitliğin sunucu tarafındaki yarısıdır; Dart tarafındaki eşi
// `lib/models/position.dart` → `positionKey` + `aggregatePositions`.

/// Netleme için gereken en küçük lot alanları.
///
/// `select` listesi bu alanları ÇEKMELİDİR; eksik çekilen alan sessizce
/// `undefined` olur ve iki lot yanlışlıkla farklı pozisyona düşer.
export interface PozisyonLot {
  id: string;
  user_id: string;
  type: string;
  ticker?: string | null;
  name?: string | null;
  sub_category?: string | null;
  currency?: string | null;
  quantity?: number | null;
  kind?: string | null;
  /// `delete_log` satırlarının ne zaman yazıldığını bilmek için gerekir
  /// (mezar taşından ESKİ alımlar silinmiş sayılır).
  added_date?: string | null;
  /// `delete_log` satırında: TEK bir lot mu silindi (dolu) yoksa
  /// pozisyonun tamamı mı (null). Ayrım kritik — bkz. `acikPozisyonLotlari`.
  ref_asset_id?: string | null;
}

/// Kayan nokta toleransı: 3 × 0.1 lot toplamı 0.30000000000000004 eder.
/// Net miktar bu eşiğin altındaysa pozisyon KAPALI sayılır.
const EPSILON = 1e-7;

/// Aggregation kimliği — hangi lot'lar aynı pozisyonda toplanır.
///
/// Dart'taki `positionKey` ile BİREBİR aynı kurallar (oradaki gerekçeler
/// için o dosyaya bak); tek fark, kullanıcı sınırının anahtara dahil
/// olmasıdır. Sunucu tek sorguda tüm kullanıcıların lot'larını okur ve
/// `user_id` düşerse bir kullanıcının satışı bir başkasının alımından
/// düşülürdü.
export function pozisyonAnahtari(a: PozisyonLot): string {
  const ticker = (a.ticker ?? '').trim().toUpperCase();
  const ad = (a.name ?? '').trim().toLowerCase();
  const alt = a.sub_category ?? '';
  const currency = (a.currency ?? 'TRY').toUpperCase();

  let core: string;
  switch (a.type) {
    case 'hisse':
    case 'fon':
      core = ticker !== '' ? ticker : `name:${ad}`;
      break;
    case 'doviz':
      core = ticker !== '' ? ticker : `sub:${alt.toUpperCase()}`;
      break;
    case 'altin':
      core = `sub:${alt.toLowerCase()}`;
      break;
    case 'mevduat':
      // Her vadeli mevduat kendi vadesi ve faiziyle bağımsız bir hesaptır —
      // asla birleştirilmez (Dart tarafıyla aynı kural).
      core = `id:${a.id}`;
      break;
    default: // emtia, diger
      core = ticker !== '' ? ticker : `name:${ad}`;
  }

  return `${a.user_id}|${a.type}|${core}|${currency}`;
}

/// Net miktarı hâlâ POZİTİF olan pozisyonların alım lot'ları.
///
/// [rows] aynı kullanıcıya ait TÜM aktif satırları içermelidir — alımlar ve
/// **satışlar** birlikte. Yalnızca alımlar verilirse fonksiyon hiçbir şey
/// netleyemez ve girdiyi olduğu gibi döndürür; hatanın kaynağı çağıran
/// taraftaki `select`/`filter` olur.
///
/// Elenen satırlar:
///   · `sell` / `delete_log` / `dividend` satırları (bunlar pozisyon DEĞİL,
///     hareket kaydıdır),
///   · net miktarı sıfıra inmiş pozisyonların alım lot'ları,
///   · pozisyonun tamamını silen bir mezar taşından ESKİ alım lot'ları
///     (ikinci savunma hattı — gerekçesi aşağıda).
///
/// Temettü miktara ASLA girmez (`dividend` satırı nakit hareketidir).
export function acikPozisyonLotlari<T extends PozisyonLot>(rows: T[]): T[] {
  const net = new Map<string, number>();
  // Pozisyonun tamamını silen mezar taşlarının EN YENİSİ (epoch ms).
  const pozisyonSilmeAni = new Map<string, number>();

  for (const r of rows) {
    const kind = r.kind ?? 'buy';
    const key = pozisyonAnahtari(r);

    if (kind === 'delete_log') {
      // ## Mezar taşı neden ayrıca dinlenir
      // Silmenin ASIL mekanizması `deleted_at` damgasıdır ve çağıran sorgu
      // onu zaten eliyor. Ama damga her zaman yerine ulaşmıyor: istemci
      // önce mezar taşını yazıp SONRA `deleted_at` UPDATE'ini atıyor
      // (`deletePositionLots`), arada bağlantı koparsa lot sunucuda AKTİF
      // kalır. Uygulama kendi durumunu iyimser günceller, yani kullanıcı
      // varlığı silinmiş görür — ama push gelmeye devam eder. Kullanıcının
      // bildirdiği şikâyet tam olarak bu: "sildiğim varlıklar için push
      // atılmaması gerekiyor."
      //
      // ## `ref_asset_id` dolu olan mezar taşları ATLANIR
      // O bir TEK lot silmesidir (`deleteAsset`) ve yalnızca o `id`'yi
      // ilgilendirir; ilgili satır zaten fiziksel silinmiştir. Pozisyon
      // geneline uygulanırsa, iki lot'lu bir varlıkta birini silmek
      // diğerini de susturur — gerçek bir varlık sessizleşirdi.
      if (r.ref_asset_id != null) continue;
      const at = zamanMs(r.added_date);
      if (at === null) continue;
      const mevcut = pozisyonSilmeAni.get(key);
      if (mevcut === undefined || at > mevcut) pozisyonSilmeAni.set(key, at);
      continue;
    }

    if (kind !== 'buy' && kind !== 'sell') continue;
    const miktar = Number(r.quantity ?? 0);
    if (!Number.isFinite(miktar)) continue;
    const delta = kind === 'sell' ? -miktar : miktar;
    net.set(key, (net.get(key) ?? 0) + delta);
  }

  return rows.filter((r) => {
    if ((r.kind ?? 'buy') !== 'buy') return false;
    const key = pozisyonAnahtari(r);
    if ((net.get(key) ?? 0) <= EPSILON) return false;

    // Mezar taşından SONRA alınmış lot yeni bir pozisyondur — kullanıcı
    // sildiği varlığı tekrar aldıysa bildirimi hak eder.
    const silme = pozisyonSilmeAni.get(key);
    if (silme === undefined) return true;
    const alim = zamanMs(r.added_date);
    // Tarih okunamıyorsa mezar taşı kazanır: yanlışlıkla bildirim
    // göndermektense sessiz kalmak yeğdir (kullanıcı açıkça istedi).
    if (alim === null) return false;
    return alim > silme;
  });
}

/// ISO zaman damgasını epoch ms'e çevirir; okunamıyorsa `null`.
function zamanMs(v: string | null | undefined): number | null {
  if (!v) return null;
  const t = new Date(v).getTime();
  return Number.isFinite(t) ? t : null;
}
