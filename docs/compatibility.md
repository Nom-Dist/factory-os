# Sürüm ve API doğrulaması

Araştırma tarihi: **11 Kasım 2026**. Oyun dünya dosyaları değiştirilmedi; yalnızca kurulum metadata/JAR/config ve resmî kaynaklar okundu.

## Yerel kurulumlar — dosyalardan doğrulandı

Şu üç instance bulundu:

- CurseForge: `Enigmatica 2 Expert Skyblock - E2ES`
- PrismLauncher: `Enigmatica 2- Expert Skyblock - E2ES`
- PrismLauncher: `Enigmatica 2- Expert Skyblock - E2ES(1)`

İki Prism `instance.cfg` dosyası **ManagedPackVersionName=1.90g-b**, `mmc-pack.json` dosyaları **Minecraft 1.12.2 / Forge 14.23.5.2860** gösteriyor. CurseForge metadata'sında Minecraft 1.12.2 doğrulandı; yalnızca pack adıyla tam pack sürümü çıkarılmadı. Üç instance'ın ilgili mod dosyaları aynı sürümleri gösteriyor:

| Mod | Yerel JAR sürümü |
|---|---|
| OpenComputers | MC1.12.2-1.8.3+274990f |
| Applied Energistics 2 | rv6-stable-7 |
| Mekanism | 1.12.2-9.8.3.390 |
| Ender IO | 1.12.2-5.3.72 |
| NuclearCraft | 2.18zzz-1.12.2 |
| Extreme Reactors | 1.12.2-0.4.5.50 |
| Draconic Evolution | 1.12.2-2.3.28.354 |
| RFTools | 1.12-7.73 |

OC JAR içindeki `mcmod.info` ayrıca **OpenComputers 1.8.3 / Minecraft 1.12.2** bildiriyor. CurseForge instance `config/opencomputers/settings.conf` içinde `defaultLua53=true`, `enableLua53=true`, `maxScreenWidth=8`, `maxScreenHeight=6`, Tier 2 wireless üst aralığı 400 okundu. Bu, kullanıcının 8×5 / 4×5 ekran düzeniyle uyumludur. Sunucuda farklı config uygulanmış olabilir.

**Aktif dünya/instance kesinleştirilmedi.** Bu rapor kurulu dosyaları doğrular; çalışan Minecraft'taki mod listesini, OpenOS HDD'deki sürümü veya Adapter davranışını doğrulamaz. OpenOS kurulum diski eski JAR'dan kurulmuşsa HDD kütüphaneleri daha eski olabilir.

## Resmî depo ile fark

[Resmî MODLIST.md](https://github.com/EnigmaticaModpacks/Enigmatica2ExpertSkyblock/blob/master/MODLIST.md) başlığı **v1.36** ve OC **1.7.5.192** içeriyor. AE2 rv6-stable-7 ve Mekanism 9.8.3.390 eşleşiyor; birçok diğer mod daha eski. Dolayısıyla repo mod listesi kullanıcının yerel 1.90g-b kurulumunun birebir manifesti sayılamaz. Proje 1.12.2 OC API alt kümesini kullanır; 1.7.5 ve 1.8.3 için aynı OpenOS uyumluluk tuzakları gözetilmiştir. Yeni AE2 veya Rebooted API'leri kullanılmadı.

## Kodda çözülen uyumluluk noktaları

| Konu | İncelenen kanıt | Uygulama |
|---|---|---|
| OpenOS require | Kurulu 1.8.3 JAR `loot/openos/lib/package.lua` | `package.preload/searchers` yok. Installer özel lexical loader kullanır; normal OpenOS require'a bundled modül yükletmez. |
| Dahili core.* modülleri | Aynı package yapısı/JAR lib listesi | Cache temizliği yalnızca FactoryOS'un tam modül adlarıyla yapılır; OpenOS `core.full_filesystem` vb. korunur. |
| makeDirectory | JAR `lib/core/full_filesystem.lua` | Mevcut dizinde nil+hata verir. Yazma öncesi exists/isDirectory kontrolü eklenmiştir. |
| Dosya kapama | JAR buffer/filesystem ve resmî FileSystem sürücüsü | `close()` başarıda değer döndürmeyebilir. Yazma ve `flush()` denetlenir; close yalnızca exception için kontrol edilir. |
| Installer satır düzeni | JAR `lib/term.lua` ve oyun ekranı | Her soruda yeni `term.read({dobreak=false})` cursor'u; ardından açık `io.write("\n")`. Şifre adımı kaldırıldı. |
| Lua bit işlemleri | Yerel config Lua 5.3 varsayılanı; gerçek Lua 5.2/5.3 testleri | 5.2 bit32; 5.3'te yoksa yerel sabit bit-op fallback. Ağdan derlenen kod yoktur. |
| Thread yaşam döngüsü | JAR `lib/thread.lua` | create, detach, status ve graceful stop. Oyun içi thread zamanlaması ayrıca test edilmelidir. |
| Foreground açılışı | Yerel JAR `etc/profile.lua`, `bin/sh.lua`, `home/.shrc` | Profil `.shrc` dosyasını etkileşimli kabukta çalıştırır. İşaretli blok + kalıcı launcher kullanılır; Ctrl+C sonrası aynı boot içinde tekrar açılmaz. |
| GPU | [Orijinal GPU dokümanı](https://ocdoc.cil.li/component:gpu) | bind/maxResolution/setResolution/setDepth/set; 1.8 VRAM/bitblt zorunlu değil. |
| Modem paket sınırı | [Kurulu 1.8.3 commit'indeki NetworkCard.scala](https://github.com/MightyPirates/OpenComputers/blob/274990f/src/main/scala/li/cil/oc/server/component/NetworkCard.scala) | `maxPacketSize` callback'i yok; kapasite `computer.getDeviceInfo()[modem.address].capacity` üzerinden okunur. Güncel wiki'deki callback bu sürüme varsayılmadı. |
| Component callback tipi | Yerel JAR `assets/opencomputers/lua/machine.lua`, `componentCallback.__call` | Proxy metotları çağrılabilir table olabilir. AE2/prob kontrolleri yalnızca `type == function` şartına bağlanmaz. Modem/GPU/AE2 testleri callable table ile yürütülür. |

## AE2 eski API

[OC AE2 dokümanı](https://ocdoc.cil.li/component:applied_energistics) açıkça AE2 rv6 ve OC 1.7.3 / Minecraft 1.12 dönemini tarif eder. [1.7.5 dönemi MC1.12 merge commit'i](https://github.com/MightyPirates/OpenComputers/blob/310db04d3379d884293c741f251cfc4343d27eae/src/main/scala/li/cil/oc/integration/appeng/NetworkControl.scala) ve [kurulu 1.8.3 JAR commit'i](https://github.com/MightyPirates/OpenComputers/blob/274990f/src/main/scala/li/cil/oc/integration/appeng/NetworkControl.scala) karşılaştırıldı. Düz `v1.7.5` etiketi MC1.7.10 kaynaklarını içerdiğinden 1.12 doğrulaması için tek başına kullanılmadı.

- Adapter'a komşu ME Interface/Controller bileşeninden `getItemsInNetwork()`, `getCpus()` ve ağ enerji metotları çağrılır. Metodun bulunması başarılı bağlantı sayılmaz; gerçek çağrı ve dönüş tipi kontrol edilir.
- `getCpus()` alanları `name`, `storage`, `coprocessors`, `busy` şeklindedir. Bu bilgiler mevcut crafting işinin ürünü/miktarı değildir.
- `getCraftables(filter)` Craftable userdata döndürür; `getItemStack()` ve `request(amount, prioritizePower, cpuName)` bunun üzerindedir. FactoryOS v0.1 bunları otomasyon için çağırmaz.
- `request()` sonucu bir job/status userdata'sıdır. `isDone()` / `isCanceled()` henüz hesaplanırken `false, "computing"` döndürebilir; kaynak eksikliği/status hatası sonraki dönüşlerde belli olabilir. Yalnızca userdata dönmesi gerçek üretim başarısı değildir.
- `getCraftingJobs`, Craftable üzerinde genel `craft`, job üzerinde modern `status` gibi yeni/varsayımsal metotlar kullanılmaz.
- NBT ayrımı her ortamda ham NBT/hash olarak sunulmaz. Kod `name`, `damage`, `hasTag` ve varsa string tag/hash'i ayrı tutar; varyantları birleştirmez. Hash yoksa `identityComplete=false` işaretler. Bu kimliklerle otomatik üretim açılmaz. Uzun etiket/tag özetleri sınırlanır; bunlar kalıcı üretim anahtarı sayılmaz.
- `getStoredPower`, `getMaxStoredPower`, `getAvgPowerInjection`, `getAvgPowerUsage` ağ değerleri **AE**, akışlar **AE/t** olarak gösterilir. Bunlar RF/FE'ye çevrilmez. Controller'a özgü yan enerji metotlarıyla karıştırılmaz.

## Henüz doğrulanmayan sürücüler

Mekanism makineleri için tek tip OC component/metot varlığı varsayılmadı. Metallurgic Infuser vb. arayüzde çalışıyor gösterilmez. Extreme Reactors, NuclearCraft, Draconic ve RF/FE desteği bu teslimatta uygulanmaz. Gerçek cihazda `tools/ingame_probe.lua` ile komponent/metot envanteri alınmalı; her driver bağımsız olarak test edilmelidir.

## Diğer birincil kaynaklar

- [OpenOS event](https://ocdoc.cil.li/api:event)
- [OpenOS thread](https://ocdoc.cil.li/api:thread)
- [OpenOS filesystem](https://ocdoc.cil.li/api:filesystem)
- [Dosya sistemi component ve close](https://ocdoc.cil.li/component:filesystem)
- [Internet component](https://ocdoc.cil.li/component:internet)
- [Serialization](https://ocdoc.cil.li/api:serialization) — unserialize kaynakta `load` kullanabildiği için ağ parser'ı olarak seçilmedi.

Web dokümanları zaman içinde güncellenebildiği için kritik OpenOS davranışları ayrıca **yerel JAR kaynaklarıyla** karşılaştırılmıştır. Bu çalışma gerçek Minecraft kabul testlerinin yerine geçmez.

Kullanıcı v0.1.1 sunucu kurulumunun tamamlandığını bildirdi; foreground başlangıcında `maxPacketSize` hatası ekran görüntüsüyle görüldü. v0.1.2 bu hatayı yukarıdaki 1.8.3 kaynaklarına göre düzeltir; kullanıcı sunucu açılışını ve iki ekranın bağlandığını doğruladı. v0.2.0'ın yeni ana ekranı mock GPU çıktısıyla kontrol edildi; yeni yerleşimin ve gerçek AE2 verilerinin oyun içi kabulü bekleniyor.

v0.3.0'da otomatik başlangıç ve iki istemcinin kablosuz güncellenmesi gerçek Lua/modem mock'larında sınandı. OpenOS thread ve bilgisayar reboot davranışının gerçek dünyadaki kabulü henüz yapılmadı.
