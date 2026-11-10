# Donanım ve kablolama

| Bilgisayar | Ekran | GPU hedefi | Diğer bileşenler |
|---|---|---|---|
| Factory Server | 1×1 konsol | Tier 1 yeterli (en az 40×12 karakter) | Tier 3 kasa/CPU, yüksek RAM, HDD, OpenOS EEPROM, Wireless Network Card Tier 2, Internet Card, AE2 Adapter |
| Main Display | 8×5 multiblock | Tier 3; en fazla 160×50 karakter | Kasa, CPU/RAM, HDD, OpenOS EEPROM, Wireless Network Card Tier 2 |
| Side Display | 4×5 multiblock | Tier 2; en fazla 80×25 karakter | Kasa, CPU/RAM, HDD, OpenOS EEPROM, Wireless Network Card Tier 2 |

Duvar 8 blok ana ekran + 1 dekoratif boşluk + 4 blok yan ekran düzenindedir. Ekran bloklarının fiziksel oranı karakter çözünürlüğü değildir. Kod, bağlanan GPU ve ekranın ortak `maxResolution()` sonucunu kullanır. Daha düşük GPU'larda ana menü sıkışık sayfa düğmelerine dönüşür; tüm roller 40×12–160×50 sınırlarında mock ile çizildi. Gerçek ekran tier'ı da çözünürlüğü sınırlayabilir.

Her bilgisayarda **bir GPU ve bir ekran** önerilir. Daha fazla aday varsa yazılım rastgele seçmez; installer adres sorar. Sonradan seçim:

```sh
factoryos stop
factoryos doctor
factoryos config gpu GPU_TAM_ADRESI
factoryos config screen EKRAN_TAM_ADRESI
factoryos config modem MODEM_TAM_ADRESI
factoryos start --foreground
```

Büyük ekranları bilgisayarlar arasında OC kablosuyla ortak bileşen ağına bağlamayın. İstemciler, sunucuyla yalnızca kablosuz modem mesajlarıyla konuşur. Ağ/ekran adresleri farklı kimliklerdir; izin listesine `modem` adresini girin.

Sunucudaki Adapter'ı tercihen AE2 ME Interface'e komşu yerleştirin; OC yerel kablosuyla sunucuya bağlayın. Driver `me_interface` veya `me_controller` gibi bir bileşen sunmalıdır. AE2 ağının enerjisi/kanalı/güvenlik yetkileri hazır olmalıdır. Birden fazla AE2 bileşeni görünüyorsa `factoryos config ae2Address TAM_ADRES` ile seçin; sadece `adapter` metotları beklenmez.

İlk kurulum için istemcilere geçici Internet Card takılabilir veya HDD/disket içeriği aktarılabilir. Günlük çalışmada Internet Card gerekmez. Sunucunun çevrimiçi güncellemeleri için kendi Internet Card'ı bulunmalıdır; v0.1 istemcilere kablosuz dosya dağıtmaz.

Varsayılan wireless strength 64'tür; kart/modpack ayarları gerçek mesafeyi sınırlayabilir. Aynı boyut, yüklü chunk'lar ve yeterli OC enerjisiyle başlayın. Güç artırmak:

```sh
factoryos stop
factoryos config strength 128
factoryos start --foreground
```

Kart gerçek üst sınıra değeri sıkıştırabilir. Bilgisayar veya chunk kapanırsa yazılım mesaj alamaz; istemcilerin OFFLINE göstergesi bu koşulları da kapsar.
