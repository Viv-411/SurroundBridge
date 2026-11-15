#!/bin/sh
# Builds the audio driver and the app for Apple Silicon, signed with your own
# "Apple Development" certificate. Output goes to build/Release.
#
# First-time setup (FFmpeg 4.4.x is the series SoundPusher's encoder code targets):
#   git clone --depth 1 --branch n4.4.8 https://git.ffmpeg.org/ffmpeg.git deps/ffmpeg-src
#   (cd deps/ffmpeg-src && FFMPEG_HOME="$PWD/../ffmpeg" ../../scripts/build-ffmpeg.sh)
set -e
cd "$(dirname "$0")/.."
TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')
xcodebuild -project SoundPusher.xcodeproj -target SoundPusherAudio -target SoundPusher \
  -configuration Release SYMROOT=build ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  FFMPEG_HOME="$PWD/deps/ffmpeg" \
  CODE_SIGN_IDENTITY="Apple Development" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" OTHER_CODE_SIGN_FLAGS= \
  build
