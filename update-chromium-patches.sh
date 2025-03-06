#!/bin/bash

CHROMIUM_VERSION=${1:-128}

download_url="https://gitlab.raptorengineering.com/raptor-engineering-public/chromium/openpower-patches/-/archive/chromium-${CHROMIUM_VERSION}/openpower-patches-chromium-${CHROMIUM_VERSION}.tar.gz?path=patches"

curl -L "${download_url}" | tar -xz --strip-components 1 --exclude='patches/ungoogled'
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' '/^ungoogled\//d' patches/series
else
  sed -i '/^ungoogled\//d' patches/series
fi
