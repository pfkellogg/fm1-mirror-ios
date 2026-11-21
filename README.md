# FM-1 Big Screen for iPad and iPhone

*Formerly called FM-1 Mirror: same app, new name.*

☕ If this helps you make music, you can [buy me a coffee on Ko-fi](https://ko-fi.com/aikellogg).

The M-VAVE FM-1's tiny 1.54-inch screen, **big on an iPad or iPhone**, live, over USB or **Bluetooth**, with the
**spyglass**: the note or chord you play on the FM-1's keys, its pitch to one decimal, the notes on a grand staff, how
hard you hit the key, and the sound playing.

The iOS sibling of [FM-1 Big Screen](https://github.com/pfkellogg/fm1-mirror) (Mac, Windows, Linux) and
[FM-1 Big Screen + Spyglass](https://github.com/pfkellogg/fm1-mirror-spyglass-android) (Android), and the same messages.

## What you need

- An FM-1 running a **Big Screen** firmware (see FM-1 Big Screen's README), or firmware built on Charles Vestal's fm1-base with its own mirror turned on (Polly, LOOM-8 and others), which the app understands too. The spyglass works with any firmware.
- **USB:** an iPad or iPhone with USB-C and a USB-C cable, or, with Lightning, Apple's *Lightning to USB 3 Camera
  Adapter* (the one with a charging port).
- **Bluetooth:** tap **Bluetooth** and connect the FM-1 (for example *FM1 Community_BLE*) on Apple's Bluetooth MIDI
  page. The FM-1 takes one Bluetooth connection at a time.
- For the spyglass to see the FM-1's own keys, turn on **KEY OUT** on the FM-1 (SEQ, page 6/8 MIDI TRACK, K4).
- iOS / iPadOS 17 or newer.

## Using it

The screen and the spyglass sit side by side (landscape) or one above the other (portrait). The bar has
**Bluetooth**, **Keys** (a USB keyboard that plays the FM-1 through the iPad or iPhone, on channel 1: Auto takes the
first one there is), the **look** (Color, Bright color, Yellow on black, White on black, Black on white), **Smooth**
(4 times bigger with Lanczos and a light sharpening: smooth, crisp letters) and **Spyglass** (shows or hides it). The
spyglass follows the keyboard and the FM-1's own keys.

## Building

    brew install xcodegen
    xcodegen generate
    open FM1Mirror.xcodeproj

`project.yml` is the project; `Sources/` the app (SwiftUI, CoreMIDI). The simulator can't see USB or Bluetooth MIDI
devices, so test builds have two demos with a recording of a real FM-1 (Erik37 + Big Screen,
`Resources/Demo/erik37.syx`): `-demo` plays it straight into the mirror; `-demo-midi` makes a pretend FM-1 and a
pretend keyboard (virtual MIDI ports) so the whole CoreMIDI path runs, the keyboard bridge too. A look can be set
from the command line: `-look "Yellow on black"`. `tools/glyphs_to_swift.py` makes
`Sources/StaffGlyphs.swift` (Noto Music outlines, SIL OFL) from the Android app's StaffGlyphs.java.

Not yet in this version: the waveform, and installing Big Screen.
