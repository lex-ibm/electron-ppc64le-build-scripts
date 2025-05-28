#!/bin/bash

CHROMIUM_VERSION=${1:-134}

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
