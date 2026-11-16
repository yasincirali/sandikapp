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
#   curl -fsSL https://raw.githubusercontent.com/yasincirali/sandikapp/main/tool/bulut_kurulum.sh | bash || true
# Ortam tüm projelerde ortaktır; sandikapp klonlanmayan projede de bu satır
# çalışır (repo herkese açık). Repo varsa `bash tool/bulut_kurulum.sh` da olur.
# Yeni oturumlar sunucuları açılışta görür; kurulumun yapıldığı oturum
# görmez. Tekrar koşmak güvenli (idempotent). Yerel makinede koşulursa
# hiçbir şey yapmadan çıkar (bkz. adım 0).
#
# Sürümler CI ile aynı: Flutter 3.47.2 (`ci.yml`), codebase-memory-mcp 0.9.0
# (yerel makinedeki sürüm), ui-ux-pro-mcp 1.5.0, Perplexity MCP 1.3.0,
# ruflo 3.56.10, caveman/ponytail eklentileri ve rtk 0.49.0 (adım 5c).
set -uo pipefail

REPO="${REPO:-/home/user/sandikapp}"
FLUTTER_VER=3.47.2
CBM_VER=0.9.0
UIUX_VER=1.5.0
PPLX_VER=1.3.0
RUFLO_VER=3.56.10
# 5c: üçüncü taraf kodu commit'e/sürüme sabit; yükseltme elle (yeni SHA'yı oku, sonra değiştir).
CAVEMAN_SHA=9b243662ff98d392bc0a95b865a554583d71be75   # caveman 4.1.0
PONYTAIL_SHA=96608e078b2d5ea607c5c3b8b5a54d1c1fba6846  # ponytail 5.3.3
RTK_VER=v0.49.0
RTK_SHA256=7278231dfd7e6a730a4ab7f847b195bcf02289c2d57622b0dab75a6411100c8f  # rtk-x86_64-unknown-linux-musl.tar.gz

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

# 4) Kayıt — local kapsam ($REPO yolu, `.mcp.json`'ı ezer) + user kapsamı (her yol).
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
    # Aynı üç sunucu user kapsamında da (kullanıcı isteği 2026-10-29: "tüm
    # threadlerde ve projelerde codebase-memory-mcp kullanalım"). Neden: proje
    # thread'leri /home/user'da açılır, local kayıt ise yalnız $REPO yolunda
    # okunur; codebase-memory hiçbir thread'e görünmüyordu (denendi). $REPO
    # içinde local kayıt `.mcp.json`'ın Windows yolunu ezmeye devam eder,
    # /home/user'da `.mcp.json` yok, user kaydı tek başına yeter.
    for s in codebase-memory-mcp dart ui-ux-pro-mcp; do
      claude mcp remove -s user "$s" >/dev/null 2>&1 || true
    done
    claude mcp add -s user codebase-memory-mcp -- /opt/cbm/codebase-memory-mcp >/dev/null
    [ -x /opt/flutter/bin/dart ] \
      && claude mcp add -s user dart -- /opt/flutter/bin/dart mcp-server --force-roots-fallback >/dev/null
    command -v ui-ux-pro-mcp >/dev/null 2>&1 \
      && claude mcp add -s user ui-ux-pro-mcp -- "$(command -v ui-ux-pro-mcp)" >/dev/null
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

# 5) Kod grafiği. Konteynerdeki her git deposu (sandikapp, piggy-crew,
# warranty-vault, birdie-smash…; 2026-10-29 önce yalnız $REPO'ydu) ayrı proje
# olarak indekslenir; depo başına 1–3 sn. Olmayan atlanır; oturumda
# `index_repository` ile yapılır. Geliştiricinin ADR'leri yalnız yerel
# grafikte; bulut grafiği ADR'siz başlar.
if [ -x /opt/cbm/codebase-memory-mcp ]; then
  goruldu=" "
  for d in "$REPO" /home/user/*/; do
    d="${d%/}"
    [ -d "$d/.git" ] || continue
    case "$goruldu" in *" $d "*) continue ;; esac
    goruldu="$goruldu$d "
    /opt/cbm/codebase-memory-mcp cli index_repository --repo-path "$d" >/dev/null 2>&1 \
      && log "kod grafiği indekslendi: $d" || log "UYARI: indeksleme başarısız: $d"
  done
fi

# 5b) Skill'ler. Repo `.claude/skills/` yalnız oturum o repoda açılınca okunur;
# proje thread'leri /home/user'da açıldığı için hiçbiri görünmüyordu (2026-10-29,
# yasin: "ui-ux-pro-max tüm uygulamalarda, Unity oyuna Unity, Flutter'a Flutter
# skill'leri"). Her repodaki skill kullanıcı klasörüne kopyalanır; aynı ad iki
# repoda varsa önce gelen ($REPO = sandikapp) kalır. Hangi skill'in hangi işe
# çağrılacağı yine her reponun CLAUDE.md yönlendirme tablosundadır.
# Unity MCP burada kurulmaz: Editor'a bağlanır, bulutta Editor yok (araç hep
# "bağlı değil" derdi). Unity MCP yasin'in PC'sinde, açık Editor'la çalışır.
mkdir -p "$HOME/.claude/skills"
for d in "$REPO" /home/user/*/; do
  d="${d%/}"
  [ -d "$d/.claude/skills" ] || continue
  for sk in "$d"/.claude/skills/*/; do
    sk="${sk%/}"; ad="$(basename "$sk")"
    [ -f "$sk/SKILL.md" ] || continue
    [ -e "$HOME/.claude/skills/$ad" ] && continue  # hesap/yerleşik skill'i ezme
    cp -r "$sk" "$HOME/.claude/skills/$ad"
  done
done
log "skill'ler kullanıcı klasöründe: $(ls "$HOME/.claude/skills" | wc -l)"

# 5c) Token tasarrufu araçları (yasin 2026-11-16: "tüm projelerimiz ve
# thread'lerimizde kullanılmak üzere ekle"). Üçü de üçüncü taraf koddur:
# README/kurulum betikleri okunup sabit commit'e bağlandı; `curl | bash`
# ve `@latest` yok, hiçbiri anahtar istemez, telemetri kapalı kalır.
#  - rtk (rtk-ai/rtk): Bash komut çıktısını (git, test, ls, log) ajan okumadan
#    sıkıştıran tek ikili + PreToolUse hook'u. Davranışı değiştirmez, yalnız
#    okunan çıktıyı kısaltır; `cat` → `rtk read` birebir aynı metni verir
#    (denendi). Telemetri varsayılan kapalı, init onay sormadan izin vermez.
#    `rtk init` llm-proxy'yi KURMAZ (API trafiğine girmez). Sürüm indirmesi
#    SHA-256 ile doğrulanır; tutmazsa kurulmaz.
#  - caveman (JuliusBrussee/caveman) ve ponytail (DietrichGebert/ponytail):
#    Claude Code eklentisi (skill + hook). Bilerek VARSAYILAN KAPALI
#    (defaultMode "off"): caveman yanıtı mağara adamı diline kısaltır,
#    ponytail her turda "en az kod" kurallarını enjekte eder; ikisi de proje
#    kurallarıyla (Türkçe, tam cümleli yanıt; kaynak yorumu = karar kaydı)
#    çakışabilir. İstenen thread'de `/caveman`, `/ponytail` ile açılır;
#    herkese açmak için aşağıdaki config'te "off" değiştirilir (yasin kararı).
#    ponytail'in webhook'u boş kalır, hiçbir veri makineden çıkmaz.
EKLENTI=/opt/claude-eklenti
sabit_klon() {  # $1 = github sahip/ad, $2 = hedef, $3 = commit SHA
  [ "$(git -C "$2" rev-parse HEAD 2>/dev/null)" = "$3" ] && return 0
  rm -rf "$2" && mkdir -p "$2" && git -C "$2" init -q \
    && git -C "$2" fetch -q --depth 1 "https://github.com/$1.git" "$3" \
    && git -C "$2" checkout -q FETCH_HEAD
}
if ! { command -v rtk >/dev/null 2>&1 && rtk --version 2>/dev/null | grep -q "${RTK_VER#v}"; }; then
  t="$(mktemp -d)"
  if curl -fsSL -o "$t/rtk.tgz" "https://github.com/rtk-ai/rtk/releases/download/${RTK_VER}/rtk-x86_64-unknown-linux-musl.tar.gz" \
     && echo "${RTK_SHA256}  $t/rtk.tgz" | sha256sum -c --quiet - \
     && tar xzf "$t/rtk.tgz" -C "$t" && install -m 755 "$t/rtk" /usr/local/bin/rtk; then
    log "rtk ${RTK_VER} kuruldu"
  else
    log "UYARI: rtk kurulamadı (indirme ya da SHA-256 tutmadı)"
  fi
  rm -rf "$t"
fi
command -v rtk >/dev/null 2>&1 \
  && { rtk init -g --auto-patch --hook-only </dev/null >/dev/null 2>&1 && log "rtk hook kaydedildi" || log "UYARI: rtk init başarısız"; }
mkdir -p "$HOME/.config/caveman" "$HOME/.config/ponytail"
[ -f "$HOME/.config/caveman/config.json" ] || echo '{"defaultMode": "off"}' > "$HOME/.config/caveman/config.json"
[ -f "$HOME/.config/ponytail/config.json" ] || echo '{"defaultMode": "off"}' > "$HOME/.config/ponytail/config.json"
if command -v claude >/dev/null 2>&1; then
  for e in "caveman JuliusBrussee/caveman $CAVEMAN_SHA" "ponytail DietrichGebert/ponytail $PONYTAIL_SHA"; do
    set -- $e
    if sabit_klon "$2" "$EKLENTI/$1" "$3"; then
      claude plugin marketplace add "$EKLENTI/$1" >/dev/null 2>&1 || true
      claude plugin install "$1@$1" >/dev/null 2>&1 && log "eklenti hazır: $1" || log "UYARI: eklenti kurulamadı: $1"
    else
      log "UYARI: $1 indirilemedi"
    fi
  done
fi

# 6) Paketler — pubspec.lock'u değiştirirse geri al (yerel Flutter meta/matcher'ı kaydırır).
if [ -f "$REPO/pubspec.yaml" ]; then
  ( cd "$REPO" && flutter pub get >/dev/null 2>&1 && git checkout -q -- pubspec.lock 2>/dev/null ) || true
fi

exit 0
