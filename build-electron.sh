#!/bin/bash
# -----------------------------------------------------------------------------
#
# Package         : Electron
# Version         : 32.2.5
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

ELECTRON_VERSION=${1:-v32.2.5}

set -eux
CWD=$(pwd)

# Prep

bootstrap=true

build_headless=false

use_vaapi=false

use_v4l2_codec=false

disable_bti=false

build_clear_key_cdm=false

userestrictedapikeys=false

useapikey=true

enable_debug=false

if [ "$enable_debug" == false ]; then
  debug_level=0
else
  debug_level=1
fi

use_custom_libcxx=true

clang=true

cfi=false

use_qt6=false
use_qt=true

bundlere2=true
bundlejsoncpp=true
bundlewoff2=true
bundlelibaom=true
bundlelibavif=true
bundlesnappy=true
bundlezstd=true
bundleicu=true
bundledav1d=true
bundlebrotli=true
bundlelibwebp=true
bundlecrc32c=true
bundleharfbuzz=true
bundlelibpng=true
bundlelibjpeg=true
bundlefreetype=true
bundlelibdrm=true
bundlefontconfig=true
bundleffmpegfree=true
bundlelibopenjpeg2=true
bundlelibtiff=true
bundlelibxml=true
bundlepylibs=false
bundlelibxslt=false
bundleflac=false
bundledoubleconversion=false
bundlelibXNVCtrl=false
bundlehighway=false
bundlelibusbx=false
bundlelibevent=false
bundlelibsecret=false
bundleopus=false
bundlelcms2=false

bundleminizip=true

# Prepare for build
export DEPOT_TOOLS_UPDATE=0
export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
export GIT_CACHE_PATH="${CWD}"/.git_cache

mkdir -p "${GIT_CACHE_PATH}"
if [ -z "$(ls -A "${CWD}"/electron/src)" ]; then
  # Checkout source
  mkdir -p electron && cd electron
  gclient config --name src/electron --unmanaged "https://github.com/electron/electron@${ELECTRON_VERSION}"
  gclient sync --with_branch_heads --with_tags -vv
  cd src

  # Fix sysroot symlinks
  rm -rf build/linux/debian_bullseye_*
  ln -s / build/linux/debian_bullseye_amd64-sysroot
  ln -s /sysroot build/linux/debian_bullseye_ppc64le-sysroot

  # Timothy Pearson's patchset
  # https://gitlab.solidsilicon.io/public-development/open-source/chromium/openpower-patches/-/tree/chromium-128/patches/ppc64le
  # Note(lex-ibm): We could automate getting the patches from the above URL, but after some discussions we decided it is better
  # to have the patches in the same repository for better control/visibility.
  while IFS= read -r patch; do
    if [[ $patch =~ ^ppc64le ]]; then
      git apply "${CWD}/patches/${patch}"
    fi
  done <"${CWD}"/patches/series

  # EPEL8 Chromium patches
  # https://src.fedoraproject.org/rpms/chromium
  git apply "${CWD}"/patches/fedora/chromium-118-dma_buf_export_sync_file-conflict.patch
  git apply "${CWD}"/patches/fedora/chromium-127-rust-clanglib.patch

  # Electron PowerPC64 Little Endian support
  git apply "${CWD}"/patches/electron-32-001-fix-runtime-api-delegate.patch
  git apply "${CWD}"/patches/electron-32-002-fix-ppc64-syscalls-headers.patch
  git apply "${CWD}"/patches/electron-32-003-enable-ppc64le-cross-compile.patch

  # Use RHEL's libpng
  
  if [ "$bundlelibusbx" == false ]; then
    rm -rf third_party/libusb/src/libusb/libusb.h
    cp -a /sysroot/usr/include/libusb-1.0/libusb.h third_party/libusb/src/libusb/libusb.h
  fi

  if [ "$bundledav1d" == false ]; then
    cp -a third_party/dav1d/version/version.h third_party/dav1d/libdav1d/include/dav1d/
  fi

  cd ../../
fi

# Build
CXXFLAGS+=' -faltivec-src-compat=mixed -Wno-deprecated-altivec-src-compat'

export CC=clang
export CXX=clang++
export AR=llvm-ar
export NM=llvm-nm
export READELF=llvm-readelf

export CXXFLAGS

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

if [ "$use_custom_libcxx" == false ]; then
  ELECTRON_GN_DEFINES+=' use_custom_libcxx=false'
fi

if [ "$bundlelibjpeg" == false ]; then
  ELECTRON_GN_DEFINES+=' use_system_libjpeg=true'
fi

if [ "$bundlelibpng" == false ]; then
  ELECTRON_GN_DEFINES+=' use_system_libpng=true'
fi

if [ "$bundlelibopenjpeg2" == false ]; then
  ELECTRON_GN_DEFINES+=' use_system_libopenjpeg2=true'
fi

if [ "$bundlelcms2" == false ]; then
  ELECTRON_GN_DEFINES+=' use_system_lcms2=true'
fi

if [ "$bundlelibtiff" == false ]; then
  ELECTRON_GN_DEFINES+=' use_system_libtiff=true'
fi

ELECTRON_GN_DEFINES+=' rtc_use_pipewire=false rtc_link_pipewire=false'

ELECTRON_GN_DEFINES+=' target_cpu="ppc64"'
ELECTRON_GN_DEFINES+=' target_os="linux"'
ELECTRON_GN_DEFINES+=' current_os="linux"'
ELECTRON_GN_DEFINES+=' use_sysroot=true'

ELECTRON_GN_DEFINES+=' treat_warnings_as_errors=false'
ELECTRON_GN_DEFINES+=' use_gnome_keyring=false'

cd electron/src

cp "$(command -v node)" third_party/node/linux/node-linux-x64/bin/node
chmod +x third_party/node/linux/node-linux-x64/bin/node

rm -rf buildtools/third_party/eu-strip/bin/eu-strip
cp "$(command -v eu-strip)" buildtools/third_party/eu-strip/bin/eu-strip

# Initialize an array to hold system libraries
system_libs=()

# Check various conditions and add corresponding libraries to the array
if [ "$bundlelibaom" = false ]; then
    system_libs+=(libaom)
fi
if [ "$bundlelibavif" = false ]; then
    system_libs+=(libavif)
fi
if [ "$bundlebrotli" = false ]; then
    system_libs+=(brotli)
fi
if [ "$bundlecrc32c" = false ]; then
    system_libs+=(crc32c)
fi
if [ "$bundledav1d" = false ]; then
    system_libs+=(dav1d)
fi
if [ "$bundlehighway" = false ]; then
    system_libs+=(highway)
fi
if [ "$bundlefontconfig" = false ]; then
    system_libs+=(fontconfig)
fi
if [ "$bundleffmpegfree" = false ]; then
    system_libs+=(ffmpeg)
fi
if [ "$bundlefreetype" = false ]; then
    system_libs+=(freetype)
fi
if [ "$bundleharfbuzz" = false ]; then
    system_libs+=(harfbuzz-ng)
fi
if [ "$bundleicu" = false ]; then
    system_libs+=(icu)
fi
if [ "$bundlelibdrm" = false ]; then
    system_libs+=(libdrm)
fi
if [ "$bundlelibevent" = false ]; then
    system_libs+=(libevent)
fi
if [ "$bundlelibjpeg" = false ]; then
    system_libs+=(libjpeg)
fi
if [ "$bundlelibpng" = false ]; then
    system_libs+=(libpng)
fi
if [ "$bundlelibusbx" = false ]; then
    system_libs+=(libusb)
fi
if [ "$bundlelibwebp" = false ]; then
    system_libs+=(libwebp)
fi
if [ "$bundlelibxml" = false ]; then
    system_libs+=(libxml)
fi
if [ "$bundlelibxslt" = false ]; then
    system_libs+=(libxslt)
fi
if [ "$bundleopus" = false ]; then
    system_libs+=(opus)
fi
if [ "$bundlere2" = false ]; then
    system_libs+=(re2)
fi
if [ "$bundlewoff2" = false ]; then
    system_libs+=(woff2)
fi
if [ "$bundleminizip" = false ]; then
    system_libs+=(zlib)
fi
if [ "$bundlejsoncpp" = false ]; then
    system_libs+=(jsoncpp)
fi
if [ "$bundledoubleconversion" = false ]; then
    system_libs+=(double-conversion)
fi
if [ "$bundlelibsecret" = false ]; then
    system_libs+=(libsecret)
fi
if [ "$bundlesnappy" = false ]; then
    system_libs+=(snappy)
fi
if [ "$bundlelibXNVCtrl" = false ]; then
    system_libs+=(libXNVCtrl)
fi
if [ "$bundleflac" = false ]; then
    system_libs+=(flac)
fi
if [ "$bundlezstd" = false ]; then
    system_libs+=(zstd)
fi

# Run the replace_gn_files.py script with the system libraries
build/linux/unbundle/replace_gn_files.py --system-libraries "${system_libs[@]}"

if [ ! -f "${CWD}"/electron/src/out/Release/electron ]; then
  gn gen out/Release --args="import(\"//electron/build/args/release.gn\") ${ELECTRON_GN_DEFINES}"
  ninja -j "$(nproc)" -C out/Release electron
  electron/script/strip-binaries.py --target-cpu ppc64 -d out/Release
  ninja -C out/Release electron:electron_dist_zip
fi

if [ -f "${CWD}"/electron/src/out/Release/dist.zip ]; then
  mv "${CWD}"/electron/src/out/Release/dist.zip "${CWD}/electron/src/out/Release/electron-${ELECTRON_VERSION}-linux-ppc64le.zip"
fi

if [ -f "${CWD}/electron/src/out/Release/electron-${ELECTRON_VERSION}-linux-ppc64le.zip" ]; then
  shasum256_zip=$(sha256sum "${CWD}/electron/src/out/Release/electron-${ELECTRON_VERSION}-linux-ppc64le.zip")
  if [ ! -f "${CWD}"/electron/src/out/Release/SHASUM256.txt ]; then
    curl -sL "https://github.com/electron/electron/releases/download/${ELECTRON_VERSION}/SHASUMS256.txt" >"${CWD}"/electron/src/out/Release/SHASUM256.txt
    printf '\n%s' "$shasum256_zip" >>"${CWD}"/electron/src/out/Release/SHASUM256.txt
  fi
  echo "$shasum256_zip"
fi
