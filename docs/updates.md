# Otomatik açılış ve düğmeyle güncelleme

v0.3.0 bütün rollerin foreground açılışını ve sunucudan kablosuz dosya almasını ekler. Yeni davranışlar Lua mock'larında doğrulandı; gerçek Minecraft reboot/aktarım kabulü bekleniyor.

## Bir defalık geçiş

v0.2 ve önceki sürümlerde güncelleme menüsü yoktur. Önce sunucuyu, sonra iki ekranı bir kez güncelleyin. Foreground panel açıksa Ctrl+C ile kabuğa dönün:

```sh
factoryos stop
factoryos update https://raw.githubusercontent.com/Nom-Dist/factory-os/main
factoryos autostart enable
reboot
```

`autostart enable` komutu **update'ten sonra, reboot'tan önce** çalıştırılır; böylece eski updater'ın bilmediği açılış dosyası da kurulur. Ekranların bu ilk indirmesi için geçici Internet Card gerekir. Alternatif olarak yeni `factoryos-offline.lua` dosyasını HDD ile taşıyıp aynı rolü yeniden kurabilirsiniz; yeni installer açılış düzenini kurar.

## Açılış davranışı

OpenOS `/etc/profile.lua`, `/home/.shrc` dosyasını etkileşimli kabuk açılırken çalıştırır. FactoryOS, `.shrc` içine kendi işaretli bloğunu ekler; kullanıcı komutlarını silmez. Blok kalıcı `/usr/lib/factoryos/autostart.lua` dosyasını çalıştırır, o da `/bin/factoryos.lua start --foreground` açar. `rc` başlangıcını sonsuza dek bloke eden bir foreground servis kurulmaz.

Aynı boot içinde bir kere başlar. Ctrl+C uygulamayı kapatıp kabuğa döndürür; uygulama yeniden kendiliğinden açılmaz. Elle `factoryos start --foreground` ile tekrar başlatılabilir. Bir sonraki bilgisayar açılışında otomatik başlar.

```sh
factoryos autostart disable
factoryos autostart enable
```

Bu komutlardan önce çalışan panelden çıkın. Devre dışı bırakma yalnızca FactoryOS bloğunu kaldırır. Ana ekranın GUNCELLEMELER sayfasında da OTOMATIK ACILIS düğmesi vardır. Eksik/kısmi işaretli blok görülürse dosya korunur ve hata verilir; kullanıcı `.shrc` komutları tahmin edilerek değiştirilmez.

## Kontrol ve uygulama

- Sunucu başlangıçtan yaklaşık 15 saniye sonra ilk manifest kontrolünü başlatır; sonra varsayılan **900 saniyede bir** tekrarlar. Periyodik kontrol yalnızca küçük manifesti indirir.
- Ana ekranda **GUNCELLEMELER → SIMDI KONTROL ET**; sunucu/yan ekranda alttaki düğme. Klavyeyle bütün rollerde **F5** kontrol, **F6** güncelleme başlatır. Arama klavyesi açıkken bu kısayollar çalıştırılmaz.
- Yeni sürüm varsa **GUNCELLE / YENIDEN AC** kullanılabilir. Otomatik kontrol kendi kendine sürüm uygulamaz.
- İstemciler sonraki güncellemelerde Internet Card kullanmaz; sunucudan dosya alır. Sunucuda Internet Card ve çalışan HTTPS erişimi gerekir.

Varsayılan kontrol ayarları config'tedir:

```sh
factoryos stop
factoryos config updateAutoCheck true
factoryos config updateCheckInterval 900
factoryos start --foreground
```

Aralık 60–86400 saniyedir. Otomatik kontrol kapalı olsa da düğmeyle kontrol yapılabilir. Sabit commit URL'sine ayarlanmış `updateBase`, yalnızca o commit'i kontrol eder; devam eden yeni sürümler için gerçek `main` adresini kullanın.

## Aktarım ve geçiş

Sunucu dosyaları `/var/lib/factoryos/update-cache/releases/` altına indirir. Menüden indirme/kontrol bir OpenOS thread'inde çalışır; ağ heartbeat döngüsü ve görüntü açık kalır. Ekranlar bir defada en fazla 1024 bayt dosya parçası ister. Her istek sürüm, dosya yolu ve offset taşır; sunucu yalnızca doğrulanmış manifestteki dosyaları verir.

İstemci dosyaları kendi staging sürümüne yazar. **Boyut, SHA256 ve yerel Lua sözdizimi** denetlenir; Lua kaynakları bu aşamada yalnızca derlenir, çalıştırılmaz. Bütün dosyalar hazır olunca üretim/idle kilidi tekrar kontrol edilir. Sonra modem kapatılır, GUI temizlenir, sürüm pointer'ı değiştirilir ve `computer.shutdown(true)` ile reboot yapılır. Otomatik açılış etkinse yeni panel gelir. Config ve favoriler korunur.

AE2 snapshot'ında meşgul CPU varsa uygulama engellenir. Reaktör/makine kontrolü zaten bu sürümde açık değildir. İleride kontrol sürücüleri eklendiğinde bu idle kontrolüne onların kalıcı iş durumları da eklenmelidir.

Bağlantı kesilmesi, hash hatası, geçersiz Lua, iptal veya son anda meşgul üretim görülmesi active pointer'ını değiştirmez. Ctrl+C bekleyen uygulamayı iptal eder. Daha önceki sürümler ve başarısız staging klasörleri inceleme/geri dönüş için kalabilir; HDD alanını kontrol edin.

Geri dönüş:

```sh
factoryos rollback
reboot
```

Önce foreground panelden çıkın. Önceki sürümün dosyaları tekrar hash kontrolünden geçer. Kalıcı açılış launcher'ı eski sürümün `start --foreground` komutuyla da çalışabilir. Açılış yeni sürümde hata verirse launcher kabuğa döner. CLI'nin kendisi açılamayacak durumdaysa sağlam önceki pointer'ı OpenOS kabuğunda `cp /usr/lib/factoryos/previous /usr/lib/factoryos/active` ile geri koyup reboot edin.

## İlk oyun kabulü

Üç bilgisayarı kapatıp açın: panel otomatik gelmeli. Ctrl+C ile çıkınca kabukta kalmalı. Sunucuda F5 kontrolünü, ardından bir ekranın Internet Card'ını çıkarıp GUNCELLEMELER düğmesini deneyin. Yeni gerçek sürüm bulunduğunda aktarım, reboot ve aynı modem izinleriyle geri bağlanmayı gözleyin. Aktarım sırasında wireless bağlantısını keserek eski sürümün korunmasını ayrıca sınayın. Bu adımlar henüz gerçek oyunda çalıştırılmadı.
