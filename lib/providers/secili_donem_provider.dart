import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/period_summary_service.dart' show SummaryPeriod;
import '../services/remote_config_service.dart';

/// Uygulama genelinde TEK seçili dönem (Sadeleştirme 2, `donem_hafizasi`).
///
/// ## Neden
/// Aynı [DonemSecici] beş yüzeyde (Performans, varlık detayı, varlık
/// sayfası, Takip, Karşılaştır) bağımsız durum ve farklı varsayılanlarla
/// çiziliyordu: Performans GÜNLÜK, varlık detayı 1H, varlık sayfası 1Y,
/// Takip 1A, Karşılaştır 3A. Kullanıcı Performans'ta 6A'ya bakıp bir
/// varlığa dokununca 1H görüyor, dönemi her ekranda yeniden seçiyordu.
/// Bayrak açıkken hepsi bu değeri okur ve yazar: bir yüzeyde seçilen dönem
/// ötekini açınca da seçilidir.
///
/// ## Neden yalnızca bellekte
/// `shared_preferences`'a yazılmaz: soğuk açılış her zaman Performans'ın
/// bugünkü varsayılanıyla (GÜNLÜK) başlar. Dönem bir "bakış" durumudur,
/// tercih değil; dün 5Y'de bırakılan ekranın bugün 5Y açılması "bugün ne
/// oldu" sorusunu bir dokunuş uzağa iterdi.
///
/// ## Bayrak kapalıyken
/// Kimse okumaz; her yüzey kendi alanını ve varsayılanını korur (eski
/// davranış birebir). Okumadan önce [donemHafizasiAcik]'a bak.
final seciliDonemProvider =
    StateProvider<SummaryPeriod>((ref) => SummaryPeriod.gunluk);

/// `donem_hafizasi` bayrağı — yüzeyler tek yerden sorar ki bayrak kalkınca
/// arama tek isimle yapılsın.
bool get donemHafizasiAcik => RemoteConfigService.instance.donemHafizasi;

/// [mevcut] içinde [istenen]e EN YAKIN dönem.
///
/// Bir yüzey ortak dönemi gösteremiyorsa (elle fiyatlanan varlıkta GÜNLÜK
/// yok) en yakını gösterir ama ortak değeri DEĞİŞTİRMEZ: kullanıcı oradan
/// Performans'a döndüğünde seçtiği GÜNLÜK'ü bulmalı. Yakınlık enum
/// sırasıyla ölçülür (dönemler kısadan uzuna sıralı); eşitlikte daha uzun
/// dönem seçilir — GÜNLÜK'ün tek komşusu 1H olduğu için GÜNLÜK → 1H.
SummaryPeriod gosterilebilirDonem(
    SummaryPeriod istenen, List<SummaryPeriod> mevcut) {
  assert(mevcut.isNotEmpty);
  if (mevcut.contains(istenen)) return istenen;
  SummaryPeriod? en;
  int? enUzak;
  for (final d in mevcut) {
    final uzak = (d.index - istenen.index).abs();
    if (enUzak == null ||
        uzak < enUzak ||
        (uzak == enUzak && d.index > en!.index)) {
      en = d;
      enUzak = uzak;
    }
  }
  return en!;
}
