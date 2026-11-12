# Test ve oyun içi kabul

## Gerçekte çalıştırılanlar

12 Kasım 2026'da Lupa 2.8'in **gerçek Lua 5.2 ve Lua 5.3 yorumlayıcılarında** 84 senaryo ve ayrı sınırlı bellek regresyonu çalıştırıldı: her yorumlayıcıda hepsi geçti. Bütün Lua dosyaları, üretilen online/offline installer ve oyun içi prob dahil sözdizimsel olarak derlendi.

v0.6.0 `tests/web.lua`: SHA-1/RFC6455 accept/masking vektörleri, parçalı yazmalı nonblocking handshake/ping, bozuk frame reddi, eski config göçü, URL/rol/token doğrulama ve HTTP uplink komut allowlist'i/kontrol kilidi/aynı kimliği tekrarlamama. `web-panel/` içinde TypeScript kontrolü, Next.js production build ve 9 Node testi geçti: codec, şifreli oturum/origin, HTTP uplink, gerçek WS komut/yanıt kaybında tekrar olmaması, eski veri/oturum süresi, salt/yanlış şifre/bozuk hash, çıkışta oturum ve socket iptali, eksik şifrede eski token girişinin reddi. Eski `/bridge` cookie'sinin silinmesi de doğrulanır. `npm run test:flow` gerçek Lua 5.2 ve 5.3 web modüllerini gerçek localhost TCP/WebSocket üzerinden Node relay'e bağlayarak şifreli oturum → stok → quote → iki aynı START → **tek native çağrı ve çağrıdan önce journal** akışını doğruladı. Component/AE2/disk mock'tur; gerçek Minecraft, HTTPS/Java sertifika uyumu veya Docker dağıtımı kabulü değildir.

v0.6.1 `tests/server_console.lua` beş host regresyonu ekler: kalıcı kayıt sonrası canlı bağlantı değişimi ve token koruma; gerçek runtime içinde F4/pano/Tab/Enter; yanlış ayar/güncelleme/flush hatasında eski bağlantıyı koruma; dokunmatik klavye ve girdi sınırları; 50×16 ve 40×12'de gizli token ve modal dokunma hedefleri. [Server ayarları](previews/server-web-settings.png), [küçük ekran](previews/server-web-settings-small.png) ve [dokunmatik klavye](previews/server-web-keyboard-small.png) örnek verilerle üretildi ve görsel olarak incelendi. Gerçek Minecraft kabulü bekleniyor.

Şifreli giriş ekranında tarayıcıyla yanlış şifrenin reddi, doğru şifreyle dashboard'a geçiş ve çıkıştan sonra ana sayfanın girişe yönlenmesi doğrulandı. [Giriş önizlemesi](previews/web-panel-login.png) yerel test sunucusundandır; gerçek kullanıcı şifresi belirlenmedi.

Web panelinde 1440 px masaüstü ve 390 px mobil yerleşim, demo etiketi ve kapalı eylemler, depo arama, stok kuralı sayfası ve mobil menü tarayıcıda incelendi. Mobil document genişliği viewport ile eşleşti (390 px); gözlenen tarayıcı konsolunda JS hata kaydı yoktu. [Desktop](previews/web-panel-desktop.png) ve [mobil](previews/web-panel-mobile.png) görseller **örnek veri** içerir.

v0.5.0 `tests/stock.lua` 15 host regresyonu ekler: minimum sınırı/hedef farkı, kalıcı kapalı kayıt, revizyonla tekrar engeli, tam varyant/AE2 adresi/CPU/güncelleme denetimi, eksik envanter, hata bekleme aralıkları, in-flight engeli ve taze stok revizyonu, reboot/yanıt kaybı, iptal/arşivlemeden önce kapatma, disk hatası, elle/harici işler, ana ekran yetkisi, 16 kural/sayfalama/monoton kimlik, modal ve dört ekran boyutu; gerçek 1024 bayt modem protokolünde kural yanıt kaybı ve reboot. Bunlar sanal saat ve mock donanımla çalışır. [Oyun içi otomatik stok kabulü](stock-automation.md) henüz yapılmadı.

Modem/GPU/HTTP/filesystem/thread/event/zaman çevresi mock'tur. Bilgisayarlar arası haberleşme uygulaması ve tüm modüller gerçek Lua koduyla yürütüldü. Kullanıcı sunucu ve iki ekranın kablosuz bağlantısının oyunda çalıştığını ayrıca doğruladı. **Yeni arayüz, otomatik boot, kablosuz sürüm aktarımı ve AE2 gerçek stokları için oyun içi kabul bekleniyor**; otomatik sonuçlar bunun yerine geçmez.

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
| 30 | Kullanıcı .shrc içeriğini koruma, idempotent hook, boot başına tek foreground başlatma ve disable |
| 31 | Eski config'e otomatik açılış/900 saniyelik kontrol ekleme, adresleri koruma, aralık doğrulama |
| 32 | Periyodik kontrol yalnızca manifest indirir; dosya/active değişikliği yapmaz |
| 33 | İki ekranın Internet kullanmadan server cache'inden hash doğrulamalı staging yapması; keyfi yol/offset/release reddi |
| 34 | Bozuk kablosuz parçada hash reddi, eski active korunması |
| 35 | Bağlantı kaybı ve açık iptalde eski active korunması |
| 36 | Başlangıçta ve indirme sonunda meşgul üretim kontrolü; ready manifest yayımlanmaması |
| 37 | Gerçek FactoryOS protokolü + 1024 bayt modem limitiyle iki eşzamanlı istemci aktarımı; RPC cache dolmaması |
| 38 | Daha önce kontrol yapılmışken heartbeat'in yeni sürümü yeniden bildirmesi |
| 39 | Modem/GUI kapandıktan sonra activate ve reboot; Ctrl+C iptali, activation hatasında reboot olmaması |
| 40 | Hash'i doğru olsa bile geçersiz Lua sözdiziminin staging'de reddi |
| AE2 tanılama | Native nil+hata dönüşü, güç kesintisi/geri gelmesi, opsiyonel metot eksikliğinin envanteri düşürmemesi, eski stok temizliği |
| AE2 seçim/log | Çoklu bileşen ve sabit adres seçimi, adres kaybı, neden/adres değişiminde log ve aynı hatada tekrar yazmama |
| AE2 CLI | Gerçek komut yolu, iki örnek arasında 10 saniye bekleme, ikinci örnekte kopma nedeninin çıktısı |
| AE2 bellek | Eski snapshot'ın sürücü çağrısından önce toplanabilmesi; aynı tablo/satırların yerinde sadeleştirilmesi, NBT hash korunması, limit ve geçersiz satırların temizliği |

`tests/crafting.lua` içindeki 16 üretim senaryosu: filtreli tam varyant; flush edilmiş kayıttan sonra native çağrı; computing/running/done ayrımı; aynı ve farklı RPC kimlikleriyle tekrar; reboot ve geçmişten çıkan emir numarası; NBT belirsizliği/çoklu tarif; eskimiş token; miktar sınırları; taze CPU kontrolü/tekrarlı veya değiştirilmiş isimler; çağrıdan önce/sonra disk hatası; eski yedeğe dönmeme; gerçek native hata; iptal/aidiyet; belirsiz işi elle arşivleme; 8 aktif/32 geçmiş sınırı; geçici durum hatası; güncelleme kilidi; modal klavye/çift tıklama/yanıt kaybı/pano; dört çözünürlük; gerçek FactoryOS protokolü + 1024 bayt modem + düşürülen yanıt + server reboot altında tek native çağrı.

`tests/ae2_memory.lua` ayrıca izole Lua allocator'ını **2 MiB** ile sınırlar ve 2000 farklı eşyayı beş defa yeniler. Lua 5.2/5.3'te v0.3.1 kodu aynı fixture/limit altında `not enough memory` verirken v0.3.2 geçmiştir. Bu rakam yalnızca izole fixture bütçesidir; OpenOS, GPU, modem ve gerçek AE2 verileri dahil toplam oyun RAM gereksinimi değildir. Gerçek ağdaki kabul testi bekleniyor.

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

Önce [donanım](hardware.md), [kurulum](installation.md) ve [otomatik açılış/güncelleme](updates.md) adımlarını tamamlayın. Sunucu/ana ekranda v0.5.0, doğru modem allowlist, aynı wireless port, yüklü chunk ve yeterli güç kullanın. Yan ekran önceki v2 protokolüyle çalışabilir. Şifre gerekmez. Aşağıdaki süreler varsayılan konfigürasyon içindir; oyun lag'i nedeniyle gözlemi birkaç saniye uzatabilirsiniz. Otomatik testte süreler sanal saatle deterministiktir.

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
| Otomatik boot | Üç bilgisayarı kapatıp açın | Her rol foreground panelini otomatik açar; Ctrl+C ile kabukta kalır |
| Menü kontrolü | Ana ekranda GUNCELLEMELER, diğerlerinde alttaki düğme/F5 | Kontrol sonucu GUI'de görünür; hata olsa da haberleşme devam eder |
| Kablosuz güncelleme | İstemcinin Internet Card'ını çıkarın; gerçek yeni sürümde GUNCELLE / YENIDEN AC seçin | Server cache'inden alır, doğrular, reboot eder ve aynı modem izinleriyle geri bağlanır |
| Üretim kilidi | AE2 CPU meşgulken güncelleme deneyin | Dosyalar uygulamaya alınmaz; bekleme nedeni görünür |

## Crafting API — v0.4.0 oyun kabulü

Yedek/test dünyasında ucuz ve kolay sayılabilen, çıktısı bir adet olan bir recipe seçin. AE2 DEPOSU → TARIFLI → satır → URETIM EMRI VER yolundan bir adet isteyin. Hem ÜRETİM sayfasındaki job sonucunu hem **AE terminalindeki gerçek stok artışını** kontrol edin. Eksik malzemeyle hata metnini ve iptali doğrulayın. Önceden devam eden işler, tam CPU kapasitesi, reboot sırasında belirsiz iş ve aynı istek tekrarını ayrıca sınayın. Elle emir kodlandı; bu gerçek oyun adımları henüz yapılmadı. Otomatik stok hedefleri ve hata sonrası bekleme v0.5.0'da kodlandı; [ayrı oyun kabulü](stock-automation.md) bekleniyor.

Reaktör kontrolü test kapsamı dışındadır; reaktör otomasyonu uygulanmadı. Önce salt okunur gerçek metotlar ve yerel bağımsız interlock düzeni doğrulanmalıdır.

## Görsel önizlemeler

`python tools/preview.py`, gerçek `ui.renderer` GPU hücre tamponunu örnek verilerle PNG'ye dönüştürür. [Ana panel](previews/main-overview.png), [depo](previews/main-stocks.png), [arama](previews/main-search.png), [offline](previews/main-offline.png), [80×25](previews/main-compact.png), [güncelleme sayfası](previews/main-updates.png), [aktarım](previews/main-update-progress.png), [sunucu düğmesi](previews/server-updates.png) ve [yan ekran düğmesi](previews/side-updates.png) görsel olarak incelendi. Görüntü başlıkları örnek veri olduğunu belirtir; bunlar Minecraft'tan alınan ekran görüntüsü değildir. 40×12, 50×16, 80×25 ve 160×50 boyutları ayrıca dokuz sekme ve arama klavyesiyle GPU sınır testinden geçti.

v0.4.0 [üretim listesi](previews/main-production.png), [miktar/CPU penceresi](previews/main-craft.png), [40×12 pencere](previews/main-craft-small.png) ve [80×25 işler](previews/main-production-compact.png) ayrıca görsel olarak incelendi. Modal açıkken yalnızca kendi düğmeleri dokunma hedefidir; arka plan ve F5/F6 güncelleme eylemleri açılmaz. Klavyeyle çift Enter da ikinci emir oluşturmaz.

v0.5.0 [stok kuralları](previews/main-stock-rules.png), [80×25 kurallar](previews/main-stock-rules-compact.png), [40×12 kurallar](previews/main-stock-rules-small.png) ve [kural düzenleme](previews/main-stock-rule-editor-small.png) aynı örnek veri yöntemiyle üretildi ve görsel olarak incelendi. 2 MiB izole allocator regresyonu artık her yenilemede 16 kuralın stok hesabını da doğrular; gerçek OpenOS toplam RAM ihtiyacını ölçmez.
