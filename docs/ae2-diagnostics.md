# AE2 bağlantı tanılaması

ME Terminal çalışırken yalnızca FactoryOS OFFLINE oluyorsa bu tek başına ME ağının kapandığını kanıtlamaz. Adapter bileşeninin kaybolması, birden fazla ME bileşeninin görünmesi veya bir API çağrısının hata vermesi ayrı ayrı araştırılmalıdır. v0.3.1 hata metnini, çağrılan metodu ve seçilen adresi korur; durum/hata/adres değişince loga yazar. Aynı hatayı her turda tekrar yazmaz.

## `not enough memory`

Kullanıcı ME Terminal açık kalırken FactoryOS'ta bu hatayı gördüğünü bildirdi. Bu, bilgisayardaki Lua bellek yetersizliğidir; tek başına gerçek ME ağının kapandığı anlamına gelmez. v0.3.2 eski snapshot'ı sürücü çağrısından önce bırakır; dönen satırları yerinde dönüştürür, kullanılmayan alanları ve 2000 sınırını aşan satırları bırakır. OpenComputers sandbox'ında `collectgarbage` dışarı sunulmadığından bu global metoda dayanmaz; OC allocator/GC mekanizmasını kullanır.

Legacy `getItemsInNetwork()` API'si Lua'ya yine bütün envanteri tek seferde aktarır; 2000 satır sınırı bu ilk tahsisin boyutunu kısıtlamaz. Çok büyük AE2 ağları için sunucu bilgisayarına daha yüksek RAM modülleri takmak hâlâ gerekebilir. İstemci ekran RAM'ini artırmak sunucudaki bu okumayı düzeltmez. `factoryos ae2` her örnekte sunucunun kullanılabilir/toplam RAM'ini KiB olarak gösterir. Yoklama aralığını artırmak yük sıklığını azaltır, tek çağrının RAM ihtiyacını azaltmaz.

Önce sunucuyu v0.3.2'ye güncelleyin. Ctrl+C ile foreground panelden çıkıp:

```sh
factoryos stop
factoryos update https://raw.githubusercontent.com/Nom-Dist/factory-os/main
factoryos ae2 12
```

Bu komut ilk örneği hemen, sonrakileri 10 saniye arayla alır; 12 örnek yaklaşık iki dakika sürer. Başlangıçta mevcut ME bileşenlerinin tam adreslerini, her örnekte ONLINE/OFFLINE, seçilen adres, destekleniyorsa `isNetworkPowered` ve hatalı metodu gösterir. Crafting başlatmaz, blok/kanal/enerji ayarı değiştirmez. Ctrl+C ile kesilebilir. Tek örnek için `factoryos ae2` kullanın. Sonrasında paneli açın:

```sh
factoryos start --foreground
```

Normal çalışmada kesinti olduktan sonra Ctrl+C ve `factoryos logs` ile geçmiş nedeni görebilirsiniz. Ana ekran ALARMLAR sayfası da AE2 hata metnini gösterir; yalnızca bu sunucu tanılaması için ekranları güncellemek gerekmez.

| Çıktı | İncelenecek durum |
| --- | --- |
| `Multiple AE2 components; set ae2Address` | Aynı OC ağı birden fazla ME bileşeni görüyor. İstenen ME ağına ait tam adresi listeden seçin; otomatik rastgele seçim yapılmaz. |
| `AE2 Adapter component missing/offline` | Adapter/ME komşuluğu, OC kablosu, bileşen ve chunk erişimi; sabitlenmiş adresin hâlâ listede bulunması. |
| `AE2 network unpowered (isNetworkPowered=false)` | Adapter'ın gördüğü ME ağının sürücüsü enerjisiz bildiriyor. Terminalin ve Adapter'ın aynı ME ağına bağlı olup olmadığını ve o ağın enerjisini kontrol edin. |
| `getItemsInNetwork: ...` | Sürücünün gerçek hata metni. `no ae grid` vb. yanıtı genel OFFLINE metniyle değiştirilmez. Hata metniyle birlikte bileşen türü/adresi gereklidir. |
| `unsupported: isNetworkPowered` | Bu sürücü güç sorgusunu sunmuyor; tek başına envanteri OFFLINE yapmaz. |
| `unsupported: getCpus` veya enerji metodu hatası | İlgili ek veri kullanılamaz; başarılı envanter okumasını OFFLINE yapmaz. |

Birden fazla bileşen varsa sunucu durmuşken, listede görünen **ME bileşeni adresini** kullanın; modem adresini kullanmayın:

```sh
factoryos config ae2Address ME_BILESENININ_TAM_ADRESI
factoryos ae2
factoryos start --foreground
```

Yazılım her normal yoklamada tekrar keşif/okuma yapar. Başarısız stok okumasında eski miktarlar canlı olarak gösterilmez; sonraki başarılı yoklamada bağlantı geri gelir. Bu değişiklik tanılama sağlar; kullanıcı ortamındaki kesintinin nedeni çıktı alınmadan kesinleştirilmiş değildir.
