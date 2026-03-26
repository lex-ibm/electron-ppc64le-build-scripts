FROM ubuntu:22.04

RUN groupadd --gid 999 builduser \
  && useradd --uid 999 --gid builduser --shell /bin/bash --create-home builduser \
  && mkdir -p /setup

# Set up TEMP directory
ENV TEMP=/tmp
RUN chmod a+rwx /tmp

# Install Linux packages
ADD tools/install-deps.sh /tmp/
ADD tools/azure_cli_deb_install.sh /tmp/
ADD patches/chromium-install-build-deps-ppc64le.patch /tmp/
RUN bash /tmp/install-deps.sh --ppc64le

# Add xvfb init script
ADD tools/xvfb-init.sh /etc/init.d/xvfb
RUN chmod a+x /etc/init.d/xvfb

RUN apt update && apt install -y elfutils ninja-build clang
RUN mkdir -p /usr/local/lib/node_modules && chown -R builduser:builduser /usr/local/lib/node_modules && chown -R builduser:builduser /usr/local/bin

RUN --mount=type=bind,source=patches/fix-depot-tools.patch,dst=/tmp/fix-depot-tools.patch \
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git /opt/depot_tools && \
    cd /opt/depot_tools && \
    patch -p1 -i /tmp/fix-depot-tools.patch && \
    echo '../../usr/bin' > /opt/depot_tools/python3_bin_reldir.txt && \
    chown -R builduser:builduser /opt/depot_tools

RUN --mount=type=bind,source=patches/fix-gn.patch,dst=/tmp/fix-gn.patch \
    git clone https://gn.googlesource.com/gn /opt/gn && \
    cd /opt/gn && \
    patch -p1 -i /tmp/fix-gn.patch

RUN rm -rf /var/lib/apt/lists/*

USER builduser

# Configure build-tools
RUN rm -rf /home/builduser/.electron_build_tools && \
	git clone https://github.com/electron/build-tools.git /home/builduser/.electron_build_tools && \
	cd /home/builduser/.electron_build_tools && \
  node --version && \
	npx --yes yarn && \
	sudo locale-gen "en_US.UTF-8"

# Build Python 3.12 from source
RUN sudo apt update && sudo apt install -y \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libncurses5-dev \
    libncursesw5-dev \
    libreadline-dev \
    libsqlite3-dev \
    libgdbm-dev \
    libdb5.3-dev \
    libbz2-dev \
    libexpat1-dev \
    liblzma-dev \
    libffi-dev \
    uuid-dev \
    python3-pip \
    wget && \
    cd /tmp && \
    wget https://www.python.org/ftp/python/3.12.8/Python-3.12.8.tgz && \
    tar -xzf Python-3.12.8.tgz && \
    cd Python-3.12.8 && \
    ./configure --enable-optimizations --prefix=/usr && \
    make -j$(nproc) && \
    sudo make install && \
    cd /tmp && \
    sudo rm -rf Python-3.12.8 Python-3.12.8.tgz && \
    python3.12 --version

RUN pip3 install 'httplib2===0.22.0' six requests

ARG CMAKE_VERSION=3.26.4
RUN curl -L "https://cmake.org/files/v3.26/cmake-${CMAKE_VERSION}.tar.gz" | tar -xz -C /tmp \
    && cd /tmp/cmake-${CMAKE_VERSION} \
    && ./bootstrap --parallel=$(nproc) --prefix=/usr/local \
    && make -j$(nproc) \
    && sudo make install \
    && cd / \
    && sudo rm -rf /tmp/cmake-${CMAKE_VERSION}

RUN sudo apt update && sudo apt install -y lld ccache

ENV PATH="/opt/depot_tools:/opt/gn/out:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

WORKDIR /home/builduser