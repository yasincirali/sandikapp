// Her cron fonksiyonu FAIL-CLOSED (2026-10-20 incelemesi).
//
// `cronYetkisiVarMi` secret boşken kontrolü ATLAR (yerel geliştirme için
// bilinçli). Tek başına çağıran yeni bir fonksiyon, secret'ı kaybolmuş bir
// ortamda herkese açık kalır. Kural: `cronYetkisiVarMi` kullanan her
// fonksiyon ondan ÖNCE `cronSecretZorunlu` çağırır. cron_auth_test bunu
// bilinen listeye bakarak denetliyordu; bu test listeye eklenmeyi unutulan
// yeni fonksiyonu da yakalar.
import { assert } from 'jsr:@std/assert@1';

const dizin = new URL('../functions/', import.meta.url);

for await (const e of Deno.readDir(dizin)) {
  if (!e.isDirectory || e.name.startsWith('_')) continue;
  let src: string;
  try {
    src = await Deno.readTextFile(new URL(`${e.name}/index.ts`, dizin));
  } catch {
    continue;
  }
  const yetki = src.indexOf('cronYetkisiVarMi(');
  if (yetki < 0) continue;
  Deno.test(`${e.name}: cron kapısı fail-closed`, () => {
    const zorunlu = src.indexOf('cronSecretZorunlu(');
    assert(zorunlu >= 0, `${e.name} cronSecretZorunlu çağırmıyor (secret yoksa açık kalır)`);
    assert(zorunlu < yetki, `${e.name} cronSecretZorunlu'yu cronYetkisiVarMi'den ÖNCE çağırmalı`);
  });
}
