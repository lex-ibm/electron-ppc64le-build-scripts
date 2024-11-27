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

PACKAGE_NAME="electron"
PACKAGE_VERSION=${1:-"v32.2.5"}
PACKAGE_URL="https://github.com/electron/electron"

set -eux

# Export variables
export CC=clang
export CXX=clang++
export AR=llvm-ar
export NM=llvm-nm
export READELF=llvm-readelf

build_dir="${BUILD_DIRECTORY:-"$PWD/build"}"
patches_dir="$PWD/patches"
electron_src="${build_dir}/src"
electron_out="${electron_src}/out/Release"

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
ELECTRON_GN_DEFINES+=' use_system_libffi=true'

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
# https://gitlab.solidsilicon.io/public-development/open-source/chromium/openpower-patches/-/tree/chromium-128/patches/ppc64le
# Note(lex-ibm): We could automate getting the patches from the above URL, but after some discussions we decided it is better
# to have the patches in the same repository for better control/visibility.
while IFS= read -r patch; do
  if [[ $patch =~ ^ppc64le ]]; then
    git apply "${patches_dir}/${patch}"
  fi
done <"${patches_dir}"/series

# EPEL8 Chromium patches
# https://src.fedoraproject.org/rpms/chromium
git apply "${patches_dir}"/fedora/chromium-118-dma_buf_export_sync_file-conflict.patch
git apply "${patches_dir}"/fedora/chromium-127-rust-clanglib.patch

# Electron PowerPC64 Little Endian support
git apply "${patches_dir}"/electron-32-001-fix-runtime-api-delegate.patch
git apply "${patches_dir}"/electron-32-002-fix-ppc64-syscalls-headers.patch
git apply "${patches_dir}"/electron-32-003-enable-ppc64le-cross-compile.patch

# Build
cd "${electron_src}"

cp "$(command -v node)" third_party/node/linux/node-linux-x64/bin/node
chmod +x third_party/node/linux/node-linux-x64/bin/node

rm -rf buildtools/third_party/eu-strip/bin/eu-strip
cp "$(command -v eu-strip)" buildtools/third_party/eu-strip/bin/eu-strip

if [ ! -f "${electron_out}/electron" ]; then
  gn gen "${electron_out}" --args="import(\"//electron/build/args/release.gn\") ${ELECTRON_GN_DEFINES}"
  ninja -j "$(nproc)" -C "${electron_out}" electron
  electron/script/strip-binaries.py --target-cpu ppc64 -d "${electron_out}"
  ninja -C "${electron_out}" electron:electron_dist_zip
fi

if [ -f "${electron_out}/dist.zip" ]; then
  mv "${electron_out}/dist.zip" "${electron_out}/${PACKAGE_NAME}-${PACKAGE_VERSION}-linux-ppc64le.zip"
fi

if [ -f "${electron_out}/${PACKAGE_NAME}-${PACKAGE_VERSION}-linux-ppc64le.zip" ]; then
  shasum256_zip=$(sha256sum "${electron_out}/${PACKAGE_NAME}-${PACKAGE_VERSION}-linux-ppc64le.zip")
  if [ ! -f "${electron_out}/SHASUM256.txt" ]; then
    curl -sL "https://github.com/electron/electron/releases/download/${PACKAGE_VERSION}/SHASUMS256.txt" > "${electron_out}/SHASUM256.txt"
    printf '\n%s' "$shasum256_zip" >> "${electron_out}/SHASUM256.txt"
  fi
  echo "$shasum256_zip"
fi
