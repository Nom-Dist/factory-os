# FactoryOS ağ protokolü v2

v0.1.1 ile ortak anahtar ve HMAC mesaj imzası kaldırıldı. Kurulum şifre sormaz. Dosya indirmelerindeki SHA256 bütünlük kontrolü korunur. v1 ve v2 haberleşmez; üç bilgisayar aynı sürüme güncellenmelidir.

## Taşıma

Varsayılan port **34100**, ilk modem argümanı `FactoryOS/2`, ikinci argüman bounded veri çerçevesidir. OpenComputers sinyal sırası:

```text
modem_message, localAddress, remoteAddress, port, distance, magic, frame
```

Gerçek gönderen modem adresi çerçevedeki `from` ile karşılaştırılır. GPU/bilgisayar adresi bu kimlik yerine geçmez. Gelen port ve yerel modem de doğrulanır. Sunucu, allowlist'te olmayan gönderenleri ayrıştırmadan reddeder. İstemcinin `serverAddress` değeri ayarlanmışsa diğer adresler reddedilir.

```text
frame = {v=2, id, from, to, part, total, data}
```

Uygulama mesajı `{v=2, kind, id, boot, target, body}` biçimindedir. Wire codec string/finite number/boolean/nil ve döngüsüz table verisi taşır. 12 katman, 16000 düğüm ve 64 KiB sınırı vardır. String/number anahtarlar deterministik sıralanır. **Network/config için `load`, `loadfile` veya `serialization.unserialize` kullanılmaz.** OpenOS `serialization.serialize` yalnızca yerel config görünümü/prob çıktısında kullanılır. Güvenilir, hash'i doğrulanmış yerel program kaynaklarının yüklenmesi ayrı bir işlemdir.

OC 1.8.3 paket sınırı `computer.getDeviceInfo()[modem.address].capacity` alanından okunur; bu alan string olabilir. Bu sürümde `modem.maxPacketSize()` metodu bulunmaz. Başka sürümlerde metadata yoksa ve bu isteğe bağlı callback gerçekten mevcutsa kullanılabilir. Sayı doğrulanır; bilgi bulunamazsa veya sınır 1024 bayttan küçükse açıklayıcı hata verilir. Taşıma ayrıca 4096 baytla sınırlıdır. İki string argümanının 4 bayt ek maliyeti ve magic uzunluğu hesaba katılır. Payload küçük parçalara ayrılır; sıra dışı gelen parçalar indeksle birleştirilir. Çakışan parçalar reddedilir. Alımlar 25 saniyede zaman aşımına uğrar. 64 parça/mesaj ve 8 paralel alım sınırı vardır.

## Keşif ve kayıt

1. İstemci açılışta yeni boot kimliği üretir; periyodik HELLO'da yeni nonce gönderir.
2. İzinli adres için sunucu kendi boot kimliği, nonce yankısı ve yeni challenge ile OFFER yollar.
3. İstemci kendi boot'unu hedefleyen, son nonce'a uyan OFFER'a REGISTER_CLIENT yanıtı verir.
4. Sunucu challenge, istemci boot'u, hedef sunucu boot'u ve 15 saniyelik süreyi doğrular. Challenge bir kez tüketilir; REGISTERED gönderilir.
5. Rol istemcinin iddiasından değil **sunucu allowlist'inden** alınır. Yanlış rol eşleştirmesinde istemci kaydı kabul etmez.

Boot/challenge değerleri OpenOS `uuid.next()` ile üretilir. Bu alanlar eski oturum mesajlarının karışmasını önler; parola veya kriptografik kimlik doğrulama değildir. Sunucu adresi boşsa otomatik keşif kullanılır.

## İstek/yanıt

Kayıtlı istemci REQUEST gönderir; body `command` ve `args` içerir. RESPONSE aynı istek kimliğini taşır, doğru uzak modem/sunucu boot'u ve hedef istemci boot'u ile eşleştirilir. Yanıt `{ok,data,error}` içerir.

4 saniye yanıtsız kalan istek aynı uygulama kimliğiyle tekrar gönderilir; toplam 3 deneme, ardından TIMEOUT. Yeni taşıma kimliği kullanılır. Sunucu `(modem,requestId)` için 60 saniyelik bounded önbellek tutar; aynı body tekrarında eski yanıtı yollar, farklı body ile kimlik tekrarını reddeder. Önbellek doluysa yeni işi yürütmez. Salt okunur ve sürüme sabitlenmiş `GET_UPDATE_FILE` parçaları idempotent olduğundan bu önbelleğe alınmaz; iki istemcinin dosya akışı normal RPC önbelleğini doldurmaz. Bu pencere dışında veya sunucu reboot'unda **kalıcı exactly-once garantisi yoktur**. Üretim/reaktör komutları reddedilir.

5 saniyede bir HEARTBEAT, sunucu genel durumu/enerji/AE2 özeti/istemci listesini getirir. 18 saniye uygun oturumdan yanıt yoksa istemci OFFLINE olur; eski telemetri güncel gösterilmez. Sunucu istemciyi de zaman aşımıyla siler. Keşif yeniden başlar. Yerel saatler senkronize edilmez; aralıklar `computer.uptime()` ile hesaplanır.

## Komutlar ve erişim

| Uygulama komutu | Main | Side | İçerik |
|---|---|---|---|
| HEARTBEAT / GET_SERVER_STATUS | evet | evet | Sunucu özeti ve telemetri |
| GET_AE2_STOCKS | evet | hayır | 24 varyant/sayfa, plain substring sorgusu, genel ad/miktar sırası ve tarifli/favori filtresi |
| GET_CRAFTING_JOBS | evet | hayır | CPU doluluğu ve en fazla 32 FactoryOS emrinin gerçek durumu |
| GET_CRAFT_OPTIONS | evet | hayır | Tam ürün kimliğinden filtreli tarif doğrulaması, CPU seçenekleri, 60 saniyelik seçim token'ı ve sıradaki emir numarası |
| START_CRAFT | evet | hayır | Token/numara/adet/CPU ile kalıcı kayıttan sonra tek üretim çağrısı |
| CANCEL_CRAFT / ARCHIVE_CRAFT | evet | hayır | Emir sahibinin işi iptal etmesi / belirsiz işi kontrol sonrası yalnızca izlemeden arşivlemesi |
| GET_POWER_STATUS | evet | evet | AE birimli AE2 enerjisi, diğer sürücüler unsupported |
| GET_MACHINE_STATUS | evet | evet | Henüz doğrulanmış sürücü olmadığı bilgisi |
| GET_UPDATE_INFO | evet | evet | Güncelleme durumu/manifest, isteğe bağlı GitHub kontrolü ve cache hazırlığı |
| GET_UPDATE_FILE | evet | evet | Manifestte izinli dosyadan en fazla 1024 bayt salt okunur parça |
| REQUEST_CRAFT, SUBSCRIBE_UPDATES, UPDATE_AVAILABLE, diğerleri | hayır | hayır | UNSUPPORTED_COMMAND |

v0.2.0 stok args alanları: `page`, `query`, `sort="name"|"amount"`, `filter="all"|"craftable"|"favorites"`. Favori filtresinde en fazla 32 adet, her biri en fazla 1024 bayt olan `favoriteKeys` string dizisi gönderilir. Anahtarlar `core.items` içindeki canonical `name/damage/hasTag/tag` temsilidir; üretim yetkisi taşımaz. Filtreleme ve sıralama sayfalamadan önce uygulanır. Yanıt `filter` ve `sort` alanlarını yankılar; eski sunucu bu alanları desteklemiyorsa ana ekran özel filtre/sıra sonucunu göstermez ve güncelleme gerektiğini bildirir. Wire protokolü v2 kalır; eski salt okunur istemciler varsayılan name/all sorgularıyla çalışabilir.

v0.3.0 `GET_UPDATE_INFO` args: `check=true` manifest kontrolünü, `prepare=true,release=...` doğrulanmış server cache hazırlığını ister. Yanıt `{info,manifest,busy,ready}`; `info` heartbeat durumuna da eklenir. Hazırlık asenkron olduğundan istemci yeni istek kimlikleriyle durumu tekrar okur. `GET_UPDATE_FILE` args `{release,path,offset}`; yanıt `{release,path,offset,size,data}`. Release ve path cache manifestiyle tam eşleşmelidir; config/başka dosyalar okunmaz. Kaynak metinleri ağdan direkt çalıştıran komut yoktur. İstemci ancak yerel kullanıcının güncelleme eyleminden sonra tam dosyaları staging alanına alır, SHA256/sözdizimi doğrular ve kendi bilgisayarını yeniden başlatır. [Güncelleme akışı](updates.md).

v0.4.0 `GET_CRAFT_OPTIONS {item={name,damage,hasTag,tag,identityComplete}}` yanıtı `{token,sequence,label,cpus,maxAmount}`; seçim ilgili istemci modemine ve AE2 bileşenine bağlıdır. `START_CRAFT {token,sequence,amount,cpu}` için CPU boş string ise otomatik seçilir. `CANCEL_CRAFT {id}` ve `ARCHIVE_CRAFT {id}` yalnızca kayıt sahibine açıktır. Job yanıtı `{id,owner,label,amount,cpu,state,error}`; userdata ve tarif nesneleri ağdan geçirilmez. Numara/token/adet/CPU uyuşmayan tekrarlar reddedilir. Diskteki monoton numara ve sınırlı kayıtlar RPC cache'i sona erdikten, kayıt geçmişten çıkarıldıktan ve sunucu reboot olduktan sonra da aynı emrin yeniden çağrılmasını engeller. Bozuk journal'da yazma komutları açılmaz. [Üretim ve reboot davranışı](crafting.md).

## Çalışma modeli

Protokol, kullanıcının güvenilen Minecraft ağı için şifresiz çalışır. Modem adresi izin listesi ve oturum denetimleri korunur; kriptografik kimlik doğrulama ve şifreleme yoktur.

Bozuk çerçeveler log taşmasına yol açmamak için sessiz reddedilir. Bağlantı geçişleri ve yazılım hataları loglanır. Bağlantı kesilmesi hiçbir üretim veya reaktör komutu tetiklemez.
