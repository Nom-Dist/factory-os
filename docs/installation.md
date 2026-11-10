# Kurulum, güncelleme ve kurtarma

## GitHub deposu ve paketler

Projenin GitHub adresi [Nom-Dist/factory-os](https://github.com/Nom-Dist/factory-os). Kaynaklar, manifest ve tek dosyalı çevrimdışı installer depoda tutulur. Yerel `tools/build.py` ayrıca tam teslimat ZIP'ini üretir; bu üretilen ZIP Git'e eklenmez.

En hızlı yol `dist/factoryos-offline.lua` dosyasını OpenOS HDD/disketine koymaktır. Bu dosya tüm kaynakları ve hash manifestini taşır; Internet Card gerektirmez. Kapasiteyi kontrol edin; tek dosya yaklaşık 90 KB'dir. Mevcut dosya boyutunu host bilgisayarda doğrulayın. Küçük disketlerde yer yetmezse HDD aktarımı veya aşağıdaki HTTPS yolu kullanılmalıdır.

## Çevrimdışı tek dosya

OpenOS kabuğunda dosyanın bulunduğu klasöre geçin:

```sh
./factoryos-offline.lua
```

Rol seçimi 1=server, 2=main, 3=side. Installer bütün rollerin kaynaklarını kurar ve seçilen rolü config'e kaydeder. Ortak anahtarı üç makinede aynı girin. Bilgisayar başına tek GPU/ekran kullanın veya aday listesinden doğru adresi seçin.

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

Boş bırakılırsa aynı anahtarla doğrulanan sunucu keşfedilir. Sunucu izin listesi boşsa istemcileri otomatik güvenilir saymaz. Yanlış anahtar/adres ile bağlantı kurulmaz ve ekranda OFFLINE kalır.

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
factoryos config key
```

Anahtar `config key` ile maskeli olarak sorulur; komut satırına yazılması gerekmez. Değiştirilirse üç cihazda aynı değeri ayarlayın. Config dosyası veri formatıdır, Lua dosyası değildir; `edit` ile rastgele değiştirmek yerine CLI kullanın. `config` komutu anahtarı gizleyerek ayarları gösterir. Ham config dosyasını paylaşmayın; paylaşılan anahtar içerir.

## Güncelleme

Çalışan servis varken güncelleme/geri dönüş reddedilir. v0.1 üretim/reaktör komutu vermediği için aktif otomasyon işi yoktur. İleri sürümlerde bu kilide kalıcı iş günlüğü ve idle doğrulaması eklenmeden üretim sırasında güncelleme açılmamalıdır.

```sh
factoryos stop
factoryos update https://raw.githubusercontent.com/Nom-Dist/factory-os/main
reboot
factoryos start --foreground
```

Sabit bir güncelleme için `main` yerine hedef commit SHA'sını kullanın. İlk online kurulumun URL'si config'te saklanır; `factoryos update` parametresiz o adresi kullanır. Sabit commit kullanılmışsa yeni sürüm için yeni commit adresi girin veya durduktan sonra `updateBase` ayarlayın.

İndirme/HTTP/SHA256 hatası aktif pointer'ı değiştirmez. Eski sürüm korunur. Config güncelleme tarafından değiştirilmez. Başarısız staging dizinleri inceleme için kalabilir; depolama alanını kontrol edin. SHA256 bozulmayı yakalar; manifest de aynı HTTPS kaynaktan gelir ve bağımsız sürüm imzası değildir. Yalnızca güvendiğiniz depoyu kullanın.

Çevrimdışı yeni sürüme geçmek için yeni `factoryos-offline.lua` dosyasını aktarın, servisi durdurun, aynı rolü tekrar kurun. Var olan config ve anahtar korunur; installer adres alanlarını yeniden sorabilir.

## Geri dönüş ve config kurtarma

```sh
factoryos stop
factoryos rollback
reboot
factoryos start --foreground
```

Önceki sürümün manifesti ve bütün dosyaları tekrar doğrulanır. Önceki sürüm yoksa açıklayıcı hata verilir. Aktif pointer yenilenirken güç kesilip `active` kaybolursa launcher `active.bak` dosyasını kullanır. Donanım/dosya sistemi atomikliği gerçek ortamda henüz test edilmedi.

Config okunamazsa geçerli `config.dat.bak` belleğe alınır, bozuk özgün dosya korunur ve uyarı loglanır. İkisi de bozuksa servis güvenle durur; installer'ı yeniden çalıştırın veya sağlam yedeği geri koyun. Yeniden kurulumda yeni anahtar tanımlamanız gerekirse tüm düğümlerde eşitleyin.
