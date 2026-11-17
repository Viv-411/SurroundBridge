# SurroundBridge

A macOS app that gives you full control over what a 5.1 speaker system plays, even when the only
connection to it is HDMI/ARC or optical (which can't carry 5.1 as plain audio).

It captures your Mac's sound as 5.1, runs it through your own settings, encodes it to Dolby Digital
(AC-3) in real time and sends that to the TV / receiver.

```
Mac apps → "SoundPusher Audio" virtual 5.1 device → capture
        → routing → bass management → EQ → volume → delay → limiter      (SurroundCore)
        → AC-3 encoder (FFmpeg) → HDMI / optical → your speakers
```

**Turn the volume down before first use.** If any device misreads the Dolby Digital stream as
normal audio you get loud static.

## Features
- Routing matrix (any source channel → any speaker, with level and phase), plus receiver-style sound
  modes: Direct 5.1, All Channel Stereo, Matrix Surround, Stereo 2.0 / 2.1, Front Stage 3.1,
  Phantom Center, 5-Channel Mono
- Per speaker: volume, mute, solo, delay and a 5-band parametric EQ with a draggable curve
- Bass management: adjustable crossover that moves low frequencies to the subwoofer
- Safety limiter so nothing clips
- Test signal on one speaker at a time, or walking around the room
- Live level meters, presets you can save and load, menu bar control

## Requirements
macOS 14.2 or later, Apple Silicon, Xcode, and an output device that accepts an AC-3 stream.
Run `swift scripts/list-audio-formats.swift` and look for `cac3` under your device.

## Building
```sh
# 1. FFmpeg 4.4.x (the series the encoder code is written against)
git clone --depth 1 --branch n4.4.8 https://git.ffmpeg.org/ffmpeg.git deps/ffmpeg-src
(cd deps/ffmpeg-src && FFMPEG_HOME="$PWD/../ffmpeg" ../../scripts/build-ffmpeg.sh)

# 2. the driver and the app (signed with your "Apple Development" certificate)
scripts/build.sh

# 3. install the virtual audio device, then restart Core Audio
sudo cp -R build/Release/SoundPusherAudio.driver /Library/Audio/Plug-Ins/HAL/
sudo killall coreaudiod

# 4. run
open build/Release/SurroundBridge.app
```
Unit tests for the audio maths: `cd Core && swift test`

## Layout of this repository
| Folder | What it is |
|---|---|
| `Core/` | SurroundCore: the audio processing engine (C++ with a C interface) and its tests |
| `SurroundBridge/` | The SwiftUI window, menu bar additions and settings model |
| `SoundPusher/` | SoundPusher's capture → encode → output engine, with small hooks for SurroundBridge |
| `SoundPusherAudio/` | SoundPusher's virtual 5.1 audio device (unchanged) |
| `scripts/` | Build scripts and test-file generators |

## Credits
SurroundBridge is built on **[SoundPusher](https://codeberg.org/q-p/SoundPusher) by Daniel Vollmer**
(MIT license), which provides the virtual audio device, the audio capture, the real-time AC-3
encoding and the digital output. Its original README is kept in
[SOUNDPUSHER-README.md](SOUNDPUSHER-README.md).

Also used: [FFmpeg](https://ffmpeg.org) (AC-3 encoder and S/PDIF muxer),
[TPCircularBuffer](https://github.com/michaeltyson/TPCircularBuffer) by Michael Tyson, and filter
formulas from Robert Bristow-Johnson's Audio EQ Cookbook.

## License
MIT, see [LICENSE](LICENSE).
