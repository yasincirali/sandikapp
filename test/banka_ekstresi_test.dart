import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_ice_aktarma.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_tablosu.dart';
import 'package:portfoy_takip/services/ekstre/fon_adi.dart';
import 'package:portfoy_takip/services/ekstre/mevduat_tablosu.dart';
import 'package:portfoy_takip/services/ekstre/tablo_okuyucular.dart';

/// Banka varlık ekstresi (2026-10-03, DenizBank "Varlık Ekstresi" PDF'i).
///
/// Kullanıcı: *"Sadece yatırım ve vadeli mevduatlar içeride olmalı,
/// yatırım kategorisindekiler içeri aktarılmalı."* Fonlar KODSUZ, adla
/// yazılır (çoğu kesik); vadeli mevduat sözleşmesinin tamamı tablodadır;
/// vadesiz hesap alınmaz. Tablolar gerçek ekstrenin DÜZENİNDE, değerler
/// sentetik (kişisel veri teste girmez). Fon unvanları TEFAS'ın açık
/// listesinden (2026-10-03).
void main() {
  const tefas = [
    (kod: 'IJC', unvan: 'İŞ PORTFÖY YARI İLETKEN TEKNOLOJİLERİ DEĞİŞKEN FON'),
    (
      kod: 'YAY',
      unvan: 'YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE SENEDİ FONU'
    ),
    (kod: 'GOL', unvan: 'GARANTİ PORTFÖY ALTIN KATILIM FONU'),
    (kod: 'DLY', unvan: 'DENİZ PORTFÖY PARA PİYASASI (TL) FONU'),
    (kod: 'DNP', unvan: 'DENİZ PORTFÖY PARA PİYASASI KATILIM SERBEST (TL) FON'),
    (kod: 'DCB', unvan: 'DENİZ PORTFÖY PARA PİYASASI SERBEST (TL) FON'),
  ];

  group('fon adı → TEFAS kodu', () {
    test('kesik ad unvanın kelime öneki: tek aday → kod', () {
      expect(
          fonKoduBul(
              'YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE', tefas),
          'YAY');
      // "FON" ↔ "FONU", büyük/küçük ve Türkçe harf, parantez önemsiz.
      expect(fonKoduBul('Deniz Portföy Para Piyasası (TL) Fonu', tefas), 'DLY');
      expect(fonKoduBul('Garanti Portföy Altın Katılım Fon', tefas), 'GOL');
    });

    test('birebir unvan, onu önek sayan uzun unvanlara karşı kazanır', () {
      expect(
          fonKoduBul('İŞ PORTFÖY YARI İLETKEN TEKNOLOJİLERİ DEĞİŞKEN FON', [
            ...tefas,
            (
              kod: 'XXX',
              unvan:
                  'İŞ PORTFÖY YARI İLETKEN TEKNOLOJİLERİ DEĞİŞKEN FON SERBEST'
            ),
          ]),
          'IJC');
    });

    test('belirsiz ya da eşleşmeyen ad tahmin edilmez', () {
      // Üç Deniz para piyasası fonunun ortak öneki.
      expect(fonKoduBul('DENİZ PORTFÖY PARA PİYASASI', tefas), isNull);
      expect(fonKoduBul('BİLİNMEYEN PORTFÖY FONU', tefas), isNull);
    });

    test('sondaki ISIN ("---TR…") ad anahtarına girmez', () {
      expect(
          fonAdiAnahtari(
              'Deniz Portföy Para Piyasası (TL) Fonu---TRMDLYWWWWW9'),
          'deniz portfoy para piyasasi tl fonu');
    });
  });

  // Gerçek ekstrenin sayfa 2 düzeni (PDF geometrisinden çıkan bloklar).
  const vadesiz = EkstreTablosu(kaynak: 'PDF', satirlar: [
    [
      'Hesap Numarası',
      'Para Birimi',
      'Bakiye',
      'Kmh Limiti',
      'Bloke Tutarı',
      'Kaptan Hesap Bakiyesi (*)',
      'Kullanılabilir Bakiye (**)'
    ],
    ['1111-2222-351', 'TL', '1,000.00', '', '', '5,000.00', '5,000.00'],
    ['1111-2222-353', 'TL', '250.00', '', '', '', '250.00'],
  ]);
  const vadeli = EkstreTablosu(kaynak: 'PDF', satirlar: [
    [
      'Hesap Numarası',
      'Vade',
      'Vade Başlangıcı',
      'Vade Sonu',
      'Para Birimi',
      'Brüt Faiz Oranı %',
      'Bloke Tutarı',
      'Bakiye',
      'Kullanılabilir Bakiye'
    ],
    [
      '1111-2222-354',
      '32',
      '01/05/2026',
      '02/06/2026',
      'TL',
      '45.25',
      '',
      '50,000.00',
      '50,000.00'
    ],
    [
      '1111-2222-356',
      '32',
      '01/05/2026',
      '02/06/2026',
      'USD',
      '3.00',
      '',
      '1,000.00',
      '1,000.00'
    ],
  ]);
  const fonlar = EkstreTablosu(kaynak: 'PDF', satirlar: [
    ['', '', '', 'YATIRIM FONLARI', '', '', ''],
    [
      'Yatırım Fonu İsmi',
      'Pay Adedi',
      'Birim Fiyat',
      'Bloke Adedi',
      'Para Birimi',
      'Bakiye',
      'Kullanılabilir Bakiye'
    ],
    [
      'İŞ PORTFÖY YARI İLETKEN TEKNOLOJİLERİ DEĞİŞKEN FON',
      '1,000.00',
      '17.0000',
      '',
      'TL',
      '17,000.00',
      '17,000.00'
    ],
    [
      'YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE',
      '10.00',
      '1700.5000',
      '',
      'TL',
      '17,005.00',
      '17,005.00'
    ],
    [
      'BİLİNMEYEN PORTFÖY KARMA FON',
      '100.00',
      '2.0000',
      '',
      'TL',
      '200.00',
      '200.00'
    ],
  ]);
  const metin = 'DenizBank A.Ş.\nVarlık Ekstresi\n'
      'Hesap Özeti Dönemi 01/05/2026 - 31/05/2026\n'
      '31/05/2026 tarihi itibariyle varlıklarınızın dağılımı\n'
      'YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE\n'
      'Denizbank A.Ş.| Genel Müdürlük';

  EkstreOkumaSonucu oku() =>
      ekstreyiAnla(EkstreBicimi.pdf, [vadesiz, vadeli, fonlar], metin);

  group('banka varlık ekstresi', () {
    test('fon tablosu adla tanımlı; "Bakiye" adet sanılmaz', () {
      final a = oku().ana!;
      expect(a.adlaTanimli, isTrue);
      expect(a.basliklar[a.roller[EkstreRol.adet]!], 'Pay Adedi');
      expect(a.basliklar[a.roller[EkstreRol.fiyat]!], 'Birim Fiyat');
    });

    test(
        'çözülen fonlar ekstre tarihiyle, fon türüyle gelir; çözülmeyen girmez',
        () {
      final s = oku().kodlarla(tefas);
      final r = CsvImportService.parse(s.kanonikMetin(),
          today: DateTime(2026, 10, 3));
      expect(r.errors, isEmpty);
      expect(r.rows.map((x) => (x.type, x.ticker, x.quantity, x.price)), [
        (AssetType.fon, 'TEFAS:IJC', 1000.0, 17.0),
        (AssetType.fon, 'TEFAS:YAY', 10.0, 1700.5),
      ]);
      // Tarih sütunu yok: bugün değil, "31/05/2026 tarihi itibariyle".
      expect(r.rows.every((x) => x.addedDate == DateTime(2026, 5, 31)), isTrue);
      expect(s.cozulemeyenFonlar, ['BİLİNMEYEN PORTFÖY KARMA FON']);
    });

    test('fon listesi yoksa hiçbir adlı satır sembol diye geçmez', () {
      // "GARANTİ PORTFÖY ALTIN…" çözülmeden geçseydi tür çıkarımı onu gram
      // altın sanardı.
      final r = CsvImportService.parse(oku().kanonikMetin());
      expect(r.rows, isEmpty);
    });

    test('yalnız TL vadeli mevduat alınır; vadesiz hiç alınmaz', () {
      final s = oku();
      expect(s.kurum, 'DenizBank');
      expect(s.mevduatlar, hasLength(1));
      final m = s.mevduatlar.single;
      expect((m.baslangic, m.vadeSonu, m.yillikFaiz, m.anapara, m.vadeGun),
          (DateTime(2026, 5, 1), DateTime(2026, 6, 2), 45.25, 50000.0, 32));
      expect(s.notlar.single, contains('USD'));
    });

    test('mevduat sepet kalemi sözleşmesini taşır', () {
      final k = oku().mevduatKalemleri().single;
      expect(k.type, AssetType.mevduat);
      expect(k.quantity, 50000);
      expect(k.addedDate, DateTime(2026, 5, 1));
      expect(k.mevduat, (
        kurum: 'DenizBank',
        yillikFaiz: 45.25,
        stopaj: 17.5, // 32 gün ≤ 6 ay, 2025-07-09 kararı
        vadeGun: 32,
      ));
    });
  });

  group('belge bilgisi', () {
    test('"itibariyle" tarihi; yoksa dönem sonu; yoksa null', () {
      expect(belgeTarihiBul('31.08.2026 tarihi itibarıyla varlıklarınızın'),
          DateTime(2026, 8, 31));
      expect(belgeTarihiBul('Hesap Özeti Dönemi 01/05/2026 - 31/05/2026'),
          DateTime(2026, 5, 31));
      expect(belgeTarihiBul('Portföy Dökümü'), isNull);
    });

    test('banka: belgede en çok geçen (fon adındaki başka banka değil)', () {
      expect(bankaAdiBul(metin), 'DenizBank');
      expect(bankaAdiBul('Portföy Dökümü'), isNull);
    });
  });
}
