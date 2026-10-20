#!/usr/bin/env bash
# Claude Code bulut oturumu kurulumu (claude.ai/code, Linux konteyner).
#
# Neden var (kullanıcı isteği 2026-10-08: "MCP'leri cloud session için de
# kur"): kök `.mcp.json` geliştiricinin Windows yollarını gösterir; bulut
# konteynerde üç sunucu da ENOENT ile düşüyordu ve Flutter kurulu değildi.
# `.mcp.json`'a DOKUNULMAZ (yerel makine onu kullanıyor); burada aynı üç
# sunucu Linux yollarıyla `-s local` kapsamında kaydedilir — local kapsam
# proje kapsamını ezer (user kapsamı EZMEZ, denendi 2026-09-28).
#
# Kullanım: Project settings › Cloud environment › Setup script alanına
#   bash tool/bulut_kurulum.sh
# ya da (repo henüz klonlanmamışsa) bu dosyanın içeriğini yapıştır.
# Yeni oturumlar sunucuları açılışta görür; kurulumun yapıldığı oturum
# görmez. Tekrar koşmak güvenli (idempotent). Yerel makinede koşulursa
# hiçbir şey yapmadan çıkar (bkz. adım 0).
#
# Sürümler CI ile aynı: Flutter 3.47.2 (`ci.yml`), codebase-memory-mcp 0.9.0
# (yerel makinedeki sürüm), ui-ux-pro-mcp 1.5.0, Perplexity MCP 1.3.0,
# ruflo 3.56.10.
set -uo pipefail

REPO="${REPO:-/home/user/sandikapp}"
FLUTTER_VER=3.47.2
CBM_VER=0.9.0
UIUX_VER=1.5.0
PPLX_VER=1.3.0
RUFLO_VER=3.56.10

log() { echo "[bulut_kurulum] $*"; }

# 0) Yalnız bulut konteynerinde koş. Neden (2026-10-08): betik geliştiricinin
# Windows makinesinde Git Bash'ten koşuldu; kurulumlar /opt'ta düştü ama
# `claude mcp add -s local` Linux yollu kayıtlar yazdı ve yerel MCP'yi
# bozabilirdi. Konteyner işareti: Linux + (CLAUDE_CODE_REMOTE ya da yazılabilir
# /opt — setup script oturum değişkenlerinden önce koşabilir). Bilerek başka
# bir Linux'ta koşmak için BULUT_KURULUM_ZORLA=1.
if [ "${BULUT_KURULUM_ZORLA:-0}" != 1 ]; then
  if [ "$(uname -s)" != Linux ] \
     || { [ "${CLAUDE_CODE_REMOTE:-}" != true ] && ! [ -w /opt ]; }; then
    log "Bu betik yalnız Claude Code bulut konteyneri içindir (Project settings › Cloud environment › Setup script)."
    log "Bu makinede hiçbir şey kurulmadı ve MCP kaydına dokunulmadı."
    exit 0
  fi
fi

# 1) Flutter (+ dart; dart MCP sunucusu bununla gelir).
if [ ! -x /opt/flutter/bin/flutter ]; then
  log "Flutter $FLUTTER_VER indiriliyor"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VER}-stable.tar.xz" \
    -o /tmp/flutter.tar.xz && tar -xf /tmp/flutter.tar.xz -C /opt && rm -f /tmp/flutter.tar.xz \
    || log "UYARI: Flutter kurulamadı"
fi
# Kök kullanıcıyla /opt/flutter git deposu "dubious ownership" verir.
git config --global --add safe.directory /opt/flutter 2>/dev/null || true
grep -q '/opt/flutter/bin' /etc/profile.d/flutter.sh 2>/dev/null \
  || echo 'export PATH=/opt/flutter/bin:$PATH' > /etc/profile.d/flutter.sh
export PATH=/opt/flutter/bin:$PATH
flutter --version >/dev/null 2>&1 || true

# 2) codebase-memory-mcp (GitHub sürüm indirmesi proxy'den geçer; api.github.com geçmez).
if [ ! -x /opt/cbm/codebase-memory-mcp ]; then
  log "codebase-memory-mcp $CBM_VER indiriliyor"
  mkdir -p /opt/cbm && curl -fsSL \
    "https://github.com/DeusData/codebase-memory-mcp/releases/download/v${CBM_VER}/codebase-memory-mcp-linux-amd64.tar.gz" \
    | tar -xz -C /opt/cbm || log "UYARI: codebase-memory-mcp kurulamadı"
fi

# 3) ui-ux-pro-mcp.
command -v ui-ux-pro-mcp >/dev/null 2>&1 \
  || npm i -g "ui-ux-pro-mcp@${UIUX_VER}" >/dev/null 2>&1 \
  || log "UYARI: ui-ux-pro-mcp kurulamadı"

# 3b) Perplexity MCP (resmi sunucu, github.com/perplexityai/modelcontextprotocol;
# kullanıcı isteği 2026-10-12). Web araması/araştırma araçları: perplexity_ask,
# _search, _reason, _research. Anahtar PERPLEXITY_API_KEY bulut ortam
# değişkeninden okunur; repoya ve kayda YAZILMAZ (repo herkese açık). Sunucu
# anahtarsız açılışta çıkıyor (exit 1), bu yüzden anahtar yoksa kayıt atlanır
# ki her oturumda "failed to connect" gürültüsü olmasın. Ağ politikası
# api.perplexity.ai'ye izin vermezse araçlar listelenir ama sorgu 403 alır.
command -v perplexity-mcp >/dev/null 2>&1 \
  || npm i -g "@perplexity-ai/mcp-server@${PPLX_VER}" >/dev/null 2>&1 \
  || log "UYARI: Perplexity MCP kurulamadı"

# 3c) ruflo MCP (github.com/ruvnet/ruflo, eski adı claude-flow; kullanıcı
# isteği 2026-10-20: "tüm threadlerde kullanılabilir yap"). Ajan/swarm
# orkestrasyonu, kalıcı vektör hafıza, iş akışı araçları (~360 araç).
# README `npx -y ruflo@latest mcp start` diyor; bilerek kullanılmadı:
# paket neredeyse her gün sürüm çıkarıyor, `@latest` her oturumda farklı
# kod ve açılışta ~1 dk npm indirmesi demek. Sabit sürüm global kurulur.
# Sürüm yükseltme elle: RUFLO_VER'i değiştir. Kendi kendini güncellemesi
# (CLAUDE_FLOW_AUTO_UPDATE) ve arka plan daemon'u (RUFLO_DAEMON_AUTOSTART)
# kayıtta kapatılır; anahtar istemez, kayda secret yazılmaz.
{ command -v ruflo >/dev/null 2>&1 && ruflo --version 2>/dev/null | grep -q "v${RUFLO_VER}"; } \
  || npm i -g "ruflo@${RUFLO_VER}" >/dev/null 2>&1 \
  || log "UYARI: ruflo kurulamadı"

# 4) Kayıt — local kapsam (yalnız bu proje yolu); ruflo user kapsamında.
if command -v claude >/dev/null 2>&1; then
  ( cd "$REPO" 2>/dev/null || cd /
    for s in codebase-memory-mcp dart ui-ux-pro-mcp perplexity ruflo; do  # ruflo: eski local kayıt
      claude mcp remove -s local "$s" >/dev/null 2>&1 || true
    done
    claude mcp add -s local codebase-memory-mcp -- /opt/cbm/codebase-memory-mcp >/dev/null
    claude mcp add -s local dart -- /opt/flutter/bin/dart mcp-server --force-roots-fallback >/dev/null
    claude mcp add -s local ui-ux-pro-mcp -- "$(command -v ui-ux-pro-mcp || echo ui-ux-pro-mcp)" >/dev/null
    # Anahtar `-e` ile kayda gömülmez; sunucu oturumun ortamından okur.
    if [ -n "${PERPLEXITY_API_KEY:-}" ] && command -v perplexity-mcp >/dev/null 2>&1; then
      claude mcp add -s local perplexity -- "$(command -v perplexity-mcp)" >/dev/null \
        && log "Perplexity MCP kaydedildi"
    else
      log "Perplexity MCP atlandı (PERPLEXITY_API_KEY ortamda yok)"
    fi
    # ruflo `.mcp.json`'da yok, bu yüzden user kapsamı yeter ve tercih edilir:
    # sandikapp dışındaki repolarda (piggy-crew, warranty-vault, birdie-smash)
    # ve /home/user'da açılan oturumlar da görür ("tüm threadler").
    claude mcp remove -s user ruflo >/dev/null 2>&1 || true
    if command -v ruflo >/dev/null 2>&1; then
      # Ad `-e`'den önce: `-e` çok değerli, sonrasındaki adı da yutuyor (denendi).
      claude mcp add -s user ruflo -e CLAUDE_FLOW_AUTO_UPDATE=false -e RUFLO_DAEMON_AUTOSTART=0 \
        -- "$(command -v ruflo)" mcp start >/dev/null && log "ruflo MCP kaydedildi"
    fi
  ) && log "MCP sunucuları kaydedildi" || log "UYARI: MCP kaydı başarısız"
else
  log "UYARI: claude CLI yok, MCP kaydı atlandı"
fi

# 5) Kod grafiği (3 sn). Repo yoksa atlanır; oturumda `index_repository` ile yapılır.
# Not: geliştiricinin ADR'leri yalnız yerel grafikte; bulut grafiği ADR'siz başlar.
if [ -d "$REPO/lib" ] && [ -x /opt/cbm/codebase-memory-mcp ]; then
  /opt/cbm/codebase-memory-mcp cli index_repository --repo-path "$REPO" >/dev/null 2>&1 \
    && log "kod grafiği indekslendi" || log "UYARI: indeksleme başarısız"
fi

# 6) Paketler — pubspec.lock'u değiştirirse geri al (yerel Flutter meta/matcher'ı kaydırır).
if [ -f "$REPO/pubspec.yaml" ]; then
  ( cd "$REPO" && flutter pub get >/dev/null 2>&1 && git checkout -q -- pubspec.lock 2>/dev/null ) || true
fi

exit 0
