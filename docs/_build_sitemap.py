"""
docs/sitemap.xml üreticisi (GitHub Pages, https://yasincirali.github.io/sandikapp/).

Run from repo root:
    python docs/_build_sitemap.py
`docs/_build_legal.py` sonunda bunu da çağırır: yasal sayfa eklenince/kalkınca
site haritası aynı koşuda yenilenir.

## Neden elle değil, diskten (2026-10-26)
Adres listesi elle yazılırsa yeni sayfa haritaya girmez ya da kalkmış sayfa
404 olarak Search Console'a gider. Betik `docs/**/index.html` dosyalarını
tarar; haritada yalnız gerçekten var olan sayfa olur. Kilit:
`test/web_paylasim_test.dart` (haritadaki her adres dosyaya karşılık gelir,
dizinlenebilir her sayfa haritadadır).

## Neler girmez
- `noindex` taşıyan sayfa (`docs/indir/`): yönlendirme kapısıdır, arama
  sonucunda yeri yok. Haritaya girerse Search Console "Gönderilen URL'de
  noindex var" hatası verir; ikisi birbiriyle çelişmesin diye betik
  `noindex`'i okuyup atlar.
- `docs/archive/` ve `_` ile başlayan klasörler: iç belge, yayın sayfası değil.

## lastmod yok
Bilerek yazılmıyor. Dosya tarihinden üretilirse her koşuda (checkout zamanı)
değişir ve harita sahte "güncellendi" sinyali verir; Google tutarsız
lastmod'u yok sayar. Çıktı deterministik kalsın ki testte kıyaslanabilsin.
"""

from pathlib import Path

DOCS = Path(__file__).resolve().parent
TABAN = "https://yasincirali.github.io/sandikapp/"
ATLA = {"archive"}


def sayfalar() -> list[str]:
    """Dizinlenebilir sayfaların TABAN'a göre yolu ("" = ana sayfa), sıralı."""
    sonuc = []
    for html in DOCS.rglob("index.html"):
        goreli = html.relative_to(DOCS)
        parcalar = goreli.parts[:-1]
        if any(p in ATLA or p.startswith((".", "_")) for p in parcalar):
            continue
        metin = html.read_text(encoding="utf-8").lower()
        if 'name="robots"' in metin and "noindex" in metin:
            continue
        sonuc.append("".join(f"{p}/" for p in parcalar))
    # Ana sayfa önce, sonra alfabetik: diff'ler okunur kalsın.
    return sorted(sonuc, key=lambda y: (y != "", y))


def uret() -> str:
    satirlar = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        "<!-- ÜRETİLDİ: python docs/_build_sitemap.py — elle düzenleme. -->",
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ]
    for yol in sayfalar():
        satirlar.append(f"  <url><loc>{TABAN}{yol}</loc></url>")
    satirlar.append("</urlset>")
    return "\n".join(satirlar) + "\n"


def yaz() -> Path:
    cikti = DOCS / "sitemap.xml"
    # newline="\n": Windows'ta CRLF yazılmasın (bkz. _build_legal.yaz).
    with open(cikti, "w", encoding="utf-8", newline="\n") as f:
        f.write(uret())
    return cikti


if __name__ == "__main__":
    yol = yaz()
    print(f"  -> docs/{yol.name} ({len(sayfalar())} sayfa)")
