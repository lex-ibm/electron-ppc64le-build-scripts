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
  git apply "${CWD}"/patches/electron-32-fix-runtime-api-delegate.patch
  git apply "${CWD}"/patches/electron-32-fix-ppc64-syscalls-headers.patch

  # Use RHEL's libpng
  build/linux/unbundle/replace_gn_files.py --system-libraries libpng

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

ELECTRON_GN_DEFINES+=' use_system_libffi=true'

ELECTRON_GN_DEFINES+=' target_cpu="ppc64"'
ELECTRON_GN_DEFINES+=' target_os="linux"'
ELECTRON_GN_DEFINES+=' current_os="linux"'
ELECTRON_GN_DEFINES+=' treat_warnings_as_errors=false'
ELECTRON_GN_DEFINES+=' use_gnome_keyring=false'

# ELECTRON_GN_DEFINES+=' use_sysroot=true'

cd electron/src

cp "$(command -v node)" third_party/node/linux/node-linux-x64/bin/node
chmod +x third_party/node/linux/node-linux-x64/bin/node

rm -rf buildtools/third_party/eu-strip/bin/eu-strip
cp "$(command -v eu-strip)" buildtools/third_party/eu-strip/bin/eu-strip

if [ ! -f "${CWD}"/electron/src/out/Release/electron ]; then
  gn gen out/Release --args="import(\"//electron/build/args/release.gn\") ${ELECTRON_GN_DEFINES}"
  ninja -j "$(nproc)" -C out/Release electron
  electron/script/strip-binaries.py -d out/Release
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
