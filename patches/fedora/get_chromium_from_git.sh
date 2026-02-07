#! /bin/bash

SRC_DIR=chromium-src
VERSION=$1
if [[ -z $VERSION ]]; then
  echo "Version is missing"
  exit 1
fi

rm -rf $SRC_DIR && mkdir -p $SRC_DIR
pushd $SRC_DIR
cat >.gclient <<EOF
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
EOF

export PATH+=":$PWD/depot_tools"
export DEPOT_TOOLS_UPDATE=0
echo "Clone chromium-$VERSION..." 
git clone -b $VERSION --depth=2 https://chromium.googlesource.com/chromium/src
echo "Clone depot_tools..."
git clone --depth=1 https://chromium.googlesource.com/chromium/tools/depot_tools
gclient sync --no-history --nohooks
src/tools/update_pgo_profiles.py --target=linux update --gs-url-base=chromium-optimization-profiles/pgo_profiles
src/build/util/lastchange.py -o src/build/util/LASTCHANGE
src/build/util/lastchange.py -s src/third_party/dawn --revision src/gpu/webgpu/DAWN_VERSION
src/build/util/lastchange.py -m GPU_LISTS_VERSION --revision-id-only --header src/gpu/config/gpu_lists_version.h
src/build/util/lastchange.py -m SKIA_COMMIT_HASH -s src/third_party/skia --header src/skia/ext/skia_commit_hash.h

find src -type d -name ".git" | xargs rm -rf
find src/third_party/jdk/current -type f -delete
rm -rf src/build/linux/debian_bullseye_amd64-sysroot \
       src/build/linux/debian_bullseye_i386-sysroot \
       src/third_party/node/linux/node-linux-x64* \
       src/third_party/rust-toolchain \
       src/third_party/rust-src

# clean ffmpeg
echo "Cleaning ffmpeg from proprietary things..."
ln -s ../clean_ffmpeg.sh .
ln -s ../ffmpeg-clean.patch .
ln -s ../get_free_ffmpeg_source_files.py .
./clean_ffmpeg.sh src 1

# clean openh264
echo "Cleaning openh264 from proprietary things..."
find src/third_party/openh264/src -type f -not -name '*.h' -delete
mv src ../chromium-$VERSION
popd

echo "Compressing cleaned tree, please wait..."
tar -cf - chromium-$VERSION | xz -9 -T 0 -f > chromium-$VERSION-clean.tar.xz
echo "Finished!"

