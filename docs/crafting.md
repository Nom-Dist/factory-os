# AE2 üretim emirleri — v0.5.0

Önce sunucuyu, ardından ana ekranı v0.5.0'a güncelleyin. [Otomatik stok kuralları](stock-automation.md) bu sürümde ayrıca eklenmiştir. Güncelleme menüsünde F5 ile kontrol, yeni sürüm yayımlanmışsa F6 ile yükleme yapılabilir. CLI alternatifi: Ctrl+C ile panelden çıkın ve her iki bilgisayarda sırasıyla çalıştırın:

```sh
factoryos stop
factoryos update https://raw.githubusercontent.com/Nom-Dist/factory-os/main
reboot
```

CLI doğrudan indirmesi Internet Card gerektirir. Menüyle ana ekran sunucudan kablosuz güncellenebilir. Yan ekran bu özellik için güncellenmek zorunda değildir; komut veremez. Modem izinleri ve mevcut ayarlar korunur.

## Kullanım

1. Ana ekranda **AE2 DEPOSU → TARIFLI** filtresini açın, ürün satırını seçin.
2. Sağ sütunda **URETIM EMRI VER** düğmesine dokunun. Sağ sütunu olmayan ekranlarda depo başlığındaki **URET** düğmesini kullanın.
3. `1 / 8 / 16 / 64` kısayolunu veya sayısal klavyeyi kullanın. Fiziksel klavye, Backspace, rakamlardan oluşan pano girişi ve Enter desteklenir. **TEMIZLE** alanı boşaltır. Miktar 1..1.000.000 arasında tam sayıdır; mevcut stoğu bu değere tamamlama hedefi değildir.
4. **CPU** düğmesi otomatik seçim ve boş, benzersiz isimli CPU'lar arasında dolaşır. Sunucu üretim anında CPU'yu tekrar kontrol eder. İsimsiz, uzun/kontrol karakterli veya aynı isimli CPU'lar otomatik seçimle kullanılabilir; bu isimler değiştirilip yanlış CPU'ya gönderilmez.
5. **64 ADET URET** gibi miktarı gösteren düğmeye dokunun. Emir kaydedilince **URETIM** sayfası açılır. Aktif iş yanında **IPTAL ET** vardır. Hesaplama sırasında API iptali kabul etmeyebilir; neden gösterilir.

Sadece AE2'ye pattern olarak tanıtılmış, tam eşya/varyant kimliği doğrulanabilen ürünler üretilebilir. NBT varlığı biliniyor fakat tag/hash okunamıyorsa üretim reddedilir. Uzun kimlikler kesilip eşleştirilmez. Sunucu `getCraftables({name,damage})`, `getItemStack()` ve tam kimlik karşılaştırmasıyla seçimi yeniden doğrular; bütün tarifleri her heartbeat'te indirmez. Bir filtrede 64'ten fazla tarif varyantı varsa seçim reddedilir; en fazla 32 CPU listelenir. Stok listesi hâlâ 2000 varyantlık RAM sınırına tabidir.

## Gerçek durumlar

| Ekran | Anlam |
| --- | --- |
| HESAPLANIYOR | API job nesnesi verdi, plan hâlâ hesaplanıyor; üretimin başladığı ilan edilmez. |
| CALISIYOR | Job sorguları henüz tamamlanma veya iptal bildirmiyor. Bu durum ilerleme yüzdesi vermez. |
| TAMAMLANDI | Job `isDone()` ile tamamlandığını bildirdi. |
| IPTAL BEKLENIYOR / IPTAL EDILDI | Önce iptal çağrısı kabul edildi; ardından job iptal durumunu doğruladı. |
| HATA | Örneğin `request failed (missing resources?)` gibi sürücünün gerçek yanıtı. Ayrıntılı eksik malzeme listesi uydurulmaz. |
| DURUMU BILINMIYOR | Çağrı yanıtı kayıp, durum okunamıyor veya sunucu yeniden başlatılmış. İş yeniden gönderilmez. |
| ELLE ARSIVLENDI | Kullanıcı belirsiz işi ME Terminal'de kontrol edip **ME'DE BAKTIM** düğmesine bastı. Bu bir tamamlanma/iptal bildirimi değildir. |

Job durumları yaklaşık iki saniyede bir sorgulanır. Ana ekran ÜRETİM sayfasını iki saniyede, diğer sayfalardaki CPU özetini on saniyede bir yeniler. API atanan CPU'yu job üzerinden vermediği için otomatik seçimin CPU ismi tahmin edilmez. AE Terminal veya başka bir programdan başlatılmış işlerin ürün/miktarı bu listede görünmez.

## Bağlantı ve yeniden başlatma

Her modem için monoton emir numarası ve son 32 emir `/var/lib/factoryos/crafting.dat` içinde saklanır. En fazla 16 emir sahibi modem ve 8 aktif/belirsiz iş izlenir. Native `request()` çağrısından **önce** emir numarası ve `submitting` kaydı yazılıp flush/rename sonucu denetlenir. Ağdaki 60 saniyelik RPC cache'inden bağımsızdır. Geçmişten silinmiş eski emir numaraları da tekrar çalıştırılmaz. Yeni bir emir vermek yeni kullanıcı eylemidir; aynı ürüne ayrı yeni emir verilebilir.

Sunucu reboot sonrası eski live userdata'ya yeniden bağlanmaz. O sırada bitmemiş kayıtlar **DURUMU BILINMIYOR** olur; otomatik yeniden üretim yoktur. ME Terminal'de işi kontrol edin. Gerekirse oradan iptal edin; ardından **ME'DE BAKTIM** yalnızca FactoryOS takibini arşivler. Aktif/belirsiz işler menüden güncellemeyi engeller. Böylece hesaplama henüz CPU'yu meşgul göstermiyorken de güncelleme başlamaz.

Bozuk/eksik üretim kaydı için daha eski `.bak` otomatik açılmaz; eski emir numarası üretimi tekrarlatabilir. Disk yazma hatasında yeni emirler durur, mevcut işlerin gözlemi devam eder. Bu dosyaları silmek veya eski yedeğe döndürmek tekrar engelini bozabilir; önce gerçek AE2 işlerini kontrol ederek kaydı inceleyin.

## Doğrulama durumu

Native API, yerel OC 1.8.3 JAR'ının [274990f kaynak koduyla](https://github.com/MightyPirates/OpenComputers/blob/274990f/src/main/scala/li/cil/oc/integration/appeng/NetworkControl.scala) ve [OC AE2 dokümanıyla](https://ocdoc.cil.li/component:applied_energistics) karşılaştırıldı. Lua 5.2/5.3'te 75 senaryo ve 2 MiB stok okuma regresyonu geçti. Modem testi gerçek FactoryOS protokolüyle, 1024 bayt paket sınırı/yanıt kaybı/sunucu reboot koşullarında aynı emir için tek native çağrı doğrular. Örnek GPU çizimleri gerçek oyun görüntüsü değildir.

Minecraft'ta ilk kabul: çıktısı bir adet olan ucuz bir recipe'den bir adet isteyin; hem job sonucunu hem ME Terminal'deki gerçek stoğu kontrol edin. Ardından az miktarla eksik kaynak, CPU doluluğu ve iptal deneyin. Oyun içi kabul henüz yapılmadı.
