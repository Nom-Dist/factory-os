# Minimum/hedef stok — v0.5.0

Bu özellik sunucuda çalışır; ana ekran bağlantısı kesilse de açık kurallar devam eder. Sunucu ve ana ekranın v0.5.0 olması gerekir. Yan ekran kural yönetemez. Kod ve paket yerelde hazırdır; gerçek Minecraft kabulü henüz yapılmadı.

## Kural oluşturma

1. **AE2 DEPOSU → TARIFLI** filtresinde ürünü seçin.
2. Depo başlığındaki **STOK HEDEFI** düğmesine dokunun.
3. **MIN** ve **HEDEF** alanlarını seçip sayısal tuşlarla değer girin. Fiziksel klavye, pano, Backspace ve Enter desteklenir; Tab iki alan arasında geçer. `1 <= minimum <= hedef <= 1.000.000` olmalıdır.
4. **KAYDET** ile kuralı kaydedin. Yeni veya düzenlenmiş kural **kapalıdır**.
5. **STOK HEDEFLERI** sayfasındaki **KAPALI: AC** düğmesiyle etkinleştirin. Örneğin minimum 64, hedef 256 ve stok 63 ise 193 adetlik bir emir verilir. Stok tam 64 iken emir verilmez.

En fazla 16 ürün/varyant için kural kaydedilir; aynı varyanta ikinci kural eklenmez. Kurallar sunucuda ortaktır; izin listesindeki bütün ana ekranlar yönetebilir. Değişikliklerde kalıcı kural revizyonu denetlenir. Eski revizyonla gelen istek yeniden uygulanmaz; liste yenilenmelidir.

**ACIK: KAPAT** yalnızca sonraki otomatik emirleri durdurur. **TUMUNU BEKLET** bütün kuralları duraklatır, **DEVAM ET** yeniden açar. Bu işlemler mevcut AE2 işini iptal etmez. Silme yalnızca ilgili ürünün aktif/belirsiz işi yokken yapılır. Küçük ekranlarda silme düğmesi **DUZENLE → KURALI SIL** içindedir.

## İşler, bekleme ve sınırlar

Sunucu her başarılı AE2 envanter yenilemesinden sonra kuralları değerlendirir; varsayılan yenileme 10 saniyedir. Açılış/etkinleştirme sonrası en az 30 saniye beklenir. Yeni otomatik denemeler arasında en az 30 saniye vardır; düşük stoklu kurallar sırayla değerlendirilir.

İlk sürüm otomatik işleri sırayla yürütür. Herhangi bir FactoryOS işi aktif/belirsizken veya gözlenen CPU'lardan biri meşgulken yeni otomatik emir vermez. Böylece devam eden üretim varken hedef farkı tekrar sipariş edilmez. Ekrandaki **Emir** değeri takip edilen işlerin başlangıç miktarlarının toplamıdır; kalan miktar veya ilerleme ölçümü değildir. Başka uygulamalardan başlatılan işlerin ürün/miktarı API'den okunamaz; dolu CPU sırasında otomasyon bekler.

İş tamamlanınca sonraki envanter revizyonu ve en az 30 saniye beklenir. Karar yeniden gerçek stok üzerinden verilir. Hedef, stoğa sert bir üst sınır koymaz: tarif çıktı katları, dış üretim ve eşzamanlı tüketim son miktarı etkileyebilir.

Planlama hatasında sürücünün gerçek mesajı gösterilir. Yeniden denemeler sırasıyla en az 60, 120, 240, 480 ve 900 saniye bekler; sonra 900 saniyede kalır. Kesin eksik malzeme listesi tahmin edilmez. Bekleme süreleri çalışma oturumuna aittir; reboot sonrası başlangıç beklemesi uygulanır. AE2 bağlantı/CPU bilgisi yoksa, 2000 varyant sınırı nedeniyle envanter kesilmişse veya kurala bağlı AE2 bileşeni değişmişse üretim bekler. Bileşen değişiminde kuralı silip doğru ağda yeniden oluşturun.

## Disk, reboot ve iptal

Kurallar, revizyon, monoton kural kimliği ve duraklatma durumu üretim emirleriyle aynı `/var/lib/factoryos/crafting.dat` journal'ında saklanır. Otomasyon `@factoryos-stock` kayıt sahibini kullanır; bu, mevcut 16 kayıt sahibi sınırında bir yer kullanır. Ayrı bir native üretim yolu yoktur: tam tarif/varyant/CPU yeniden doğrulanır, emir **request() çağrısından önce** flush/rename denetimiyle diske yazılır. Bozuk/eksik journal veya disk yazma hatası yeni emirleri engeller; eski `.bak` otomatik kullanılmaz.

Sunucu reboot sonrası devam eden iş **DURUMU BILINMIYOR** olur. Yanıtı kaybolan veya durumu belirsizleşen iş otomatik tekrar gönderilmez; diğer otomasyon da bekler. **URETIM** sayfasında gerçek işi ME Terminal'de kontrol ettikten sonra **ME'DE BAKTIM** ile yalnızca takibi arşivleyin. Otomatik iş arşivlenirken ilgili kural önce kalıcı olarak kapatılır; devam etmek için ayrıca yeniden açın.

Otomatik bir işte **IPTAL ET** de önce ilgili kuralı kapatır, sonra iptali dener. API hesaplama sırasında iptali reddetse bile kural kapalı kalır. İzin listesindeki her ana ekran otomatik işi iptal/arşivleyebilir; elle verilen işlerin sahiplik kuralı korunur. Güncelleme worker'ı çalışırken yeni kural değişikliği ve otomatik üretim başlamaz; aktif/belirsiz işler güncellemeyi engeller.

## Gerçek Minecraft kabulü — bekliyor

Önce [elle bir adet üretimin kabulünü](crafting.md) tamamlayın. Sonra ucuz, tek çıktı veren ve malzemesi yeterli bir tarifte küçük minimum/hedef değerleriyle:

1. Kuralı kaydedip kapalıyken üretim başlamadığını gözleyin; ardından açın.
2. Minimumun üstünde/tam minimumda beklediğini, altına indiğinde hedef farkını **bir kez** sipariş ettiğini hem URETIM sayfasında hem ME Terminal'de doğrulayın.
3. İş hesaplanırken/çalışırken ikinci otomatik emir çıkmadığını ve tamamlanınca gerçek stoğun tekrar okunduğunu doğrulayın.
4. Eksik kaynak, dolu CPU, tümünü beklet/devam, iptal ve düzenleme sonrası kapalı kalma davranışlarını gözleyin.
5. Aktif işte server reboot yaparak belirsiz kaydın yeniden gönderilmediğini, ME kontrolünden sonra arşivlemenin kuralı kapattığını doğrulayın. Ekranın bağlantı kaybını ayrıca deneyin.

Host regresyonları bu oyun adımlarının yerine geçmez. [Örnek veriyle ekran önizlemesi](previews/main-stock-rules.png) ve [kural düzenleme](previews/main-stock-rule-editor.png) gerçek Minecraft görüntüsü değildir.
