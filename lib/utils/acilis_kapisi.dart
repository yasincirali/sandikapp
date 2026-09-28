/// Ekran açılışının "hepsi birden" kapısı.
///
/// ## Karar (kullanıcı, 2026-09-28)
/// *"Sayfalarda kullanılan servisler hızlı çekilecek ve performans olarak
/// tatmin edici halde olmalı; ekranı açtığımda tek tek değil tümden
/// dolmalı."*
///
/// Varlık detayı ve varlık sayfası açılışta birbirinden bağımsız dört beş
/// istek atıyordu (seçili dönem, öteki dönemler, sinyal serisi) ve her biri
/// geldiği an kendi parçasını çiziyordu: önce grafik, sonra çiplerin
/// getirisi birer birer, en son sinyal paneli. Yerleşim açılışta dört beş
/// kez oynuyordu. Artık hepsi AYNI ANDA başlatılır; ekran tek bir iskelet
/// gösterir ve hepsi gelince birlikte çizilir.
///
/// ## Üst sınır
/// Yavaş tek bir kaynak (ör. 5Y haftalık seri) bütün ekranı rehin almasın:
/// [acilisSiniri] dolunca gelenler çizilir, geç kalan kendi yerinde
/// sonradan dolar — boş ekranda beklemekten iyidir. `HistoryService`'in
/// kendi zaman aşımı 8 sn; 3 sn tipik bir açılışın (hepsi paralel,
/// < 1 sn) çok üstünde, kötü bir ağda ise hâlâ katlanılabilir.
///
/// Hata da kapıyı açar: hatayı her parça kendi yerinde söyler ("fiyat
/// geçmişi çekilemedi"), kapı onu yutmaz, yalnızca beklemez.
library;

const acilisSiniri = Duration(seconds: 3);

/// [isler]in hepsi bitince (başarılı ya da hatalı) ya da [sinir] dolunca
/// tamamlanır; asla hata fırlatmaz.
Future<void> acilisKapisi(
  Iterable<Future<Object?>> isler, {
  Duration sinir = acilisSiniri,
}) =>
    Future.wait<void>([
      for (final f in isler) f.then<void>((_) {}, onError: (Object _) {}),
    ]).timeout(sinir, onTimeout: () => const []).then((_) {});
