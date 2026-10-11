# Discord DPI (macOS)

Türkiye'deki Discord engelini aşmak için küçük bir kurulum. [SpoofDPI](https://github.com/xvzc/SpoofDPI)'ı sadece Discord için çalıştırır: VPN değildir, internet hızını etkilemez, diğer uygulamalara ve tarayıcıya dokunmaz.

## Kurulum

1. **Terminal**'i aç (`⌘ + Boşluk`, "Terminal" yaz, Enter).
2. Aşağıdaki satırı kopyalayıp yapıştır ve Enter'a bas:

   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rudyatkinson/discord-macos-dpi/main/install.sh)"
   ```

3. "Kurulum tamam." yazısını bekle (1-2 dakika). Discord kendiliğinden açılır.

Şifre sorulmaz. Discord kurulu değilse kurulum onu da indirir.

Bundan sonra Discord'u her zamanki gibi kendi ikonundan açabilirsin. İlk açılışta bir kez kapanıp yeniden açılması normaldir.

## Sorun olursa

1. **Discord DPI Yardım** uygulamasını aç (`⌘ + Boşluk`, "Discord DPI" yaz, Enter).
2. **Sorun bildir (log oluştur)** seçip **Devam**'a bas, yaklaşık 1 dakika bekle.
3. Masaüstünde `DiscordDPI-tanilama-...zip` adlı bir dosya oluşur ve Finder'da seçili açılır. Bu dosyayı kurulumu sana gönderen kişiye ilet.

macOS "Masaüstü klasörüne erişim" izni sorarsa **İzin Ver**'e bas. İzin verilmezse dosya ev klasörüne yazılır.

Aynı uygulamadaki **Onar** çoğu sorunu kendisi çözer (yeni bir ağa geçince bağlanmıyorsa önce bunu dene). **Kaldır** her şeyi siler; Discord'un kendisine dokunmaz.

## Güncelleme

Kurulum satırını tekrar çalıştırmak yeterli.

---

## Yöneten kişi için

### Nasıl çalışır

- SpoofDPI yalnızca `127.0.0.1:8881`'de dinler. Sistem proxy ayarı değişmez; proxy'yi sadece `--proxy-server` bayrağıyla açılan Discord kullanır.
- Bir LaunchAgent (`local.discord-dpi`) oturum açılışında başlar ve şunları yapar:
  - SpoofDPI'ı ayakta tutar.
  - Discord proxy'siz açılmışsa (Dock ikonu, açılışta otomatik başlama, güncelleme sonrası yeniden başlama) kapatıp proxy ile yeniden açar.
  - Discord açıkken dakikada bir, ağ değişince hemen bağlantıyı test eder. Bağlantı yoksa sırayla farklı parçalama stratejilerini dener ve çalışanına geçer.
- `sudo` gerekmez, her şey kullanıcı klasöründedir.

### Kurulan dosyalar

| Yol | Ne |
|---|---|
| `~/Library/Application Support/DiscordDPI/` | `bin/spoofdpi`, `discord-dpi` script'i, seçili `strategy`, `VERSION` |
| `~/Library/LaunchAgents/local.discord-dpi.plist` | Arka plan servisi |
| `~/Library/Logs/DiscordDPI/` | `watch.log` (servis), `spoofdpi.log` |
| `/Applications/Discord DPI Yardım.app` | Yardım uygulaması (`/Applications` yazılamıyorsa `~/Applications`) |

### Tanılama zip'ini okumak

`ozet.txt` en üstte tek satırlık bir **SONUÇ** ve **ÖNERİ** ile başlar:

| SONUÇ | Anlamı |
|---|---|
| İnternet bağlantısı yok / Ağ bir giriş sayfası istiyor | Sorun bizde değil; ağa bağlanınca düzelir. |
| Kurulum bozuk / Arka plan servisi yüklü değil | Kurulum satırı yeniden çalıştırılmalı. |
| 8881 portunu başka bir uygulama kullanıyor | Adı yazan uygulama kapatılmalı. |
| Seçili strateji çalışmıyor ama çalışan var | **Onar** düzeltir; servis de 5 dk içinde kendisi geçer. |
| Bu ağda hiçbir strateji çalışmıyor | Bu operatörde/ağda SpoofDPI yetmiyor; VPN ya da WARP gerekir. |
| Bağlantı çalışıyor görünüyor | Proxy sağlam; sorun başka (ör. sesli kanal). Kullanıcıya tam olarak neyin çalışmadığını sor. |

Altındaki bölümlerde operatör adı, DNS yanıtları, çalışan VPN'ler ve her stratejinin test sonucu yer alır (`000` = engellendi). `watch.log` servisin ne zaman ne yaptığını, `spoofdpi.log` SpoofDPI'ın uyarılarını gösterir. Zip'te Discord hesabına ait veri ya da açık IP adresi yoktur.

### Komut satırı

```
"$HOME/Library/Application Support/DiscordDPI/discord-dpi" diagnose   # zip üretir, yolunu yazar
"$HOME/Library/Application Support/DiscordDPI/discord-dpi" repair
"$HOME/Library/Application Support/DiscordDPI/discord-dpi" uninstall
```

### Bilinen sınırlar

- Sesli kanallar UDP kullanır ve proxy'den geçmez; engellenmiyorsa çalışır, engelleniyorsa bu araç çözmez.
- Intel Mac'lerde ve yönetici olmayan hesaplarda denenmedi.
- Yeni bir strateji gerekirse `install.sh` içindeki `STRATEGIES` listesine eklenir.
