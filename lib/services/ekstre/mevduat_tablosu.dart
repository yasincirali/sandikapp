import '../../utils/tr_katla.dart';
import 'ekstre_tablosu.dart';
import 'tablo_anlama.dart';

/// Banka ekstresindeki VADELİ mevduat — SAF, ağ yok.
///
/// ## Kapsam (kullanıcı kararı, 2026-10-03)
/// *"Sadece yatırım ve vadeli mevduatlar içeride olmalı."* Vadesiz hesap
/// bir yatırım değil, harcama hesabıdır; içe aktarılmaz. Vadeli tablo
/// sözleşmenin TAMAMINI verir (başlangıç, vade sonu, brüt faiz, anapara) —
/// uygulamanın mevduatı fiyatlamak için istediği tam da bu
/// (`SozlesmeNotifier.mevduatAc`). Eksik alanlı satır alınmaz: faiz ya da
/// vade olmadan birim değer hesaplanamaz, uydurulmaz.
///
/// Tanıma başlıktan: bir satırda "vade sonu" (ya da "vade bitiş"/"vade
/// tarihi") + "faiz" + bakiye/anapara/tutar. Vadesiz tablonun başlığında
/// vade sonu yoktur; ayrıca dışlamaya gerek kalmaz.
class EkstreMevduati {
  const EkstreMevduati({
    required this.hesap,
    required this.baslangic,
    required this.vadeSonu,
    required this.yillikFaiz,
    required this.anapara,
  });

  /// Hesap numarası ya da tablodaki ilk metin (görünen ad için).
  final String hesap;
  final DateTime baslangic;
  final DateTime vadeSonu;

  /// Yıllık brüt faiz, yüzde (43,5 = %43,5).
  final double yillikFaiz;
  final double anapara;

  int get vadeGun => vadeSonu.difference(baslangic).inDays;
}

/// Tablolardaki vadeli mevduat satırları ve atlananların nedenleri.
({List<EkstreMevduati> mevduatlar, List<String> notlar}) vadeliMevduatlar(
  List<EkstreTablosu> tablolar,
) {
  final out = <EkstreMevduati>[];
  final notlar = <String>[];
  for (final t in tablolar) {
    final s = t.satirlar;
    for (var b = 0; b < s.length; b++) {
      final k = [for (final h in s[b]) _norm(h)];
      final vadeSonu = _sutun(
        k,
        (h) =>
            h == 'vade sonu' ||
            h == 'vade bitis' ||
            h.startsWith('vade bitis') ||
            h == 'vade tarihi' ||
            h == 'vade sonu tarihi',
      );
      final faiz = _sutun(k, (h) => h.contains('faiz'));
      // "Bakiye" "Kullanılabilir Bakiye"den önce: kullanılabilir bakiye
      // blokeyi düşer, anapara değildir.
      final tutar = _sutun(k, (h) => h == 'bakiye' || h == 'anapara') ??
          _sutun(k, (h) => h == 'tutar' || h == 'vadeli bakiye');
      if (vadeSonu == null || faiz == null || tutar == null) continue;
      final baslangic = _sutun(
        k,
        (h) => h.contains('baslangic') || h.contains('acilis') || h == 'valor',
      );
      final gun = _sutun(
        k,
        (h) => h == 'vade' || h == 'gun' || h == 'vade gun',
      );
      final para = _sutun(k, (h) => h == 'para birimi' || h == 'doviz cinsi');
      // Sayı biçimi tablonun kendi kanıtından ("72,210.52" İngilizce).
      final turkce = sayiStiliTurkceMi([
        for (final r in s.skip(b + 1))
          for (final c in [faiz, tutar])
            if (c < r.length) r[c],
      ]);
      for (final r in s.skip(b + 1)) {
        String h(int? c) => c == null || c >= r.length ? '' : r[c].trim();
        final son = tarihCoz(h(vadeSonu));
        if (son == null) {
          // Veri bitti (dipnot, sonraki tablo) — boş satırı atla, gerisinde dur.
          if (r.every((x) => x.trim().isEmpty)) continue;
          break;
        }
        final pb = trKatla(h(para));
        if (pb.isNotEmpty && pb != 'tl' && pb != 'try' && pb != 'ytl') {
          // v1'de döviz mevduatı yok (AssetType.mevduat TL).
          notlar.add(
            '${h(0)}: ${h(para)} vadeli hesap alınmadı '
            '(yalnızca TL mevduat destekleniyor).',
          );
          continue;
        }
        final oran = sayiCoz(h(faiz), turkce: turkce);
        final anapara = sayiCoz(h(tutar), turkce: turkce);
        var bas = tarihCoz(h(baslangic));
        final g = int.tryParse(h(gun));
        if (bas == null && g != null) bas = son.subtract(Duration(days: g));
        if (oran == null ||
            oran <= 0 ||
            anapara == null ||
            anapara <= 0 ||
            bas == null ||
            !bas.isBefore(son)) {
          notlar.add(
            '${h(0)}: vadeli hesabın faiz, vade ya da tutarı '
            'okunamadı; alınmadı.',
          );
          continue;
        }
        out.add(
          EkstreMevduati(
            hesap: h(0),
            baslangic: bas,
            vadeSonu: son,
            yillikFaiz: oran,
            anapara: anapara,
          ),
        );
      }
    }
  }
  return (mevduatlar: out, notlar: notlar);
}

/// Belgenin "itibariyle" tarihi: varlık dökümü O GÜNÜN fotoğrafıdır; tarih
/// sütunu olmayan satırlar bugünün değil bu günün tarihini almalı.
/// "31/05/2026 tarihi itibariyle", "31.08.2026 tarihi itibarıyla"; yoksa
/// "Dönemi 01/05/2026 - 31/05/2026" aralığının sonu. Bulunamazsa `null`.
DateTime? belgeTarihiBul(String metin) {
  final k = trKatla(metin);
  const tarih = r'(\d{1,2}[./]\d{1,2}[./]\d{4})';
  var m = RegExp('$tarih\\s+tarih\\w*\\s+itibar').firstMatch(k);
  m ??= RegExp(
    'donem\\w*\\s*:?\\s*\\d{1,2}[./]\\d{1,2}[./]\\d{4}\\s*-\\s*$tarih',
  ).firstMatch(k);
  return m == null ? null : tarihCoz(m.group(1)!);
}

/// Belgedeki banka adı (mevduat sözleşmesinin kurumu). Bilinen bankalar;
/// bulunamazsa `null` — kullanıcı sonra düzenler.
String? bankaAdiBul(String metin) {
  final k = ' ${trKatla(metin)} ';
  const bankalar = <String, String>{
    'denizbank': 'DenizBank',
    'ziraat': 'Ziraat Bankası',
    'is bankasi': 'İş Bankası',
    'isbank': 'İş Bankası',
    'garanti bbva': 'Garanti BBVA',
    'akbank': 'Akbank',
    'yapi kredi': 'Yapı Kredi',
    'halkbank': 'Halkbank',
    'vakifbank': 'VakıfBank',
    'qnb': 'QNB',
    'enpara': 'Enpara',
    'teb': 'TEB',
    'ing': 'ING',
    'fibabanka': 'Fibabanka',
    'sekerbank': 'Şekerbank',
    'odeabank': 'Odeabank',
    'kuveyt turk': 'Kuveyt Türk',
    'albaraka': 'Albaraka',
    'hsbc': 'HSBC',
  };
  // Belgede en çok geçen banka — fon adlarında başka banka geçebilir
  // ("YAPI KREDİ PORTFÖY…" bir DenizBank ekstresinde).
  String? enIyi;
  var enCok = 0;
  for (final e in bankalar.entries) {
    final n = RegExp('\\b${e.key}\\b').allMatches(k).length;
    if (n > enCok) {
      enCok = n;
      enIyi = e.value;
    }
  }
  return enIyi;
}

String _norm(String s) => trKatla(
      s,
    )
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

int? _sutun(List<String> basliklar, bool Function(String) uyar) {
  for (var i = 0; i < basliklar.length; i++) {
    if (uyar(basliklar[i])) return i;
  }
  return null;
}
