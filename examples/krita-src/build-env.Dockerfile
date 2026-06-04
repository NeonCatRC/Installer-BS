# Build environment for the from-source Krita experiment: compiles + installs
# Krita to /krita-pkg so examples/krita-src/recipe can bundle it without a
# recompile each time. Build the image once:
#
#   docker build -t krita-built:24.04 - < examples/krita-src/build-env.Dockerfile
#
# Then package + smoke-test (Qt-clean room):
#
#   docker run --rm -v "$PWD:/work:ro" -v "$PWD/dist:/out" krita-built:24.04 \
#       /work/bs make /work/examples/krita-src/recipe -o /out/krita-src.bs
#
# Note: build-dep installs the entire "dependency hell" in one command (~1-4 min)
# — the same fact-check as Museum hall 18.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends build-essential cmake ninja-build ca-certificates patchelf file xz-utils \
 && apt-get build-dep -y krita \
 && cd /tmp && apt-get source krita \
 && cd krita-*/ && mkdir _b && cd _b \
 && cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
 && ninja \
 && DESTDIR=/krita-pkg ninja install \
 && cd / && rm -rf /tmp/krita-*
# Result: /krita-pkg/usr/{bin/krita, lib/.../{libkrita*,kritaplugins}, share/};
# Qt/KF build-deps stay installed so ldd resolves them at packaging time.
