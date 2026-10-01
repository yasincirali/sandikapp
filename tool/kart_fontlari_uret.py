"""supabase/functions/bildirim-karti/fontlar.ts dosyasını yeniden üretir.

Kart görseli edge function'da çizilir ve DM Sans'ı gömülü base64'ten yükler
(bkz. fontlar.ts başlığı). Yazı tipi değişirse bunu bir kez çalıştır.
"""
import base64
import pathlib

KOK = pathlib.Path(__file__).resolve().parent.parent
BASLIK = [
    "// ÜRETİLMİŞ DOSYA — elle düzenleme. Kaynak: assets/fonts/DMSans-{Bold,Medium}.ttf",
    "// (uygulamanın kendi yazı tipi, SIL OFL 1.1). Kart görseli sunucuda çizilir;",
    "// edge runtime'da sistem yazı tipi yok, dosya okuma da paketlemeye bağlı —",
    "// en sağlam yol yazı tipini modülün içine gömmek (~130 KB).",
    "//",
    "// Yeniden üretmek: python3 tool/kart_fontlari_uret.py",
    "",
]

satirlar = list(BASLIK)
for ad in ("Bold", "Medium"):
    ham = (KOK / "assets" / "fonts" / f"DMSans-{ad}.ttf").read_bytes()
    satirlar.append(f"export const DM_SANS_{ad.upper()} = '{base64.b64encode(ham).decode()}';")
(KOK / "supabase" / "functions" / "bildirim-karti" / "fontlar.ts").write_text("\n".join(satirlar) + "\n")
