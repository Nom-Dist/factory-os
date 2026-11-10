# FactoryOS ağ protokolü v1

## Taşıma

Varsayılan port **34100**, ilk modem argümanı `FactoryOS/1`, ikinci argüman bounded veri çerçevesidir. OpenComputers sinyal sırası:

```text
modem_message, localAddress, remoteAddress, port, distance, magic, frame
```

Gerçek gönderen modem adresi çerçevedeki `from` ile karşılaştırılır. GPU/bilgisayar adresi bu kimlik yerine geçmez. Gelen port ve yerel modem de doğrulanır. Sunucu, allowlist'te olmayan gönderenleri ayrıştırmadan reddeder. İstemcinin `serverAddress` değeri ayarlanmışsa diğer adresler reddedilir.

```text
frame = {v, id, from, to, part, total, data, mac}
mac = HMAC-SHA256(sharedKey, canonicalEncode(frame_without_mac))
```

Uygulama mesajı `{v, kind, id, boot, target, body}` biçimindedir. Wire codec string/finite number/boolean/nil ve döngüsüz table verisi taşır. 12 katman, 16000 düğüm ve 64 KiB sınırı vardır. String/number anahtarlar deterministik sıralanır. **Network/config için `load`, `loadfile` veya `serialization.unserialize` kullanılmaz.** OpenOS `serialization.serialize` yalnızca yerel config görünümü/prob çıktısında kullanılır. Güvenilir, hash'i doğrulanmış yerel program kaynaklarının yüklenmesi ayrı bir işlemdir.

Modem `maxPacketSize()` okunur; taşıma 4096 baytı aşmaz. İki string argümanının 4 bayt ek maliyeti ve magic uzunluğu hesaba katılır. Payload küçük parçalara ayrılır. Her parça ayrı imzalanır; sıra dışı gelen parçalar indeksle birleştirilir. Çakışan parçalar reddedilir. Alımlar 25 saniyede zaman aşımına uğrar. 64 parça/mesaj ve 8 paralel alım sınırı vardır.

## Keşif ve kayıt

1. İstemci açılışta yeni boot kimliği üretir; periyodik HELLO'da yeni nonce gönderir.
2. İzinli adres için sunucu kendi boot kimliği, nonce yankısı ve yeni challenge ile OFFER yollar.
3. İstemci kendi boot'unu hedefleyen, son nonce'a uyan OFFER'a REGISTER_CLIENT yanıtı verir.
4. Sunucu challenge, istemci boot'u, hedef sunucu boot'u ve 15 saniyelik süreyi doğrular. Challenge bir kez tüketilir; REGISTERED gönderilir.
5. Rol istemcinin iddiasından değil **sunucu allowlist'inden** alınır. Yanlış rol eşleştirmesinde istemci kaydı kabul etmez.

Boot/challenge değerleri OpenOS `uuid.next()` ile üretilir. Benzersizlik beklenir; kriptografik rastgelelik iddia edilmez. Gizli olmayan nonce'lar HMAC anahtarının yerini tutmaz. Paylaşılan anahtar host tarafında güçlü bir rastgele üreticiden oluşturulmalıdır.

## İstek/yanıt

Kayıtlı istemci REQUEST gönderir; body `command` ve `args` içerir. RESPONSE aynı istek kimliğini taşır, doğru uzak modem/sunucu boot'u ve hedef istemci boot'u ile eşleştirilir. Yanıt `{ok,data,error}` içerir.

4 saniye yanıtsız kalan istek aynı uygulama kimliğiyle tekrar gönderilir; toplam 3 deneme, ardından TIMEOUT. Yeni taşıma kimliği kullanılır. Sunucu `(modem,requestId)` için 60 saniyelik bounded önbellek tutar; aynı body tekrarında eski yanıtı yollar, farklı body ile kimlik tekrarını reddeder. Önbellek doluysa yeni işi yürütmez. Bu pencere dışında veya sunucu reboot'unda **kalıcı exactly-once garantisi yoktur**. v0.1 bütün durum değiştiren ağ komutlarını reddeder.

5 saniyede bir HEARTBEAT, sunucu genel durumu/enerji/AE2 özeti/istemci listesini getirir. 18 saniye doğrulanmış yanıt yoksa istemci OFFLINE olur; eski telemetri güncel gösterilmez. Sunucu istemciyi de zaman aşımıyla siler. Keşif yeniden başlar. Yerel saatler senkronize edilmez; aralıklar `computer.uptime()` ile hesaplanır.

## Komutlar ve erişim

| Uygulama komutu | Main | Side | İçerik |
|---|---|---|---|
| HEARTBEAT / GET_SERVER_STATUS | evet | evet | Sunucu özeti ve telemetri |
| GET_AE2_STOCKS | evet | hayır | 24 varyant/sayfa, plain substring sorgusu |
| GET_CRAFTING_JOBS | evet | hayır | CPU doluluğu; mevcut iş ayrıntıları unsupported |
| GET_POWER_STATUS | evet | evet | AE birimli AE2 enerjisi, diğer sürücüler unsupported |
| GET_MACHINE_STATUS | evet | evet | Henüz doğrulanmış sürücü olmadığı bilgisi |
| REQUEST_CRAFT, SUBSCRIBE_UPDATES, UPDATE_AVAILABLE, diğerleri | hayır | hayır | UNSUPPORTED_COMMAND |

## Güvenlik sınırları

HMAC doğrulama sağlar, **şifreleme sağlamaz**; yakın ağ gözlemcisi durum verisini görebilir. Anahtar pakete açık olarak eklenmez. Bütün düğümler aynı grup anahtarını bildiğinden ele geçirilen izinli bir düğüme karşı ayrı istemci gizliliği yoktur. Sunucu adresini sabitlemek keşif alanını daraltır. RF paraziti, paket kaybı, flooding veya ele geçirilmiş oyun sunucusuna karşı kullanılabilirlik garantisi verilmez.

Anahtar uyuşmazlığı ve bozuk çerçeveler log taşmasına yol açmamak için sessiz reddedilir. Bağlantı geçişleri ve yazılım hataları loglanır. Ham paket/config/anahtar loglanmamalıdır. Bağlantı kesilmesi hiçbir üretim veya reaktör komutu tetiklemez.
