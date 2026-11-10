# Test ve oyun içi kabul

## Gerçekte çalıştırılanlar

11 Kasım 2026'da Lupa 2.8'in **gerçek Lua 5.2 ve Lua 5.3 yorumlayıcılarında** 21 senaryo çalıştırıldı: her yorumlayıcıda 21/21 geçti. Bütün Lua dosyaları, üretilen online/offline installer ve oyun içi prob dahil sözdizimsel olarak derlendi.

Modem/GPU/HTTP/filesystem/thread/event/zaman çevresi mock'tur. Bilgisayarlar arası haberleşme uygulaması ve tüm modüller gerçek Lua koduyla yürütüldü. Bu sonuçlar **Minecraft'ta üç bilgisayarlı uçtan uca doğrulama değildir**.

Yerel OC 1.8.3 JAR içindeki OpenOS kaynakları incelenerek mock'lar şu davranışlara uyarlandı: `package.preload` olmaması, mevcut dizinde makeDirectory hatası, close'un boş dönüşü ve term.read cursor/newline seçenekleri. Gerçek Java filesystem, Lua mimarisi/GPU bütçeleri ve OpenOS thread scheduler'ı yine oyun içinde doğrulanmalı.

ARTEMIS `mobile_diagnose(attempt_fix=true)` çalıştırıldı; ADB'de bağlı Android cihaz/emülatör yoktu. Minecraft Java, Android hedefi değildir; ilişkisiz bir Android emülatörü başlatılmadı ve ARTEMIS ile Minecraft UI testinin geçtiği iddia edilmedi. Kullanıcıdan verilen proje talimatındaki erişilemeyen Minecraft ortamı için manuel kabul adımı yolu izlendi. Kurulu instance'lar okunabildi; oyun ekranı/dünya bileşenleri kontrol edilmedi.

## Otomatik senaryolar

| # | Kapsam |
|---|---|
| 1 | Dosya bütünlüğü için SHA256 boş/abc/1000 bayt test vektörleri |
| 2 | Canonical veri codec, çalıştırılabilir veri/cycle/duplicate/truncated input reddi |
| 3 | Atomic config, .bak kurtarma, .corrupt koruma, yanlış aralıklar, write/flush hatası |
| 4 | Sunucu kapalı istemci açılışı; sunucu sonradan gelince üç düğümlü kayıt |
| 5 | 10 KB stok yanıtının parçalanması, modem bayt sınırı, istek eşleştirme |
| 6 | Yan ekran ACL ve REQUEST_CRAFT güvenli reddi |
| 7 | Aynı kimlik/body bir kez dispatch; farklı body ile tekrar reddi |
| 8 | Eski protokol, bozuk çerçeve, yanlış kaynak adresi, izinsiz peer/eski boot reddi |
| 9 | 21 saniyelik kesinti sonrası OFFLINE; bağlantı dönünce kayıt |
| 10 | İstemci ve sunucu restart; yeni boot ile yeniden eşleşme |
| 11 | Parçalı alım sınırı ve 25 saniyelik temizleme, aşırı büyük gönderim reddi |
| 12 | Eksik/çoklu GPU, ekran, modem ve açık adres seçimi |
| 13 | AE2 örnek stack, metadata/NBT ayrımı, CPU sınırı; bağlantı kaybında eski stok/enerji temizliği |
| 14 | 160×50, 80×25, 50×16, 40×12 bütün roller/sayfalar; aynı frame sıfır GPU yazısı; yanlış ekrandan touch reddi |
| 15 | Staging kurulumu, hash hatası, indirme kopması, eski active korunması, rollback doğrulaması, path traversal reddi |
| 16 | Eksik Internet Card, boş kaynak ve HTTP URL reddi |
| 17 | HTTP 200/404, timeout/uzunluk limiti ve handle kapama |
| 18 | Üretilen tek dosya ile üç rol kurulumu; şifre sorulmaması, her giriş sonrası ayrı newline, global preload'a bağımlılık olmaması |
| 19 | CLI detached servis start/stop ve çalışan serviste update/config reddi |
| 20 | Gerçek üretilen launcher'ın active.bak fallback'i ve OpenOS core cache korunması |
| 21 | Eski config'teki ortak anahtarın kullanılmadan kaldırılması, modem/ekran/rol ayarlarının korunması |

Host'ta tekrar çalıştırma:

```sh
python -m pip install --target .tools lupa==2.8
python tools/build.py
python tests/run.py
```

## Salt okunur oyun probu

`tools/ingame_probe.lua` dosyasını **sunucu OpenOS diskinize** aktarın, servisi durdurduktan sonra çalıştırın:

```sh
ingame_probe.lua
```

`/home/factoryos-probe.log` Lua/OpenOS sürümünü, component/metot listesini, ekran ölçülerini ve desteklenirse AE2 stok örneği/CPU/enerji dönüşlerini kaydeder. GPU rebind, crafting veya makine durumu değiştirmez. Bu dosyayı host'a oyun diski aktarımıyla çıkartabilirsiniz; Android ADB, Minecraft Java dosyalarını çıkarmaz.

Probun çıktısında stok satırı bulunması üretim testi değildir. Şu ana kadar bu script gerçek oyunda çalıştırılmadı.

## Üç bilgisayarlı kabul sırası

Önce [donanım](hardware.md) ve [kurulum](installation.md) adımlarını tamamlayın. Üç cihazda v0.1.1, doğru modem allowlist, aynı wireless port, yüklü chunk ve yeterli güç kullanın. Şifre gerekmez. Aşağıdaki süreler varsayılan konfigürasyon içindir; oyun lag'i nedeniyle gözlemi birkaç saniye uzatabilirsiniz. Otomatik testte süreler sanal saatle deterministiktir.

| Senaryo | Oyunda yapılacak işlem | Kabul ölçütü |
|---|---|---|
| Sunucu kapalı başlangıç | Yalnız iki ekranı `start --foreground` ile açın; 10 s gözleyin | İki panel de OFFLINE; çökme yok |
| Sunucu sonradan açılır | Sunucuda `factoryos start` çalıştırın; 15 s gözleyin | İki panel ONLINE; sunucu `Clients: 2`; logda iki kayıt |
| Wireless kesilmesi | Sunucuyu `factoryos stop` ile durdurun; 20–25 s bekleyin | İki panel OFFLINE, eski enerji/stok güncel gösterilmez |
| Yeniden bağlanma | Sunucuyu tekrar başlatın; 15 s gözleyin | Ekranlara elle müdahale etmeden ONLINE |
| Eksik Internet Card | Çevrimdışı installer ile istemci kurun; sonra online güncelleme deneyin | Offline kurulum/ağ çalışır; online download anlaşılır hata verir |
| Eksik GPU/ekran | Kapalı test bilgisayarından GPU/ekranı ayırıp başlatın | Açıklayıcı eksik bileşen hatası; log/config kaybolmaz |
| AE2 kaybı | Sunucunun Adapter bağlantısını ayırın; 10–25 s bekleyin | Sunucu/istemci ağı çalışır; AE2 OFFLINE, eski stok/enerji kaldırılır |
| AE2 geri gelir | Aynı Adapter'ı yeniden bağlayın | Bir sonraki snapshot ve heartbeat sonrası AE2 ONLINE |
| Tekrar crafting isteği | v0.1 GUI'de crafting düğmesi bulunmadığını doğrulayın | REQUEST_CRAFT protokolde reddedilir; gerçek üretim başlamaz. Yinelenen read istekleri host testindedir |
| Eksik malzemeyle crafting | v0.1'de otomasyon açılmaz | Bu üretim senaryosu **bekliyor**, başarılı diye raporlanmaz |
| İstemci restart | Ana ekranı Ctrl+C ile durdurup yeniden açın veya bilgisayarı reboot edin | Config korunur, yeni oturum kaydolur, ikinci ekran bağımsız çalışır |
| Güncellemede kopma | Önce durdurun; yeni gerçek HTTPS sürümünü indirirken Internet Card'ı ayırın | Hata sonrası eski active sürümünden başlatılabilir; config korunur |
| Güncellemede çalışan servis | Servis çalışırken `factoryos update` deneyin | Dosya indirmeden "Stop FactoryOS" hatası |
| Yanlış modem/allowlist | Bir test istemcisinin adres eşleştirmesini değiştirin; sonra geri düzeltin | İzin listesinde bulunmayan cihaz OFFLINE |
| Kurulum satırları | Yeni installer ile bir rol kurun; her soruda Enter'a basın | Şifre sorulmaz; sonraki soru yeni satırda başlar. Bu UI düzeltmesinin gerçek oyundaki kabulü bekleniyor |
| Dokunmatik ayırma | Ana ekranda AE2 stocks/CPUs/Energy menülerine dokunun | Ana ekran değişir, yan ekran kendi telemetrisiyle kalır |
| Stok doğruluğu | AE terminalinde iki metadata/NBT varyantını karşılaştırın; eşya ekleyip çıkarın | 10 s poll ve istemci poll sonrası değerler eşleşir; NBT belirsizliği üretim kimliği sayılmaz |
| Arama/sayfalama | AE2 stocks'ta search'e dokunun, fiziksel klavyeyle ASCII sorgu girip Enter'a basın | Alt dize filtresi; next/prev 24'lük sayfa; küçük ekranlarda scroll |
| GPU kararlılığı | İki paneli 10 dakika açık tutun | GPU ekranlar arasında geçiş yapmaz; gereksiz tam ekran temizleme/titreme yok |

## Crafting API kabulü — sonraki aşamanın ön koşulu

Yedek/test dünyasında ucuz ve kolay sayılabilen bir recipe seçin. `getCraftables(filter)` sonucundaki `getItemStack()` kimliğini doğrulayın. Tek sefer `request` verip hem `isDone/isCanceled` ve ikinci dönüş metinlerini hem **AE terminalindeki gerçek stok artışını** kontrol edin. Eksik malzemeyle tekrarlayıp başarısızlık ve backoff tasarımını doğrulayın. Önceden devam eden işler, tam CPU kapasitesi, reboot sırasında belirsiz iş ve aynı istek tekrarını ayrıca sınayın. Bu adımlar henüz kodda otomasyona bağlanmadı ve oyunda yapılmadı.

Reaktör kontrolü test kapsamı dışındadır; otomasyon kapalıdır. Önce salt okunur gerçek metotlar ve yerel bağımsız interlock düzeni doğrulanmalıdır.
