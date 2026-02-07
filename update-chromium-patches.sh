#!/bin/bash

CHROMIUM_VERSION=${1:-142}
FEDORA_CHROMIUM_COMMIT_SHA=${2:-"21c645393dd764701f3c95f28a6471ce178c5c85"}

# Remove old patches
rm -rf patches/fedora patches/openpower-patches

# Fetch Fedora's Chromium Patches
## So, I did need to modify some patches from Fedora to make them work, but I
## might actually need to work around that to make this more stable.
mkdir -p patches/fedora
pushd patches/fedora || exit 1
git init
git remote add origin https://src.fedoraproject.org/rpms/chromium.git
git fetch origin --depth=1 "${FEDORA_CHROMIUM_COMMIT_SHA}"
git reset --hard "${FEDORA_CHROMIUM_COMMIT_SHA}"
rm -rf .git
popd || exit 1

# Timothy Pearson's Patches
download_url="https://gitlab.raptorengineering.com/raptor-engineering-public/chromium/openpower-patches/-/archive/chromium-${CHROMIUM_VERSION}/openpower-patches-chromium-${CHROMIUM_VERSION}.tar.gz?path=patches"
mkdir -p patches/openpower-patches
curl -L "${download_url}" | tar -xz --strip-components 2 --exclude='patches/ungoogled' -C patches/openpower-patches
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' '/^ungoogled\//d' patches/openpower-patches/series
else
  sed -i '/^ungoogled\//d' patches/openpower-patches/series
fi

# Fetch LICENSE
curl -L "https://gitlab.raptorengineering.com/raptor-engineering-public/chromium/openpower-patches/-/raw/chromium-${CHROMIUM_VERSION}/LICENSE" > patches/openpower-patches/LICENSE
