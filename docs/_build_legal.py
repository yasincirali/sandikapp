"""
Legal + landing HTML builder for GitHub Pages (docs/).

Reads Markdown files from legal/ and store_listing/, wraps them in the shared
Sandık-branded HTML layout, and writes them into docs/ at the URL paths
referenced by app/legal docs.

Run from repo root:
    python docs/_build_legal.py
"""
from pathlib import Path
import markdown

ROOT = Path(__file__).parent.parent
DOCS = ROOT / "docs"
LEGAL = ROOT / "legal"

# Layout ─ tek CSS, marka renkleri (Sandık amber/gold/dark), mobile-first.
LAYOUT = """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} — sandık</title>
<meta name="description" content="{desc}">
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
{body}
<footer>
  sandık — <a href="/sandikapp/">Ana Sayfa</a> · <a href="/sandikapp/privacy">Gizlilik</a> · <a href="/sandikapp/terms">Kullanım</a> · <a href="/sandikapp/data-deletion">Hesap Silme</a>
</footer>
</div>
</body>
</html>
"""

def build(md_path: Path, out_path: Path, title: str, subtitle: str, desc: str, lang: str = "tr"):
    src = md_path.read_text(encoding="utf-8")
    html_body = markdown.markdown(src, extensions=["tables", "fenced_code"])
    html = LAYOUT.format(
        title=title, subtitle=subtitle, desc=desc, body=html_body, lang=lang,
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")
    print(f"  -> {out_path.relative_to(ROOT)}")

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

print("Building legal pages...")
for src, out, title, subtitle, desc, lang in pages:
    build(src, out, title, subtitle, desc, lang)

# ── Landing page + favicon: BU BETİK YAZMAZ (2026-10-01) ────────────────────
# `docs/index.html` ve `docs/favicon.svg` elle bakılır. Eskiden betik ikisini
# de kendi içindeki şablondan yeniden basıyordu; şablon eskimişti (akıllı
# bant, mağaza düğmesi, güncel özellikler yoktu) ve betiği koşan herkes ana
# sayfayı sessizce geriletiyordu (TECHNICAL_DEBT, KAPANDI). Favicon da
# gerçek logo yerine "S" harfiydi; artık `assets/images/sandik_logo.svg`'den.

print("\nDone. To serve locally: python -m http.server 8000 --directory docs")
print("GitHub Pages settings: Source = main branch / docs folder")
