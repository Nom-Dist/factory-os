# Test ve oyun içi kabul

## Gerçekte çalıştırılanlar

11 Kasım 2026'da Lupa 2.8'in **gerçek Lua 5.2 ve Lua 5.3 yorumlayıcılarında** 29 senaryo çalıştırıldı: her yorumlayıcıda 29/29 geçti. Bütün Lua dosyaları, üretilen online/offline installer ve oyun içi prob dahil sözdizimsel olarak derlendi.

Modem/GPU/HTTP/filesystem/thread/event/zaman çevresi mock'tur. Bilgisayarlar arası haberleşme uygulaması ve tüm modüller gerçek Lua koduyla yürütüldü. Kullanıcı sunucu ve iki ekranın kablosuz bağlantısının oyunda çalıştığını ayrıca doğruladı. **Yeni v0.2 arayüzü ve AE2 gerçek stokları için oyun içi kabul bekleniyor**; otomatik sonuçlar bunun yerine geçmez.

Yerel OC 1.8.3 JAR içindeki OpenOS kaynakları incelenerek mock'lar şu davranışlara uyarlandı: `package.preload` olmaması, mevcut dizinde makeDirectory hatası, close'un boş dönüşü ve term.read cursor/newline seçenekleri. Gerçek Java filesystem, Lua mimarisi/GPU bütçeleri ve OpenOS thread scheduler'ı yine oyun içinde doğrulanmalı.

v0.1.2 testlerinde modemler `maxPacketSize` metodu sunmaz; `getDeviceInfo` içindeki string `capacity` kullanılır. Modem/GPU/AE2 callback'leri OC `machine.lua` gibi `__call` metotlu table olarak taklit edilir. Kullanıcının boş istemci listesiyle server foreground başlatma senaryosu ayrıca çalıştırılır.

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
| 22 | maxPacketSize olmadan device info kapasitesi; optional callable callback, bozuk/eksik/küçük sınır kontrolü |
| 23 | Boş istemci listesi ve OC callable-table metotlarıyla server/main/side foreground açılışı, panel çizimi ve temiz kapanış |
| 24 | Stokların tüm sonuç kümesinde miktara göre sıralanması, tarif/favori filtresi, sınır dışı sayfanın düzeltilmesi |
| 25 | Arama taslağının Enter ile uygulanması, iptal, pano metni, geç gelen eski yanıtın yok sayılması, periyodik istek biriktirmeme |
| 26 | Favorilerin ekran diskinde kalıcılığı, NBT belirsizliği reddi, 32 kayıt sınırı, disk hatasında geri alma |
| 27 | Küçük çözünürlükte 24'lük sayfanın bütün satırlarını dolaşma, ağ sayfaları arasında ileri/geri geçiş |
| 28 | OFFLINE sırasında stok/CPU cache temizliği, eski callback reddi, yeniden bağlantıda iki verinin yenilenmesi |
| 29 | Üç satırlı dokunma alanı, modal klavyede arkadaki düğmelere basılmaması, offline/AE2 kaybında eski miktarların gizlenmesi |

Host'ta tekrar çalıştırma:

```sh
python -m pip install --target .tools -r requirements-dev.txt
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

Önce [donanım](hardware.md) ve [kurulum](installation.md) adımlarını tamamlayın. Sunucu ve ana ekranda v0.2.0, doğru modem allowlist, aynı wireless port, yüklü chunk ve yeterli güç kullanın. Yan ekran protokol v2 ile bağımsız çalışır. Şifre gerekmez. Aşağıdaki süreler varsayılan konfigürasyon içindir; oyun lag'i nedeniyle gözlemi birkaç saniye uzatabilirsiniz. Otomatik testte süreler sanal saatle deterministiktir.

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
| Dokunmatik ayırma | Ana ekranda AE2 DEPOSU/URETIM/ENERJI menülerine dokunun | Ana ekran değişir, yan ekran kendi telemetrisiyle kalır |
| Stok doğruluğu | AE terminalinde iki metadata/NBT varyantını karşılaştırın; eşya ekleyip çıkarın | 10 s poll ve istemci poll sonrası değerler eşleşir; NBT belirsizliği üretim kimliği sayılmaz |
| Arama/sayfalama | AE2 DEPOSU'nda ARA'ya dokunun, ekrandaki harflerle veya fiziksel klavyeyle sorgu girip onaylayın | Alt dize filtresi; ONCE/SONRA bütün satırları ve sonra ağ sayfalarını dolaşır |
| Sıralama/filtre | MIKTAR'a, sonra TARIFLI/FAVORILER'e dokunun | Tüm envanterde sıralama; yalnızca ilgili sonuçlar gelir |
| Favori kalıcılığı | Satırdaki + işaretine basın, ekranı yeniden başlatın, FAVORILER'i açın | Seçilen varyant korunur; belirsiz NBT varyantı eklenmez |
| Yeni panel | ANA PANEL'i açın, gerçek AE2 bağlantısını ayırıp geri takın | Uyarılar ve özet kartları gerçek bağlantı durumuna göre değişir; bilinmeyen değerler -- olur |
| GPU kararlılığı | İki paneli 10 dakika açık tutun | GPU ekranlar arasında geçiş yapmaz; gereksiz tam ekran temizleme/titreme yok |

## Crafting API kabulü — sonraki aşamanın ön koşulu

Yedek/test dünyasında ucuz ve kolay sayılabilen bir recipe seçin. `getCraftables(filter)` sonucundaki `getItemStack()` kimliğini doğrulayın. Tek sefer `request` verip hem `isDone/isCanceled` ve ikinci dönüş metinlerini hem **AE terminalindeki gerçek stok artışını** kontrol edin. Eksik malzemeyle tekrarlayıp başarısızlık ve backoff tasarımını doğrulayın. Önceden devam eden işler, tam CPU kapasitesi, reboot sırasında belirsiz iş ve aynı istek tekrarını ayrıca sınayın. Bu adımlar henüz kodda otomasyona bağlanmadı ve oyunda yapılmadı.

Reaktör kontrolü test kapsamı dışındadır; otomasyon kapalıdır. Önce salt okunur gerçek metotlar ve yerel bağımsız interlock düzeni doğrulanmalıdır.

## Görsel önizlemeler

`python tools/preview.py`, gerçek `ui.renderer` GPU hücre tamponunu örnek verilerle PNG'ye dönüştürür. [Ana panel](previews/main-overview.png), [depo](previews/main-stocks.png), [arama](previews/main-search.png), [offline](previews/main-offline.png) ve [80×25](previews/main-compact.png) görüntüleri görsel olarak incelendi. Görüntü başlıkları örnek veri olduğunu belirtir; bunlar Minecraft'tan alınan ekran görüntüsü değildir. 40×12, 50×16, 80×25 ve 160×50 boyutları ayrıca bütün sekmeler ve arama klavyesiyle GPU sınır testinden geçti.
