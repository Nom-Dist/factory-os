# FactoryOS — proje bağlamı ve çalışma notları

Son güncelleme: 11 Kasım 2026. Bu dosya, tamamlanan işleri ve sonraki çalışmalar için önemli kararları kaydeder.

## Mevcut durum

- Depo: `https://github.com/Nom-Dist/factory-os.git`, dal: `main`.
- Yayımlanan uygulama: **v0.4.0**, release: `0.4.0-2d9866b39c6f`.
- Son uygulama commit'i: `8ddde1e` — üretim öncesi disk kayıt hatasını, üretim başlamış gibi göstermeme düzeltmesi. Ana üretim özelliği commit'i: `b439b81`.
- Paket ve yeni üretim modülleri GitHub raw adreslerinden indirilip yerel dosyalarla karşılaştırıldı.
- Sunucunun ve iki ekranın kablosuz bağlandığını kullanıcı Minecraft içinde doğruladı.
- Yeni üretim özelliği gerçek Minecraft'ta henüz denenmedi. Mock/Lua testlerini oyun içi doğrulama olarak sunma. Yeni arayüz, boot ve kablosuz güncelleme için de açık kullanıcı kabulü kaydedilmedi.

## Hedef ortam ve mimari

- Minecraft Java **1.12.2**, Enigmatica 2 Expert Skyblock. Yerel Prism kurulumları pack **1.90g-b** gösteriyor; aktif dünya/instance kesinleştirilmedi.
- Kurulu mod kaynakları: **OpenComputers 1.8.3+274990f**, **AE2 rv6-stable-7**. Kritik davranışlar yerel JAR ve aynı OC commit'inin kaynak koduyla doğrulandı. Güncel sürümlerin API'lerini bu ortama varsayma.
- Lua **5.2 ve 5.3** desteklenir. Yerel OC ayarında varsayılan 5.3.
- Üç ayrı bilgisayar: Factory Server (1×1 konsol), Main Display (8×5, hedef 160×50 karakter), Side Display (4×5, hedef 80×25).
- Her bilgisayar kendi GPU/ekranını kullanır. Ekranlar sunucuyla yalnızca modem mesajları üzerinden haberleşir. GPU veya AE2 proxy nesneleri ağdan aktarılmaz.
- Kullanıcı şifre/ortak anahtar mekanizmasını kaldırmayı istedi. Protokol `FactoryOS/2`, wire sürümü 2; modem allowlist, oturum/boot kimliği, sınırlar ve tekrar denetimi korunur. SHA256 yazılım dosyası bütünlüğü içindir.

Doğrulanmış modem adresleri:

| Rol | Adres |
| --- | --- |
| Server | `e89669fc-89dc-450d-ae26-13ec670daaf1` |
| Main | `7fa79c00-5e2e-4af0-b7c5-c64874dfe0bd` |
| Side | `62a7da92-1bbb-4ee5-b0cd-d2c7a8094f59` |

Ana ekran adresi önce yanlış okunmuştu; yukarıdaki değer doğrudur. Modem adresi ile `ae2Address` aynı şey değildir. `ae2Address`, Adapter'ın sunduğu ME bileşenini seçer. Birden fazla bileşende rastgele seçim yapma.

## Tamamlanan özellikler

- Şifresiz installer, soruların ayrı satırda gösterilmesi, doğru OpenOS komut yolu.
- Üç rol, otomatik keşif/kayıt, heartbeat, yeniden bağlanma, paket parçalama ve sınırlar.
- Ana ekran: dokuz sekme, stok arama, dokunmatik klavye, fiziksel klavye/pano, ad/miktar sırası, tarifli/favori filtreleri, sayfalama ve kalıcı 32 favori.
- AE2 stok/CPU/enerji okuması; eski veriler bağlantı kaybında canlı gösterilmez.
- Foreground otomatik açılış: `/home/.shrc` içindeki işaretli blok, kullanıcı satırları korunur. Ctrl+C sonrasında aynı boot içinde kendiliğinden yeniden açılmaz.
- Güncelleme: server açılıştan yaklaşık 15 saniye sonra ve sonra 900 saniyede bir manifest kontrol eder. Otomatik kontrol sürümü kendiliğinden uygulamaz. F5 kontrol, F6 kullanıcı isteğiyle uygulama. Ekranlar dosyaları sunucudan kablosuz alabilir; yalnızca server Internet Card gerektirir.
- v0.3.1: `factoryos ae2 [örnek sayısı]`, gerçek metot/hata/adres ve güç tanılaması.
- v0.3.2: `not enough memory` için stok yenilemesinde eski snapshot'ı önce bırakma, native tabloyu kopyalamadan sadeleştirme ve kullanılmayan alanları temizleme.
- v0.4.0: ana ekrandan miktar/CPU seçerek elle otocraft emri; durum takibi, iptal, kalıcı tekrar engeli, belirsiz işi kullanıcı kontrolünden sonra izleme listesinden arşivleme.

**Kullanıcının iptal ettiği özellik:** tür sayısının yanında maksimum kapasite ve doluluk yüzdesi. Kurulu ağ API'si toplam tür kapasitesini doğrudan vermediği için kullanıcı elle kapasite girilmesini de reddetti. Bu deneme tamamen geri alındı. Gerçek veri olmadan kapasite, doluluk veya benzer değerler ekleme.

## Üretim akışı ve değişmezler

- Kullanım: **AE2 DEPOSU → TARIFLI → ürün satırı → URETIM EMRI VER**. Miktar kısayolları 1/8/16/64; sayısal giriş 1..1.000.000. Miktar bir üretim emridir, hedef stok değildir.
- Server `getCraftables({name,damage})`, `getItemStack()` ve tam varyant kimliğiyle ürünü tekrar doğrular. Belirsiz NBT, kesilmiş uzun kimlik ve çoklu eşleşme ile üretim başlatılmaz. Aynı filtrede en fazla 64 tarif varyantı incelenir; en fazla 32 CPU listelenir.
- Native çağrı: `request(amount, true)` veya isimli CPU için `request(amount, true, cpuName)`. Otomatik CPU'da üçüncü argümanı hiç gönderme; açık `nil` göndermeye dayanma.
- `isDone()` / `isCanceled()` hesaplama sürerken **nil, "computing"**, hata durumunda **false, hata metni** döndürebilir. Job nesnesinin dönmesi, üretimin başladığı veya tamamlandığı anlamına gelmez.
- İlerleme yüzdesi, ayrıntılı eksik malzeme listesi ve otomatik atanan CPU ismi API'den gelmiyorsa tahmin edilmez. Başka uygulamalardan verilen işlerin ürün/miktarı okunmaz.
- Komutlar: `GET_CRAFT_OPTIONS`, `START_CRAFT`, `CANCEL_CRAFT`, `ARCHIVE_CRAFT`. Sadece allowlist'te `main` rolündeki modemler erişebilir; iptal/arşivleme kayıt sahibine bağlıdır.
- `/var/lib/factoryos/crafting.dat`: modem başına monoton emir numarası ve son 32 kayıt. En fazla 16 kayıt sahibi ve 8 aktif/belirsiz iş.
- **Native `request()` çağrısından önce kayıt diske yazılıp flush/rename başarısı denetlenir.** Bu sıralamayı bozma. 60 saniyelik RPC cache'i tek başına kalıcı tekrar engeli değildir.
- Geçmişten çıkarılmış eski emir numaraları da tekrar çalıştırılmaz. Reboot sonrası eski userdata'ya otomatik yeniden bağlanılmaz; bitmemiş işler `unknown` olur ve yeniden gönderilmez.
- Kullanıcı ME Terminal'de kontrol ettikten sonra **ME'DE BAKTIM** düğmesi yalnızca takibi `reviewed` olarak arşivler. AE2 işini iptal etmez ve tamamlandı ilan etmez.
- Aktif/belirsiz kayıtlar menüden güncellemeyi engeller; hesaplama sırasında CPU boş görünse bile. Server güncelleme worker'ı çalışırken yeni üretim başlatılmaz.
- Bozuk/eksik journal için eski `.bak` otomatik kullanılmaz. Disk hatasında yeni emirler durur. Üretim kaydını silerek veya eski kayda dönerek tekrar engelini kaldırma.

## OC/OpenOS uyumluluk tuzakları

- `install.lua` tek başına yazılırsa OpenOS'un kendi `/bin/install.lua` dosyası çalışabilir. Kullanıcı installer'ı için `/home/install.lua` veya `./install.lua` kullanılır. Üzerine indirme: `wget -f URL /home/install.lua`.
- Bu OC sürümünde `modem.maxPacketSize()` yoktur. Kapasite `computer.getDeviceInfo()[modem.address].capacity` üzerinden okunur.
- Proxy callback'leri `__call` metotlu **table** olabilir. Yalnızca `type(method)=="function"` kontrolü yapma.
- OC sandbox'ında global `collectgarbage` yoktur. Üretim/stok kodunu buna bağımlı yapma.
- `getItemsInNetwork()` tüm native envanteri tek seferde verir. Yerel 2000 satır cache sınırı ilk tahsisin RAM gereksinimini azaltmaz; çok büyük ağlarda oyun içindeki server RAM'ini yükseltmek gerekebilir.
- AE2 enerji birimi **AE**, akış **AE/t**; RF/FE diye etiketleme.
- OpenOS `package.preload` desteklemez. Üretilmiş installer özel lexical `require` kullanır. Test runner'ın standart Lua preload kullanımını hedef ortama kopyalama.
- `filesystem.makeDirectory` mevcut dizinde hata verebilir; önce varlık/tür kontrolü gerekir. Başarılı `close()` değer döndürmeyebilir; write/flush ve exception kontrolü yapılır.
- Boot cache temizliğinde yalnızca FactoryOS'un tam modül isimlerini temizle. OpenOS'un kendi `core.*` modüllerini topluca silme. Yeni modül eklerken `src/boot.lua` listesini güncelle.
- Ağ/config parser'ı data-only `core.codec`; gelen veriyi `load` veya `serialization.unserialize` ile çalıştırma.

## Dosyalar ve kalıcı veriler

- Üretim: `src/server/crafting.lua`, `src/client/crafting.lua`, `src/ui/crafting.lua`.
- AE2 snapshot: `src/server/ae2.lua`; komut dağıtımı: `src/server/main.lua`; event döngüsü: `src/core/runtime.lua`.
- Ağ izinleri/protokol: `src/network/messages.lua`, `src/network/protocol.lua`, `src/network/modem.lua`.
- Ana ekran: `src/ui/main_screen.lua`, `src/client/main_display.lua`.
- Config `/etc/factoryos/config.dat`, favoriler `/etc/factoryos/display.dat`, üretim journal'ı `/var/lib/factoryos/crafting.dat`, log `/var/log/factoryos.log`.
- Sürümler `/usr/lib/factoryos/releases/`; active pointer ve önceki sürüm hash kontrolleri korunur. Güncelleme config/favori/journal dosyalarını sıfırlamaz.
- Ayrıntılı rehberler: `docs/crafting.md`, `docs/ae2-diagnostics.md`, `docs/updates.md`, `docs/compatibility.md`, `docs/testing.md`.

## Build, test ve yayımlama

```sh
python tools/build.py
python tests/run.py
python tools/preview.py
git diff --check
```

- Test bağımlılığı: yerel `.tools` içinde Lupa 2.8; görsel önizlemeler için Pillow. Kurulum gerekirse `python -m pip install --target .tools -r requirements-dev.txt`.
- Son sonuç: **Lua 5.2'de 60/60, Lua 5.3'te 60/60**; ayrıca 2000 eşyanın beş yenilemesini 2 MiB allocator sınırı altında çalıştıran stok regresyonu geçti. Bu izole test bütçesi gerçek OpenOS toplam RAM ihtiyacı değildir.
- `tests/crafting.lua` gerçek Lua koduyla disk hatası, reboot, tekrar/çift tıklama, NBT, CPU, iptal, arşivleme, dört ekran boyutu ve gerçek FactoryOS protokolünü 1024 bayt modem/yanıt kaybı koşulunda sınar. Component, modem, disk, zaman ve GPU çevresi mock'tur.
- `tools/preview.py` gerçek Lua renderer hücrelerini örnek verilerle PNG'ye çevirir. `docs/previews/` görüntüleri Minecraft ekran görüntüsü değildir. UI değişince üret ve görsel olarak incele.
- Kaynakları `src/` altında düzenle. `install.lua`, `manifest.dat`, `dist/factoryos-offline.lua` build çıktılarıdır; elle düzeltme. Bunlar git'te izlenir. ZIP, `.tools/`, `.research/` ve loglar ignore edilir.
- Sürüm değişiminde `tools/build.py`, server status ve UI footer sabitlerini tutarlı güncelle; preview fixture sürümlerini de gözden geçir. LF satır sonlarını koru. Release kimliği kaynak hash'ini içerir.
- Kaynak değişiminden sonra yeniden build et ve ilgili testleri tamamla. Sadece dokümantasyon değişikliği uygulama paketi/hash değişikliği gerektirmez.
- Önceki uygulama sürümleri `main` dalına commit/push edildi. Bu dosyanın yazılması, yeni üretim emirlerini kullanıcı adına oyunda çalıştırma yetkisi değildir.

## Açık kalan işler

1. v0.4.0 için gerçek Minecraft kabulü: ucuz, tek çıktı veren tariften bir adet üretip job durumunu ve ME Terminal stoğunu doğrulamak; ardından eksik kaynak, dolu CPU, iptal ve bağlantı/reboot senaryoları.
2. Sonraki özellik adayı: minimum/hedef stokla otomatik üretim. Henüz uygulanmadı; in-flight miktarı, kaynak eksiğinde bekleme ve hız sınırı ayrıca tasarlanmalı.
3. Mekanism, RF/FE ve reaktör sürücüleri henüz uygulanmadı. UI'da desteklenmeyen veriyi çalışıyor gibi gösterme.

Kullanıcı Türkçe iletişim ve oyun bilgisayarına doğrudan yapıştırılabilir komutlar tercih ediyor. Gerçek API verisi ile örnek/hesaplanmış veriyi açıkça ayır; yapılmış işi tekrar teklif etmek yerine mevcut durumdan devam et.
