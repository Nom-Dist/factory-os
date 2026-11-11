# Kurulum, güncelleme ve kurtarma

## GitHub deposu ve paketler

Projenin GitHub adresi [Nom-Dist/factory-os](https://github.com/Nom-Dist/factory-os). Kaynaklar, manifest ve tek dosyalı çevrimdışı installer depoda tutulur. Yerel `tools/build.py` ayrıca tam teslimat ZIP'ini üretir; bu üretilen ZIP Git'e eklenmez.

En hızlı yol `dist/factoryos-offline.lua` dosyasını OpenOS HDD/disketine koymaktır. Bu dosya tüm kaynakları ve hash manifestini taşır; Internet Card gerektirmez. Kapasiteyi kontrol edin; tek dosya yaklaşık 120 KB'dir. Mevcut dosya boyutunu host bilgisayarda doğrulayın. Küçük disketlerde yer yetmezse HDD aktarımı veya aşağıdaki HTTPS yolu kullanılmalıdır.

## Çevrimdışı tek dosya

OpenOS kabuğunda dosyanın bulunduğu klasöre geçin:

```sh
./factoryos-offline.lua
```

Rol seçimi 1=server, 2=main, 3=side. Installer bütün rollerin kaynaklarını kurar ve seçilen rolü config'e kaydeder. **Şifre/ortak anahtar gerekmez.** Sorular her girişten sonra yeni satıra geçer. Bilgisayar başına tek GPU/ekran kullanın veya aday listesinden doğru adresi seçin.

Installer donanımı denetler, dosya boyutu/SHA256 doğrular, staging sürümünü hazırlar, config'i yedekli yazar, `factoryos` komutunu kurar ve aktif sürüm pointer'ını en son değiştirir. Ağ keşfinin başarılı olduğunu iddia etmez; sunucu ve istemcileri başlattıktan sonra kabul testini uygulayın.

## Kaynak ağacından çevrimdışı kurulum

ZIP'ten açılan `FactoryOS` klasörünü OpenOS tarafından görülen bir diske kopyalayın. Klasörde `install.lua`, `manifest.dat` ve `src/` birlikte bulunmalıdır. Örnek disk bağlama yolu `/mnt/abc/FactoryOS` ise:

```sh
cd /mnt/abc/FactoryOS
./install.lua --local /mnt/abc/FactoryOS
```

`abc` gerçek diskinizin bağlama adıdır. Bütün paket standart küçük diskete sığmayabilir; HDD kullanabilirsiniz.

## GitHub üzerinden çevrimiçi kurulum

Depo kökünde `install.lua`, `manifest.dat` ve `src/` birlikte bulunur. `tools/build.py` çalıştırmadan kaynak değiştirmeyin; manifest hash'leri uyuşmaz. Güncel ana daldan kurulum:

```sh
wget https://raw.githubusercontent.com/Nom-Dist/factory-os/main/install.lua install.lua
./install.lua https://raw.githubusercontent.com/Nom-Dist/factory-os/main
```

`./install.lua` biçimini koruyun. OpenOS'un `/bin/install.lua` adında kendi programı vardır; yalnızca `install.lua` yazmak indirdiğiniz dosya yerine onu çalıştırabilir. `Nothing to install labeled: https://...` görürseniz dosya indirilmiştir fakat yanlış program açılmıştır. `/home` içine indirdiyseniz tekrar indirmeden şu komutla devam edin:

```sh
/home/install.lua https://raw.githubusercontent.com/Nom-Dist/factory-os/main
```

`wget` tekrarında `file already exists` mesajı, önceki dosyanın hâlâ bulunduğunu gösterir; bu durumda yukarıdaki çalıştırma komutunu kullanın.

Sabit sürüm kurulumu için iki URL'de de `main` yerine aynı gerçek commit SHA'sını kullanın. Varsayılan kaynak gömülü değildir; URL parametresi verilmezse installer HTTPS adresini sorar. Dal adresi kullanılırken eşzamanlı yayımlama sırasında hash kontrolü kurulumu güvenle durdurabilir.

İstemcilerde ilk yükleme için geçici Internet Card takılabilir; çalışma sırasında çıkarılabilir. Sunucu bu sürümde istemcilere yazılım dağıtmaz.

## İlk eşleştirme

Üç cihazda `components` komutunu çalıştırıp modem adreslerini not alın. Sunucuda:

```sh
factoryos config allow ANA_MODEM_ADRESI main
factoryos config allow YAN_MODEM_ADRESI side
```

İstemcide sunucu modem adresini sabitlemek önerilir:

```sh
factoryos config serverAddress SUNUCU_MODEM_ADRESI
```

Boş bırakılırsa sunucu otomatik keşfedilir. Sunucu izin listesi boşsa istemciler kaydedilmez. Yanlış modem adresiyle bağlantı kurulmaz ve ekranda OFFLINE kalır. Ortak anahtar veya mesaj imzası kontrolü yoktur.

## Çalıştırma ve ayarlar

Ekran makineleri:

```sh
factoryos start --foreground
```

Ctrl+C ile durdurun. Sunucu konsolundan komut kullanmak için:

```sh
factoryos start
factoryos status
factoryos logs
factoryos stop
```

Arka planda kabuk ve panel aynı ekranı paylaşır. Komut çıktısı paneli bozabilir; ekran bilgisayarlarında foreground önerilir. `restart` arka plan servisini yeniden başlatır. `doctor` yerel donanım denetimidir, uçtan uca ağ testi değildir. Otomatik boot servisi bu sürümde kurulmaz.

```sh
factoryos stop
factoryos config poll 15
factoryos config ae2Address AE2_BILESEN_ADRESI
factoryos config ae2Enabled true
```

Config dosyası veri formatıdır, Lua dosyası değildir; `edit` ile rastgele değiştirmek yerine CLI kullanın. `config` komutu ayarları gösterir. v0.1.0 ayarları okunurken şema v2'ye geçirilir; eski ortak anahtar bellekte kaldırılır ve sonraki kayıtta yeni config'e yazılmaz. Eski yedek dosyalar korunur.

## Güncelleme

v0.2.0 ana ekranını kullanmak için **önce sunucuyu, sonra ana ekranı** aşağıdaki komutlarla güncelleyin. Foreground panel açıksa Ctrl+C ile kabuğa dönün. Ana ekranda indirme sırasında geçici Internet Card gerekir; kurulumdan sonra çıkarılabilir. Yan ekranın yerleşimi aynı kalır ve eski protokol v2 sürümüyle çalışabilir. Modem adreslerini/izinlerini yeniden girmeniz gerekmez.

v0.1.1 sunucusu açılışta `maxPacketSize` hatası verdiyse istemci adreslerini doldurmanız gerekmez; v0.1.2'ye geçin. Hata sonrası servis durmuş olduğundan aşağıdaki güncelleme akışı kullanılabilir. Sunucu ayarları korunur. v0.1.1 ve v0.1.2 aynı ağ protokolündedir.

Çalışan servis varken güncelleme/geri dönüş reddedilir. v0.1 üretim/reaktör komutu vermediği için aktif otomasyon işi yoktur. İleri sürümlerde bu kilide kalıcı iş günlüğü ve idle doğrulaması eklenmeden üretim sırasında güncelleme açılmamalıdır.

```sh
factoryos stop
factoryos update https://raw.githubusercontent.com/Nom-Dist/factory-os/main
reboot
factoryos start --foreground
```

Sabit bir güncelleme için `main` yerine hedef commit SHA'sını kullanın. İlk online kurulumun URL'si config'te saklanır; `factoryos update` parametresiz o adresi kullanır. Sabit commit kullanılmışsa yeni sürüm için yeni commit adresi girin veya durduktan sonra `updateBase` ayarlayın.

İndirme/HTTP/SHA256 hatası aktif pointer'ı değiştirmez. Eski sürüm korunur. Config güncelleme tarafından değiştirilmez. Başarısız staging dizinleri inceleme için kalabilir; depolama alanını kontrol edin. SHA256 bozulmayı yakalar; manifest de aynı HTTPS kaynaktan gelir ve bağımsız sürüm imzası değildir. Yalnızca güvendiğiniz depoyu kullanın.

Çevrimdışı yeni sürüme geçmek için yeni `factoryos-offline.lua` dosyasını aktarın, servisi durdurun, aynı rolü tekrar kurun. Var olan rol/modem/ekran ayarları korunur; installer adres alanlarını yeniden sorabilir. **v0.1.1 protokol v2 kullanır; üç bilgisayarı da aynı sürüme geçirin.** Eski installer dosyası kendiliğinden güncellenmez; yeni dosyayı indirmeniz gerekir.

## Yeni ana ekranı kullanma

- `AE2 DEPOSU` veya `DEPO`: `ARA` düğmesi dokunmatik klavyeyi açar. Harflere dokunun, ardından `ARA`; fiziksel klavyede Enter da sorguyu onaylar. Esc veya `IPTAL` önceki sorguyu korur. Pano metni yalnızca arama alanına eklenir.
- `TUM / TARIFLI / FAVORILER` sunucuda tüm envanteri filtreler. `AD A-Z / MIKTAR` tüm sonuç kümesini sıralar; yalnızca görünen sayfayı sıralamaz.
- Satırdaki `+` favoriye ekler, `*` kaldırır. En fazla 32 favori `/etc/factoryos/display.dat` dosyasında bu ekran için saklanır. `?`, NBT kimliğinin favori için belirsiz olduğunu gösterir.
- Ürün satırına dokununca geniş ekranda sağ sütunda miktar, kimlik, metadata ve tarif bilgisi görünür. `ONCE / SONRA`, düşük çözünürlükte önce aynı sayfanın kalan satırlarına sonra sonraki 24'lük ağ sayfasına geçer.
- Ana paneldeki CPU sayıları yalnızca gerçek CPU verisi geldiyse gösterilir. Sunucu/AE2 bağlantısı yokken eski miktarlar güncel olarak çizilmez.
- `STOK HEDEFLERI`, makine sürücüleri ve crafting başlatma sonraki aşamadır. Bu sürüm yalnızca izler.

## Geri dönüş ve config kurtarma

```sh
factoryos stop
factoryos rollback
reboot
factoryos start --foreground
```

Önceki sürümün manifesti ve bütün dosyaları tekrar doğrulanır. Önceki sürüm yoksa açıklayıcı hata verilir. Aktif pointer yenilenirken güç kesilip `active` kaybolursa launcher `active.bak` dosyasını kullanır. Donanım/dosya sistemi atomikliği gerçek ortamda henüz test edilmedi.

Config okunamazsa geçerli `config.dat.bak` belleğe alınır, bozuk özgün dosya korunur ve uyarı loglanır. İkisi de bozuksa servis güvenle durur; installer'ı yeniden çalıştırın veya sağlam yedeği geri koyun.
