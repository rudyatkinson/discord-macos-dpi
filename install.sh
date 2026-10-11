#!/bin/bash
# Discord DPI kurulumu (macOS).
#
# Türkiye'deki Discord engelini SpoofDPI ile aşar. SpoofDPI sadece 127.0.0.1:8881'de
# dinler ve onu yalnızca Discord kullanır; sistem proxy ayarına dokunulmaz, sudo gerekmez.
# Tekrar çalıştırmak güncelleme yerine geçer.
#
#   Kurulum : /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rudyatkinson/discord-macos-dpi/main/install.sh)"
#   Kaldırma: bash install.sh --uninstall   (ya da "Discord DPI Yardım" > Kaldır)

set -u

VERSION=1.0.0
SPOOF_VERSION=1.5.4
SPOOF_SHA_arm64=92f7dd41c3b414865410c5cc8c845915375ace9d03a8cf15b23fc7374c354bc6
SPOOF_SHA_x86_64=a39ad5361e3fe1a263cd4017583bc8ac4b8dbf6e4886f55ddeee0cfde3cf9255

APP_DIR="$HOME/Library/Application Support/DiscordDPI"
LOG_DIR="$HOME/Library/Logs/DiscordDPI"
TOOL="$APP_DIR/discord-dpi"
LABEL=local.discord-dpi
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HELPER_APP="Discord DPI Yardım.app"
PROXY=http://127.0.0.1:8881
DOMAIN="gui/$(id -u)"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[31mHATA: %s\033[0m\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  [ -x "$TOOL" ] || die "Discord DPI kurulu görünmüyor."
  "$TOOL" uninstall
  exit $?
fi

# --- 1. Kontroller ---------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || die "Bu kurulum sadece macOS içindir."
[ "$(id -u)" -ne 0 ] || die "Bu komutu sudo ile çalıştırma; başına sudo yazmadan tekrar dene."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 12 ] || die "macOS 12 ya da daha yenisi gerekiyor."

if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
  ARCH=arm64; SPOOF_SHA=$SPOOF_SHA_arm64
else
  ARCH=x86_64; SPOOF_SHA=$SPOOF_SHA_x86_64
fi

TMP=$(mktemp -d) || die "Geçici klasör oluşturulamadı."
trap 'hdiutil detach "$TMP/mnt" > /dev/null 2>&1; rm -rf "$TMP"' EXIT

# --- 2. Önceki kurulumu durdur ---------------------------------------------

step "Hazırlanıyor"
unload_agent() {
  launchctl bootout "$DOMAIN/$1" > /dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print "$DOMAIN/$1" > /dev/null 2>&1 || return 0
    sleep 0.5
  done
}
unload_agent "$LABEL"

# İlk elle kurulumdan kalanlar.
unload_agent com.bilal.discord-dpi
rm -f "$HOME/Library/LaunchAgents/com.bilal.discord-dpi.plist" \
  "$HOME/.local/bin/discord-dpi" "$HOME/.local/bin/discord-dpi-watch" \
  "$HOME/Library/Logs/discord-dpi.log" "$HOME/.cache/discord-dpi.pid"
rm -rf "$HOME/Applications/Discord DPI.app"

mkdir -p "$APP_DIR/bin" "$LOG_DIR" "$HOME/Library/LaunchAgents" || die "Klasörler oluşturulamadı."

# --- 3. SpoofDPI ------------------------------------------------------------

step "SpoofDPI $SPOOF_VERSION indiriliyor ($ARCH)"
URL="https://github.com/xvzc/spoofdpi/releases/download/v$SPOOF_VERSION/spoofdpi_${SPOOF_VERSION}_darwin_$ARCH.tar.gz"
curl -fL --retry 3 --progress-bar -m 300 -o "$TMP/spoofdpi.tar.gz" "$URL" \
  || die "SpoofDPI indirilemedi. İnternet bağlantını kontrol edip tekrar dene."
[ "$(shasum -a 256 "$TMP/spoofdpi.tar.gz" | cut -d' ' -f1)" = "$SPOOF_SHA" ] \
  || die "İndirilen SpoofDPI dosyası doğrulanamadı (SHA256 uyuşmuyor)."
tar -xzf "$TMP/spoofdpi.tar.gz" -C "$TMP" spoofdpi || die "SpoofDPI arşivi açılamadı."
mv -f "$TMP/spoofdpi" "$APP_DIR/bin/spoofdpi" && chmod 755 "$APP_DIR/bin/spoofdpi"
"$APP_DIR/bin/spoofdpi" --version > /dev/null 2>&1 || die "SpoofDPI bu Mac'te çalışmadı."

# --- 4. Servis script'i, LaunchAgent, Yardım uygulaması ----------------------

step "Servis kuruluyor"
printf '%s\n' "$VERSION" > "$APP_DIR/VERSION"

cat > "$TOOL" <<'DISCORD_DPI_TOOL'
#!/bin/zsh
# Discord DPI — SpoofDPI'ı yalnızca Discord için çalıştıran yardımcı.
#   watch      arka plan servisi (LaunchAgent bunu çalıştırır)
#   diagnose   tanılama zip'i üretir, yolunu yazar
#   repair     çalışan stratejiyi yeniden seçer, servisi ve Discord'u yeniden başlatır
#   uninstall  her şeyi kaldırır (Discord'a dokunmaz)
# Sistem proxy ayarına dokunmaz; proxy'yi sadece --proxy-server ile açılan Discord kullanır.

zmodload zsh/datetime

# LaunchAgent ve Yardım uygulaması farklı ortamlarla çalıştırır; ikisinde de aynı olsun.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
USER=${USER:-$(id -un)}

APP_DIR="$HOME/Library/Application Support/DiscordDPI"
LOG_DIR="$HOME/Library/Logs/DiscordDPI"
SPOOF="$APP_DIR/bin/spoofdpi"
STRATEGY_FILE="$APP_DIR/strategy"
LABEL=local.discord-dpi
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HELPER_APP="Discord DPI Yardım.app"
PORT=8881
TEST_PORT=8882
PROXY=http://127.0.0.1:$PORT
VERSION=$(cat "$APP_DIR/VERSION" 2>/dev/null)
HOSTS=(discord.com/api/v9/gateway gateway.discord.gg cdn.discordapp.com)

# Sırayla denenir, üç Discord adresine de ulaşan ilki kullanılır. Operatöre göre
# hangisinin çalıştığı değişir; SpoofDPI'ın varsayılanı (sni) çoğu ağda yetmiyor.
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

log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" }
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

# Dosya 1 MB'ı geçtiyse son kısmını .1 olarak saklar ve dosyayı boşaltır.
trim_log() {
  [[ -f $1 ]] || return 0
  (( $(stat -f%z "$1") > 1048576 )) || return 0
  tail -c 262144 "$1" > "$1.1"
  : > "$1"
}

# probe <port>: o porttaki proxy üzerinden üç Discord adresi de yanıt veriyorsa 0.
probe() {
  local h code
  for h in $HOSTS; do
    code=$(curl -s -o /dev/null -m 8 -x http://127.0.0.1:$1 -w '%{http_code}' "https://$h" 2>/dev/null)
    [[ -z $code || $code == 000 ]] && return 1
  done
  return 0
}

# run_test <bayraklar> [fast]: stratejiyi geçici portta dener, adres başına HTTP kodunu
# yazar (000 = engellendi). fast verilirse ilk başarısız adreste durur.
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
    codes="proxy açılamadı"
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
  # Önceki servisten kalmış bir SpoofDPI varsa portu bırakması için kapat.
  pkill -f "^$SPOOF --no-tui --clean --listen-addr 127.0.0.1:$PORT " 2>/dev/null && sleep 1
  "$SPOOF" --no-tui --clean --listen-addr 127.0.0.1:$PORT --dns-mode https ${=flags} >> "$LOG_DIR/spoofdpi.log" 2>&1 &
  SPOOF_PID=$!
  wait_port $PORT
  sleep 0.5
  if kill -0 $SPOOF_PID 2>/dev/null; then
    log "SpoofDPI çalışıyor (pid $SPOOF_PID, strateji: $flags)"
    return 0
  fi
  log "SpoofDPI başlatılamadı; $PORT portu başka bir uygulamada olabilir. 30 sn sonra yeniden denenecek."
  SPOOF_PID=
  return 1
}

# Canlı proxy'den Discord'a ulaşılamıyorsa çalışan stratejiyi yeniden seçer.
# force=1 iken (açılış, ağ değişimi, Discord'un yeni açılması) 5 dk beklemeden seçer.
health_check() {
  local old new
  trim_log "$LOG_DIR/spoofdpi.log"
  trim_log "$LOG_DIR/watch.log"
  if probe $PORT || { sleep 3; probe $PORT }; then
    (( offline || bad )) && log "Discord'a proxy üzerinden ulaşılıyor"
    offline=0; bad=0; force=0
    next_check=$(( EPOCHSECONDS + 60 ))
    return 0
  fi
  if ! online; then
    (( offline )) || log "internet yok ya da ağ giriş sayfası istiyor; bekleniyor"
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
  log "Discord'a ulaşılamıyor (strateji: $old); stratejiler deneniyor"
  if pick_strategy; then
    new=$(current_strategy)
    log "çalışan strateji: $new"
    bad=0
    if [[ $new != $old ]]; then
      kill $SPOOF_PID 2>/dev/null
      wait $SPOOF_PID 2>/dev/null
      start_spoof
    fi
  else
    (( bad )) || log "bu ağda hiçbir strateji çalışmadı"
    bad=1
  fi
}

cmd_watch() {
  mkdir -p "$LOG_DIR"
  trim_log "$LOG_DIR/watch.log"
  exec >> "$LOG_DIR/watch.log" 2>&1
  log "servis başladı (sürüm $VERSION, macOS $(sw_vers -productVersion), $(uname -m))"

  local retries=0 was_running=0 running net="" cur
  force=1 next_check=0 last_pick=0 offline=0 bad=0
  while true; do
    if [[ -z $SPOOF_PID ]] || ! kill -0 $SPOOF_PID 2>/dev/null; then
      start_spoof || { sleep 30; continue }
      force=1; next_check=0
    fi

    cur=$(net_sig)
    if [[ $cur != $net ]]; then
      [[ -n $net ]] && log "ağ değişti: ${cur:-bağlantı yok}"
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
      # Art arda 3 denemede proxy'li açılamazsa kapat-aç döngüsüne girme, 1 dk bekle.
      if (( retries >= 3 )); then
        log "Discord 3 denemede proxy ile açılamadı; 1 dk bekleniyor"
        sleep 60
        retries=0
      else
        (( retries++ ))
        log "Discord proxy'siz açılmış; proxy ile yeniden açılıyor (deneme $retries)"
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

# Tanılama ayrıntılarını yazar; VERDICT ve ADVICE'ı doldurur.
collect() {
  local cap internet agent listener s codes working="" live="" live_ok=1 h code app found=0 pids discord_proxy=""

  print "== Genel =="
  print "Tarih: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  print "Discord DPI sürümü: ${VERSION:-bilinmiyor}"
  print "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"
  print "Kullanıcı: $USER"
  print "SpoofDPI: $("$SPOOF" --version 2>&1 | head -1)"

  print "\n== İnternet =="
  cap=$(curl -s -m 6 http://captive.apple.com/hotspot-detect.html 2>/dev/null)
  if [[ $cap == *Success* ]]; then internet=var
  elif [[ -n $cap ]]; then internet="giriş sayfası (captive portal)"
  else internet=yok
  fi
  print "İnternet: $internet"
  print "Ağ geçidi / arayüz: $(route -n get default 2>/dev/null | awk '/gateway:|interface:/{printf "%s ", $2}')"
  print "DNS sunucuları: $(scutil --dns 2>/dev/null | awk '/nameserver\[/{print $3}' | sort -u | tr '\n' ' ')"
  [[ $internet == var ]] && print "Operatör: $(curl -s -m 6 https://ipinfo.io/org 2>/dev/null)"

  print "\n== Servis =="
  agent=$(launchctl print gui/$UID/$LABEL 2>/dev/null | awk '/^\tstate =|^\tpid =|^\truns =|^\tlast exit code =/{$1=$1; printf "%s; ", $0}')
  print "LaunchAgent: ${agent:-YÜKLÜ DEĞİL}"
  listener=$(lsof -nP -iTCP:$PORT -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $1" (pid "$2")"}' | sort -u | tr '\n' ' ')
  print "Port $PORT dinleyen: ${listener:-yok}"
  print "Seçili strateji: $(cat "$STRATEGY_FILE" 2>/dev/null || print yok)"

  print "\n== Discord =="
  for app in /Applications/Discord.app "$HOME/Applications/Discord.app"; do
    if [[ -d $app ]]; then
      found=1
      print "Kurulu: $app (sürüm $(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null))"
    fi
  done
  (( found )) || print "Kurulu: BULUNAMADI"
  pids=$(pgrep -x Discord | tr '\n' ' ')
  if [[ -n $pids ]]; then
    print "Çalışıyor: evet (pid $pids)"
    if has_proxy; then discord_proxy=var; else discord_proxy=YOK; fi
    print "Proxy bayrağı: $discord_proxy"
    print "Proxy'ye açık bağlantı sayısı: $(lsof -nP -iTCP:$PORT 2>/dev/null | grep -c '^Discord')"
  else
    print "Çalışıyor: hayır"
  fi

  print "\n== Sistem proxy / VPN =="
  scutil --proxy 2>/dev/null | grep -E 'Enable|Proxy|Port' | sed 's/^ */  /'
  print "VPN bağlantıları: $(scutil --nc list 2>/dev/null | grep -c '(Connected)')"
  print "İlgili uygulamalar: $(ps -axo comm= | grep -iE 'warp|vpn|wireguard|tailscale|outline|v2ray|clash|tunnelblick|sing-box|zapret' | xargs -n1 basename 2>/dev/null | sort -u | tr '\n' ' ')"

  if [[ $internet == var ]]; then
    print "\n== DNS =="
    print "Sistem DNS'i discord.com: $(dig +short +time=3 +tries=1 discord.com 2>/dev/null | head -3 | tr '\n' ' ')"
    print "DoH dns.google: $(curl -s -o /dev/null -m 6 -w '%{http_code}' -H 'accept: application/dns-json' 'https://dns.google/resolve?name=discord.com&type=A')"
    print "DoH cloudflare: $(curl -s -o /dev/null -m 6 -w '%{http_code}' -H 'accept: application/dns-json' 'https://cloudflare-dns.com/dns-query?name=discord.com&type=A')"

    print "\n== Discord erişimi (000 = ulaşılamadı) =="
    print "Proxy'siz (engelliyse 000 beklenir): $(curl -s -o /dev/null -m 6 -w '%{http_code}' https://discord.com/api/v9/gateway)"
    for h in $HOSTS; do
      code=$(curl -s -o /dev/null -m 8 -x $PROXY -w '%{http_code}' "https://$h" 2>/dev/null)
      [[ -z $code ]] && code=000
      [[ $code == 000 ]] && live_ok=0
      live+="$code "
    done
    print "Çalışan proxy üzerinden: $live(${(j:, :)HOSTS})"

    print "\n== Strateji testleri =="
    for s in $STRATEGIES; do
      if codes=$(run_test "$s"); then
        [[ -z $working ]] && working=$s
        print "ÇALIŞIYOR  $codes  $s"
      else
        print "çalışmıyor $codes  $s"
      fi
    done
  else
    live_ok=0
    print "\n(İnternet olmadığı için DNS, erişim ve strateji testleri atlandı.)"
  fi

  if [[ $internet == yok ]]; then
    VERDICT="İnternet bağlantısı yok."
    ADVICE="Wi-Fi/kablo bağlantısını kontrol et."
  elif [[ $internet != var ]]; then
    VERDICT="Ağ bir giriş sayfası istiyor (captive portal)."
    ADVICE="Tarayıcıdan ağın giriş sayfasını geçince kendiliğinden düzelir."
  elif ! "$SPOOF" --version > /dev/null 2>&1; then
    VERDICT="Kurulum bozuk: SpoofDPI çalışmıyor."
    ADVICE="Kurulum satırını yeniden çalıştır."
  elif [[ -z $agent ]]; then
    VERDICT="Arka plan servisi yüklü değil."
    ADVICE="Yardım uygulamasından Onar'ı çalıştır; olmazsa kurulum satırını yeniden çalıştır."
  elif [[ -n $listener && $listener != spoofdpi* ]]; then
    VERDICT="$PORT portunu başka bir uygulama kullanıyor: $listener"
    ADVICE="O uygulamayı kapatıp Onar'ı çalıştır."
  elif (( live_ok )); then
    if [[ $discord_proxy == YOK ]]; then
      VERDICT="Proxy çalışıyor ama Discord proxy'siz açılmış."
      ADVICE="Birkaç saniye içinde kendiliğinden yeniden açılmalı; açılmazsa Onar'ı çalıştır."
    else
      VERDICT="Bağlantı çalışıyor görünüyor: proxy üzerinden Discord'a ulaşılıyor."
      ADVICE="Sorun sürüyorsa ne olduğunu yaz (ör. sadece sesli kanal, sadece güncelleme ekranı)."
    fi
  elif [[ -n $working ]]; then
    VERDICT="Seçili strateji bu ağda çalışmıyor ama çalışan bir strateji var: $working"
    ADVICE="Onar'ı çalıştır; servis bunu 5 dk içinde kendisi de düzeltir."
  else
    VERDICT="Bu ağda hiçbir strateji çalışmıyor."
    ADVICE="Bu ağ için VPN ya da Cloudflare WARP gerekebilir."
  fi
}

cmd_diagnose() {
  TEST_PORT=8883
  local name="DiscordDPI-tanilama-$USER-$(date +%Y%m%d-%H%M%S)"
  local tmp=$(mktemp -d) dest="$HOME/Desktop" f
  local out="$tmp/$name"
  mkdir -p "$out"

  collect > "$tmp/detay.txt" 2>&1
  { print "SONUÇ: $VERDICT"; print "ÖNERİ: $ADVICE"; print; cat "$tmp/detay.txt" } > "$out/ozet.txt"
  for f in watch.log watch.log.1 spoofdpi.log spoofdpi.log.1; do
    [[ -f "$LOG_DIR/$f" ]] && tail -n 3000 "$LOG_DIR/$f" | strip_ansi > "$out/$f"
  done

  # Masaüstüne yazma izni verilmezse ev klasörüne düş.
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
    print "Kurulum eksik görünüyor. Kurulum satırını yeniden çalıştır."
    return 1
  fi
  if ! online; then
    print "İnternet yok ya da ağ giriş sayfası istiyor. Önce internete bağlan, sonra tekrar dene."
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
    print "Onarıldı. Discord yeniden açılıyor."
  else
    print "Onarım Discord bağlantısını düzeltemedi. Yardım uygulamasından \"Sorun bildir\" ile log oluşturup gönder."
    return 1
  fi
}

cmd_uninstall() {
  local i
  launchctl bootout gui/$UID/$LABEL > /dev/null 2>&1
  for i in {1..20}; do launchctl print gui/$UID/$LABEL > /dev/null 2>&1 || break; sleep 0.5; done
  pkill -f "^$SPOOF " 2>/dev/null
  rm -f "$PLIST"
  rm -rf "/Applications/$HELPER_APP" "$HOME/Applications/$HELPER_APP" "$LOG_DIR" "$APP_DIR"
  print "Discord DPI kaldırıldı. Discord açıksa kapatıp yeniden aç."
}

case $1 in
  watch)
    # zsh'te fonksiyon içindeki EXIT tuzağı fonksiyona özel olduğu için burada kurulur.
    trap '[[ -n $SPOOF_PID ]] && kill $SPOOF_PID 2>/dev/null' EXIT
    trap 'exit' INT TERM
    cmd_watch ;;
  diagnose) cmd_diagnose ;;
  repair) cmd_repair ;;
  uninstall) cmd_uninstall ;;
  *) print "kullanım: discord-dpi watch|diagnose|repair|uninstall"; exit 2 ;;
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
rm -rf "/Applications/$HELPER_APP" "$HOME/Applications/$HELPER_APP"

cat > "$TMP/yardim.applescript" <<'DISCORD_DPI_APPLET'
set tool to quoted form of ((POSIX path of (path to home folder)) & "Library/Application Support/DiscordDPI/discord-dpi")
set appTitle to "Discord DPI Yardım"
set optReport to "Sorun bildir (log oluştur)"
set optRepair to "Onar"
set optRemove to "Kaldır"

set picked to choose from list {optReport, optRepair, optRemove} with title appTitle with prompt "Ne yapmak istiyorsun?" default items {optReport} OK button name "Devam" cancel button name "Vazgeç"
if picked is false then return
set choice to item 1 of picked

if choice is optReport then
	display dialog "Tanılama başlıyor, yaklaşık 1 dakika sürer." & return & return & "Bitince dosya Finder'da seçili olarak açılacak." with title appTitle buttons {"Tamam"} default button 1 giving up after 6
	with timeout of 1800 seconds
		set zipPath to do shell script tool & " diagnose"
	end timeout
	display dialog "Tanılama dosyası hazır:" & return & zipPath & return & return & "Finder'da seçili duran bu dosyayı, kurulumu sana gönderen kişiye ilet." with title appTitle buttons {"Tamam"} default button 1
else if choice is optRepair then
	display dialog "Onarım başlıyor, yaklaşık 1 dakika sürer. Discord kapanıp yeniden açılacak." with title appTitle buttons {"Tamam"} default button 1 giving up after 6
	try
		with timeout of 1800 seconds
			set msg to do shell script tool & " repair"
		end timeout
	on error errText
		set msg to errText
	end try
	display dialog msg with title appTitle buttons {"Tamam"} default button 1
else if choice is optRemove then
	set answer to display dialog "Discord DPI kaldırılsın mı?" & return & return & "Discord uygulaması silinmez ama engel yüzünden bağlanamaz." with title appTitle buttons {"Vazgeç", "Kaldır"} default button "Vazgeç" cancel button "Vazgeç"
	if button returned of answer is "Kaldır" then
		set msg to do shell script tool & " uninstall"
		display dialog msg with title appTitle buttons {"Tamam"} default button 1
	end if
end if
DISCORD_DPI_APPLET
osacompile -o "$APPS/$HELPER_APP" "$TMP/yardim.applescript" > /dev/null 2>&1 \
  || die "Yardım uygulaması oluşturulamadı."

# --- 5. Servisi başlat, çalışan stratejiyi bekle ----------------------------

step "Servis başlatılıyor ve bu ağda çalışan ayar aranıyor (1-2 dakika sürebilir)"
launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST" 2>/dev/null \
  || die "Arka plan servisi yüklenemedi."

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
  step "Discord'a ulaşılamadı; tanılama dosyası hazırlanıyor"
  ZIP=$("$TOOL" diagnose)
  printf '\n\033[31mKurulum yapıldı ama bu ağda Discord bağlantısı kurulamadı.\033[0m\n'
  printf 'Tanılama dosyası: %s\n' "$ZIP"
  printf 'Bu dosyayı kurulumu sana gönderen kişiye ilet.\n\n'
  exit 1
fi

# --- 6. Discord kurulu değilse kur -------------------------------------------

if [ ! -d /Applications/Discord.app ] && [ ! -d "$HOME/Applications/Discord.app" ]; then
  step "Discord indiriliyor"
  curl -fL --retry 2 --progress-bar -m 900 -x "$PROXY" -o "$TMP/Discord.dmg" \
    "https://discord.com/api/download?platform=osx" || die "Discord indirilemedi."
  mkdir -p "$TMP/mnt"
  hdiutil attach -nobrowse -readonly -mountpoint "$TMP/mnt" "$TMP/Discord.dmg" > /dev/null \
    || die "Discord kurulum dosyası açılamadı."
  cp -R "$TMP/mnt/Discord.app" "$APPS/" || die "Discord $APPS klasörüne kopyalanamadı."
  hdiutil detach "$TMP/mnt" > /dev/null 2>&1
fi

# --- 7. Discord'u aç ----------------------------------------------------------

# Açık ve proxy'siz bir Discord varsa servis onu birkaç saniyede kendisi yeniden açar.
pgrep -xq Discord || open -a Discord --env HTTPS_PROXY=$PROXY --env HTTP_PROXY=$PROXY \
  --args --proxy-server=$PROXY

printf '\n\033[32m\033[1mKurulum tamam.\033[0m\n\n'
printf 'Discord açılıyor. Bundan sonra Discord'"'"'u her zamanki gibi kendi ikonundan açabilirsin;\n'
printf 'ilk açılışta bir kez kapanıp yeniden açılması normal.\n\n'
printf 'Sorun olursa: "%s" uygulamasını aç (Spotlight'"'"'a "Discord DPI" yaz),\n' "${HELPER_APP%.app}"
printf '"Sorun bildir"i seç ve oluşan dosyayı kurulumu sana gönderen kişiye ilet.\n\n'
