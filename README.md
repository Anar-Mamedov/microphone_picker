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

Boşta CPU kullanımı %0, bellek ~50 MB.

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
- macOS'un Ses Ayarları'nda göstermediği dahili birleşik cihazlar (`~:AMS2_Aggregate:*`,
  ör. "noise cancellation on") menüde listelenmez. Audio MIDI Setup'ta kendiniz
  oluşturduğunuz birleşik cihazlar listede görünür.

## Geliştirme

```
Sources/MicrophonePicker/
  main.swift             # Giriş noktası, .accessory (Dock simgesi yok)
  AppDelegate.swift      # Menü çubuğu öğesi ve menü
  MicrophoneLock.swift   # Kilit mantığı, dinleyiciler, nöbetçi zamanlayıcı
  CoreAudioBridge.swift  # CoreAudio HAL sarmalayıcısı
  LoginItem.swift        # SMAppService ile girişte başlatma
Resources/Info.plist     # LSUIElement = true
build.sh                 # swift build + .app paketleme + ad-hoc imza
```

Gereksinim: macOS 13+, Swift 5.9+.
