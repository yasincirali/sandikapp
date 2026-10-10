// PDF → düz metin (Fon X-Ray Katman A, 0132).
//
// Ayrı dosya: npm bağımlılığı (`unpdf`) yalnız `fon-kalem-raporu`
// yüklenince gelir; saf kontrolleri sınayan Deno testleri bunu içe aktarmaz.
//
// Neden unpdf (2026-10-10 düzeltmesi): ilk sürüm `npm:pdfjs-dist` tam
// paketini içe aktarıyordu; fonksiyon paketi 32 MB oldu ve Supabase
// dağıtımı 413 "request entity too large" ile reddetti (run 38020347414,
// Frankfurt; Tokyo iptal). unpdf aynı PDF.js motorunun sunucusuz ortamlar
// için tek dosyalık derlemesini taşır (paket ~2 MB, pdfjs-dist ~37 MB);
// `getDocumentProxy` aynı `PDFDocumentProxy`'yi döndürür, sayfa/metin
// döngüsü değişmedi. Tarayıcı API'si (DOMMatrix, canvas) gerektirmez.
// Sürüm sabit: yeni ana sürüm API'yi kırabilir. Doğrulama: Türkçe
// karakterli ve "%12,34" biçimli örnek PDF Deno'da okundu.
//
// Metin katmanı olmayan PDF (yazısı vektör çizilmiş — İş Portföy — ya da
// taranmış) boş/kısa metin verir; karar `metinYeterliMi`'de, OCR YOK
// (araştırma: "OCR güvenilmez").

import { getDocumentProxy } from 'npm:unpdf@1.8.1';

/// En çok bu kadar sayfa okunur: portföy tablosu ilk sayfalarda; dev bir
/// ek modeli ve süreyi boşa harcamasın.
export const SAYFA_USTU = 20;

export async function pdfMetni(baytlar: Uint8Array): Promise<string> {
  // `isEvalSupported` seçeneği unpdf derlemesinde yok (eval zaten kapalı).
  const doc = await getDocumentProxy(baytlar, {
    disableFontFace: true,
    useSystemFonts: false,
  });
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
    // unpdf'in belge nesnesinde `destroy()` yok; bellek `cleanup()` ile
    // bırakılır (istek sonunda izole zaten kapanır).
    await doc.cleanup();
  }
}
