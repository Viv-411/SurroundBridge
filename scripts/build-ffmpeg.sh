#!/bin/sh
# Builds the cut-down FFmpeg that SoundPusher needs (script from SoundPusher's README).
# Usage: FFMPEG_HOME=/path/to/install ./build-ffmpeg.sh   (run from inside the FFmpeg source dir)
set -e
MACOSX_DEPLOYMENT_TARGET=10.14 export MACOSX_DEPLOYMENT_TARGET
./configure --prefix=$FFMPEG_HOME --cc=clang --extra-cflags="-fno-stack-check" --disable-static --enable-shared --disable-all --disable-autodetect --disable-programs --disable-doc --disable-everything --disable-pthreads --disable-network --disable-dct --disable-dwt --disable-lsp --disable-lzo --disable-rdft --disable-faan --disable-pixelutils --enable-avutil --enable-avcodec --enable-avformat --enable-swresample --enable-encoder=ac3 --enable-muxer=spdif
make -j8
make install
# update shared library install names
cd $FFMPEG_HOME/lib
AVUTIL_ID=`otool -D libavutil.dylib | tail -1`
AVCODEC_ID=`otool -D libavcodec.dylib | tail -1`
AVFORMAT_ID=`otool -D libavformat.dylib | tail -1`
SWRESAMPLE_ID=`otool -D libswresample.dylib | tail -1`
for lib in libavutil libavcodec libavformat libswresample
do
    install_name_tool -id @rpath/$lib.dylib -change $AVUTIL_ID @rpath/libavutil.dylib -change $AVCODEC_ID @rpath/libavcodec.dylib -change $AVFORMAT_ID @rpath/libavformat.dylib -change $SWRESAMPLE_ID @rpath/libswresample.dylib $lib.dylib
done
