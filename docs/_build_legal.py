"""
Legal HTML builder for GitHub Pages (docs/) + uygulama içi yasal belge kaynağı.

Reads Markdown files from legal/, wraps them in the shared Sandık-branded HTML
layout, and writes them into docs/ at the URL paths referenced by app/legal
docs. Ayrıca uygulamanın gösterdiği belgelerin kanonik metnini
`lib/config/yasal_belge_kaynaklari.g.dart`'a yazar.

Run from repo root:
    python docs/_build_legal.py

## Tek kaynak (kullanıcı kararı 2026-10-04: "Webdekiyle de her zaman eşleyelim")
`legal/tr/*.md` (ve çevirisi `legal/en/*.md`) hem web'in hem uygulamanın tek
kaynağıdır. Bu betik İKİ çıktıyı birden üretir:
  1. docs/**/index.html — yer tutucular web'in ifadesiyle doldurulur;
  2. lib/config/yasal_belge_kaynaklari.g.dart — uygulamadaki belgelerin
     ŞABLON hâli (yer tutucular doldurulmadan). Uygulama ülkeyi bağlı
     sunucudan doldurur; veritabanındaki `govde_hash` bu şablonun sha256'sıdır.
Her HTML başlığına kaynak md'nin hash'i (`sandik-kaynak-sha256`) ve sayfa
gövdesinin hash'i (`sandik-govde-sha256`) gömülür. `test/yasal_web_esleme_test`
ikisini de doğrular: md değişip betik koşulmazsa ya da HTML elle düzenlenirse
CI kırılır. Uygulama belgelerinde `sandik-kaynak-sha256` == veritabanındaki
`govde_hash`: web sayfası ile onaylanan metin aynı kimliği taşır.

## Kanonik metin
BOM atılır, satır sonu LF, dosya sonundaki boşluk kırpılır. Dart tarafındaki
eşi `YasalBelge.kanonik` (lib/services/yasal_belge.dart) — biri değişirse
öteki de; değişmesi BÜTÜN hash'leri değiştirir (yeni sürüm demektir).
BOM'un atılması web'deki bir hatayı da kapattı (2026-10-04): BOM'lu md'lerde
ilk satır başlık olarak tanınmıyor, sayfa "# Kullanım Koşulları — sandık"
diye düz paragrafla başlıyordu.
"""
import hashlib
import re
from pathlib import Path

import markdown

ROOT = Path(__file__).parent.parent
DOCS = ROOT / "docs"
LEGAL = ROOT / "legal"
DART_CIKTI = ROOT / "lib" / "config" / "yasal_belge_kaynaklari.g.dart"

# Uygulamanın gösterdiği belgeler — `YasalBelge` (lib/services/yasal_belge.dart)
# ile aynı liste; test ikisini karşılaştırır. İngilizce belgeler uygulamada
# gösterilmez (gerekçe: yasal_metin_katalogu.dart → "İngilizce").
UYGULAMA_BELGELERI = [
    "legal/tr/TERMS_OF_SERVICE.md",
    "legal/tr/PRIVACY_POLICY.md",
    "legal/tr/KVKK_AYDINLATMA_METNI.md",
    "legal/tr/ACIK_RIZA_METNI.md",
]

# Web'de yer tutucuların değeri. Uygulama aynı yer tutucuyu bağlı sunucunun
# ülkesiyle doldurur (`LegalDocs.yerTutucuDegerleri`). Web hangi sunucuya
# bağlı olunduğunu bilemez → iki sunucunun gerçek durumunu yazar (Tokyo
# canlıda, Frankfurt'a taşınma sürecinde). Taşınma bitince YALNIZ burası
# değişir; md şablonu ve veritabanındaki metin sürümü aynı kalır.
YER_TUTUCULAR = {
    "tr": {
        "SUPABASE_ULKE": "Japonya (AWS Tokyo); Almanya'ya (AWS Frankfurt, AB) taşınma sürecinde",
        "SUPABASE_ULKEDE": "Japonya'da (AWS Tokyo; Almanya'ya — AWS Frankfurt, AB — taşınma sürecinde)",
    },
    "en": {
        "SUPABASE_ULKE": "Japan (AWS Tokyo); migrating to Germany (AWS Frankfurt, EU)",
        "SUPABASE_ULKEDE": "in Japan (AWS Tokyo; migrating to Germany — AWS Frankfurt, EU)",
    },
}
_YER_TUTUCU = re.compile(r"\{SUPABASE_[A-Z_]+\}")

GOVDE_BASLA = "<!-- sandik-govde:basla -->"
GOVDE_BITTI = "<!-- sandik-govde:bitti -->"


def kanonik(md_text: str) -> str:
    """BOM yok, LF, sondaki boşluk kırpılmış — Dart `YasalBelge.kanonik` eşi."""
    return md_text.lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n").rstrip()


def sha256(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def doldur(sablon: str, lang: str, kaynak: str) -> str:
    degerler = YER_TUTUCULAR.get(lang, {})
    for ad, deger in degerler.items():
        sablon = sablon.replace("{" + ad + "}", deger)
    kalan = _YER_TUTUCU.findall(sablon)
    if kalan:
        raise SystemExit(f"{kaynak}: doldurulmamış yer tutucu {sorted(set(kalan))} "
                         f"(YER_TUTUCULAR['{lang}']'a ekle)")
    return sablon


def yaz(yol: Path, metin: str) -> None:
    # newline="\n": Windows'ta write_text CRLF yazardı; gövde hash'i LF
    # üzerinden alınır (test de CRLF'i LF'e çevirip okur).
    yol.parent.mkdir(parents=True, exist_ok=True)
    with open(yol, "w", encoding="utf-8", newline="\n") as f:
        f.write(metin)


# Layout ─ tek CSS, marka renkleri (Sandık amber/gold/dark), mobile-first.
LAYOUT = """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} — sandık</title>
<meta name="description" content="{desc}">
<meta name="sandik-kaynak" content="{kaynak}">
<meta name="sandik-kaynak-sha256" content="{kaynak_hash}">
<meta name="sandik-govde-sha256" content="{govde_hash}">
<link rel="icon" href="/sandikapp/favicon.svg" type="image/svg+xml">
<style>
:root {{
  --bg: #0A1E15;
  --surface: #10281E;
  --surface-2: #1A3D2E;
  --border: rgba(255,255,255,0.06);
  --text: rgba(255,255,255,0.90);
  --text-58: rgba(255,255,255,0.58);
  --text-36: rgba(255,255,255,0.36);
  --amber: #F5A623;
  --gold: #F5C842;
  --gain: #6BB77B;
  --loss: #E86A5E;
}}
* {{ box-sizing: border-box; }}
html, body {{ margin: 0; padding: 0; background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'DM Sans', sans-serif; line-height: 1.6; }}
.container {{ max-width: 720px; margin: 0 auto; padding: 24px 20px 64px; }}
header {{ display: flex; align-items: center; gap: 12px; padding: 20px 0 32px; border-bottom: 1px solid var(--border); margin-bottom: 32px; }}
header .logo {{ width: 40px; height: 40px; background: linear-gradient(135deg, var(--gold), var(--amber)); border-radius: 10px; display: flex; align-items: center; justify-content: center; font-weight: 900; color: #0A1E15; font-size: 20px; }}
header .brand {{ font-size: 22px; font-weight: 800; letter-spacing: -0.5px; }}
header .brand small {{ font-size: 12px; color: var(--text-58); font-weight: 500; display: block; letter-spacing: 0; }}
h1 {{ font-size: 28px; font-weight: 800; letter-spacing: -0.5px; margin: 0 0 8px; }}
h2 {{ font-size: 20px; font-weight: 700; margin: 32px 0 12px; color: var(--gold); }}
h3 {{ font-size: 16px; font-weight: 700; margin: 20px 0 8px; color: var(--text); }}
p, li {{ font-size: 15px; }}
a {{ color: var(--amber); text-decoration: none; }}
a:hover {{ text-decoration: underline; }}
code {{ background: var(--surface); padding: 2px 6px; border-radius: 4px; font-size: 13px; font-family: 'Fira Code', 'Consolas', monospace; }}
pre {{ background: var(--surface); padding: 16px; border-radius: 8px; overflow-x: auto; border: 1px solid var(--border); }}
pre code {{ background: transparent; padding: 0; }}
blockquote {{ border-left: 3px solid var(--amber); padding: 8px 14px; margin: 16px 0; background: rgba(245,166,35,0.06); border-radius: 0 6px 6px 0; color: var(--text); }}
hr {{ border: 0; height: 1px; background: var(--border); margin: 32px 0; }}
table {{ width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 14px; }}
th, td {{ padding: 10px 12px; text-align: left; border-bottom: 1px solid var(--border); }}
th {{ background: var(--surface); font-weight: 700; color: var(--gold); }}
tr:hover td {{ background: rgba(255,255,255,0.02); }}
ul, ol {{ padding-left: 20px; }}
li {{ margin: 6px 0; }}
footer {{ margin-top: 48px; padding-top: 24px; border-top: 1px solid var(--border); text-align: center; font-size: 12px; color: var(--text-36); }}
footer a {{ color: var(--text-58); margin: 0 8px; }}
input[type="text"], input[type="email"], textarea {{ width: 100%; padding: 10px 12px; background: var(--surface); border: 1px solid var(--border); border-radius: 6px; color: var(--text); font-family: inherit; font-size: 14px; }}
input:focus, textarea:focus {{ outline: none; border-color: var(--amber); }}
button {{ background: var(--amber); color: #0A1E15; border: 0; padding: 12px 24px; border-radius: 8px; font-size: 15px; font-weight: 700; cursor: pointer; }}
button:hover {{ opacity: 0.9; }}
.checkbox-row {{ display: flex; align-items: flex-start; gap: 10px; margin: 12px 0; font-size: 14px; color: var(--text-58); }}
.checkbox-row input {{ width: auto; margin-top: 3px; }}
</style>
</head>
<body>
<div class="container">
<header>
  <div class="logo">S</div>
  <div class="brand">sandık<small>{subtitle}</small></div>
</header>
""" + GOVDE_BASLA + """
{body}
""" + GOVDE_BITTI + """
<footer>
  sandık — <a href="/sandikapp/">Ana Sayfa</a> · <a href="/sandikapp/privacy">Gizlilik</a> · <a href="/sandikapp/terms">Kullanım</a> · <a href="/sandikapp/data-deletion">Hesap Silme</a>
</footer>
</div>
</body>
</html>
"""


def build(md_path: Path, out_path: Path, title: str, subtitle: str, desc: str, lang: str = "tr"):
    kaynak = md_path.relative_to(ROOT).as_posix()
    sablon = kanonik(md_path.read_text(encoding="utf-8"))
    html_body = markdown.markdown(doldur(sablon, lang, kaynak), extensions=["tables", "fenced_code"])
    html = LAYOUT.format(
        title=title, subtitle=subtitle, desc=desc, body=html_body, lang=lang,
        kaynak=kaynak, kaynak_hash=sha256(sablon), govde_hash=sha256(html_body),
    )
    yaz(out_path, html)
    print(f"  -> {out_path.relative_to(ROOT).as_posix()}")


def dart_yaz():
    """Uygulama belgelerinin şablon hâli → const Dart (elle düzenlenmez)."""
    satirlar = [
        "// ÜRETİLDİ — elle düzenleme. Kaynak: legal/tr/*.md; üreten:",
        "// `python docs/_build_legal.py`. Kayma kilidi: test/yasal_web_esleme_test.dart.",
        "//",
        "// Değerler md'nin KANONİK hâlidir (BOM yok, LF, sondaki boşluk kırpılmış;",
        "// yer tutucular doldurulmamış). Veritabanındaki `govde` ve `govde_hash`",
        "// bu metinlerdir (`YasalMetinKatalogu`).",
        "",
        "/// Uygulamada gösterilen yasal belgelerin kanonik md metni — anahtar",
        "/// depo köküne göre kaynak yolu.",
        "const yasalBelgeKaynaklari = <String, String>{",
    ]
    for yol in UYGULAMA_BELGELERI:
        metin = kanonik((ROOT / yol).read_text(encoding="utf-8"))
        if "'''" in metin or metin.endswith("'"):
            raise SystemExit(f"{yol}: ''' içeremez / ' ile bitemez (Dart ham dizgisi)")
        satirlar.append(f"  '{yol}': r'''{metin}''',")
    satirlar.append("};")
    yaz(DART_CIKTI, "\n".join(satirlar) + "\n")
    print(f"  -> {DART_CIKTI.relative_to(ROOT).as_posix()}")


# ── Legal HTML pages ────────────────────────────────────────────────────────
pages = [
    # (source, output, title, subtitle, description, lang)
    (LEGAL / "tr/PRIVACY_POLICY.md",       DOCS / "privacy/index.html",      "Gizlilik Politikası",       "Gizlilik Politikası",      "Sandık uygulamasının gizlilik politikası — KVKK ve GDPR uyumlu.", "tr"),
    (LEGAL / "en/PRIVACY_POLICY.md",       DOCS / "privacy-en/index.html",   "Privacy Policy",            "Privacy Policy",           "Sandık app privacy policy — GDPR compliant.", "en"),
    (LEGAL / "tr/TERMS_OF_SERVICE.md",     DOCS / "terms/index.html",        "Kullanım Koşulları",        "Kullanım Koşulları",       "Sandık uygulamasının kullanım koşulları.", "tr"),
    (LEGAL / "en/TERMS_OF_SERVICE.md",     DOCS / "terms-en/index.html",     "Terms of Service",          "Terms of Service",         "Sandık app terms of service.", "en"),
    (LEGAL / "tr/KVKK_AYDINLATMA_METNI.md",DOCS / "legal/kvkk/index.html",   "KVKK Aydınlatma Metni",    "KVKK",                     "KVKK Madde 10 aydınlatma yükümlülüğü.", "tr"),
    (LEGAL / "en/GDPR_NOTICE.md",          DOCS / "legal/gdpr/index.html",   "GDPR Notice",               "GDPR",                     "GDPR notice for EU/EEA users of Sandık.", "en"),
    (LEGAL / "tr/ACIK_RIZA_METNI.md",      DOCS / "legal/acik-riza/index.html","Açık Rıza Metni",         "Açık Rıza",                "KVKK Madde 5(1) ve 9(1) yurt dışı aktarım açık rıza metni.", "tr"),
    (LEGAL / "tr/COKEZ_VE_DEPOLAMA.md",    DOCS / "legal/depolama/index.html","Çerezler ve Yerel Depolama","Depolama",               "Yerel depolama ve çerez kullanımı bilgilendirmesi.", "tr"),
    (LEGAL / "DATA_DELETION_REQUEST_FORM.md", DOCS / "data-deletion/index.html","Hesap Silme Talebi",    "Hesap Silme",              "Hesap silme talep formu — 30 gün içinde işleme alınır.", "tr"),
    (LEGAL / "DATA_DELETION_REQUEST_FORM.md", DOCS / "data-request/index.html","Data Access Request",   "Data Request",             "Data access/deletion request under GDPR / KVKK.", "en"),
]

if __name__ == "__main__":
    print("Building legal pages...")
    for src, out, title, subtitle, desc, lang in pages:
        build(src, out, title, subtitle, desc, lang)
    print("Writing app legal sources...")
    dart_yaz()

    # ── Landing page + favicon: BU BETİK YAZMAZ (2026-10-01) ────────────────
    # `docs/index.html` ve `docs/favicon.svg` elle bakılır. Eskiden betik ikisini
    # de kendi içindeki şablondan yeniden basıyordu; şablon eskimişti (akıllı
    # bant, mağaza düğmesi, güncel özellikler yoktu) ve betiği koşan herkes ana
    # sayfayı sessizce geriletiyordu (TECHNICAL_DEBT, KAPANDI). Favicon da
    # gerçek logo yerine "S" harfiydi; artık `assets/images/sandik_logo.svg`'den.

    print("\nDone. To serve locally: python -m http.server 8000 --directory docs")
    print("GitHub Pages settings: Source = main branch / docs folder")
