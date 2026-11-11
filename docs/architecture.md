# FactoryOS mimarisi

## Çalışma sınırları

```text
8x5 screen <-- local GPU -- Main Display -- wireless --+
                                                     |
                                              Factory Server -- Adapter -- ME Interface / AE2
                                                     |
4x5 screen <-- local GPU -- Side Display -- wireless -+
                                                     |
                                           local GPU -- 1x1 console
```

Hiçbir ekran istemcisi AE2 proxy'si almaz. Sunucu yalnızca veri yanıtlar; istemci GPU'sunu uzaktan bağlamaz. Üç OC yerel bileşen ağı ayrıdır. Üç bilgisayarda kablosuz modem, kendi GPU'su ve ekranı bulunur.

## Modüller

| Dizin | Sorumluluk |
|---|---|
| `src/core` | config, dosya işlemleri, kripto, bounded codec, donanım, yaşam döngüsü, log, installer/updater |
| `src/network` | modem parçalama/kuyrukları, oturum ve istek yönetimi, komut erişim kuralları |
| `src/server` | AE2 snapshot, enerji adaptasyonu, doğrulanmamış makine yeteneklerinin açık reddi |
| `src/client` | ana ekran sayfa/arama/favori durumu, asenkron istek eşleştirme, yerel tercihler, yan ekran salt durum tüketimi |
| `src/ui` | GPU hücre farkı, çok satırlı dokunmatik alanlar, widgets/format, main_screen yerleşimi ve dokunmatik klavye |
| `tests` | iki Lua sürümünde hata ve entegrasyon senaryoları |
| `tools` | yeniden üretilebilir paketleme, oyun içi salt okunur prob |

## Ana döngü

`event.pull(0.12)` boş beklemeyle CPU'yu bırakır. Her döngüde en fazla bir modem çerçevesi gönderilir. Ekran en fazla saniyede bir değerlendirilir; GPU'ya yalnızca değişen karakter/renk aralıkları yazılır. OC 1.8 video buffer API'leri kullanılmaz. Her rol tek GPU'yu tek ekrana bir kez bağlar.

Heartbeat varsayılan 5 saniye, bağlantı kaybı 18 saniye, AE2 snapshot aralığı 10 saniyedir. Ana ekran yalnızca depo sayfası açıkken stok verisini ister; CPU özetini sağ sütun/ana panel için 10 saniyede bir alır. Aynı türdeki periyodik istek sürerken yenisi biriktirilmez. Arama taslağı onaylanana kadar ağ isteği gönderilmez; eski sorguya ait gecikmiş yanıtlar yeni görünümü değiştirmez. Yan ekran yalnızca heartbeat telemetrisini kullanır. Push/subscription protokolü bu sürümde uygulanmaz.

Bir bilgisayarda yalnızca bir FactoryOS servisi başlatılır. Arka plan OpenOS `thread.create(...):detach()` ile çalışır; `stop` döngüye durma bayrağı verir, temizlik için 8 saniyeye kadar bekler. Aktif servis varken CLI config/güncelleme reddedilir; menü kontrollü bir hazırlama/kapanış akışı kullanır. `status`, yerel süreç belleğindeki servis kaydını kontrol eder; eski diskteki PID dosyasına güvenmez. Reboot sonrası eski servis kaydı yoktur; config kalıcıdır.

v0.3.0 açılışta `.shrc` üzerinden foreground başlatır. Güncelleme menüsü HTTP/dosya işini bağlı bir OpenOS worker thread'ine verir; ağ ve GPU döngüsü devam eder. Server 15 dakikada bir yalnızca manifest kontrol eder. İstemciler açık kullanıcı eylemiyle sunucunun cache'inden 1024 baytlık parçalar alır; tam hash/sözdizimi doğrulaması ve idle kontrolünden sonra runtime modem/GUI'yi kapatır, pointer'ı değiştirir ve reboot eder. [Açılış/güncelleme tasarımı](updates.md).

## Kaynak sınırları

- Çerçeve: modem sınırı veya 4096 bayttan küçüğü; modem limiti en az 1024 olmalı.
- Bir uygulama mesajı en fazla 64 KiB ve 64 parça; küçük modem limitinde efektif üst sınır daha düşüktür.
- 256 bekleyen gönderim çerçevesi, 8 parçalı alım, 8 bekleyen istemci isteği.
- 16 izinli istemci; sunucu tekrar önbelleği en fazla 128 kayıt / 60 saniye.
- Envanter snapshot'ı en fazla 2000 varyant; limit ekranda işaretlenir. v0.3.2 eski snapshot'ı okumadan önce bırakır, dönen tabloyu yerinde sadeleştirir; ikinci tam kopya oluşturmaz. AE2'nin `getItemsInNetwork()` çağrısı önce tüm Java/Lua tablosunu üretir; çok büyük ağlar hâlâ RAM sınırına takılabilir.
- 24 stok/sayfa, 160 karakter eşya adı/etiketi, 512 karakter tag/hash özeti.
- Ana ekranda 32 yerel favori; belirsiz NBT kimliği favori olarak kalıcılaştırılmaz. Favori filtresi bounded canonical varyant anahtarlarıyla sunucuda uygulanır.
- Log yaklaşık 64 KiB'de döner; bir önceki dosya korunur.
- Güncelleme en fazla 128 dosya, dosya başına 64 KiB, toplam kaynak 512 KiB.

Saf Lua SHA256 yalnızca kurulum/güncelleme dosya bütünlüğünde kullanılır; ağ mesajları şifre veya imza işlemi yapmaz. Modem/GPU çağrı bütçesi Minecraft üzerinde ölçülmelidir. Tier 3 sunucu ve ana ekran için yüksek RAM önerilir. İnce GPU çözünürlüğü ve büyük ağ snapshot'larıyla gerçek bellek tüketimi henüz ölçülmedi.

## Aşamaların gerçek durumu

Phase 1'in sunucu ve iki ekran arasındaki kablosuz bağlantısı kullanıcı tarafından oyun içinde doğrulandı. Yeni arayüz, otomatik açılış ve kablosuz güncelleme için oyun kabulü beklenir. Phase 2'de salt okunur AE2 sürücüsü/arayüzü hazırdır. v0.4.0 Phase 3'ün elle üretim emri, miktar/CPU seçimi, takip ve iptalini ekler; gerçek Minecraft crafting kabulü beklenir. Otomatik stok hedefleri ve Phase 4 reaktör sürücüleri uygulanmadı; Phase 5'in kablosuz yazılım dağıtımı hazırdır.

v0.4.0 `server.crafting`, filtreli native tariften tam varyantı doğrular. Tek `request()` çağrısından önce modem başına monoton emir numarası ve kayıt diske flush edilir. RPC cache'inden bağımsız tekrar denetimi, 8 aktif/belirsiz iş, 32 geçmiş kayıt, CPU tekrar kontrolü ve güncelleme kilidi vardır. Reboot sonrası userdata tekrar bağlanmaz; belirsiz işler yeniden gönderilmez ve ME Terminal kontrolünden sonra kullanıcı tarafından yalnızca izlemeden arşivlenebilir. [Üretim akışı](crafting.md). Otomatik stok hedefleri için ayrıca in-flight stok hesabı, kaynak eksikliğinde bekleme ve hız sınırı gerekir.

Reaktör sürücülerinin başlangıcı salt okunur olmalı. Gerçek kontrol eklenirken yerel bağımsız kapama/interlock düzeni zorunlu tasarım girdisidir; merkezî heartbeat kaybı bir güvenlik sistemi yerine geçmez.
