#!/bin/bash
# -----------------------------------------------------------------------------
#
# Package         : Electron
# Version         : 34.2.0
# Source repo     : https://github.com/electron/electron
# Tested on       : RHEL 8.10
# Language        : C++
# Travis-Check    : false
# Script License  : Apache License, Version 2 or later
# Maintainer      : Lex <lex@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

# shellcheck disable=SC2034
PACKAGE_NAME="electron"
PACKAGE_VERSION=${1:-"v34.2.0"}
PACKAGE_URL="https://github.com/electron/electron"

set -eux

# Export variables
export CC=clang
export CXX=clang++
export AR=llvm-ar
export NM=llvm-nm
export READELF=llvm-readelf

build_dir="${BUILD_DIRECTORY:-"${PWD}/build"}"
patches_dir="${PWD}/patches"
electron_src="${build_dir}/src"
electron_out="${electron_src}/out/Default"
assets_dir="${PWD}/assets"

CXXFLAGS+=' -faltivec-src-compat=mixed -Wno-deprecated-altivec-src-compat'
export CXXFLAGS

export DEPOT_TOOLS_UPDATE=0
export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
export GIT_CACHE_PATH="${GIT_CACHE_PATH:-${PWD}/.git_cache}"

# need for error: the option `Z` is only accepted on the nightly compiler
export RUSTC_BOOTSTRAP=1

# set rustc version
rustc_version="$(rustc --version)"
# set rust bindgen root
rust_bindgen_root="/usr"

# set clang version
clang_version="$(clang --version | sed -n 's/clang version //p' | cut -d. -f1)"
clang_base_path="$(clang --version | grep InstalledDir | cut -d' ' -f2 | sed 's#/bin##')"

ELECTRON_GN_DEFINES+=' chrome_pgo_phase=0'

ELECTRON_GN_DEFINES+=' is_clang=true'
ELECTRON_GN_DEFINES+=" clang_base_path=\"$clang_base_path\""
ELECTRON_GN_DEFINES+=" clang_version=\"$clang_version\""
ELECTRON_GN_DEFINES+=' clang_use_chrome_plugins=false'
ELECTRON_GN_DEFINES+=' use_lld=true'

# enable system rust
ELECTRON_GN_DEFINES+=' rust_sysroot_absolute="/usr"'
ELECTRON_GN_DEFINES+=" rust_bindgen_root=\"$rust_bindgen_root\""
ELECTRON_GN_DEFINES+=" rustc_version=\"$rustc_version\""

ELECTRON_GN_DEFINES+=' rtc_use_pipewire=false rtc_link_pipewire=false'

ELECTRON_GN_DEFINES+=' target_cpu="ppc64"'
if [ "$(arch)" != "ppc64le" ]; then
  ELECTRON_GN_DEFINES+=' use_sysroot=true'
fi

ELECTRON_GN_DEFINES+=' treat_warnings_as_errors=false'
ELECTRON_GN_DEFINES+=' use_gnome_keyring=false'
# ELECTRON_GN_DEFINES+=' use_system_libffi=true' # Containerfile has libffi_pic.a 3.4.4

# Create git cache directory if not already present
if [ ! -d "${GIT_CACHE_PATH}" ]; then
  mkdir -p "${GIT_CACHE_PATH}"
fi

# Ensure that compiler-rt and rustlib are there
if [ ! -d /usr/lib/clang/18/lib/ppc64le-redhat-linux-gnu/ ] && [ "$(arch)" != "ppc64le" ]; then
  ln -s /sysroot/usr/lib/clang/18/lib/ppc64le-redhat-linux-gnu /usr/lib/clang/18/lib/ppc64le-redhat-linux-gnu
fi
if [ ! -d /usr/lib/rustlib/powerpc64le-unknown-linux-gnu/ ] && [ "$(arch)" != "ppc64le" ]; then
  ln -s /sysroot/usr/lib/rustlib/powerpc64le-unknown-linux-gnu /usr/lib/rustlib/powerpc64le-unknown-linux-gnu
fi

# Checkout source

if [ ! -d "${build_dir}" ]; then
  mkdir -p "${build_dir}"
fi
cd "${build_dir}"

gclient config --name src/electron --unmanaged "${PACKAGE_URL}@${PACKAGE_VERSION}"
gclient sync --with_branch_heads --with_tags -vv

cd "${electron_src}"

# Don't use debian sysroots, even when cross-compiling
rm -rf build/linux/debian_bullseye_*
ln -s / build/linux/debian_bullseye_amd64-sysroot
ln -s / build/linux/debian_bullseye_arm64-sysroot
if [ "$(arch)" == "ppc64le" ]; then
  ln -s / build/linux/debian_bullseye_ppc64el-sysroot
else
  ln -s /sysroot build/linux/debian_bullseye_ppc64el-sysroot
fi

# Timothy Pearson's patchset
# https://gitlab.raptorengineering.com/raptor-engineering-public/chromium/openpower-patches
# Note(lex-ibm): We could automate getting the patches from the above URL, but after some discussions we decided it is better
# to have the patches in the same repository for better control/visibility.
while IFS= read -r patch; do
  if [[ $patch =~ ^ppc64le ]]; then
    git apply "${patches_dir}/openpower-patches/${patch}"
  fi
done <"${patches_dir}"/openpower-patches/series

# EPEL8 Chromium patches
# https://src.fedoraproject.org/rpms/chromium
patch -p1 < "${patches_dir}"/fedora/chromium-117-widevine-other-locations.patch
patch -p1 < "${patches_dir}"/fedora/chromium-disable-font-tests.patch
patch -p1 < "${patches_dir}"/fedora/chromium-123-screen-ai-service.patch
patch -p1 < "${patches_dir}"/fedora/chromium-98.0.4758.102-remoting-no-tests.patch
patch -p1 < "${patches_dir}"/fedora/chromium-107-proprietary-codecs.patch
patch -p1 < "${patches_dir}"/fedora/chromium-118-sigtrap_system_ffmpeg.patch
patch -p1 < "${patches_dir}"/fedora/chromium-121-system-old-ffmpeg.patch
patch -p1 < "${patches_dir}"/fedora/chromium-125-disable-FFmpegAllowLists.patch
patch -p1 < "${patches_dir}"/fedora/chromium-129-disable-H.264-video-parser-during-demuxing.patch
patch -p1 < "${patches_dir}"/fedora/chromium-118-dma_buf_export_sync_file-conflict.patch
# git apply "${patches_dir}"/fedora/chromium-131-revert-decommit-pooled-pages-by-default.patch
patch -p1 < "${patches_dir}"/fedora/chromium-129-el8-atk-compiler-error.patch
patch -p1 < "${patches_dir}"/fedora/chromium-132-el8-unsupport-clang-flags.patch
patch -p1 < "${patches_dir}"/fedora/chromium-132-el8-unsupport-rustc-flags.patch
patch -p1 < "${patches_dir}"/fedora/chromium-132-el8-clang18-build-error.patch
patch -p1 < "${patches_dir}"/fedora/chromium-123-fstack-protector-strong.patch
patch -p1 < "${patches_dir}"/fedora/chromium-122-clang-build-flags.patch
patch -p1 < "${patches_dir}"/fedora/chromium-126-split-threshold-for-reg-with-hint.patch
patch -p1 < "${patches_dir}"/fedora/chromium-130-hardware_destructive_interference_size.patch
patch -p1 < "${patches_dir}"/fedora/chromium-127-rust-clanglib.patch
patch -p1 < "${patches_dir}"/fedora/0001-swiftshader-fix-build.patch

# Electron PowerPC64 Little Endian support
patch -p1 < "${patches_dir}"/electron-32-001-fix-runtime-api-delegate.patch
patch -p1 < "${patches_dir}"/electron-32-002-fix-ppc64-syscalls-headers.patch
patch -p1 < "${patches_dir}"/electron-32-004-libpng.patch
patch -p1 < "${patches_dir}"/electron-34-001-remove-warnings.patch

# Build
cd "${electron_src}"

cp "$(command -v node)" third_party/node/linux/node-linux-x64/bin/node
chmod +x third_party/node/linux/node-linux-x64/bin/node

rm -rf buildtools/third_party/eu-strip/bin/eu-strip
cp "$(command -v eu-strip)" buildtools/third_party/eu-strip/bin/eu-strip

gn gen "${electron_out}" --args="import(\"//electron/build/args/release.gn\") ${ELECTRON_GN_DEFINES}"

# Build Electron
ninja -j "$(nproc)" -C "${electron_out}" electron

#Strip Electron Binaries
electron/script/copy-debug-symbols.py --target-cpu="ppc64" --out-dir="${electron_out}/debug" --compress
electron/script/strip-binaries.py --target-cpu="ppc64" --verbose
electron/script/add-debug-link.py --target-cpu="ppc64" --debug-dir="${electron_out}/debug"

# Build Electron dist.zip
ninja -j "$(nproc)" -C "${electron_out}" electron:electron_dist_zip
electron/script/zip_manifests/check-zip-manifest.py "${electron_out}/dist.zip" electron/script/zip_manifests/dist_zip.linux.x64.manifest # This works, so ¯\_(ツ)_/¯

# Build Mksnapshot
ninja -j "$(nproc)" -C "${electron_out}" electron:electron_mksnapshot
gn desc "${electron_out}" v8:run_mksnapshot_default args > "${electron_out}/mksnapshot_args"
sed -i '/.*builtins-pgo/d' "${electron_out}/mksnapshot_args"
sed -i '/--turbo-profiling-input/d' "${electron_out}/mksnapshot_args"
electron/script/strip-binaries.py --file "${electron_out}/mksnapshot"
electron/script/strip-binaries.py --file "${electron_out}/v8_context_snapshot_generator"
ninja -j "$(nproc)" -C "${electron_out}" electron:electron_mksnapshot_zip
cd "${electron_out}"
zip mksnapshot.zip mksnapshot_args gen/v8/embedded.S

cd "${electron_src}"

# Build Chromedriver
ninja -j "$(nproc)" -C "${electron_out}" electron:electron_chromedriver
ninja -C "${electron_out}" electron:electron_chromedriver_zip

# Build Node.js headers
ninja -j "$(nproc)" -C "${electron_out}" electron:node_headers

# Generate & Zip Symbols
ninja -j "$(nproc)" -C "${electron_out}" electron:electron_symbols
ninja -j "$(nproc)" -C "${electron_out}" electron:licenses
ninja -j "$(nproc)" -C "${electron_out}" electron:electron_version_file
DELETE_DSYMS_AFTER_ZIP=1 electron/script/zip-symbols.py -b "${electron_out}"

# Generate FFMpeg
gn gen "${electron_out}/../ffmpeg" --args="import(\"//electron/build/args/ffmpeg.gn\") ${ELECTRON_GN_DEFINES}"
ninja -j "$(nproc)" -C "${electron_out}/../ffmpeg" electron:electron_ffmpeg_zip

# Generate Hunspell Dictionaries
ninja -j "$(nproc)" -C "${electron_out}" electron:hunspell_dictionaries_zip

# Generate Libcxx
ninja -j "$(nproc)" -C "${electron_out}" electron:libcxx_headers_zip
ninja -j "$(nproc)" -C "${electron_out}" electron:libcxxabi_headers_zip
ninja -j "$(nproc)" -C "${electron_out}" electron:libcxx_objects_zip

# Generate TypeScript Definitions
cd "${electron_src}"/electron
node script/yarn create-typescript-definitions

# Move files to assets directory
if [ ! -d "${assets_dir}" ]; then
  mkdir -p "${assets_dir}"
fi
cd "${electron_out}"

cp chromedriver.zip "${assets_dir}/chromedriver-${PACKAGE_VERSION}-linux-ppc64le.zip"
cp debug.zip "${assets_dir}/electron-${PACKAGE_VERSION}-linux-ppc64le-debug.zip"
cp symbols.zip "${assets_dir}/electron-${PACKAGE_VERSION}-linux-ppc64le-symbols.zip"
cp dist.zip "${assets_dir}/electron-${PACKAGE_VERSION}-linux-ppc64le.zip"
cp ./gen/electron/tsc/typings/electron.d.ts "${assets_dir}/electron.d.ts"
cp ../ffmpeg/ffmpeg.zip "${assets_dir}/ffmpeg-${PACKAGE_VERSION}-linux-ppc64le.zip"
cp hunspell_dictionaries.zip "${assets_dir}/hunspell_dictionaries.zip"
cp libcxx_objects.zip "${assets_dir}/libcxx-objects-${PACKAGE_VERSION}-linux-ppc64le.zip"
cp libcxx_headers.zip "${assets_dir}/libcxx_headers.zip"
cp libcxxabi_headers.zip "${assets_dir}/libcxxabi_headers.zip"
cp mksnapshot.zip "${assets_dir}/mksnapshot-${PACKAGE_VERSION}-linux-ppc64le.zip"

# Generate SHASUMS256.txt
cd "${assets_dir}"
# shellcheck disable=SC2035
sha256sum * | sed 's/  / */' | tee SHASUMS256.txt

# Generate SHASUMS256.txt patch
curl -sL "https://github.com/electron/electron/releases/download/${PACKAGE_VERSION}/SHASUMS256.txt" > SHASUMS256.txt.orig
echo "" >> SHASUMS256.txt.orig
grep -v -e "hunspell_dictionaries.zip" -e "libcxxabi_headers.zip" -e "libcxx_headers.zip" -e "electron.d.ts" SHASUMS256.txt > SHASUMS256.txt.tmp
cat SHASUMS256.txt.tmp SHASUMS256.txt.orig | sort -k2 > SHASUMS256.txt.pp64le
diff -u SHASUMS256.txt.orig SHASUMS256.txt.pp64le > "${assets_dir}/SHASUMS256.txt.patch" || true
rm -f SHASUMS256.txt.orig SHASUMS256.txt.tmp SHASUMS256.txt.pp64le

echo "Build completed successfully!"