# Sleight

Turn your Magic Trackpad into a control surface. Sleight adds physical-feeling
custom gestures to macOS — most importantly a **volume knob**: put two fingers
on the trackpad and turn them like a dial.

Free, open source, and fully native (Swift + SwiftUI, no dependencies).

## Gestures

| Gesture | How | Default action |
|---|---|---|
| **Two-Finger Dial** | Place two fingers (thumb + index feels best) and rotate them like a knob | Volume |
| **Three-Finger Dial** | Same knob motion with three fingers — e.g. index + middle together, thumb below | Display brightness |
| **Hold + Sweep** | Rest a thumb on the pad, then sweep another finger around it in a line or arc | Keyboard backlight |
| **3 / 4 / 5-finger tap** | Quick tap | Configurable |

Every continuous gesture can be remapped to volume, display brightness, or
keyboard backlight, with per-gesture sensitivity and direction. Taps can
play/pause, skip tracks, mute, launch an app, or run a shell command.

Details that make it feel native:

- **Haptic detents** — the trackpad clicks softly every few percent, like a real knob.
- **Zero dead zone** — rotation accumulated while the gesture is being recognized is applied the moment it activates, so nothing is lost.
- **Scroll suppression** — while a dial is active, an event tap swallows the scroll events macOS would otherwise send, so turning the volume never scrolls the page under your cursor.
- **Smooth values** — volume is set directly through CoreAudio with sub-percent resolution instead of the 16 coarse steps of the volume keys.
- **A HUD** that appears while you adjust and fades away.
- **A live visualizer** in Settings that shows every raw touch in real time.
- Handles Bluetooth trackpad disconnects/reconnects and sleep/wake automatically.

## Install

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/kamenlevi/Sleight.git
cd Sleight
swift scripts/makeicon.swift
iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns
./scripts/build-app.sh
cp -R build/Sleight.app /Applications/
open /Applications/Sleight.app
```

On first launch, grant the two permissions Sleight asks for:

- **Input Monitoring** — required to read raw finger positions from the trackpad.
- **Accessibility** — used to suppress system scrolling during dial gestures and to post media-key events.

Both are in System Settings → Privacy & Security. The Settings window
(menu bar icon → Settings…) shows live status for each.

## How it works

Raw per-finger touch data is only exposed by Apple's private
`MultitouchSupport.framework` — the same framework BetterTouchTool and friends
use. Sleight loads it (plus `DisplayServices` for display brightness and
`CoreBrightness` for keyboard backlight) at runtime with `dlopen`/`dlsym`, so
nothing private is linked at build time. Because of the private API use, this
app can never ship on the App Store — build it yourself and enjoy.

The gesture engine measures the mean angular velocity of the touch set around
its own centroid each frame (translation cancels out), which cleanly separates
"turning a knob" from "scrolling" within a few degrees of rotation. A
hold-+-sweep is distinguished from a dial by displacement ratio and landing
stagger: rest the thumb first, then sweep.

## Notes

- Ad-hoc signed builds get a fresh identity each rebuild, so macOS re-asks for
  the permissions after you rebuild. Day-to-day use is unaffected.
- If a gesture feels too fast or slow, tune its sensitivity in
  Settings → Gestures.

## License

MIT
