#!/bin/sh
# Removes SurroundBridge and its virtual audio device from this Mac. Asks for your password once.
osascript -e 'tell application id "io.github.viv-411.SurroundBridge" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf /Applications/SurroundBridge.app
echo "Removing the audio device (needs your password; sound will cut out briefly)"
sudo sh -c "rm -rf /Library/Audio/Plug-Ins/HAL/SoundPusherAudio.driver && killall coreaudiod"
echo "Removed. Your settings are kept in ~/Library/Containers/io.github.viv-411.SurroundBridge; delete that folder to remove them too."
