#!/usr/bin/env bash
# main'e push'tan SONRA kod grafiği indeksini tazeler.
#
# ## Neden hook, neden elle değil
# Bayat indeks SESSİZ ve yanıltıcıdır: `search_graph` var olmayan sembolleri
# ya da eski satır numaralarını döndürür ve bu bir hata gibi görünmez —
# yanlış dosyaya bakılır. Tazeleme 0,26 sn sürüyor (ölçüldü), yani push
# başına maliyeti pratikte sıfır.
#
# ## Neden `PostToolUse`
# Hook, Bash aracı çalıştıktan SONRA tetiklenir ve stdin'den komutu okur.
# Push'tan ÖNCE indekslemek yanlış olurdu: push başarısız olsa bile indeks
# tazelenirdi. `PostToolUse` yalnızca araç başarıyla döndüğünde çalışır.
#
# ## Neden `main` filtresi
# Kullanıcı isteği tam olarak "her main pushlamasında". Feature dalına
# yapılan push, main'in gördüğü koda karşılık gelmez.
#
# Çıktı JSON'dur (hook sözleşmesi); sessiz kalması gereken durumda da
# geçerli JSON basar.
set -u

# stdin'den hook yükü. Boşsa (elle çalıştırma) sessizce çık.
PAYLOAD="$(cat 2>/dev/null || true)"

emit() {
  # $1: systemMessage (boşsa yalnızca suppress)
  if [ -n "${1:-}" ]; then
    python -c "
import json,sys
print(json.dumps({'systemMessage': sys.argv[1], 'suppressOutput': True}))
" "$1"
  else
    printf '{\"suppressOutput\": true}\n'
  fi
}

# Komutu yükten çıkar. `jq` her ortamda yok; python guaranteed (betik zaten
# python kullanıyor).
CMD="$(printf '%s' "$PAYLOAD" | python -c "
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(''); raise SystemExit
print((d.get('tool_input') or {}).get('command', '') or '')
" 2>/dev/null || printf '')"

[ -z "$CMD" ] && { emit ''; exit 0; }

# `git push` mü? Alt komutlar (`git push --dry-run`) elenmeli: dry-run
# uzaktaki kodu DEĞİŞTİRMEZ, indekslemeye gerek yok.
case "$CMD" in
  *"git push"*) : ;;
  *) emit ''; exit 0 ;;
esac
case "$CMD" in
  *--dry-run*) emit ''; exit 0 ;;
esac

# main'e mi gitti?
#
# Hedef komutta AÇIKÇA yazılıysa ona bakılır; yazılmamışsa (`git push`)
# o anki dal geçerlidir. Sıra önemli: önce açık hedefi ayıkla, HEAD'e
# yalnızca gerçekten hedef yoksa düş.
#
# Bu ayrım ölçülerek bulundu: `*main*` kalıbıyla başlayıp "eşleşmezse
# HEAD'e bak" demek, `git push origin feature/x` komutunu da indeksliyordu
# — çünkü HEAD o sırada main'di. Refspec varken HEAD'e düşmek yanlış.
REFSPEC="$(printf '%s' "$CMD" | python -c "
import re,sys
# 'git push [bayraklar] [remote] [refspec]' — bayrakları ve remote'u at.
m = re.search(r'git\s+push\s+(.*)', sys.stdin.read())
if not m:
    print(''); raise SystemExit
parts = [p for p in m.group(1).split() if not p.startswith('-')]
# ilk konumsal = remote, ikincisi = refspec
print(parts[1] if len(parts) >= 2 else '')
" 2>/dev/null || printf '')"

if [ -n "$REFSPEC" ]; then
  # `main`, `HEAD:main`, `main:main` kabul; `feature/x` ret.
  case "${REFSPEC##*:}" in
    main) ;;
    *) emit ''; exit 0 ;;
  esac
else
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
  [ "$BRANCH" = "main" ] || { emit ''; exit 0; }
fi

CM="C:/Users/vasin/AppData/Local/Programs/codebase-memory-mcp/codebase-memory-mcp.exe"
[ -x "$CM" ] || { emit "indeks tazelenemedi: codebase-memory-mcp bulunamadi"; exit 0; }

# `cli` modu daemon başlatmaz — çalışan MCP sunucusunun SQLite kilidiyle
# çakışmaz (bkz. CLAUDE.md).
OUT="$("$CM" cli index_repository --repo-path "c:\projects\PortfoyTakip" 2>&1 | tail -1)"

SUMMARY="$(printf '%s' "$OUT" | python -c "
import json,sys
raw = sys.stdin.read().strip()
try:
    d = json.loads(raw)
except Exception:
    print(''); raise SystemExit
if d.get('status') == 'indexed':
    print('kod grafigi indeksi tazelendi: %s dugum, %s kenar'
          % (d.get('nodes','?'), d.get('edges','?')))
" 2>/dev/null || printf '')"

if [ -n "$SUMMARY" ]; then
  emit "$SUMMARY"
else
  emit "indeks tazelenemedi (push etkilenmedi)"
fi
exit 0
