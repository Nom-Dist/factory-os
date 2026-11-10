# FactoryOS v0.1.0

Minecraft **1.12.2 / Enigmatica 2: Expert Skyblock / OpenComputers / OpenOS** için üç bilgisayarlı fabrika kontrol yazılımı. Lua 5.2 ve 5.3 hedeflenir. Oyun dışında çalışan testleri olan ilk altyapı teslimatıdır; **Minecraft içinde henüz doğrulanmamıştır**.

Sunucu, 8×5 ana ekran ve 4×5 yan ekran ayrı bilgisayarlardır. Her bilgisayar yalnızca kendi GPU ve ekranını kullanır. Ağ üzerinden GPU/bileşen çağrısı yapılmaz.

## Bu teslimatta

- Üç rolü sunan installer; Internet Card olmadan da kullanılabilen tek dosyalı çevrimdışı paket.
- Donanım keşfi, birden fazla bileşen varsa açık adres seçimi, güvenli çözünürlük sınırları.
- HMAC-SHA256 imzalı kablosuz mesajlar, izin listesi, keşif, oturum kaydı, heartbeat, OFFLINE ve yeniden bağlanma.
- İstek kimlikleri, timeout/yeniden deneme, tekrar yanıt önbelleği, parçalama ve bellek/kuyruk sınırları.
- Koyu renkli iki ayrı panel, dokunmatik menü, stok sayfalama, değişen hücreleri çizen GPU arayüzü.
- AE2 Adapter üzerinden **salt okunur** stok, metadata/NBT belirsizlik işareti, crafting CPU doluluğu, AE enerji verileri.
- OpenOS servis komutları, config yedeği, sınırlı log dosyası, SHA256 doğrulamalı aşamalı güncelleme ve geri dönüş.

**Henüz uygulanmayanlar:** otomatik stok hedefleri, crafting başlatma/takibi, Mekanism sürücüleri, RF/FE sürücüleri, reaktör kontrolü ve kablosuz güncelleme dağıtımı. İlgili ekranlar bunları `unsupported` veya devre dışı gösterir. CPU'nun `busy` olması mevcut işin ayrıntılarının okunabildiği anlamına gelmez.

## Hızlı başlangıç — GitHub gerektirmez

1. [Proje ZIP'ini](https://github.com/Nom-Dist/factory-os/archive/refs/heads/main.zip) açın. `dist/factoryos-offline.lua` dosyasını bir OpenOS HDD/disketine aktarın. Bu tek dosya yaklaşık 90 KB'dir; standart disket kapasiteniz yetmiyorsa HDD veya geçici Internet Card kullanın. Boyut sürüme göre değişir.
2. Her bilgisayarda dosyanın bulunduğu konuma geçip çalıştırın:

```sh
factoryos-offline.lua
```

3. Sırasıyla Server, Main Display ve Side Display rollerini kurun. Üçünde aynı, rastgele oluşturulmuş **en az 32 karakterlik anahtarı** girin. Anahtar ekranda maskelenir.
4. Sunucuda istemcilerin **modem adreslerini** izin listesine ekleyin. Bilgisayar/ekran adresi kullanmayın:

```sh
factoryos config allow ANA_EKRAN_MODEM_ADRESI main
factoryos config allow YAN_EKRAN_MODEM_ADRESI side
```

Yukarıdaki iki adres alanı kendi bileşen adreslerinizle değiştirilmelidir. Adresleri `components` veya `factoryos doctor` ile bulun.

5. Üç bilgisayarda çalıştırın:

```sh
factoryos start --foreground
```

Sunucuyu önce açmanız gerekmez; istemciler bağlantıyı arar. İlk kayıt normal koşullarda yaklaşık 5–10 saniyedir; gerçek oyun gecikmesi kabul testinde ölçülmelidir. Foreground moddan Ctrl+C ile çıkılır. Arka plan için `factoryos start` kullanın; kabuk aynı ekranı paylaştığından görüntüyü bozabilir. Ekran bilgisayarlarında foreground önerilir.

## GitHub kurulumu

Depo: [Nom-Dist/factory-os](https://github.com/Nom-Dist/factory-os). Internet Card bulunan OpenOS bilgisayarında:

```sh
wget https://raw.githubusercontent.com/Nom-Dist/factory-os/main/install.lua install.lua
install.lua https://raw.githubusercontent.com/Nom-Dist/factory-os/main
```

`main` değişebilir; sabit sürüm kurulumu için iki URL'de de aynı commit SHA'sını kullanın. Çevrimdışı seçenek ve ayrıntılar [kurulum kılavuzunda](docs/installation.md).

## Komutlar

```sh
factoryos start
factoryos stop
factoryos restart
factoryos status
factoryos doctor
factoryos config
factoryos logs
factoryos update
factoryos rollback
```

`update` için gerçek HTTPS kaynak adresi gerekir. Çalışan servis güncellenmez; önce durdurun. Güncelleme/geri dönüş sonrasında yeniden başlatın (`reboot`). Ayarlar `/etc/factoryos/config.dat`, log `/var/log/factoryos.log`, sürümler `/usr/lib/factoryos/releases/` altında tutulur. Otomatik açılış kurulmaz; yeniden başlatmada ayarlar korunur, servis elle başlatılır.

## Geliştirme ve doğrulama

Python yalnızca geliştirici bilgisayarında paketleme/test için gerekir; OpenOS'ta harici Lua paketi gerekmez.

```sh
python -m pip install --target .tools lupa==2.8
python tools/build.py
python tests/run.py
```

Test çalıştırıcısı Lua 5.2 **ve** 5.3'te kaynakları/üretilen installer'ları derler ve 20 senaryoyu çalıştırır. Testler gerçek Lua yürütür; modem, GPU, filesystem, zaman, HTTP ve OpenOS thread/event çevresi mock'tur. Oyun gecikmesini, Java mod sürücülerini ve gerçek üretimi doğrulamaz. [Oyun içi kabul adımları](docs/testing.md) ve [salt okunur prob](tools/ingame_probe.lua) ayrıca sağlanmıştır.

## Dokümanlar

- [Kurulum, güncelleme ve kurtarma](docs/installation.md)
- [Donanım ve üç bilgisayarlı bağlantı](docs/hardware.md)
- [Mimari ve kapsam](docs/architecture.md)
- [Mesaj protokolü ve güvenlik sınırları](docs/protocol.md)
- [Sürüm/API araştırması ve kaynaklar](docs/compatibility.md)
- [Test sonuçları ve Minecraft kabul senaryoları](docs/testing.md)

Yereldeki Prism kurulumları **1.90g-b / Minecraft 1.12.2**, üç yerel instance'ın JAR dosyaları **OC 1.8.3+274990f / AE2 rv6-stable-7** gösteriyor. Eski resmî depo mod listesi ise **1.36 / OC 1.7.5.192** içeriyor. Bu fark [uyumluluk raporunda](docs/compatibility.md) belgelenmiştir. Aktif dünyanın hangi instance'a ait olduğu ve oyun içi bileşen davranışları henüz doğrulanmadı.
