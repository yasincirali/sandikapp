import 'package:flutter/foundation.dart';

/// Bir varlık ekleme akışı başarıyla bitti — [VarlikEklendi.kanal] olayı.
///
/// [no] her duyuruda artar: aynı pozisyona art arda iki alış da dinleyiciyi
/// tetiklesin (aynı değere yazılan `ValueNotifier` susardı). [anahtar]
/// eklenen pozisyonun `positionKey`'i; toplu eklemede birden çok satır
/// geldiği için `null`.
typedef VarlikEklendiOlayi = ({int no, String? anahtar});

/// "Varlık eklendi" duyurusu — ekleme NEREDEN yapılırsa yapılsın.
///
/// ## Neden (kullanıcı kuralı, TestFlight 2026-10-10)
/// *"Ekleme nereden yapıldıysa yapılsın ekleme bittiğinde portföy tüm
/// portföy gözükecek şekilde açılmalı; son eklenen varlık da odak
/// çizgileriyle odaklanıyor, bu kaçmamış olur."*
///
/// Eskiden yalnız orta tuştan (FAB) açılan ekleme Portföy sekmesine
/// geçiyordu; aramadan, takip listesinden, Karşılaştır'dan, halka arzdan,
/// boş ana ekrandan açılan ekleme kullanıcıyı olduğu yerde bırakıyordu.
/// Portföy'ün tür süzgeci de sıfırlanmıyor, yeni satır süzgecin dışında
/// kalabiliyordu.
///
/// ## Kim ne yapar
/// - Ekleme akışları (tekli form, sözleşmeli form, toplu ekleme) BAŞARIDA
///   [duyur] çağırır — düzenleme ve sepet modu çağırmaz.
/// - `MainNavigationScreen` araya açılmış rotaları kapatır ve Portföy
///   sekmesine geçer.
/// - `PortfolioScreen` süzgeci "Tümü"ye döndürür ve [VarlikEklendiOlayi.anahtar]
///   satırını kaydırıp parlatır.
///
/// Riverpod değil `ValueNotifier`: olay bir durum değil, tek seferlik
/// sinyal; `MainNavigationScreen.sekmeIstegi` ile aynı desen.
abstract final class VarlikEklendi {
  static final kanal = ValueNotifier<VarlikEklendiOlayi?>(null);

  static int _no = 0;

  static void duyur({String? pozisyonAnahtari}) =>
      kanal.value = (no: ++_no, anahtar: pozisyonAnahtari);
}
