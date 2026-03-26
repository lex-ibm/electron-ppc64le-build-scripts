#!/usr/bin/env bash

set -e

echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections

if [[ "$1" == "--32bit" ]]; then
  dpkg --add-architecture i386
fi
apt-get update

package_list="
    ca-certificates \
    curl \
    file \
    gcc-10 \
    g++-10 \
    gdb \
    gnupg \
    jq \
    libnotify-bin \
    locales \
    lsb-release \
    nano \
    sudo \
    vim-nox \
    wget \
    lsof \
    libasound2 \
    libfuse2 \
    software-properties-common \
    desktop-file-utils \
    weston \
    xvfb"

package_list_32bit="
    g++-multilib \
    libgl1:i386 \
    libgtk-3-0:i386 \
    libgdk-pixbuf-2.0-0:i386 \
    libdbus-1-3:i386 \
    libgbm1:i386 \
    libnss3:i386 \
    libcurl4:i386 \
    libasound2:i386"

package_list_arm="
    unzip \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libgbm1 \
    libgtk-3-0 \
    make \
    build-essential \
    git"

package_list_ppc64le="
    unzip \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libgbm1 \
    libgtk-3-0 \
    make \
    build-essential \
    git"

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $package_list
if [[ "$1" == "--32bit" ]]; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $package_list_32bit
fi
if [[ "$1" == "--arm" ]]; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $package_list_arm
fi
if [[ "$1" == "--ppc64le" ]]; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $package_list_ppc64le
fi

add-apt-repository ppa:git-core/ppa -y && apt-get update

# Download deps installation files from Chromium
# Pin to a specific SHA for reproducibility. To update, get the latest SHA from:
# curl -s "https://chromium.googlesource.com/chromium/src/+/HEAD?format=JSON" | tail -n +2 | jq -r '.commit'
CHROMIUM_SRC_SHA="fd5261f78cf1f838a476348fe7073b81e6d13f27"
curl "https://chromium.googlesource.com/chromium/src/+/${CHROMIUM_SRC_SHA}/build/install-build-deps.sh?format=TEXT" | base64 --decode | cat > /setup/install-build-deps.sh
curl "https://chromium.googlesource.com/chromium/src/+/${CHROMIUM_SRC_SHA}/build/install-build-deps.py?format=TEXT" | base64 --decode | cat > /setup/install-build-deps.py

# Remove snapcraft to avoid issues on docker build
sed -i 's/packages.append("snapcraft")/print("skipping snapcraft")/g' /setup/install-build-deps.py

# Apply ppc64le architecture support patch
if [[ "$1" == "--ppc64le" ]]; then
  if [ -f /tmp/chromium-install-build-deps-ppc64le.patch ]; then
    patch -p1 -d /setup/.. < /tmp/chromium-install-build-deps-ppc64le.patch
  else
    echo "WARNING: PPC64LE patch not found, attempting to patch manually"
    sed -i "s/if architecture not in \[\"i686\", \"x86_64\", 'aarch64'\]:/if architecture not in [\"i686\", \"x86_64\", 'aarch64', 'ppc64le']:/" /setup/install-build-deps.py
    sed -i 's/Only x86 and ARM64 architectures are currently supported/Only x86, ARM64, and PPC64LE architectures are currently supported/' /setup/install-build-deps.py
  fi
fi

# Ensure installation files are executable
chmod +x /setup/install-build-deps.sh
chmod +x /setup/install-build-deps.py

# Ensure g++ and gcc are linked to the correct version
current_gcc_version=$(g++ -dumpversion | cut -d. -f1)
if [[ "$current_gcc_version" -lt 10 ]]; then
  update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100
  update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100

  sudo update-alternatives --config gcc
  sudo update-alternatives --config g++
fi

# No Sudo Prompt
echo 'builduser ALL=NOPASSWD: ALL' >> /etc/sudoers.d/50-builduser
echo 'Defaults    env_keep += "DEBIAN_FRONTEND"' >> /etc/sudoers.d/env_keep

if [[ "$1" == "--32bit" ]]; then
  DEBIAN_FRONTEND=noninteractive bash /setup/install-build-deps.sh --syms --no-prompt --no-chromeos-fonts --lib32 --arm --no-nacl
elif [[ "$1" == "--arm" ]]; then
  echo Not installing Chromium deps
elif [[ "$1" == "--ppc64le" ]]; then
  DEBIAN_FRONTEND=noninteractive bash /setup/install-build-deps.sh --syms --no-prompt --no-chromeos-fonts --no-arm --no-nacl
else
  DEBIAN_FRONTEND=noninteractive bash /setup/install-build-deps.sh --syms --no-prompt --no-chromeos-fonts --no-arm --no-nacl
fi
rm -rf /var/lib/apt/lists/*

# Install Node.js
ARCH=$(uname -m)
if [[ "$ARCH" == "ppc64le" ]]; then
  NODE_VERSION=24.12.0
  NODE_DISTRO="node-v${NODE_VERSION}-linux-ppc64le"
  curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_DISTRO}.tar.xz"
  tar -C /usr/local --strip-components=1 -xJf "${NODE_DISTRO}.tar.xz"
  rm -f "${NODE_DISTRO}.tar.xz"
else
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  NODE_MAJOR=22
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
  apt-get update
  apt-get install -y nodejs npm
fi

# Install Yarn
npm i -g yarn

# dbusmock is needed for Electron tests
# apt-get install -y python3-dbusmock

# Install Azure CLI for use in CI (skip on ppc64le - not supported)
if [[ "$1" != "--ppc64le" ]]; then
  sudo rm -rf /var/lib/apt/lists/*
  /tmp/azure_cli_deb_install.sh
else
  echo "WARNING: Azure CLI installation skipped - ppc64le architecture not officially supported"
fi

mkdir /tmp/workspace
chown builduser:builduser /tmp/workspace
