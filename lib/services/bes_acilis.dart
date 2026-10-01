import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/sozlesme.dart';
import 'sozlesme_deposu.dart';

/// BES açılışından önceki geçmiş: **düz çizgi** (kullanıcı kararı 2026-10-01).
///
/// ## Neden fon serisinden geriye hesaplanmıyor
/// Kullanıcı *"geçmiş kâr zararımı fon değerlerine göre değil, eklendiği
/// günkü ana para, devlet katkısı ve kârla girdirtip düz çizgi gösterelim;
/// fon dağılımını sık değiştirmiş olabilirim"* dedi. Bugünkü fonların
/// serisini geçmişe uygulamak, o fonlarda hiç durmamış bir birikime uydurma
/// bir tarihçe yazar (fiyat kaynağı sözleşmesi §3: uydurma sayı yasak).
/// Bildiğimiz tek gerçek açılış anındaki birikim ve ana paradır.
///
/// ## Model
///   · Açılış lotları sisteme GİRİŞ tarihiyle yazılır (`besAc`): ana para o
///     gün yatırılmış sayılır, kâr baştan vardır, açılış günü sıçrama ve
///     sahte "piyasa etkisi" oluşmaz. Nakit akışı hesapları (dönem özeti,
///     XIRR) lot tarihini okuduğu için ayrı kural istemez.
///   · Açılış ANINDAN önceki her an lot, açılış anındaki fiyatla
///     değerlenir — bu dosyanın tek kuralı. Açılıştan sonrası fon serisiyle
///     yürür; fon değişikliği (`besFonDegistir`) o günden sonra yeni
///     fonların serisine geçer.
///   · Açılış anı sözleşmenin `created_at`'idir ([Sozlesme.olusturuldu]).
///     Şema değişikliği gerekmedi; eski sürümlerle yazılmış açılış lotları
///     zaten açılış anında tarihli olduğu için kural onlarda etkisizdir.
///
/// Fiyatın nereden okunacağına karar veren tek yer fiyat kaynağıdır; bu
/// kural da BES'e özgü bir "hangi anın fiyatı" kararı olarak oradan
/// çağrılır (`HistoryService` iki seri yolunda).
abstract final class BesAcilis {
  /// [a] bir BES lotuysa sözleşmesinin açılış anı (ms); değilse ya da
  /// sözleşme/an bilinmiyorsa `null` — o zaman kural uygulanmaz (eski yol).
  static int? acilisMs(Asset a, {Sozlesme? Function(String id)? sozlesme}) {
    if (a.type != AssetType.bes) return null;
    final id = a.sozlesmeId;
    if (id == null) return null;
    final s = (sozlesme ?? SozlesmeDeposu.instance.sozlesme)(id);
    return s?.olusturuldu?.millisecondsSinceEpoch;
  }

  /// [a]'nın [ts] anı için fiyatının okunacağı an: açılıştan önceyse
  /// açılış anı, değilse [ts].
  static int fiyatAni(Asset a, int ts,
      {Sozlesme? Function(String id)? sozlesme}) {
    final acilis = acilisMs(a, sozlesme: sozlesme);
    return acilis != null && ts < acilis ? acilis : ts;
  }

  /// Depoda olmayan BES sözleşmeleri (ör. ortağınki) — seri hesabından
  /// önce yüklenir ki ortak görünümü de aynı düz çizgiyi çizsin.
  static Set<String> eksikler(Iterable<Asset> assets) => {
        for (final a in assets)
          if (a.type == AssetType.bes &&
              a.sozlesmeId != null &&
              SozlesmeDeposu.instance.sozlesme(a.sozlesmeId!) == null)
            a.sozlesmeId!,
      };
}
