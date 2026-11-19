# Discord DPI (macOS)

**[English](#english)** | **[Türkçe](#türkçe)**

---

## English

A small installer that gets Discord past the block in Türkiye. It runs [SpoofDPI](https://github.com/xvzc/SpoofDPI) for Discord only: it is not a VPN, does not slow down your internet, and does not touch other apps or your browser.

Everything it shows (installer, Help app, logs) is in Turkish when your Mac's language is Turkish and in English otherwise.

### Install

1. Open **Terminal** (`⌘ + Space`, type "Terminal", press Enter).
2. Copy the line below, paste it, and press Enter:

   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rudyatkinson/discord-macos-dpi/main/install.sh)"
   ```

3. Wait for "Installation complete." (1-2 minutes). Discord opens by itself.

No password is asked. If Discord is not installed, the installer downloads it too.

From now on, open Discord from its own icon as usual. It is normal for it to close and reopen once when it starts.

### If something goes wrong

1. Open the **Discord DPI Help** app (`⌘ + Space`, type "Discord DPI", press Enter).
2. Choose **Report a problem (create log)**, press **Continue**, and wait about a minute.
3. A file named `DiscordDPI-diagnostics-...zip` appears on your Desktop and is shown selected in Finder. Send that file to the person who gave you the installer.

If macOS asks for access to the Desktop folder, press **Allow**. Without it, the file is written to your home folder instead.

**Repair** in the same app fixes most problems by itself (try it first if Discord does not connect after you switch networks). **Uninstall** removes everything except Discord itself.

### Update

Run the install line again.

### For the person managing it

#### How it works

- SpoofDPI listens only on `127.0.0.1:8881`. The system proxy settings are not changed; only a Discord started with the `--proxy-server` flag uses the proxy.
- A LaunchAgent (`local.discord-dpi`) starts at login and:
  - keeps SpoofDPI running;
  - relaunches Discord with the proxy whenever it was started without it (Dock icon, launch at login, restart after an update);
  - tests the connection every minute while Discord is open, and immediately when the network changes. If Discord is unreachable it tries the fragmentation strategies in order and switches to one that works.
- No `sudo` is needed; everything lives in the user's own folders.

#### Installed files

| Path | What |
|---|---|
| `~/Library/Application Support/DiscordDPI/` | `bin/spoofdpi`, the `discord-dpi` script, the selected `strategy`, `VERSION` |
| `~/Library/LaunchAgents/local.discord-dpi.plist` | Background service |
| `~/Library/Logs/DiscordDPI/` | `watch.log` (service), `spoofdpi.log` |
| `/Applications/Discord DPI Help.app` | Help app (`~/Applications` if `/Applications` is not writable; named `Discord DPI Yardım.app` on Turkish systems) |

#### Reading the diagnostics zip

`summary.txt` (`ozet.txt` on Turkish systems) starts with a one-line **RESULT** and **ADVICE**:

| RESULT | Meaning |
|---|---|
| No internet connection / The network wants a sign-in page | Not our problem; it fixes itself once the Mac is online. |
| Connections are being refused | Something answers with a reset instead of letting traffic out: usually a VPN/firewall app on the Mac (kill switch, dead tunnel) or the router. The "Raw connectivity" and "System proxy / VPN" sections show which. Restarting Discord DPI does not help. |
| Broken install / The background service is not loaded | The install line must be run again. |
| Another app is using port 8881 | The named app must be quit. |
| The selected strategy fails but another one works | **Repair** fixes it; the service also switches by itself within 5 minutes. |
| No strategy works on this network | SpoofDPI is not enough for this ISP or network; a VPN or WARP is needed. |
| The connection looks fine | The proxy is healthy; the problem is elsewhere (e.g. voice channels). Ask the user exactly what fails. |

The sections below it list the ISP name, DNS answers, running VPNs and the test result of every strategy (`000` = blocked). `watch.log` shows what the service did and when; `spoofdpi.log` holds SpoofDPI's warnings. The zip contains no Discord account data and no public IP address.

#### Language

The language follows the Mac's system language. To force one, set `DISCORD_DPI_LANG` when installing:

```
DISCORD_DPI_LANG=en /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rudyatkinson/discord-macos-dpi/main/install.sh)"
```

#### Command line

```
"$HOME/Library/Application Support/DiscordDPI/discord-dpi" diagnose   # builds the zip, prints its path
"$HOME/Library/Application Support/DiscordDPI/discord-dpi" repair
"$HOME/Library/Application Support/DiscordDPI/discord-dpi" uninstall
```

#### Known limits

- Voice channels use UDP, which does not go through the proxy. They work if UDP is not blocked; if it is, this tool does not fix it.
- Not tested on Intel Macs or on non-admin accounts.
- If a new strategy is needed, add it to the `STRATEGIES` list in `install.sh`.

---

## Türkçe

Türkiye'deki Discord engelini aşmak için küçük bir kurulum. [SpoofDPI](https://github.com/xvzc/SpoofDPI)'ı sadece Discord için çalıştırır: VPN değildir, internet hızını etkilemez, diğer uygulamalara ve tarayıcıya dokunmaz.

Gösterdiği her şey (kurulum, Yardım uygulaması, loglar) Mac'inin dili Türkçe ise Türkçe, değilse İngilizcedir.

### Kurulum

1. **Terminal**'i aç (`⌘ + Boşluk`, "Terminal" yaz, Enter).
2. Aşağıdaki satırı kopyalayıp yapıştır ve Enter'a bas:

   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rudyatkinson/discord-macos-dpi/main/install.sh)"
   ```

3. "Kurulum tamam." yazısını bekle (1-2 dakika). Discord kendiliğinden açılır.

Şifre sorulmaz. Discord kurulu değilse kurulum onu da indirir.

Bundan sonra Discord'u her zamanki gibi kendi ikonundan açabilirsin. Açılırken bir kez kapanıp yeniden açılması normaldir.

### Sorun olursa

1. **Discord DPI Yardım** uygulamasını aç (`⌘ + Boşluk`, "Discord DPI" yaz, Enter).
2. **Sorun bildir (log oluştur)** seçip **Devam**'a bas, yaklaşık 1 dakika bekle.
3. Masaüstünde `DiscordDPI-tanilama-...zip` adlı bir dosya oluşur ve Finder'da seçili açılır. Bu dosyayı kurulumu sana gönderen kişiye ilet.

macOS Masaüstü klasörüne erişim izni sorarsa **İzin Ver**'e bas. İzin verilmezse dosya ev klasörüne yazılır.

Aynı uygulamadaki **Onar** çoğu sorunu kendisi çözer (yeni bir ağa geçince bağlanmıyorsa önce bunu dene). **Kaldır** Discord'un kendisi dışında her şeyi siler.

### Güncelleme

Kurulum satırını tekrar çalıştırmak yeterli.

### Yöneten kişi için

#### Nasıl çalışır

- SpoofDPI yalnızca `127.0.0.1:8881`'de dinler. Sistem proxy ayarı değişmez; proxy'yi sadece `--proxy-server` bayrağıyla açılan Discord kullanır.
- Bir LaunchAgent (`local.discord-dpi`) oturum açılışında başlar ve şunları yapar:
  - SpoofDPI'ı ayakta tutar.
  - Discord proxy'siz açılmışsa (Dock ikonu, açılışta otomatik başlama, güncelleme sonrası yeniden başlama) kapatıp proxy ile yeniden açar.
  - Discord açıkken dakikada bir, ağ değişince hemen bağlantıyı test eder. Discord'a ulaşılamıyorsa parçalama stratejilerini sırayla dener ve çalışanına geçer.
- `sudo` gerekmez, her şey kullanıcının kendi klasörlerindedir.

#### Kurulan dosyalar

| Yol | Ne |
|---|---|
| `~/Library/Application Support/DiscordDPI/` | `bin/spoofdpi`, `discord-dpi` script'i, seçili `strategy`, `VERSION` |
| `~/Library/LaunchAgents/local.discord-dpi.plist` | Arka plan servisi |
| `~/Library/Logs/DiscordDPI/` | `watch.log` (servis), `spoofdpi.log` |
| `/Applications/Discord DPI Yardım.app` | Yardım uygulaması (`/Applications` yazılamıyorsa `~/Applications`; İngilizce sistemlerde adı `Discord DPI Help.app`) |

#### Tanılama zip'ini okumak

`ozet.txt` (İngilizce sistemlerde `summary.txt`) en üstte tek satırlık bir **SONUÇ** ve **ÖNERİ** ile başlar:

| SONUÇ | Anlamı |
|---|---|
| İnternet bağlantısı yok / Ağ bir giriş sayfası istiyor | Sorun bizde değil; Mac internete bağlanınca düzelir. |
| Bağlantılar reddediliyor | Trafik dışarı çıkmak yerine reset ile yanıtlanıyor: genelde Mac'teki bir VPN/güvenlik duvarı uygulaması (kill switch, ölü tünel) ya da modem. Hangisi olduğunu "Ham bağlantı" ve "Sistem proxy / VPN" bölümleri gösterir. Discord DPI'yi yeniden başlatmak çözmez. |
| Kurulum bozuk / Arka plan servisi yüklü değil | Kurulum satırı yeniden çalıştırılmalı. |
| 8881 portunu başka bir uygulama kullanıyor | Adı yazan uygulama kapatılmalı. |
| Seçili strateji çalışmıyor ama çalışan var | **Onar** düzeltir; servis de 5 dk içinde kendisi geçer. |
| Bu ağda hiçbir strateji çalışmıyor | Bu operatörde ya da ağda SpoofDPI yetmiyor; VPN ya da WARP gerekir. |
| Bağlantı çalışıyor görünüyor | Proxy sağlam; sorun başka yerde (ör. sesli kanal). Kullanıcıya tam olarak neyin çalışmadığını sor. |

Altındaki bölümlerde operatör adı, DNS yanıtları, çalışan VPN'ler ve her stratejinin test sonucu yer alır (`000` = engellendi). `watch.log` servisin ne zaman ne yaptığını, `spoofdpi.log` SpoofDPI'ın uyarılarını gösterir. Zip'te Discord hesabına ait veri ya da açık IP adresi yoktur.

#### Dil

Dil, Mac'in sistem dilini izler. Birini zorlamak için kurulumda `DISCORD_DPI_LANG` ver:

```
DISCORD_DPI_LANG=tr /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rudyatkinson/discord-macos-dpi/main/install.sh)"
```

#### Komut satırı

```
"$HOME/Library/Application Support/DiscordDPI/discord-dpi" diagnose   # zip üretir, yolunu yazar
"$HOME/Library/Application Support/DiscordDPI/discord-dpi" repair
"$HOME/Library/Application Support/DiscordDPI/discord-dpi" uninstall
```

#### Bilinen sınırlar

- Sesli kanallar UDP kullanır ve UDP proxy'den geçmez. UDP engellenmiyorsa çalışır; engelleniyorsa bu araç çözmez.
- Intel Mac'lerde ve yönetici olmayan hesaplarda denenmedi.
- Yeni bir strateji gerekirse `install.sh` içindeki `STRATEGIES` listesine eklenir.
