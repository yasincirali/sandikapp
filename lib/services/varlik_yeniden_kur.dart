/// "Varlığı güncelle"nin çekirdeği (bkz. `widgets/varlik_guncelle.dart`).
///
/// Silme + yeniden ekleme, ekleme düşerse silme geri alınır.
///
/// SAF orkestrasyon: Supabase'siz test edilebilsin diye üç adım dışarıdan
/// verilir (`PortfolioNotifier.pozisyonuYenidenKur` gerçeklerini bağlar).
/// Sıra bilerek "önce sil": ücretsiz sınır dolu kullanıcı varlığını
/// düzeltirken sınıra takılmasın — silinen pozisyon kotadan düşer,
/// yenisi onun yerini alır.
///
/// Geri alma da düşerse asıl hata yine fırlatılır; çağıran defteri
/// sunucudan tazeler, kullanıcı hatayı görür.
Future<void> silVeYenidenEkle<M>({
  required Future<M?> Function() sil,
  required Future<void> Function() ekle,
  required Future<void> Function(M makbuz) geriAl,
  void Function(Object hata, StackTrace st)? geriAlmaHatasi,
}) async {
  final makbuz = await sil();
  try {
    await ekle();
  } catch (_) {
    if (makbuz != null) {
      try {
        await geriAl(makbuz);
      } catch (e, st) {
        geriAlmaHatasi?.call(e, st);
      }
    }
    rethrow;
  }
}
