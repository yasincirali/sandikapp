// PDF → düz metin (Fon X-Ray Katman A, 0132).
//
// Ayrı dosya: npm bağımlılığı (`pdfjs-dist`) yalnız `fon-kalem-raporu`
// yüklenince gelir; saf kontrolleri sınayan Deno testleri bunu içe aktarmaz.
//
// Neden pdfjs: Deno'da (Supabase Edge Runtime) npm belirteciyle çalışan,
// yerel kütüphane istemeyen tek yaygın PDF okuyucu. `legacy` derlemesi
// tarayıcı API'si (DOMMatrix, Path2D) beklemez; metin çıkarmak için canvas
// gerekmez (yalnız çizim için). Sürüm sabit: yeni ana sürüm API'yi kırabilir.
// 2026-10-10'da BTE Eylül raporu (3 sayfa, 11,6 bin karakter) bununla okundu.
//
// Metin katmanı olmayan PDF (yazısı vektör çizilmiş — İş Portföy — ya da
// taranmış) boş/kısa metin verir; karar `metinYeterliMi`'de, OCR YOK
// (araştırma: "OCR güvenilmez").

import { getDocument } from 'npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs';

/// En çok bu kadar sayfa okunur: portföy tablosu ilk sayfalarda; dev bir
/// ek modeli ve süreyi boşa harcamasın.
export const SAYFA_USTU = 20;

export async function pdfMetni(baytlar: Uint8Array): Promise<string> {
  const doc = await getDocument({
    data: baytlar,
    disableFontFace: true,
    isEvalSupported: false,
    useSystemFonts: false,
  }).promise;
  try {
    let metin = '';
    const n = Math.min(doc.numPages, SAYFA_USTU);
    for (let i = 1; i <= n; i++) {
      const sayfa = await doc.getPage(i);
      const icerik = await sayfa.getTextContent();
      let satir = '';
      for (const it of icerik.items as Array<{ str?: string; hasEOL?: boolean }>) {
        satir += it.str ?? '';
        if (it.hasEOL) {
          metin += satir + '\n';
          satir = '';
        } else {
          satir += ' ';
        }
      }
      metin += satir + '\n';
    }
    return metin;
  } finally {
    await doc.destroy();
  }
}
