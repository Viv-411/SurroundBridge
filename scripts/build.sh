#!/bin/sh
# Builds the audio driver and the app for Apple Silicon. Output goes to build/Release.
#
# Signing: uses your "Apple Development" certificate if you have one (free with an Apple ID in
# Xcode > Settings > Accounts). Otherwise it falls back to "ad-hoc" signing, which works on the Mac
# that built it but makes macOS ask for the audio permissions again after every rebuild.
#
# FFmpeg must be built first (scripts/install.sh does that for you):
#   git clone --depth 1 --branch n4.4.8 https://git.ffmpeg.org/ffmpeg.git deps/ffmpeg-src
#   (cd deps/ffmpeg-src && FFMPEG_HOME="$PWD/../ffmpeg" ../../scripts/build-ffmpeg.sh)
set -e
cd "$(dirname "$0")/.."
SYMROOT="${SYMROOT:-build}"

if [ -z "$ADHOC" ] && security find-certificate -c "Apple Development" >/dev/null 2>&1; then
  TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')
  set -- CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM="$TEAM"
else
  echo "No Apple Development certificate found (or ADHOC set): using ad-hoc signing."
  # Without a team, the hardened runtime would refuse to load the FFmpeg libraries, so it is turned off.
  set -- CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO
fi

xcodebuild -project SoundPusher.xcodeproj -target SoundPusherAudio -target SoundPusher \
  -configuration Release SYMROOT="$SYMROOT" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  FFMPEG_HOME="$PWD/deps/ffmpeg" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS= "$@" \
  build
