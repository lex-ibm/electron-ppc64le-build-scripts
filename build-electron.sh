#!/bin/bash
# -----------------------------------------------------------------------------
#
# Package         : Electron
# Version         : 39.8.0
# Source repo     : https://github.com/electron/electron
# Tested on       : Ubuntu 22.04
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
PACKAGE_VERSION=${1:-"v39.8.0"}
PACKAGE_URL="https://github.com/electron/electron"
BUILD_TYPE="release"
APPLY_PATCHES=1
DO_CHECKOUT=1
DO_SYSROOT=1
PACKAGE_VERSION_SET=0

export PATH="$PATH:$buildtools/src"

usage() {
  cat <<'EOF'
Usage: build-electron.sh [version] [options]

Options:
  --without-patches           Skip applying bundled patch sets
  --skip-checkout             Skip gclient config/sync
  --build-type {release|testing}  Choose build args target (default: release)
  -h, --help                  Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --without-patches)
      APPLY_PATCHES=0
      shift
      ;;
    --skip-checkout)
      DO_CHECKOUT=0
      shift
      ;;
    --skip-sysroot)
      DO_SYSROOT=0
      shift
      ;;
    --build-type)
      if [[ -n "${2:-}" ]]; then
        BUILD_TYPE="$2"
        shift 2
      else
        echo "--build-type requires a value (release|testing)" >&2
        usage
        exit 1
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ ${PACKAGE_VERSION_SET} -eq 0 ]]; then
        PACKAGE_VERSION="$1"
        PACKAGE_VERSION_SET=1
        shift
      else
        echo "Unexpected positional argument: $1" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

case "${BUILD_TYPE}" in
  release|testing) ;;
  *)
    echo "Unsupported build type: ${BUILD_TYPE}" >&2
    exit 1
    ;;
esac

set -eux

build_dir="${BUILD_DIRECTORY:-"${PWD}/gclient"}"
patches_dir="${PWD}/patches"
electron_src="${build_dir}/src"
electron_out="${electron_src}/out/${BUILD_TYPE^}"
export ELECTRON_OUT_DIR="${BUILD_TYPE^}"
assets_dir="${PWD}/assets"

export DEPOT_TOOLS_UPDATE=0
export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
export GIT_CACHE_PATH="${GIT_CACHE_PATH:-${PWD}/.git_cache}"

# need for error: the option `Z` is only accepted on the nightly compiler
export RUSTC_BOOTSTRAP=1

# Checkout source
if [ "${DO_CHECKOUT}" -eq 1 ]; then
  if [ ! -d "${build_dir}" ]; then
    mkdir -p "${build_dir}"
  fi
  cd "${build_dir}"

  gclient config --name src/electron --unmanaged "${PACKAGE_URL}@${PACKAGE_VERSION}" --custom-var checkout_pgo_profiles=False
  gclient sync --with_branch_heads --with_tags -vv
else
  if [ ! -d "${electron_src}" ]; then
    echo "--skip-checkout specified but ${electron_src} is missing" >&2
    exit 1
  fi
fi

cd "${electron_src}"

if [ "${APPLY_PATCHES}" -eq 1 ]; then
  # Timothy Pearson's patchset
  # https://gitlab.raptorengineering.com/raptor-engineering-public/chromium/openpower-patches
  # Note(lex-ibm): We could automate getting the patches from the above URL, but after some discussions we decided it is better
  # to have the patches in the same repository for better control/visibility.
  while IFS= read -r patch; do
    if [[ $patch =~ ^ppc64le ]]; then
      patch -p1 -i "${patches_dir}/openpower-patches/${patch}"
    fi
  done <"${patches_dir}"/openpower-patches/series

  # Electron PowerPC64 Little Endian support
  patch -p1 -i "${patches_dir}"/electron-32-002-fix-ppc64-syscalls-headers.patch
  patch -p1 -i "${patches_dir}"/electron-32-004-libpng.patch
  patch -p1 -i "${patches_dir}"/electron-39-001-fix-runtime-api-delegate.patch
  patch -p1 -i "${patches_dir}"/electron-39-001-fix-fontconfig.patch
  patch -p1 -i "${patches_dir}"/electron-39-001-fix-webrtc.patch
  patch -p1 -i "${patches_dir}"/electron-41-sysroot-creator.patch
  patch -p1 -i "${patches_dir}"/electron-41-clang-build.patch
  patch -p1 -i "${patches_dir}"/electron-41-rust-build.patch
  patch -p1 -i "${patches_dir}"/electron-41-remove-variations-test-data.patch
  patch -p1 -i "${patches_dir}"/electron-41-sysroot.patch
  ##patch -p1 -i "${patches_dir}"/electron-41-devtools-node-compat.patch
  patch -p1 -i "${patches_dir}"/electron-41-swiftshader.patch
fi

## Build sysroot

cd "${electron_src}"

if [ "${DO_SYSROOT}" -eq 1 ]; then
  ./build/linux/sysroot_scripts/sysroot_creator.py build ppc64el
  mkdir -p build/linux/debian_bullseye_ppc64el-sysroot
  tar xf out/sysroot-build/bullseye/debian_bullseye_ppc64el_sysroot.tar.xz -C build/linux/debian_bullseye_ppc64el-sysroot
else
  if [ -f out/sysroot-build/bullseye/debian_bullseye_ppc64el_sysroot.tar.xz ]; then
      echo "Using prebuilt sysroot" >&2
      tar xf out/sysroot-build/bullseye/debian_bullseye_ppc64el_sysroot.tar.xz -C build/linux/debian_bullseye_ppc64el-sysroot
  elif [ ! -d "build/linux/debian_bullseye_ppc64el-sysroot" ]; then
    echo "--skip-sysroot specified but sysroot is missing" >&2
    exit 1
  fi
fi

## Build clang

tools/clang/scripts/build.py --use-system-cmake --with-ml-inliner-model='' --without-android --without-fuchsia --host-cc=/usr/bin/clang --host-cxx=/usr/bin/clang++ --bootstrap

## Build openssl 1.1.1
mkdir -p out/openssl
curl -L "https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1/openssl-1.1.1.tar.gz" | tar xzf - -C out/openssl --strip-components=1

cd out/openssl
./config --prefix="${electron_src}"/third_party/llvm-build-tools/openssl \
  --openssldir="${electron_src}"/third_party/llvm-build-tools/openssl \
  no-shared \
  no-tests
make -j "$(nproc)"
make install_sw install_ssldirs

cd "${electron_src}"

cp third_party/llvm-build-tools/openssl/lib/libssl.a third_party/llvm-build-tools/debian_bullseye_ppc64le_sysroot/usr/lib/powerpc64le-linux-gnu/

## Extract libstdc++.a for ppc64le
mkdir -p out/libstdcpp-extract
cd out/libstdcpp-extract
curl -L "http://ftp.us.debian.org/debian/pool/main/g/gcc-10-cross/libstdc++-10-dev-ppc64el-cross_10.2.1-6cross1_all.deb" -o libstdc++-10-dev-ppc64el-cross.deb
ar x libstdc++-10-dev-ppc64el-cross.deb
tar xf data.tar.xz
cp usr/lib/gcc-cross/powerpc64le-linux-gnu/10/libstdc++.a ../../third_party/llvm-build-tools/debian_bullseye_ppc64le_sysroot/usr/lib/powerpc64le-linux-gnu/
cd "${electron_src}"


export CC="${electron_src}"/third_party/llvm-build/Release+Asserts/bin/clang
export CXX="${electron_src}"/third_party/llvm-build/Release+Asserts/bin/clang++
export AR="${electron_src}"/third_party/llvm-build/Release+Asserts/bin/llvm-ar
export NM="${electron_src}"/third_party/llvm-build/Release+Asserts/bin/llvm-nm
export READELF="${electron_src}"/third_party/llvm-build/Release+Asserts/bin/llvm-readelf

## Build ncurses 6.0
mkdir -p out/ncurses
curl -L "https://stuff.mit.edu/afs/sipb/project/ncurses/releases/ncurses-6.0.tar.gz" | tar xzf - -C out/ncurses --strip-components=1

cd out/ncurses

export CXXFLAGS="-std=c++11"
./configure --prefix="${electron_src}"/third_party/llvm-build-tools/ncursesw \
  --enable-widec \
  --with-shared=no \
  --with-normal \
  --with-debug \
  --with-cxx-binding \
  --with-cxx \
  --enable-pc-files \
  --with-pkg-config-libdir="${electron_src}"/third_party/llvm-build-tools/ncursesw/lib/pkgconfig \
  --without-ada \
  --without-manpages \
  --without-tests

make -j "$(nproc)"
make install

unset CXXFLAGS

## Build GN

pushd /opt/gn
sudo -E python3 build/gen.py
sudo -E ninja -j $(nproc) -C out
popd

cd "${electron_src}"

## Build rust

git config --global user.email "builduser@ibm.com"
git config --global user.name "builduser"

export CARGO_PROFILE_RELEASE_OPT_LEVEL=0
tools/rust/build_rust.py --skip-test --entire-toolchain

# set clang version
clang_version="$($electron_src/third_party/llvm-build/Release+Asserts/bin/clang --version | sed -n 's/clang version //p' | cut -d. -f1)"
clang_base_path="$($electron_src/third_party/llvm-build/Release+Asserts/bin/clang --version | grep InstalledDir | cut -d' ' -f2 | sed 's#/bin##')"

ELECTRON_GN_DEFINES+=' chrome_pgo_phase=0'

ELECTRON_GN_DEFINES+=' is_clang=true'
ELECTRON_GN_DEFINES+=" clang_base_path=\"$clang_base_path\""
ELECTRON_GN_DEFINES+=" clang_version=$clang_version"
# ELECTRON_GN_DEFINES+=" dcheck_always_on=false is_debug=false is_official_build=false symbol_level=2"
ELECTRON_GN_DEFINES+=' target_cpu="ppc64"'
ELECTRON_GN_DEFINES+=' use_sysroot=true'
ELECTRON_GN_DEFINES+=' treat_warnings_as_errors=false'
ELECTRON_GN_DEFINES+=' clang_warning_suppression_file=""'
# Disable ThinLTO on ppc64le to avoid LLVM assertion failures with Rust code
ELECTRON_GN_DEFINES+=' use_thin_lto=false'

# Create git cache directory if not already present
if [ ! -d "${GIT_CACHE_PATH}" ]; then
  mkdir -p "${GIT_CACHE_PATH}"
fi

# Build
cd "${electron_src}"

cp "$(command -v node)" third_party/node/linux/node-linux-x64/bin/node
chmod +x third_party/node/linux/node-linux-x64/bin/node

rm -rf third_party/openscreen/src/buildtools/third_party/eu-strip/bin/eu-strip
mkdir -p third_party/openscreen/src/buildtools/third_party/eu-strip/bin/
cp "$(command -v eu-strip)" third_party/openscreen/src/buildtools/third_party/eu-strip/bin/eu-strip

npm install -g esbuild@0.25.1
mkdir -p third_party/devtools-frontend/src/third_party/esbuild/
cp /usr/local/lib/node_modules/esbuild/bin/esbuild third_party/devtools-frontend/src/third_party/esbuild/esbuild

#unpack rollup binary for ppc64le
mkdir -p third_party/devtools-frontend/src/node_modules/@rollup/rollup-linux-powerpc64le-gnu
curl -L https://npm.skia.org/chrome-devtools/@rollup%2frollup-linux-powerpc64le-gnu/-/rollup-linux-powerpc64le-gnu-4.22.4.tgz | tar -xvzf - --strip-components=1 -C third_party/devtools-frontend/src/node_modules/@rollup/rollup-linux-powerpc64le-gnu


gn gen "${electron_out}" --args="import(\"//electron/build/args/${BUILD_TYPE}.gn\") ${ELECTRON_GN_DEFINES}"

# Build Electron
NINJA_SUMMARIZE_BUILD=1 ninja -j "$(nproc)" -C "${electron_out}" "electron:${BUILD_TYPE}_build"
cp "${electron_out}/.ninja_log" "${electron_src}/out/electron_ninja_log"
node electron/script/check-symlinks.js

# Build Mksnapshot
ELECTRON_DEPOT_TOOLS_DISABLE_LOG=1 gn desc "${electron_out}" v8:run_mksnapshot_default args > "${electron_out}/mksnapshot_args"
sed -i '/.*builtins-pgo/d' "${electron_out}/mksnapshot_args"
sed -i '/--turbo-profiling-input/d' "${electron_out}/mksnapshot_args"
(cd "${electron_out}" && zip mksnapshot.zip mksnapshot_args gen/v8/embedded.S)

cd "${electron_src}"

# Build Chromedriver
ninja -j "$(nproc)" -C "${electron_out}" electron:electron_chromedriver_zip

# Generate & Zip Symbols
DELETE_DSYMS_AFTER_ZIP=1 electron/script/zip-symbols.py -b "${electron_out}"

# Generate FFMpeg
gn gen "${electron_out}/../ffmpeg" --args="import(\"//electron/build/args/ffmpeg.gn\") ${ELECTRON_GN_DEFINES}"
ninja -j "$(nproc)" -C "${electron_out}/../ffmpeg" electron:electron_ffmpeg_zip

# Generate TypeScript Definitions
cd "${electron_src}"/electron
node script/yarn.js create-typescript-definitions

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
