# Mikrofon Kilidi (MicrophonePicker)

macOS menü çubuğunda çalışan küçük bir uygulama. Bir mikrofon seçersiniz, sistem
varsayılan giriş cihazını ne yaparsa yapsın o mikrofonda kalır.

Kulaklık takıp çıkardığınızda, AirPods bağlandığında ya da bir uygulama kendi
kafasına göre girişi değiştirdiğinde uygulama devreye girip seçtiğiniz mikrofonu
geri getirir.

## Kurulum

```bash
./build.sh --install
```

`/Applications/MicrophonePicker.app` oluşturulur ve başlatılır. Menü çubuğunda bir
mikrofon simgesi görünür.

Kurmadan sadece derlemek için:

```bash
./build.sh
```

## Kullanım

Menü çubuğundaki simgeye tıklayın:

- **Giriş Cihazları** listesinden kilitlemek istediğiniz mikrofonu seçin. Seçtiğiniz
  anda hem sistem varsayılanı olur hem de kilitlenir.
- **Giriş Ayarları** bölümündeki kaydırıcı, kilitli mikrofonun giriş seviyesini
  gösterir. Kaydırıcıyı oynattığınız anda o değer **o cihaz için** kaydedilir ve
  kilitlenir; seviye düşerse otomatik geri çekilir. Kaldırmak için altındaki satıra
  tıklayın.
- **Susturulmasını engelle** işaretliyken, bir uygulama kilitli mikrofonu susturursa
  otomatik geri açılır. Bu ayar da cihaz başına saklanır. Susturma kontrolü sunmayan
  cihazlarda (RØDE PodMic USB bunlardan biri) seçenek pasif görünür.
- **Kilidi Kaldır** ile macOS'un normal (otomatik) davranışına dönersiniz.
- **Oturum Açılışında Başlat** ile Mac her açıldığında uygulama kendiliğinden çalışır.
- **Son işlem** satırı, en son ne zaman hangi cihazdan hangisine geri dönüldüğünü gösterir.

Simge durumu anlatır:

| Simge | Anlamı |
|---|---|
| `mic` (içi boş) | Kilit kapalı |
| `mic.fill` (dolu) | Kilit aktif, cihaz bağlı |
| `mic.slash.fill` (çizgili) | Kilitli cihaz şu an takılı değil, geri gelmesi bekleniyor |

## Nasıl çalışıyor

Seçim, cihaz kimliği (`AudioDeviceID`) yerine kalıcı **UID** olarak saklanır —
kimlikler her yeniden bağlanmada değişir, UID değişmez. Yani PodMic'i çıkarıp
tekrar taktığınızda kilit hâlâ geçerlidir.

Üç savunma hattı var:

1. **`kAudioHardwarePropertyDefaultInputDevice` dinleyicisi** — sistem varsayılanı
   değiştirir değiştirmez haber alınır ve anında geri alınır (ölçümde ~25–55 ms).
2. **`kAudioHardwarePropertyDevices` dinleyicisi** — kulaklık takılıp çıkarıldığında
   tetiklenir. macOS bazen cihaz listesini güncelledikten *birkaç yüz ms sonra*
   varsayılanı değiştirdiği için ardından 0,2 s ile 5 s arasında birkaç kez daha kontrol edilir.
3. **1 saniyelik nöbetçi zamanlayıcı** — hiçbir bildirim üretmeden varsayılanı
   değiştiren uygulamaları (Zoom, Teams vb.) yakalar.

Kilitli cihaz takılı değilse uygulama sisteme hiç karışmaz; cihaz geri geldiğinde
kendiliğinden devreye girer.

Uygulama başlarken **App Nap'ten çıkar** (`beginActivity`). Penceresiz menü çubuğu
uygulamaları App Nap'in birinci hedefi ve App Nap zamanlayıcıları birleştirip
dakikalarca geciktirebiliyor — bu düzeltme olmadan yukarıdaki 3. savunma hattı
sessizce çalışmıyor. Sistemin boşta uykuya geçmesine karışılmaz.

Boşta CPU kullanımı %0, bellek ~50 MB.

### Seviye ve susturma kilidi

Ayarlar **cihaz başına** saklanır (RØDE %90, dahili mikrofon %50, AirPods %70 —
hepsi ayrı). Ama zorlama **yalnızca o an kilitli olan mikrofona** uygulanır: diğer
cihazların değerleri hatırlanır, sistem onları kıssa ya da sustursa bile uygulama
karışmaz.

Kilitli cihaz `kAudioDevicePropertyVolumeScalar` ve `kAudioDevicePropertyMute`
üzerinden dinlenir. Bu dinleyiciler sistem nesnesine değil cihazın kendisine
bağlandığı için, cihaz her yeniden bağlandığında (`AudioDeviceID` değiştiğinde)
sökülüp yeniden takılır.

Her cihaz her kontrolü sunmaz — RØDE PodMic USB'de seviye kontrolü var ama
**susturma kontrolü hiç yok**; dahili mikrofonda ve diğer USB cihazda ikisi de var.
Kontrolü olmayan cihazlarda ilgili kilit sessizce devre dışı kalır, menüde sebebi yazar.

İki tasarım detayı önemli:

- **Kuantalama toleransı.** Donanım, yazdığınız değeri en yakın adıma yuvarlar —
  RØDE PodMic USB'de %90 yazıldığında cihaz %90.48'e oturuyor (22–63 dB aralığı ayrık
  adımlarla ilerliyor). Tam eşitlik karşılaştırması yapılsaydı uygulama her turda
  "eşit değil" deyip sonsuza kadar yazardı. Bunun yerine %1 tolerans kullanılıyor ve
  cihazın oturduğu gerçek değer hedef kabul ediliyor.
- **Savaş algılayıcı.** Zoom, Teams ve Discord'un otomatik mikrofon seviyesi (AGC)
  ayarı sistem kaydırıcısını gerçekten oynatır. Karşılıklı itişme, kayıtta duyulabilir
  seviye dalgalanmasına ve donanım gain'ine saniyede onlarca yazmaya yol açar.
  3 saniye içinde 5 düzeltme gerekirse kilit 30 saniye duraklatılır ve menüde sebebi
  yazar — çünkü kalıcı çözüm o uygulamanın kendi ayarında. Aynı mekanizma susturma
  için de geçerlidir; duraklatma ikisi arasında paylaşılır.

### Kim değiştirdi?

Her düzeltmede menüde şu satır belirir:

```
Son düzeltme: 14:32:07 · %50 → %90 · Wispr Flow
```

**CoreAudio, bir özelliği hangi işlemin değiştirdiğini söylemez** — böyle bir API yok.
Bunun yerine, düzeltmenin yapıldığı anda **mikrofondan kayıt yapan** uygulamalar
örneklenir (macOS 14.4+ Audio Process nesneleri). Seviyeyi oynatan uygulama neredeyse
her zaman aynı anda kayıt da yapıyor olduğu için pratikte doğru adı verir; yine de bir
çıkarımdır, o yüzden menüde "sürekli değiştiren" değil "mikrofonu kullanan" diye sunulur.

Hiçbir uygulama kayıt yapmıyorken seviye değişiyorsa bu da bilgidir — menüde
"mikrofonu kullanan uygulama yoktu" yazar ve sebep büyük ihtimalle bir sürücü ya da
sistem ayarıdır.

Yardımcı işlemler ana uygulamaya indirgenir: mikrofonu `com.google.Chrome.helper`
açar ama menüde "Google Chrome" görürsünüz.

## Bilinmesi gerekenler

- **Kilit açıkken Sistem Ayarları'ndan mikrofon değiştiremezsiniz** — uygulama geri
  alır. Zaten amaç bu. Değiştirmek istediğinizde menüden yeni cihazı seçin ya da
  önce kilidi kaldırın.
- **Sadece giriş cihazına dokunur.** Çıkış (hoparlör/kulaklık) hiç değişmez, yani
  AirPods'unuzdan dinlemeye devam edersiniz. Yan faydası: AirPods mikrofonu
  kullanılmadığı için Bluetooth bağlantısı düşük kaliteli HFP moduna geçmez,
  ses A2DP kalitesinde kalır.
- **Uygulama içi seçimler ayrı bir konu.** Zoom/Teams gibi programlarda mikrofon
  "Sistem Varsayılanı / Same as System" seçiliyse bu uygulamayı takip eder. Programın
  içinde elle "AirPods" seçtiyseniz, orayı da düzeltmeniz gerekir.
- **Mikrofon izni istemez.** Uygulama ses kaydetmez, yalnızca cihaz yönlendirmesini
  değiştirir; bu yüzden TCC izni sormaz.
- **Uygulamayı taşırsanız** (`/Applications` dışına), "Oturum Açılışında Başlat"
  ayarını kapatıp yeniden açın — kayıt uygulamanın yoluna bağlıdır.
- **Seviye kilidi ancak kaydırıcıyı oynattıktan sonra devreye girer.** Menüyü açıp
  hiçbir şey yapmazsanız seviyeye dokunulmaz.
- **Her cihaz seviye kontrolü sunmaz.** Bazı USB mikrofonlarda macOS'un giriş
  kaydırıcısı gri görünür; o cihazlarda menüde "seviye kontrolü sunmuyor" yazar.
- macOS'un Ses Ayarları'nda göstermediği dahili birleşik cihazlar (`~:AMS2_Aggregate:*`,
  ör. "noise cancellation on") menüde listelenmez. Audio MIDI Setup'ta kendiniz
  oluşturduğunuz birleşik cihazlar listede görünür.

## Geliştirme

```
Sources/MicrophonePicker/
  main.swift             # Giriş noktası, .accessory (Dock simgesi yok)
  AppDelegate.swift      # Menü çubuğu öğesi ve menü
  MicrophoneLock.swift   # Kilit mantığı, dinleyiciler, nöbetçi zamanlayıcı
  VolumeLock.swift       # Cihaz başına seviye hedefi, tolerans, savaş algılayıcı
  VolumeSliderView.swift # Menüye gömülü kaydırıcı (yazma kısıtlamalı)
  AudioProcesses.swift   # "Mikrofonu şu an kim kullanıyor?" (macOS 14.4+)
  CoreAudioBridge.swift  # CoreAudio HAL sarmalayıcısı
  LoginItem.swift        # SMAppService ile girişte başlatma
Resources/Info.plist     # LSUIElement = true
build.sh                 # swift build + .app paketleme + ad-hoc imza
```

Gereksinim: macOS 13+, Swift 5.9+.
