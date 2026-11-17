#!/bin/sh
# Builds SurroundBridge from source and installs it on this Mac:
#   - the app into /Applications
#   - the virtual 5.1 audio device ("SoundPusher Audio") into /Library/Audio/Plug-Ins/HAL
# You will be asked for your password once, for the audio device. Sound cuts out for a second
# while Core Audio restarts. Run it again any time to update. Undo with scripts/uninstall.sh.
set -e
cd "$(dirname "$0")/.."
FFMPEG_VERSION=n4.4.8

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode is required. Install it from the App Store, open it once, then run this again."; exit 1
fi

if [ ! -f deps/ffmpeg/lib/libavcodec.dylib ]; then
  echo "==> Building FFmpeg $FFMPEG_VERSION (first time only, takes a minute)"
  mkdir -p deps
  [ -d deps/ffmpeg-src ] || git clone --depth 1 --branch "$FFMPEG_VERSION" https://git.ffmpeg.org/ffmpeg.git deps/ffmpeg-src
  (cd deps/ffmpeg-src && FFMPEG_HOME="$PWD/../ffmpeg" ../../scripts/build-ffmpeg.sh > ../ffmpeg-build.log 2>&1) \
    || { echo "FFmpeg build failed, see deps/ffmpeg-build.log"; exit 1; }
fi

echo "==> Building SurroundBridge"
scripts/build.sh > deps/xcodebuild.log 2>&1 || { echo "Build failed, see deps/xcodebuild.log"; exit 1; }

echo "==> Installing the app into /Applications"
osascript -e 'tell application id "io.github.viv-411.SurroundBridge" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf /Applications/SurroundBridge.app
cp -R build/Release/SurroundBridge.app /Applications/

DRIVER=/Library/Audio/Plug-Ins/HAL/SoundPusherAudio.driver
if [ -d "$DRIVER" ] && diff -rq build/Release/SoundPusherAudio.driver "$DRIVER" >/dev/null 2>&1; then
  echo "==> Audio device already installed and up to date"
else
  echo "==> Installing the audio device (needs your password; sound will cut out briefly)"
  sudo sh -c "rm -rf '$DRIVER' && cp -R build/Release/SoundPusherAudio.driver /Library/Audio/Plug-Ins/HAL/ && killall coreaudiod"
fi

echo "==> Done. Turn your speaker volume down, then open SurroundBridge from Applications."
