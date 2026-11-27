// Canlı Etkinlik'in kullanıcı seçimli push sıklığı (27 Kas 2026; istemci
// `lib/services/yenileme_sikligi.dart`).
//
// İstemci özete `yenilemeDk` yazar (5, 15 ya da 30); alan yoksa satır
// bugünkü ritimde kalır (tarifli her dakika, tarifsiz 5 dakikada bir).
// Eski istemci alanı hiç yazmaz, yani davranışı birebir aynı. Tanınmayan
// değer (1, eksi, 7 gibi) yok sayılır: seyrekleştirme yalnız bilinen
// seçeneklerde, beklenmedik değer kilit ekranını dondurmasın.

const SECENEKLER = new Set([5, 15, 30]);

/// Bu dakika bu satır push'lanmadan geçilmeli mi?
export function yenilemeAtlanir(
  row: Record<string, unknown>,
  simdi: Date,
): boolean {
  const dk = Number(row.yenilemeDk);
  if (!SECENEKLER.has(dk)) return false;
  return simdi.getUTCMinutes() % dk !== 0;
}
