# FactoryOS v0.3.2

v0.3.2, AE2 stok yenilemesinde eski snapshot'ı önceden bırakır ve yeni satırları kopyalamadan işler; RAM yükünü azaltır. v0.3.1'de eklenen `factoryos ae2 12` komutu gerçek hata/adres ve RAM bilgisini gösterir. Kullanım ve bellek sınırı için [AE2 tanılama kılavuzu](docs/ae2-diagnostics.md).

Minecraft **1.12.2 / Enigmatica 2: Expert Skyblock / OpenComputers / OpenOS** için üç bilgisayarlı fabrika kontrol yazılımı. Lua 5.2 ve 5.3 hedeflenir. Sunucu ve iki ekranın kablosuz bağlantısı kullanıcı tarafından oyun içinde doğrulandı. **Yeni arayüz, otomatik açılış, kablosuz güncelleme ve gerçek AE2 davranışı için oyun içi kabul bekleniyor.**

Sunucu, 8×5 ana ekran ve 4×5 yan ekran ayrı bilgisayarlardır. Her bilgisayar yalnızca kendi GPU ve ekranını kullanır. Ağ üzerinden GPU/bileşen çağrısı yapılmaz.

## Bu teslimatta

- Üç rolü sunan installer; Internet Card olmadan da kullanılabilen tek dosyalı çevrimdışı paket.
- Donanım keşfi, birden fazla bileşen varsa açık adres seçimi, güvenli çözünürlük sınırları.
- Şifresiz kablosuz mesajlar, modem adresi izin listesi, keşif, oturum kaydı, heartbeat, OFFLINE ve yeniden bağlanma.
- İstek kimlikleri, timeout/yeniden deneme, tekrar yanıt önbelleği, parçalama ve bellek/kuyruk sınırları.
- Ana ekranda koyu endüstriyel panel: üst durum şeridi, büyük sol menü, özet kartları ve sağ uyarı/ürün detayı sütunu.
- AE2 deposunda dokunmatik arama klavyesi, fiziksel klavye/pano girişi, genel miktar sıralaması, tarifli/favori filtreleri, ürün seçimi ve kesintisiz sayfalama.
- Ekrana özel diskte saklanan en fazla 32 favori; metadata/NBT belirsizliği olan varyantlar favoriye eklenmez.
- Yan panel ayrı GPU/ekranla çalışır; GPU'ya yalnızca değişen hücreler yazılır.
- AE2 Adapter üzerinden **salt okunur** stok, metadata/NBT belirsizlik işareti, crafting CPU doluluğu, AE enerji verileri.
- OpenOS servis komutları, config yedeği, sınırlı log dosyası, SHA256 doğrulamalı aşamalı güncelleme ve geri dönüş.
- Bilgisayar açılınca foreground panel; kullanıcı `.shrc` içeriği korunur. Ctrl+C ile komut satırına dönülür.
- Sunucuda 15 dakikada bir GitHub sürüm kontrolü. Ana ekranda GUNCELLEMELER sayfası, sunucu/yan ekranda güncelleme düğmesi; F5 kontrol / F6 güncelleme.
- Ekranlar dosyaları sunucudan kablosuz alır; sonraki güncellemelerde Internet Card gerekmez. Kullanıcı düğmeye bastığında dosyalar hash/sözdizimi kontrolünden geçer, uygulama kapanır ve yeni sürümle reboot edilir.

**Henüz uygulanmayanlar:** otomatik stok hedefleri, crafting başlatma/takibi, Mekanism sürücüleri, RF/FE sürücüleri ve reaktör kontrolü. İlgili ekranlar bunları `unsupported` veya devre dışı gösterir. CPU'nun `busy` olması mevcut işin ayrıntılarının okunabildiği anlamına gelmez.

## Hızlı başlangıç — GitHub gerektirmez

1. [Proje ZIP'ini](https://github.com/Nom-Dist/factory-os/archive/refs/heads/main.zip) açın. `dist/factoryos-offline.lua` dosyasını bir OpenOS HDD/disketine aktarın. Bu tek dosya yaklaşık 140 KB'dir; standart disket kapasiteniz yetmiyorsa HDD veya geçici Internet Card kullanın. Boyut sürüme göre değişir.
2. Her bilgisayarda dosyanın bulunduğu konuma geçip çalıştırın:

```sh
./factoryos-offline.lua
```

3. Sırasıyla Server, Main Display ve Side Display rollerini kurun. **Şifre veya ortak anahtar sorulmaz.** Her girişten sonra soru ayrı satıra geçer.
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

Sunucuyu önce açmanız gerekmez; istemciler bağlantıyı arar. İlk kayıt normal koşullarda yaklaşık 5–10 saniyedir; gerçek oyun gecikmesi kabul testinde ölçülmelidir. Sonraki açılışlarda panel otomatik foreground başlar. Ctrl+C ile kabuğa dönülür ve aynı boot içinde tekrar kendiliğinden açılmaz. Arka plan için `factoryos start` da kullanılabilir.

## GitHub kurulumu

Depo: [Nom-Dist/factory-os](https://github.com/Nom-Dist/factory-os). Internet Card bulunan OpenOS bilgisayarında:

```sh
wget https://raw.githubusercontent.com/Nom-Dist/factory-os/main/install.lua install.lua
./install.lua https://raw.githubusercontent.com/Nom-Dist/factory-os/main
```

`./` öneki gereklidir: `install.lua` tek başına yazılırsa OpenOS'un kendi installer'ı seçilebilir ve `Nothing to install labeled` hatası alınır. `main` değişebilir; sabit sürüm kurulumu için iki URL'de de aynı commit SHA'sını kullanın. Çevrimdışı seçenek ve ayrıntılar [kurulum kılavuzunda](docs/installation.md).

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
factoryos autostart enable
factoryos autostart disable
```

CLI `update` için gerçek HTTPS kaynak adresi gerekir; önce servisi durdurun. Menüden güncelleme dosyaları arka planda hazırlanır ve doğrulanır; uygulama ancak etkinleştirme aşamasında kapanır. Ayarlar `/etc/factoryos/config.dat`, favoriler `/etc/factoryos/display.dat`, log `/var/log/factoryos.log`, sürümler `/usr/lib/factoryos/releases/` altında tutulur.

**v0.2 ve öncesinden bir defalık geçiş:** önce sunucuda, sonra iki ekranda Ctrl+C ile kabuğa dönüp aşağıdakileri çalıştırın. Ekranların bu ilk indirmesi için geçici Internet Card veya çevrimdışı installer gerekir; bundan sonraki menü güncellemeleri kablosuzdur.

```sh
factoryos stop
factoryos update https://raw.githubusercontent.com/Nom-Dist/factory-os/main
factoryos autostart enable
reboot
```

Sonraki güncellemelerde ana ekranda **GUNCELLEMELER → SIMDI KONTROL ET → GUNCELLE / YENIDEN AC** kullanılır. Sunucu/yan ekranda alttaki düğme veya F5/F6 kullanılabilir. Otomatik kontrol yalnızca yeni sürümü bildirir; kendi kendine sürüm uygulamaz. AE2 CPU'ları meşgulse uygulama bekletilir.

## Geliştirme ve doğrulama

Python yalnızca geliştirici bilgisayarında paketleme/test için gerekir; OpenOS'ta harici Lua paketi gerekmez.

```sh
python -m pip install --target .tools -r requirements-dev.txt
python tools/build.py
python tests/run.py
```

Test çalıştırıcısı Lua 5.2 **ve** 5.3'te kaynakları/üretilen installer'ları derler ve 40 senaryoyu çalıştırır. Testler gerçek Lua yürütür; modem, GPU, filesystem, zaman, HTTP ve OpenOS thread/event çevresi mock'tur. İki ekranın küçük paket sınırında eşzamanlı kablosuz güncellenmesi de sınanır. Oyun gecikmesini, gerçek OpenOS boot/thread scheduler'ını ve Java mod sürücülerini doğrulamaz. [Oyun içi kabul adımları](docs/testing.md) ve [salt okunur prob](tools/ingame_probe.lua) ayrıca sağlanmıştır.

GPU tamponundan örnek verilerle oluşturulan [ana panel](docs/previews/main-overview.png), [depo](docs/previews/main-stocks.png), [arama klavyesi](docs/previews/main-search.png) ve [küçük çözünürlük](docs/previews/main-compact.png) önizlemeleri vardır. Bunlar oyun ekran görüntüsü veya gerçek fabrika verisi değildir. Host'ta yeniden üretmek için `python tools/preview.py` çalıştırın; Pillow ve Lupa gerekir.

v0.1.1 ağ protokolü v2 kullanır. v0.1.0 ile haberleşmez; üç bilgisayarı da güncelleyin. Eski config'teki modem/ekran/rol ayarları korunur, ortak anahtar artık kullanılmaz. SHA256 yalnızca indirilen dosyaların bütünlüğünü kontrol eder.

v0.1.2, OC 1.8.3 üzerinde foreground başlangıcında görülen `maxPacketSize` hatasını düzeltir. v0.1.1 ile aynı ağ protokolünü kullanır. Sunucunun istemci adresleri boşken açılması desteklenir; sadece istemci kaydı izin listesi doldurulana kadar bekler.

v0.2.0 ana ekran tasarımını yeniler. Sıralama ve tarifli/favori filtreleri için **sunucu ve ana ekranı birlikte güncelleyin**; yan ekran önceki protokol v2 sürümüyle çalışmaya devam edebilir. Modem izinleri/config korunur; favoriler `/etc/factoryos/display.dat` dosyasında ayrıca saklanır. Uzak crafting komutları açılmadı.

## Dokümanlar

- [Kurulum, güncelleme ve kurtarma](docs/installation.md)
- [Otomatik açılış ve kablosuz güncelleme](docs/updates.md)
- [Donanım ve üç bilgisayarlı bağlantı](docs/hardware.md)
- [Mimari ve kapsam](docs/architecture.md)
- [Mesaj protokolü ve güvenlik sınırları](docs/protocol.md)
- [Sürüm/API araştırması ve kaynaklar](docs/compatibility.md)
- [Test sonuçları ve Minecraft kabul senaryoları](docs/testing.md)

Yereldeki Prism kurulumları **1.90g-b / Minecraft 1.12.2**, üç yerel instance'ın JAR dosyaları **OC 1.8.3+274990f / AE2 rv6-stable-7** gösteriyor. Eski resmî depo mod listesi ise **1.36 / OC 1.7.5.192** içeriyor. Bu fark [uyumluluk raporunda](docs/compatibility.md) belgelenmiştir. Aktif dünyanın hangi instance'a ait olduğu ve oyun içi bileşen davranışları henüz doğrulanmadı.
