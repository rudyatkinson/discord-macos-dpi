#!/bin/bash
# Discord DPI installer (macOS) / Discord DPI kurulumu (macOS)
#
# EN: Gets Discord past the block in Türkiye using SpoofDPI. SpoofDPI listens only on
#     127.0.0.1:8881 and only Discord uses it; system proxy settings are not touched and
#     sudo is not needed. Running it again updates an existing install.
# TR: Türkiye'deki Discord engelini SpoofDPI ile aşar. SpoofDPI sadece 127.0.0.1:8881'de
#     dinler ve onu yalnızca Discord kullanır; sistem proxy ayarına dokunulmaz, sudo
#     gerekmez. Tekrar çalıştırmak güncelleme yerine geçer.
#
#   Install / Kurulum:
#     /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rudyatkinson/discord-macos-dpi/main/install.sh)"
#   Uninstall / Kaldırma:
#     bash install.sh --uninstall   (or the Help app > Uninstall / ya da Yardım uygulaması > Kaldır)
#
# Messages are Turkish when the system language is Turkish and English otherwise.
# Set DISCORD_DPI_LANG=tr or =en to force one.

set -u

VERSION=1.1.0
SPOOF_VERSION=1.5.4
SPOOF_SHA_arm64=92f7dd41c3b414865410c5cc8c845915375ace9d03a8cf15b23fc7374c354bc6
SPOOF_SHA_x86_64=a39ad5361e3fe1a263cd4017583bc8ac4b8dbf6e4886f55ddeee0cfde3cf9255

APP_DIR="$HOME/Library/Application Support/DiscordDPI"
LOG_DIR="$HOME/Library/Logs/DiscordDPI"
TOOL="$APP_DIR/discord-dpi"
LABEL=local.discord-dpi
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HELPER_TR="Discord DPI Yardım.app"
HELPER_EN="Discord DPI Help.app"
PROXY=http://127.0.0.1:8881
DOMAIN="gui/$(id -u)"

UI_LANG=${DISCORD_DPI_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')}
case "$UI_LANG" in tr*) UI_LANG=tr ;; *) UI_LANG=en ;; esac

# t <turkish> <english>: prints the one for the current language.
t() { if [ "$UI_LANG" = tr ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
say() { printf '%s\n' "$(t "$1" "$2")"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$(t "$1" "$2")"; }
die() { printf '\n\033[31m%s %s\033[0m\n' "$(t HATA: ERROR:)" "$(t "$1" "$2")" >&2; exit 1; }

HELPER_APP=$(t "$HELPER_TR" "$HELPER_EN")

if [ "${1:-}" = "--uninstall" ]; then
  [ -x "$TOOL" ] || die "Discord DPI kurulu görünmüyor." "Discord DPI does not appear to be installed."
  "$TOOL" uninstall
  exit $?
fi

# --- 1. Checks ---------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || die "Bu kurulum sadece macOS içindir." "This installer is for macOS only."
[ "$(id -u)" -ne 0 ] || die "Bu komutu sudo ile çalıştırma; başına sudo yazmadan tekrar dene." \
  "Do not run this with sudo; run it again without sudo."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 12 ] || die "macOS 12 ya da daha yenisi gerekiyor." \
  "macOS 12 or newer is required."

if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
  ARCH=arm64; SPOOF_SHA=$SPOOF_SHA_arm64
else
  ARCH=x86_64; SPOOF_SHA=$SPOOF_SHA_x86_64
fi

TMP=$(mktemp -d) || die "Geçici klasör oluşturulamadı." "Could not create a temporary folder."
trap 'hdiutil detach "$TMP/mnt" > /dev/null 2>&1; rm -rf "$TMP"' EXIT

# --- 2. Stop any previous install ----------------------------------------------

step "Hazırlanıyor" "Preparing"
unload_agent() {
  launchctl bootout "$DOMAIN/$1" > /dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print "$DOMAIN/$1" > /dev/null 2>&1 || return 0
    sleep 0.5
  done
}
unload_agent "$LABEL"

# Leftovers from the first, hand-made setup.
unload_agent com.bilal.discord-dpi
rm -f "$HOME/Library/LaunchAgents/com.bilal.discord-dpi.plist" \
  "$HOME/.local/bin/discord-dpi" "$HOME/.local/bin/discord-dpi-watch" \
  "$HOME/Library/Logs/discord-dpi.log" "$HOME/.cache/discord-dpi.pid"
rm -rf "$HOME/Applications/Discord DPI.app"

mkdir -p "$APP_DIR/bin" "$LOG_DIR" "$HOME/Library/LaunchAgents" \
  || die "Klasörler oluşturulamadı." "Could not create folders."

# --- 3. SpoofDPI ---------------------------------------------------------------

step "SpoofDPI $SPOOF_VERSION indiriliyor ($ARCH)" "Downloading SpoofDPI $SPOOF_VERSION ($ARCH)"
URL="https://github.com/xvzc/spoofdpi/releases/download/v$SPOOF_VERSION/spoofdpi_${SPOOF_VERSION}_darwin_$ARCH.tar.gz"
curl -fL --retry 3 --progress-bar -m 300 -o "$TMP/spoofdpi.tar.gz" "$URL" \
  || die "SpoofDPI indirilemedi. İnternet bağlantını kontrol edip tekrar dene." \
    "Could not download SpoofDPI. Check your internet connection and try again."
[ "$(shasum -a 256 "$TMP/spoofdpi.tar.gz" | cut -d' ' -f1)" = "$SPOOF_SHA" ] \
  || die "İndirilen SpoofDPI dosyası doğrulanamadı (SHA256 uyuşmuyor)." \
    "The downloaded SpoofDPI file failed verification (SHA256 mismatch)."
tar -xzf "$TMP/spoofdpi.tar.gz" -C "$TMP" spoofdpi \
  || die "SpoofDPI arşivi açılamadı." "Could not extract the SpoofDPI archive."
mv -f "$TMP/spoofdpi" "$APP_DIR/bin/spoofdpi" && chmod 755 "$APP_DIR/bin/spoofdpi"
"$APP_DIR/bin/spoofdpi" --version > /dev/null 2>&1 \
  || die "SpoofDPI bu Mac'te çalışmadı." "SpoofDPI does not run on this Mac."

# --- 4. Service script, LaunchAgent, Help app -----------------------------------

step "Servis kuruluyor" "Installing the service"
printf '%s\n' "$VERSION" > "$APP_DIR/VERSION"
# A forced language is remembered for the service and the Help app.
if [ -n "${DISCORD_DPI_LANG:-}" ]; then printf '%s\n' "$UI_LANG" > "$APP_DIR/lang"; else rm -f "$APP_DIR/lang"; fi

cat > "$TOOL" <<'DISCORD_DPI_TOOL'
#!/bin/zsh
# Discord DPI: runs SpoofDPI for Discord only.
#   watch      background service (run by the LaunchAgent)
#   diagnose   builds a diagnostics zip and prints its path
#   repair     re-picks a working strategy, restarts the service and Discord
#   uninstall  removes everything (leaves Discord itself alone)
#   lang       prints the message language in use (tr or en)
# The system proxy settings are never touched; only a Discord started with
# --proxy-server uses the proxy.

zmodload zsh/datetime

# The LaunchAgent and the Help app run this with different environments; make them equal.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
USER=${USER:-$(id -un)}

APP_DIR="$HOME/Library/Application Support/DiscordDPI"
LOG_DIR="$HOME/Library/Logs/DiscordDPI"
SPOOF="$APP_DIR/bin/spoofdpi"
STRATEGY_FILE="$APP_DIR/strategy"
LABEL=local.discord-dpi
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HELPER_APPS=("Discord DPI Yardım.app" "Discord DPI Help.app")
PORT=8881
TEST_PORT=8882
PROXY=http://127.0.0.1:$PORT
VERSION=$(cat "$APP_DIR/VERSION" 2>/dev/null)
HOSTS=(discord.com/api/v9/gateway gateway.discord.gg cdn.discordapp.com)

# Tried in order; the first one that reaches all three Discord hosts is used. Which one
# works depends on the ISP; SpoofDPI's default (sni) is not enough on most networks.
STRATEGIES=(
  "--https-split-mode chunk --https-chunk-size 5"
  "--https-split-mode chunk --https-chunk-size 1"
  "--https-split-mode chunk --https-chunk-size 2"
  "--https-split-mode random"
  "--https-split-mode first-byte --https-disorder"
  "--https-split-mode sni --https-disorder"
  "--https-split-mode sni"
  "--dns-https-url https://cloudflare-dns.com/dns-query --https-split-mode chunk --https-chunk-size 5"
)

SPOOF_PID=

# Messages are Turkish when the system language is Turkish and English otherwise.
# A "lang" file next to this script (written when the installer was run with
# DISCORD_DPI_LANG) forces one.
UI_LANG=$(cat "$APP_DIR/lang" 2>/dev/null)
[[ -n $UI_LANG ]] || UI_LANG=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')
if [[ $UI_LANG == tr* ]]; then UI_LANG=tr; else UI_LANG=en; fi

# t <turkish> <english>: prints the one for the current language.
t() { if [[ $UI_LANG == tr ]]; then print -r -- "$1"; else print -r -- "$2"; fi }
log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $(t "$1" "$2")" }
strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g' }

wait_port() {
  local i
  for i in {1..40}; do nc -z 127.0.0.1 $1 2>/dev/null && return 0; sleep 0.25; done
  return 1
}

online() { [[ $(curl -s -m 6 http://captive.apple.com/hotspot-detect.html 2>/dev/null) == *Success* ]] }

net_sig() {
  print -r -- "$(route -n get default 2>/dev/null | awk '/gateway:|interface:/{printf "%s ", $2}')$(scutil --dns 2>/dev/null | awk '/nameserver\[0\]/{print $3; exit}')"
}

# Once a file passes 1 MB, keep its tail as .1 and empty it.
trim_log() {
  [[ -f $1 ]] || return 0
  (( $(stat -f%z "$1") > 1048576 )) || return 0
  tail -c 262144 "$1" > "$1.1"
  : > "$1"
}

# probe <port>: 0 if all three Discord hosts answer through the proxy on that port.
probe() {
  local h code
  for h in $HOSTS; do
    code=$(curl -s -o /dev/null -m 8 -x http://127.0.0.1:$1 -w '%{http_code}' "https://$h" 2>/dev/null)
    [[ -z $code || $code == 000 ]] && return 1
  done
  return 0
}

# run_test <flags> [fast]: tries a strategy on the test port and prints the HTTP code
# per host (000 = blocked). With fast, stops at the first host that fails.
run_test() {
  local pid h code codes="" rc=0
  "$SPOOF" --no-tui --clean --listen-addr 127.0.0.1:$TEST_PORT --dns-mode https ${=1} > /dev/null 2>&1 &
  pid=$!
  if wait_port $TEST_PORT; then
    for h in $HOSTS; do
      code=$(curl -s -o /dev/null -m 6 -x http://127.0.0.1:$TEST_PORT -w '%{http_code}' "https://$h" 2>/dev/null)
      [[ -z $code ]] && code=000
      codes+="$code "
      if [[ $code == 000 ]]; then
        rc=1
        [[ -n $2 ]] && break
      fi
    done
  else
    codes=$(t "proxy açılamadı" "proxy failed to start")
    rc=1
  fi
  kill $pid 2>/dev/null
  wait $pid 2>/dev/null
  print -r -- $codes
  return $rc
}

pick_strategy() {
  local s
  for s in $STRATEGIES; do
    if run_test "$s" fast > /dev/null; then
      print -r -- "$s" > "$STRATEGY_FILE"
      return 0
    fi
  done
  return 1
}

current_strategy() {
  local s=$(cat "$STRATEGY_FILE" 2>/dev/null)
  (( ${STRATEGIES[(Ie)$s]} )) || s=$STRATEGIES[1]
  print -r -- "$s"
}

has_proxy() { ps -axo args= | grep -q -- "[D]iscord.app/Contents/MacOS/Discord .*--proxy-server=$PROXY" }
launch() {
  open -a Discord --env HTTPS_PROXY=$PROXY --env HTTP_PROXY=$PROXY \
    --args --proxy-server=$PROXY
}
stop_discord() {
  local i
  pkill -x Discord
  for i in {1..40}; do pgrep -xq Discord || break; sleep 0.25; done
}

start_spoof() {
  local flags=$(current_strategy)
  print -r -- "$flags" > "$STRATEGY_FILE"
  # A SpoofDPI left over from a previous service instance must release the port first.
  pkill -f "^$SPOOF --no-tui --clean --listen-addr 127.0.0.1:$PORT " 2>/dev/null && sleep 1
  "$SPOOF" --no-tui --clean --listen-addr 127.0.0.1:$PORT --dns-mode https ${=flags} >> "$LOG_DIR/spoofdpi.log" 2>&1 &
  SPOOF_PID=$!
  wait_port $PORT
  sleep 0.5
  if kill -0 $SPOOF_PID 2>/dev/null; then
    log "SpoofDPI çalışıyor (pid $SPOOF_PID, strateji: $flags)" \
      "SpoofDPI running (pid $SPOOF_PID, strategy: $flags)"
    return 0
  fi
  log "SpoofDPI başlatılamadı; $PORT portu başka bir uygulamada olabilir. 30 sn sonra yeniden denenecek." \
    "SpoofDPI failed to start; port $PORT may be in use by another app. Retrying in 30 s."
  SPOOF_PID=
  return 1
}

# Re-picks a working strategy when Discord is unreachable through the live proxy.
# With force=1 (startup, network change, Discord just opened) it does not wait out the
# 5-minute limit between picks.
health_check() {
  local old new
  trim_log "$LOG_DIR/spoofdpi.log"
  trim_log "$LOG_DIR/watch.log"
  if probe $PORT || { sleep 3; probe $PORT }; then
    (( offline || bad )) && log "Discord'a proxy üzerinden ulaşılıyor" "Discord is reachable through the proxy"
    offline=0; bad=0; force=0
    next_check=$(( EPOCHSECONDS + 60 ))
    return 0
  fi
  if ! online; then
    (( offline )) || log "internet yok ya da ağ giriş sayfası istiyor; bekleniyor" \
      "no internet, or the network wants a sign-in page; waiting"
    offline=1
    next_check=$(( EPOCHSECONDS + 15 ))
    return 1
  fi
  offline=0
  next_check=$(( EPOCHSECONDS + 60 ))
  if (( ! force && EPOCHSECONDS - last_pick < 300 )); then
    return 1
  fi
  force=0
  last_pick=$EPOCHSECONDS
  old=$(current_strategy)
  log "Discord'a ulaşılamıyor (strateji: $old); stratejiler deneniyor" \
    "Discord is unreachable (strategy: $old); trying strategies"
  if pick_strategy; then
    new=$(current_strategy)
    log "çalışan strateji: $new" "working strategy: $new"
    bad=0
    if [[ $new != $old ]]; then
      kill $SPOOF_PID 2>/dev/null
      wait $SPOOF_PID 2>/dev/null
      start_spoof
    fi
  else
    (( bad )) || log "bu ağda hiçbir strateji çalışmadı" "no strategy worked on this network"
    bad=1
  fi
}

cmd_watch() {
  mkdir -p "$LOG_DIR"
  trim_log "$LOG_DIR/watch.log"
  exec >> "$LOG_DIR/watch.log" 2>&1
  log "servis başladı (sürüm $VERSION, macOS $(sw_vers -productVersion), $(uname -m))" \
    "service started (version $VERSION, macOS $(sw_vers -productVersion), $(uname -m))"

  local retries=0 was_running=0 running net="" cur
  force=1 next_check=0 last_pick=0 offline=0 bad=0
  while true; do
    if [[ -z $SPOOF_PID ]] || ! kill -0 $SPOOF_PID 2>/dev/null; then
      start_spoof || { sleep 30; continue }
      force=1; next_check=0
    fi

    cur=$(net_sig)
    if [[ $cur != $net ]]; then
      [[ -n $net ]] && log "ağ değişti: ${cur:-bağlantı yok}" "network changed: ${cur:-no connection}"
      net=$cur
      force=1; next_check=0
    fi

    running=0
    pgrep -xq Discord && running=1
    if (( running && ! was_running )); then
      force=1; next_check=0
    fi
    was_running=$running

    if (( EPOCHSECONDS >= next_check )) && (( force || running )); then
      health_check
    fi

    if (( running )) && ! has_proxy; then
      # After 3 failed attempts in a row, wait a minute instead of looping kill/relaunch.
      if (( retries >= 3 )); then
        log "Discord 3 denemede proxy ile açılamadı; 1 dk bekleniyor" \
          "Discord could not be started with the proxy in 3 attempts; waiting 1 min"
        sleep 60
        retries=0
      else
        (( retries++ ))
        log "Discord proxy'siz açılmış; proxy ile yeniden açılıyor (deneme $retries)" \
          "Discord was started without the proxy; relaunching it with the proxy (attempt $retries)"
        stop_discord
        launch
        sleep 5
      fi
    else
      retries=0
    fi
    sleep 2
  done
}

section() { print; t "== $1 ==" "== $2 ==" }
row() { print -r -- "$(t "$1" "$2"): $3" }

# Writes the diagnostic details; fills in VERDICT and ADVICE.
collect() {
  local cap internet agent listener s codes working="" live="" live_ok=1 h code app found=0 pids discord_proxy=""
  local none=$(t yok none)

  t "== Genel ==" "== General =="
  row "Tarih" "Date" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  row "Discord DPI sürümü" "Discord DPI version" "${VERSION:-?}"
  row "macOS" "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"
  row "Kullanıcı" "User" "$USER"
  row "Dil" "Language" "$UI_LANG"
  row "SpoofDPI" "SpoofDPI" "$("$SPOOF" --version 2>&1 | head -1)"

  section "İnternet" "Internet"
  cap=$(curl -s -m 6 http://captive.apple.com/hotspot-detect.html 2>/dev/null)
  if [[ $cap == *Success* ]]; then
    internet=ok
    row "İnternet" "Internet" "$(t var yes)"
  elif [[ -n $cap ]]; then
    internet=portal
    row "İnternet" "Internet" "$(t "giriş sayfası (captive portal)" "sign-in page (captive portal)")"
  else
    internet=none
    row "İnternet" "Internet" "$(t yok no)"
  fi
  row "Ağ geçidi / arayüz" "Gateway / interface" "$(route -n get default 2>/dev/null | awk '/gateway:|interface:/{printf "%s ", $2}')"
  row "DNS sunucuları" "DNS servers" "$(scutil --dns 2>/dev/null | awk '/nameserver\[/{print $3}' | sort -u | tr '\n' ' ')"
  [[ $internet == ok ]] && row "Operatör" "ISP" "$(curl -s -m 6 https://ipinfo.io/org 2>/dev/null)"

  section "Servis" "Service"
  agent=$(launchctl print gui/$UID/$LABEL 2>/dev/null | awk '/^\tstate =|^\tpid =|^\truns =|^\tlast exit code =/{$1=$1; printf "%s; ", $0}')
  row "LaunchAgent" "LaunchAgent" "${agent:-$(t "YÜKLÜ DEĞİL" "NOT LOADED")}"
  listener=$(lsof -nP -iTCP:$PORT -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $1" (pid "$2")"}' | sort -u | tr '\n' ' ')
  row "Port $PORT dinleyen" "Listening on port $PORT" "${listener:-$none}"
  row "Seçili strateji" "Selected strategy" "$(cat "$STRATEGY_FILE" 2>/dev/null || print -r -- $none)"

  section "Discord" "Discord"
  for app in /Applications/Discord.app "$HOME/Applications/Discord.app"; do
    if [[ -d $app ]]; then
      found=1
      row "Kurulu" "Installed" "$app ($(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null))"
    fi
  done
  (( found )) || row "Kurulu" "Installed" "$(t BULUNAMADI "NOT FOUND")"
  pids=$(pgrep -x Discord | tr '\n' ' ')
  if [[ -n $pids ]]; then
    row "Çalışıyor" "Running" "$(t evet yes) (pid $pids)"
    if has_proxy; then
      discord_proxy=yes
      row "Proxy bayrağı" "Proxy flag" "$(t var present)"
    else
      discord_proxy=no
      row "Proxy bayrağı" "Proxy flag" "$(t YOK MISSING)"
    fi
    row "Proxy'ye açık bağlantı sayısı" "Open connections to the proxy" "$(lsof -nP -iTCP:$PORT 2>/dev/null | grep -c '^Discord')"
  else
    row "Çalışıyor" "Running" "$(t hayır no)"
  fi

  section "Sistem proxy / VPN" "System proxy / VPN"
  scutil --proxy 2>/dev/null | grep -E 'Enable|Proxy|Port' | sed 's/^ */  /'
  row "VPN bağlantıları" "VPN connections" "$(scutil --nc list 2>/dev/null | grep -c '(Connected)')"
  row "İlgili uygulamalar" "Related apps" "$(ps -axo comm= | grep -iE 'warp|vpn|wireguard|tailscale|outline|v2ray|clash|tunnelblick|sing-box|zapret' | xargs -n1 basename 2>/dev/null | sort -u | tr '\n' ' ')"

  if [[ $internet == ok ]]; then
    section "DNS" "DNS"
    row "Sistem DNS'i discord.com" "System DNS for discord.com" "$(dig +short +time=3 +tries=1 discord.com 2>/dev/null | head -3 | tr '\n' ' ')"
    row "DoH dns.google" "DoH dns.google" "$(curl -s -o /dev/null -m 6 -w '%{http_code}' -H 'accept: application/dns-json' 'https://dns.google/resolve?name=discord.com&type=A')"
    row "DoH cloudflare" "DoH cloudflare" "$(curl -s -o /dev/null -m 6 -w '%{http_code}' -H 'accept: application/dns-json' 'https://cloudflare-dns.com/dns-query?name=discord.com&type=A')"

    section "Discord erişimi (000 = ulaşılamadı)" "Discord reachability (000 = unreachable)"
    row "Proxy'siz (engelliyse 000 beklenir)" "Without the proxy (000 expected when blocked)" \
      "$(curl -s -o /dev/null -m 6 -w '%{http_code}' https://discord.com/api/v9/gateway)"
    for h in $HOSTS; do
      code=$(curl -s -o /dev/null -m 8 -x $PROXY -w '%{http_code}' "https://$h" 2>/dev/null)
      [[ -z $code ]] && code=000
      [[ $code == 000 ]] && live_ok=0
      live+="$code "
    done
    row "Çalışan proxy üzerinden" "Through the running proxy" "$live(${(j:, :)HOSTS})"

    section "Strateji testleri" "Strategy tests"
    for s in $STRATEGIES; do
      if codes=$(run_test "$s"); then
        [[ -z $working ]] && working=$s
        print -r -- "$(t "ÇALIŞIYOR " "WORKS ") $codes  $s"
      else
        print -r -- "$(t "çalışmıyor" "fails ") $codes  $s"
      fi
    done
  else
    live_ok=0
    print
    t "(İnternet olmadığı için DNS, erişim ve strateji testleri atlandı.)" \
      "(DNS, reachability and strategy tests were skipped because there is no internet.)"
  fi

  if [[ $internet == none ]]; then
    VERDICT=$(t "İnternet bağlantısı yok." "No internet connection.")
    ADVICE=$(t "Wi-Fi/kablo bağlantısını kontrol et." "Check the Wi-Fi or cable connection.")
  elif [[ $internet == portal ]]; then
    VERDICT=$(t "Ağ bir giriş sayfası istiyor (captive portal)." "The network wants a sign-in page (captive portal).")
    ADVICE=$(t "Tarayıcıdan ağın giriş sayfasını geçince kendiliğinden düzelir." \
      "It fixes itself once you get past the network's sign-in page in a browser.")
  elif ! "$SPOOF" --version > /dev/null 2>&1; then
    VERDICT=$(t "Kurulum bozuk: SpoofDPI çalışmıyor." "Broken install: SpoofDPI does not run.")
    ADVICE=$(t "Kurulum satırını yeniden çalıştır." "Run the install line again.")
  elif [[ -z $agent ]]; then
    VERDICT=$(t "Arka plan servisi yüklü değil." "The background service is not loaded.")
    ADVICE=$(t "Yardım uygulamasından Onar'ı çalıştır; olmazsa kurulum satırını yeniden çalıştır." \
      "Run Repair from the Help app; if that fails, run the install line again.")
  elif [[ -n $listener && $listener != spoofdpi* ]]; then
    VERDICT=$(t "$PORT portunu başka bir uygulama kullanıyor: $listener" "Another app is using port $PORT: $listener")
    ADVICE=$(t "O uygulamayı kapatıp Onar'ı çalıştır." "Quit that app, then run Repair.")
  elif (( live_ok )); then
    if [[ $discord_proxy == no ]]; then
      VERDICT=$(t "Proxy çalışıyor ama Discord proxy'siz açılmış." "The proxy works but Discord was started without it.")
      ADVICE=$(t "Birkaç saniye içinde kendiliğinden yeniden açılmalı; açılmazsa Onar'ı çalıştır." \
        "It should relaunch by itself within seconds; if it does not, run Repair.")
    else
      VERDICT=$(t "Bağlantı çalışıyor görünüyor: proxy üzerinden Discord'a ulaşılıyor." \
        "The connection looks fine: Discord is reachable through the proxy.")
      ADVICE=$(t "Sorun sürüyorsa ne olduğunu yaz (ör. sadece sesli kanal, sadece güncelleme ekranı)." \
        "If the problem persists, describe what fails (e.g. only voice channels, only the update screen).")
    fi
  elif [[ -n $working ]]; then
    VERDICT=$(t "Seçili strateji bu ağda çalışmıyor ama çalışan bir strateji var: $working" \
      "The selected strategy fails on this network but another one works: $working")
    ADVICE=$(t "Onar'ı çalıştır; servis bunu 5 dk içinde kendisi de düzeltir." \
      "Run Repair; the service also fixes this by itself within 5 minutes.")
  else
    VERDICT=$(t "Bu ağda hiçbir strateji çalışmıyor." "No strategy works on this network.")
    ADVICE=$(t "Bu ağ için VPN ya da Cloudflare WARP gerekebilir." "This network may need a VPN or Cloudflare WARP.")
  fi
}

cmd_diagnose() {
  TEST_PORT=8883
  local name="DiscordDPI-$(t tanilama diagnostics)-$USER-$(date +%Y%m%d-%H%M%S)"
  local tmp=$(mktemp -d) dest="$HOME/Desktop" f
  local out="$tmp/$name"
  mkdir -p "$out"

  collect > "$tmp/details.txt" 2>&1
  {
    t "SONUÇ: $VERDICT" "RESULT: $VERDICT"
    t "ÖNERİ: $ADVICE" "ADVICE: $ADVICE"
    print
    cat "$tmp/details.txt"
  } > "$out/$(t ozet summary).txt"
  for f in watch.log watch.log.1 spoofdpi.log spoofdpi.log.1; do
    [[ -f "$LOG_DIR/$f" ]] && tail -n 3000 "$LOG_DIR/$f" | strip_ansi > "$out/$f"
  done

  # Fall back to the home folder if writing to the Desktop is not permitted.
  if ! (cd "$tmp" && zip -qr "$dest/$name.zip" "$name") 2>/dev/null; then
    dest=$HOME
    (cd "$tmp" && zip -qr "$dest/$name.zip" "$name")
  fi
  rm -rf "$tmp"
  open -R "$dest/$name.zip"
  print -r -- "$dest/$name.zip"
}

cmd_repair() {
  TEST_PORT=8883
  local i
  if [[ ! -f $PLIST ]] || ! "$SPOOF" --version > /dev/null 2>&1; then
    t "Kurulum eksik görünüyor. Kurulum satırını yeniden çalıştır." \
      "The install looks incomplete. Run the install line again."
    return 1
  fi
  if ! online; then
    t "İnternet yok ya da ağ giriş sayfası istiyor. Önce internete bağlan, sonra tekrar dene." \
      "No internet, or the network wants a sign-in page. Get online first, then try again."
    return 1
  fi
  pick_strategy
  if launchctl print gui/$UID/$LABEL > /dev/null 2>&1; then
    launchctl kickstart -k gui/$UID/$LABEL > /dev/null 2>&1
  else
    launchctl bootstrap gui/$UID "$PLIST" > /dev/null 2>&1
  fi
  pgrep -xq Discord && stop_discord
  sleep 2
  for i in {1..10}; do probe $PORT && break; sleep 3; done
  launch
  if probe $PORT; then
    t "Onarıldı. Discord yeniden açılıyor." "Repaired. Discord is reopening."
  else
    t "Onarım Discord bağlantısını düzeltemedi. Yardım uygulamasından \"Sorun bildir\" ile log oluşturup gönder." \
      "Repair could not restore the Discord connection. Use \"Report a problem\" in the Help app to create a log and send it."
    return 1
  fi
}

cmd_uninstall() {
  local i app
  launchctl bootout gui/$UID/$LABEL > /dev/null 2>&1
  for i in {1..20}; do launchctl print gui/$UID/$LABEL > /dev/null 2>&1 || break; sleep 0.5; done
  pkill -f "^$SPOOF " 2>/dev/null
  rm -f "$PLIST"
  for app in $HELPER_APPS; do rm -rf "/Applications/$app" "$HOME/Applications/$app"; done
  rm -rf "$LOG_DIR" "$APP_DIR"
  t "Discord DPI kaldırıldı. Discord açıksa kapatıp yeniden aç." \
    "Discord DPI was removed. If Discord is open, quit and reopen it."
}

case $1 in
  watch)
    # In zsh an EXIT trap set inside a function is local to it, so set it here.
    trap '[[ -n $SPOOF_PID ]] && kill $SPOOF_PID 2>/dev/null' EXIT
    trap 'exit' INT TERM
    cmd_watch ;;
  diagnose) cmd_diagnose ;;
  repair) cmd_repair ;;
  uninstall) cmd_uninstall ;;
  lang) print -r -- $UI_LANG ;;
  *) t "kullanım: discord-dpi watch|diagnose|repair|uninstall|lang" "usage: discord-dpi watch|diagnose|repair|uninstall|lang"; exit 2 ;;
esac; exit
DISCORD_DPI_TOOL
chmod 755 "$TOOL"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$TOOL</string>
    <string>watch</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF

if [ -w /Applications ]; then APPS=/Applications; else APPS="$HOME/Applications"; mkdir -p "$APPS"; fi
rm -rf "/Applications/$HELPER_TR" "$HOME/Applications/$HELPER_TR" \
  "/Applications/$HELPER_EN" "$HOME/Applications/$HELPER_EN"

cat > "$TMP/helper.applescript" <<'DISCORD_DPI_APPLET'
set tool to quoted form of ((POSIX path of (path to home folder)) & "Library/Application Support/DiscordDPI/discord-dpi")

if (do shell script tool & " lang") is "tr" then
	set appTitle to "Discord DPI Yardım"
	set optReport to "Sorun bildir (log oluştur)"
	set optRepair to "Onar"
	set optRemove to "Kaldır"
	set promptText to "Ne yapmak istiyorsun?"
	set btnGo to "Devam"
	set btnCancel to "Vazgeç"
	set btnOK to "Tamam"
	set reportStart to "Tanılama başlıyor, yaklaşık 1 dakika sürer." & return & return & "Bitince dosya Finder'da seçili olarak açılacak."
	set reportReady to "Tanılama dosyası hazır:"
	set reportSend to "Finder'da seçili duran bu dosyayı, kurulumu sana gönderen kişiye ilet."
	set repairStart to "Onarım başlıyor, yaklaşık 1 dakika sürer. Discord kapanıp yeniden açılacak."
	set removeAsk to "Discord DPI kaldırılsın mı?" & return & return & "Discord uygulaması silinmez ama engel yüzünden bağlanamaz."
else
	set appTitle to "Discord DPI Help"
	set optReport to "Report a problem (create log)"
	set optRepair to "Repair"
	set optRemove to "Uninstall"
	set promptText to "What would you like to do?"
	set btnGo to "Continue"
	set btnCancel to "Cancel"
	set btnOK to "OK"
	set reportStart to "Diagnostics are starting; this takes about a minute." & return & return & "When done, the file will be shown selected in Finder."
	set reportReady to "The diagnostics file is ready:"
	set reportSend to "Send this file, selected in Finder, to the person who gave you the installer."
	set repairStart to "Repair is starting; this takes about a minute. Discord will close and reopen."
	set removeAsk to "Uninstall Discord DPI?" & return & return & "The Discord app is not removed, but it will not be able to connect because of the block."
end if

set picked to choose from list {optReport, optRepair, optRemove} with title appTitle with prompt promptText default items {optReport} OK button name btnGo cancel button name btnCancel
if picked is false then return
set choice to item 1 of picked

if choice is optReport then
	display dialog reportStart with title appTitle buttons {btnOK} default button 1 giving up after 6
	with timeout of 1800 seconds
		set zipPath to do shell script tool & " diagnose"
	end timeout
	display dialog reportReady & return & zipPath & return & return & reportSend with title appTitle buttons {btnOK} default button 1
else if choice is optRepair then
	display dialog repairStart with title appTitle buttons {btnOK} default button 1 giving up after 6
	try
		with timeout of 1800 seconds
			set msg to do shell script tool & " repair"
		end timeout
	on error errText
		set msg to errText
	end try
	display dialog msg with title appTitle buttons {btnOK} default button 1
else if choice is optRemove then
	set answer to display dialog removeAsk with title appTitle buttons {btnCancel, optRemove} default button btnCancel cancel button btnCancel
	if button returned of answer is optRemove then
		set msg to do shell script tool & " uninstall"
		display dialog msg with title appTitle buttons {btnOK} default button 1
	end if
end if
DISCORD_DPI_APPLET
osacompile -o "$APPS/$HELPER_APP" "$TMP/helper.applescript" > /dev/null 2>&1 \
  || die "Yardım uygulaması oluşturulamadı." "Could not create the Help app."

# --- 5. Start the service and wait for a working strategy -------------------------

step "Servis başlatılıyor ve bu ağda çalışan ayar aranıyor (1-2 dakika sürebilir)" \
  "Starting the service and finding a setting that works on this network (may take 1-2 minutes)"
launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST" 2>/dev/null \
  || die "Arka plan servisi yüklenemedi." "Could not load the background service."

discord_reachable() {
  [ "$(curl -s -o /dev/null -m 8 -x "$PROXY" -w '%{http_code}' https://discord.com/api/v9/gateway 2>/dev/null)" = "200" ]
}
OK=0
DEADLINE=$((SECONDS + 240))
while [ "$SECONDS" -lt "$DEADLINE" ]; do
  if discord_reachable; then OK=1; break; fi
  printf '.'
  sleep 3
done
printf '\n'

if [ "$OK" -ne 1 ]; then
  step "Discord'a ulaşılamadı; tanılama dosyası hazırlanıyor" "Could not reach Discord; preparing a diagnostics file"
  ZIP=$("$TOOL" diagnose)
  printf '\n\033[31m%s\033[0m\n' "$(t "Kurulum yapıldı ama bu ağda Discord bağlantısı kurulamadı." \
    "Installed, but could not connect to Discord on this network.")"
  printf '%s %s\n' "$(t "Tanılama dosyası:" "Diagnostics file:")" "$ZIP"
  say "Bu dosyayı kurulumu sana gönderen kişiye ilet." "Send this file to the person who gave you the installer."
  printf '\n'
  exit 1
fi

# --- 6. Install Discord if it is missing -------------------------------------------

if [ ! -d /Applications/Discord.app ] && [ ! -d "$HOME/Applications/Discord.app" ]; then
  step "Discord indiriliyor" "Downloading Discord"
  curl -fL --retry 2 --progress-bar -m 900 -x "$PROXY" -o "$TMP/Discord.dmg" \
    "https://discord.com/api/download?platform=osx" || die "Discord indirilemedi." "Could not download Discord."
  mkdir -p "$TMP/mnt"
  hdiutil attach -nobrowse -readonly -mountpoint "$TMP/mnt" "$TMP/Discord.dmg" > /dev/null \
    || die "Discord kurulum dosyası açılamadı." "Could not open the Discord disk image."
  cp -R "$TMP/mnt/Discord.app" "$APPS/" \
    || die "Discord $APPS klasörüne kopyalanamadı." "Could not copy Discord to $APPS."
  hdiutil detach "$TMP/mnt" > /dev/null 2>&1
fi

# --- 7. Open Discord ------------------------------------------------------------------

# If a Discord without the proxy is already open, the service relaunches it within seconds.
pgrep -xq Discord || open -a Discord --env HTTPS_PROXY=$PROXY --env HTTP_PROXY=$PROXY \
  --args --proxy-server=$PROXY

printf '\n\033[32m\033[1m%s\033[0m\n\n' "$(t "Kurulum tamam." "Installation complete.")"
say "Discord açılıyor. Bundan sonra Discord'u her zamanki gibi kendi ikonundan açabilirsin;" \
  "Discord is opening. From now on, open Discord from its own icon as usual;"
say "ilk açılışta bir kez kapanıp yeniden açılması normal." \
  "it is normal for it to close and reopen once when it starts."
printf '\n'
say "Sorun olursa: \"${HELPER_APP%.app}\" uygulamasını aç (Spotlight'a \"Discord DPI\" yaz)," \
  "If something goes wrong: open the \"${HELPER_APP%.app}\" app (type \"Discord DPI\" in Spotlight),"
say "\"Sorun bildir\"i seç ve oluşan dosyayı kurulumu sana gönderen kişiye ilet." \
  "choose \"Report a problem\" and send the resulting file to the person who gave you the installer."
printf '\n'
