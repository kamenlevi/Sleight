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
| **Edge Slider** | One finger on the top edge, one on the bottom (same spot horizontally), sweep both sideways together | Keyboard backlight |
| **Custom gestures** | Design your own in Settings → Custom: place finger zones on the pad, give each a direction or keep it stationary, draw a boundary where the gesture may start, choose speed and what it controls |  |
| **3 / 4 / 5-finger tap** | Quick tap | Configurable |
| **Keyboard shortcuts** | Bind any combination (e.g. 🌐Space) to a Sleight action, with warnings about which macOS function you'd be giving up |  |
| **Automations** | Schedule any action for a set time on chosen days — e.g. keyboard backlight to 20% at 21:00, or mute weekdays at 9:00 (Settings → Automation) |  |

Every continuous gesture can be remapped to volume, display brightness, or
keyboard backlight, with per-gesture sensitivity and direction. Taps can
play/pause, skip tracks, mute, cycle the keyboard backlight through
off · mid · max, launch an app, or run a shell command — and all of those can
also be bound to global keyboard shortcuts in Settings → Shortcuts.

Details that make it feel native:

- **Haptic detents** — the trackpad clicks softly every few percent, like a real knob, driven directly through the trackpad's actuator so it never skips.
- **Zero dead zone** — rotation accumulated while the gesture is being recognized is applied the moment it activates, so nothing is lost.
- **Lift-and-resume** — lift one finger mid-gesture (keep any finger down) and the gesture waits; put the finger back and keep turning.
- **Scroll suppression** — while a dial is active, an event tap swallows the scroll events macOS would otherwise send, so turning the volume never scrolls the page under your cursor.
- **Smooth values** — volume is set directly through CoreAudio with sub-percent resolution instead of the 16 coarse steps of the volume keys.
- **A HUD** that appears while you adjust and fades away. (Optionally it can
  also flash a confirmation when a tap or shortcut fires something invisible
  — off by default, so nothing ever interrupts you.)
- **A deep action catalogue** — every tap, shortcut and custom gesture picks
  from 40+ actions: media keys, volume/brightness/backlight steps, cycle the
  keyboard language, mute the microphone, Mission Control / App Exposé /
  show desktop / switch Spaces, Spotlight, back/forward and tab control,
  window management, screenshots, lock/sleep/screen saver, light/dark mode,
  empty trash, launch any app, or run a shell command. The picker shows the
  everyday ones; **More…** opens the searchable full list.
- **App-targeted actions** — aim a media or keystroke action at one specific
  app: play/pause *your music player*, no matter what else is playing, or
  send ⌘W / back / zoom to an app even while it's in the background. If the
  chosen app isn't running, the action deliberately does nothing.
- **A live visualizer** in Settings that shows every raw touch in real time —
  with a button to [Menagerie](https://github.com/kamenlevi/Menagerie), the
  same idea grown into a toy full of cardboard creatures.
- Handles Bluetooth trackpad disconnects/reconnects and sleep/wake automatically.

## Install

### Download (easiest)

1. Download `Sleight-<version>.zip` from the
   [latest release](https://github.com/kamenlevi/Sleight/releases/latest) and unzip it.
2. Drag `Sleight.app` into your **Applications** folder.
3. Open it. macOS will warn that it can't verify the app (it's signed with a
   local certificate, not notarized) — allow it in
   System Settings → Privacy & Security → "Open Anyway".

If you skip step 2 and launch straight from Downloads, Sleight installs
itself into Applications and relaunches from there — running from a
quarantined folder would break self-updating and permissions.

### Build from source

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/kamenlevi/Sleight.git
cd Sleight
./scripts/make-identity.sh     # once per machine — keeps permissions across updates
swift scripts/makeicon.swift
iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns
./scripts/build-app.sh
cp -R build/Sleight.app /Applications/
open /Applications/Sleight.app
```

`make-identity.sh` creates a local signing certificate so macOS treats every
build of Sleight as the same app — without it, Accessibility and Input
Monitoring grants reset on every update.

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
"turning a knob" from "scrolling" within a few degrees of rotation. As a
second guard, dials require *non-parallel* finger motion: scrolling fingers
travel in the same direction (cosine similarity ≈ +1) while dialing fingers
oppose each other (≈ −1), so scrolls can't misfire a dial no matter how
sloppy the arc. Sliders are distinguished by their starting posture at the
pad edges, which scrolling never uses.

## Updating

Sleight never updates itself behind your back. It checks GitHub Releases
twice a day and, when a newer version exists, says so in the menu bar and in
Settings → General — nothing is downloaded or installed until you click
Install there (the app relaunches once, keeping all your settings and
permissions).

To update manually from source at any time:

```sh
cd Sleight && ./scripts/update.sh
```

## Notes

- If a permission shows enabled in System Settings but Sleight's General tab
  says ✕, the entry is stale — click "Repair Permissions" in the General tab
  (or toggle Sleight off and on in the System Settings list). With the local
  signing identity this should only ever be needed once.
- If a gesture feels too fast or slow, tune its sensitivity in
  Settings → Gestures.

## License

MIT
