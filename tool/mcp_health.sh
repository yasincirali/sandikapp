#!/usr/bin/env bash
# MCP sunucu sağlık kontrolü — SessionStart hook'undan çağrılır.
#
# NE YAPAR: `.mcp.json`'daki her sunucunun çalıştırılabilir dosyasının
# yerinde olduğunu ve kod grafiği indeksinin bayat olmadığını denetler.
#
# NE YAPMAZ: sunucuları BAŞLATMAZ. MCP süreçlerini Claude Code'un kendisi
# ayağa kaldırır; buradan ikinci bir kopya spawn etmek codebase-memory gibi
# SQLite kilidi tutan sunucularda çakışma üretir. Bu betik yalnızca RAPOR
# eder — bulduğunu Claude'a bildirir, o da kullanıcıya söyler.
#
# Elle:  bash tool/mcp_health.sh
#
# Çıktı: tek satır JSON (SessionStart hook sözleşmesi).

set -uo pipefail
cd "$(dirname "$0")/.." 2>/dev/null || exit 0

CACHE="$HOME/.cache/codebase-memory-mcp"
PROJE="C-projects-PortfoyTakip"

python - "$CACHE" "$PROJE" <<'PY'
# -*- coding: utf-8 -*-
import json, os, sqlite3, subprocess, sys
from datetime import datetime, timezone

# Windows konsolu cp1254'e düşüp Türkçe karakterleri bozuyor (ş → ?).
# Çıktı JSON olarak Claude'a gidiyor; bozuk kodlama mesajı okunamaz kılar.
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

cache, proje = sys.argv[1], sys.argv[2]
sorunlar, notlar = [], []


def kabuk(*a):
    try:
        return subprocess.run(a, capture_output=True, text=True,
                              timeout=15).stdout.strip()
    except Exception:
        return ""


# ── 1. Sunucu binary'leri yerinde mi ───────────────────────────────────
# `.mcp.json` mutlak yol tutuyor. npm global güncellemesi ya da yeniden
# kurulum bu yolu kaydırır; sunucu o zaman sessizce hiç başlamaz ve
# araçlar "yok" gibi davranır.
try:
    with open('.mcp.json', encoding='utf-8') as f:
        cfg = json.load(f).get('mcpServers', {})
except FileNotFoundError:
    cfg = {}
    sorunlar.append('.mcp.json yok — proje MCP sunucuları tanımsız')
except Exception as e:
    cfg = {}
    sorunlar.append('.mcp.json okunamadı: %s' % e)

for ad, s in cfg.items():
    komut = s.get('command', '')
    if not komut:
        sorunlar.append('%s: command tanımsız' % ad)
        continue
    # Mutlak yol ya da PATH'te çözülebilen bir ad kabul edilir.
    varmi = os.path.isfile(komut) or any(
        os.path.isfile(os.path.join(p, komut))
        for p in os.environ.get('PATH', '').split(os.pathsep) if p
    )
    if not varmi:
        sorunlar.append('%s: çalıştırılabilir bulunamadı (%s)' % (ad, komut))

# ── 2. Kod grafiği indeksi bayat mı ────────────────────────────────────
# İndeks bayatsa `search_graph` artık var olmayan sembolleri döndürür ya
# da yenilerini hiç görmez — sessiz ve yanıltıcı. Ölçü: indeksleme zamanı
# son commit'ten ESKİYSE indeks geride kalmış demektir.
db = os.path.join(cache, proje + '.db')
if not os.path.isfile(db):
    notlar.append('kod grafiği indeksi yok — ilk indeksleme gerekebilir')
else:
    try:
        con = sqlite3.connect('file:%s?mode=ro' % db.replace('\\', '/'),
                              uri=True, timeout=3)
        row = con.execute(
            'select indexed_at from projects where name=?', (proje,)
        ).fetchone()
        con.close()
        if row and row[0]:
            idx = datetime.fromisoformat(row[0].replace('Z', '+00:00'))
            son = kabuk('git', 'log', '-1', '--format=%cI')
            if son:
                commit = datetime.fromisoformat(son).astimezone(timezone.utc)
                if idx < commit:
                    fark = commit - idx
                    saat = int(fark.total_seconds() // 3600)
                    notlar.append(
                        'kod grafiği indeksi son commit\'ten %d saat geride '
                        '— tazele: codebase-memory-mcp cli index_repository '
                        '--repo-path "c:\\projects\\PortfoyTakip"' % saat
                    )
    except sqlite3.OperationalError:
        # Kilit normal: sunucu o an yazıyor olabilir. Sorun sayma.
        pass
    except Exception as e:
        notlar.append('indeks durumu okunamadı: %s' % e)

# ── 3. Rapor ───────────────────────────────────────────────────────────
if sorunlar:
    mesaj = 'MCP SAĞLIK — SORUN:\n' + '\n'.join('  x ' + s for s in sorunlar)
    if notlar:
        mesaj += '\n' + '\n'.join('  ! ' + n for n in notlar)
    mesaj += ('\nKullanıcıya bildir; bu sunucunun araçlarına güvenmeden '
              'önce çöz.')
elif notlar:
    mesaj = 'MCP SAĞLIK — dikkat:\n' + '\n'.join('  ! ' + n for n in notlar)
else:
    mesaj = ('MCP sağlık: %d sunucu yerinde, kod grafiği indeksi güncel.'
             % len(cfg))

print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': mesaj,
    },
    'suppressOutput': True,
}, ensure_ascii=False))
PY
