# SETUP WORKSPACE
FROM archlinux:latest AS builder
RUN yes | pacman -Syu
RUN yes | pacman -S which make cmake nasm git ninja autoconf automake libtool texinfo help2man yasm gcc
RUN pacman -S mingw-w64 --noconfirm

RUN mkdir /src
WORKDIR /src

# SETUP TOOLCHAIN
RUN mkdir /src/patch
COPY toolchain/ /src/toolchain
ARG ARCH
ENV TOOLCHAIN_ARCH=$ARCH
ENV TOOLCHAIN_NAME=$TOOLCHAIN_ARCH-w64-mingw32
ENV TOOLCHAIN_CMAKE=/src/toolchain/$TOOLCHAIN_NAME-toolchain.cmake

# BUILD ZLIB
FROM builder AS zlib-build
RUN git clone https://github.com/madler/zlib.git /src/zlib
WORKDIR /src/zlib
RUN git fetch; git checkout cacf7f1d4e3d44d871b605da3b647f07d718623f
RUN mkdir /src/zlib/build
WORKDIR /src/zlib/build
RUN cmake .. -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_CMAKE -G Ninja -Wno-dev -DCMAKE_INSTALL_PREFIX=/build -DCMAKE_BUILD_TYPE=Release
RUN cmake --build . -j `nproc`
RUN cmake --install .

# BUILD OPENSSL
FROM builder AS openssl-build
RUN git clone https://github.com/janbar/openssl-cmake.git /src/openssl
WORKDIR /src/openssl
RUN mkdir /src/openssl/build
WORKDIR /src/openssl/build
RUN cmake .. -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_CMAKE -G Ninja -Wno-dev -DCMAKE_INSTALL_PREFIX=/build \
             -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
RUN cmake --build . -j `nproc`
RUN cmake --install . 

# BUILD OPENH264
FROM builder AS openh264-build
RUN git clone https://github.com/cisco/openh264 /src/openh264
WORKDIR /src/openh264
RUN git fetch; git checkout 50a1fcf70fafe962c526749991cb4646406933ba
COPY patch/mingw32-openh64.patch /src/patch/
RUN git apply /src/patch/mingw32-openh64.patch
RUN make OS=mingw_nt ARCH=$ARCH LDFLAGS=-static -j `nproc`
RUN make OS=mingw_nt PREFIX=/build install

# BUILD LIBUSB
FROM builder AS libusb-build
RUN git clone https://github.com/libusb/libusb.git /src/libusb
WORKDIR /src/libusb
RUN git fetch; git checkout c6a35c56016ea2ab2f19115d2ea1e85e0edae155
RUN mkdir m4; autoreconf -ivf
RUN ./configure --host=$TOOLCHAIN_NAME --prefix=/build
RUN make -j `nproc` && make install

# BUILD FFMPEG
FROM builder AS ffmpeg-build
RUN git clone https://github.com/FFmpeg/FFmpeg /src/FFmpeg
WORKDIR /src/FFmpeg
RUN git fetch; git checkout dc91b913b6260e85e1304c74ff7bb3c22a8c9fb1
RUN ./configure --arch=$TOOLCHAIN_ARCH --target-os=mingw32 --cross-prefix=$TOOLCHAIN_NAME- --prefix=/build  --extra-cflags=" -w "  --extra-cxxflags=" -w " --enable-dxva2
RUN make -j `nproc` && make install

# BUILD FREERDP
FROM builder AS freerdp-build
RUN git clone https://github.com/alexandru-bagu/FreeRDP.git /src/FreeRDP
COPY --from=zlib-build /build /build
COPY --from=openssl-build /build /build
COPY --from=openh264-build /build /build
COPY --from=libusb-build /build /build
COPY --from=ffmpeg-build /build /build
RUN mkdir /src/FreeRDP/build
WORKDIR /src/FreeRDP
RUN git fetch; git checkout 21a12ff6e55ba5245c564a55b09578a5338d7aac
COPY patch/mingw32-freerdp.patch /src/patch/
RUN git apply /src/patch/mingw32-freerdp.patch
WORKDIR /src/FreeRDP/build
RUN cmake .. -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_CMAKE -G Ninja -Wno-dev -DCMAKE_INSTALL_PREFIX=/build \
             -DWITH_X11=OFF -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release \
             -DWITH_ZLIB=ON -DZLIB_INCLUDE_DIR=/build \
             -DWITH_OPENH264=ON -DOPENH264_INCLUDE_DIR=/build/include \
             -DOPENH264_LIBRARY=/build/lib/libopenh264.dll.a -DWITH_MEDIA_FOUNDATION=OFF \
             -DOPENSSL_INCLUDE_DIR=/build/include \
             -DLIBUSB_1_INCLUDE_DIRS=/build/include/libusb-1.0 \
             -DLIBUSB_1_LIBRARIES=/build/lib/libusb-1.0.a \
             -DWITH_WINPR_TOOLS=OFF -DWITH_WIN_CONSOLE=ON \
             -DWITH_FFMPEG=ON -DWITH_DSP_FFMPEG=ON -DWITH_SWSCALE=ON \
             -DAVCODEC_INCLUDE_DIR=/build/include \
             -DAVCODEC_LIBRARY=/build/lib/libavcodec.a \
             -DAVUTIL_INCLUDE_DIR=/build/include \
             -DAVUTIL_LIBRARY=/build/lib/libavutil.a \
             -DSWRESAMPLE_INCLUDE_DIR=/build/include \
             -DSWRESAMPLE_LIBRARY=/build/lib/libswresample.a \
             -DSWScale_INCLUDE_DIR=/build/include \
             -DSWScale_LIBRARY=/build/lib/libswscale.a \
             -DCMAKE_C_FLAGS="${CMAKE_C_FLAGS} -static"
RUN cmake --build . -j `nproc`
RUN cmake --install . 