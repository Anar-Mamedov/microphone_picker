# MicrophonePicker

A tiny macOS menu bar app that keeps your Mac on the microphone you chose. Pick
an input device once, and it stays the system default no matter what macOS or
other apps try to do.

Plug in headphones, connect AirPods, or let an app switch the input on its own —
MicrophonePicker notices and puts your microphone back. It can also hold that
microphone's input level and stop apps from muting it.

> **Note:** the menu is currently in Turkish (the app shows up as *Mikrofon
> Kilidi*, "Microphone Lock"). Menu labels below are given in Turkish with the
> English meaning alongside.

## Install

Requires macOS 13 or later and Swift 5.9 or later (Xcode 15+ or the Command
Line Tools).

```bash
git clone https://github.com/Anar-Mamedov/microphone_picker.git
cd microphone_picker
./build.sh --install
```

This builds `/Applications/MicrophonePicker.app` and launches it. A microphone
icon appears in the menu bar.

To build without installing:

```bash
./build.sh
```

The app is signed ad-hoc, so no Apple Developer account is needed. It does not
ask for microphone permission: it never records audio, it only changes which
device macOS routes input from.

## Usage

Click the menu bar icon:

- **Giriş Cihazları** (Input Devices) — choose the microphone to lock. The
  moment you pick it, it becomes the system default and is locked.
- **Giriş Ayarları** (Input Settings) — a slider showing the locked
  microphone's input level. As soon as you move it, that value is saved **for
  that device** and locked; if the level drops, it is pulled back
  automatically. Click the line below the slider to remove the level lock.
- **Susturulmasını engelle** (Prevent muting) — when checked, the locked
  microphone is unmuted again if an app mutes it. This is also saved per
  device. On devices that offer no mute control (the RØDE PodMic USB is one)
  the option is disabled.
- **Kilidi Kaldır** (Unlock) — return to macOS's normal, automatic behavior.
- **Oturum Açılışında Başlat** (Launch at Login) — start the app automatically
  whenever you log in.
- **Son işlem** (Last action) — shows when the app last switched back, and
  from which device to which.

The icon shows the current state:

| Icon | Meaning |
|---|---|
| `mic` (outline) | Lock is off |
| `mic.fill` (filled) | Lock is on and the device is connected |
| `mic.slash.fill` (slashed) | The locked device is not connected; waiting for it to come back |

## How it works

The choice is stored as the device's persistent **UID** rather than its
`AudioDeviceID`. IDs change every time a device reconnects; the UID does not.
So if you unplug the PodMic and plug it back in, the lock still applies.

There are three lines of defense:

1. **A `kAudioHardwarePropertyDefaultInputDevice` listener** — the app hears
   about a change to the system default immediately and reverts it (measured
   at roughly 25–55 ms).
2. **A `kAudioHardwarePropertyDevices` listener** — fires when headphones are
   plugged in or removed. macOS sometimes changes the default a few hundred
   milliseconds *after* updating the device list, so the app checks again
   several times between 0.2 s and 5 s afterwards.
3. **A 1-second watchdog timer** — catches apps that change the default
   without producing any notification (Zoom, Teams and the like).

While the locked device is not connected, the app leaves the system alone and
takes over again as soon as the device returns.

On launch the app **opts out of App Nap** (`beginActivity`). Windowless menu bar
apps are App Nap's first target, and App Nap can coalesce timers and delay them
by minutes — without this, the third line of defense above silently stops
working. The system's idle sleep is not affected.

At idle it uses 0% CPU and about 50 MB of memory.

### Level and mute lock

Settings are stored **per device** (say RØDE at 90%, the built-in microphone at
50%, AirPods at 70% — all separate). But they are enforced **only on the
microphone that is currently locked**: other devices' values are remembered,
and the app does not interfere even if the system turns them down or mutes
them.

The locked device is watched through `kAudioDevicePropertyVolumeScalar` and
`kAudioDevicePropertyMute`. Because these listeners attach to the device itself
rather than to the system object, they are removed and re-attached every time
the device reconnects (that is, whenever its `AudioDeviceID` changes).

Not every device offers every control. The RØDE PodMic USB has a level control
but **no mute control at all**; the built-in microphone and other USB devices
have both. On devices without a control, the matching lock is quietly disabled
and the menu says why.

Two design details matter:

- **Quantization tolerance.** Hardware rounds the value you write to its
  nearest step — on the RØDE PodMic USB, writing 90% lands the device at 90.48%
  (its 22–63 dB range moves in discrete steps). Comparing for exact equality
  would make the app see "not equal" every round and write forever. Instead it
  uses a 1% tolerance and treats the value the device actually settles on as
  the target.
- **Fight detector.** Automatic gain control (AGC) in Zoom, Teams and Discord
  really does move the system slider. A tug-of-war causes audible level
  pumping in recordings and dozens of writes per second to the hardware gain.
  If 5 corrections are needed within 3 seconds, the lock pauses for 30 seconds
  and the menu explains why — because the lasting fix is in that app's own
  settings. The same mechanism applies to muting, and the pause is shared
  between the two.

### Who changed it?

After every correction the menu shows a line like this:

```
Son düzeltme: 14:32:07 · %50 → %90 · Wispr Flow
```

("Last correction: time · old → new level · app")

**CoreAudio does not say which process changed a property** — there is no API
for that. Instead, at the moment of the correction the app samples which apps
are **recording from the microphone** (Audio Process objects, macOS 14.4+). The
app that moves the level is almost always recording at the same time, so in
practice this names the right one; it is still an inference, which is why the
menu presents it as "using the microphone" rather than "keeps changing it".

If the level changes while no app is recording, that is useful information too
— the menu says no app was using the microphone, and the cause is most likely
a driver or a system setting.

Helper processes are attributed to their main app: `com.google.Chrome.helper`
opens the microphone, but the menu shows "Google Chrome".

## Good to know

- **While the lock is on, you cannot change the microphone in System
  Settings** — the app reverts it. That is the point. To switch, pick the new
  device from the menu, or unlock first.
- **Only the input device is touched.** Output (speakers/headphones) never
  changes, so you keep listening on your AirPods. A side benefit: since the
  AirPods microphone is not used, the Bluetooth connection does not drop to
  the low-quality HFP mode and audio stays at A2DP quality.
- **In-app choices are a separate matter.** In apps like Zoom or Teams, if the
  microphone is set to "Same as System", it follows this app. If you picked
  "AirPods" by hand inside the app, you need to change it there too.
- **If you move the app** out of `/Applications`, turn *Launch at Login* off
  and on again — the registration is tied to the app's path.
- **The level lock only starts after you move the slider.** If you open the
  menu and do nothing, the level is left alone.
- **Not every device offers a level control.** On some USB microphones macOS's
  input slider is greyed out; for those the menu says the device has no level
  control.
- Internal aggregate devices that macOS hides from Sound settings
  (`~:AMS2_Aggregate:*`, e.g. "noise cancellation on") are not listed.
  Aggregate devices you create yourself in Audio MIDI Setup do appear.

## Development

```
Sources/MicrophonePicker/
  main.swift             # Entry point, .accessory activation policy (no Dock icon)
  AppDelegate.swift      # Menu bar item and menu
  MicrophoneLock.swift   # Lock logic, listeners, watchdog timer
  VolumeLock.swift       # Per-device level target, tolerance, fight detector
  VolumeSliderView.swift # Slider embedded in the menu (write-throttled)
  AudioProcesses.swift   # "Who is using the microphone right now?" (macOS 14.4+)
  CoreAudioBridge.swift  # CoreAudio HAL wrapper
  LoginItem.swift        # Launch at login via SMAppService
Resources/Info.plist     # LSUIElement = true
build.sh                 # swift build + .app bundling + ad-hoc signing
```

Issues and pull requests are welcome — an English localization of the menu
would be a great first contribution.

## License

[MIT](LICENSE)
