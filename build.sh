#!/bin/bash
# Build one image with the official OpenWrt ImageBuilder. Usage: ./build.sh <image>, where images/<image>/
# holds image.env, versions.env, packages.txt and optionally files/.
# The image gets: the package lists named in LISTS (lists/<name>.txt) plus its packages.txt, AmneziaWG
# from awg-openwrt and sing-box when versions.env pins them, and the overlays named in OVERLAYS
# (overlays/<name>/) followed by its own files/.
# Runs the same on a workstation and in GitHub Actions (.github/workflows/build.yml).
# Needs: git, curl, rsync, zstd, the ImageBuilder prerequisites (make, gawk, patch, ...) and, for an image
# that builds sing-box from source, go (>= sing-box's go.mod).
# Output: .build/<image>/out with the images, manifest, sha256sums and BUILDINFO.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
IMAGE=${1:?usage: $0 <image>}
IMAGE_DIR=$REPO_DIR/images/$IMAGE
[ -f "$IMAGE_DIR/image.env" ] || { echo "no such image: $IMAGE"; exit 1; }
# TARGET, PROFILE, ARCH_PACKAGES, LISTS, OVERLAYS; optional EXTRA_IMAGE_NAME, ROOTFS_PARTSIZE,
# SINGBOX_BUILD_TAGS + SINGBOX_GOARCH
. "$IMAGE_DIR/image.env"
# OPENWRT_VERSION; optional SINGBOX_TAG + SINGBOX_COMMIT or SINGBOX_IPK_SHA256, AWG_TAG + *_SHA256
. "$IMAGE_DIR/versions.env"
WORK_DIR=${WORK_DIR:-$REPO_DIR/.build/$IMAGE}
OUT_DIR=$WORK_DIR/out
rm -rf "$OUT_DIR" "$WORK_DIR/sing-box.bin"
mkdir -p "$WORK_DIR" "$OUT_DIR"

SB_INFO=none
if [ -n "${SINGBOX_TAG:-}" ] && [ -n "${SINGBOX_BUILD_TAGS:-}" ]; then
    echo "==> sing-box $SINGBOX_TAG from source (slim: $SINGBOX_BUILD_TAGS) for $SINGBOX_GOARCH"
    SB_SRC=$WORK_DIR/sing-box-src
    rm -rf "$SB_SRC"
    git clone -q --depth 1 -b "$SINGBOX_TAG" https://github.com/SagerNet/sing-box.git "$SB_SRC"
    [ "$(git -C "$SB_SRC" rev-parse HEAD)" = "$SINGBOX_COMMIT" ] || { echo "sing-box $SINGBOX_TAG is not commit $SINGBOX_COMMIT"; exit 1; }
    SB_VERSION="${SINGBOX_TAG#v}-slim"
    (cd "$SB_SRC" && GOOS=linux GOARCH=$SINGBOX_GOARCH CGO_ENABLED=0 go build -trimpath \
        -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=$SB_VERSION' $(cat release/LDFLAGS) -s -w -buildid=" \
        -tags "$SINGBOX_BUILD_TAGS" -o "$WORK_DIR/sing-box.bin" ./cmd/sing-box)
    SB_INFO="$SINGBOX_TAG ($SINGBOX_COMMIT), tags $SINGBOX_BUILD_TAGS, $(go version)"
elif [ -n "${SINGBOX_TAG:-}" ]; then
    # The upstream release build, binary only: the OpenWrt sing-box package in the lists provides the
    # init script and UCI config, and the overlay replaces its /usr/bin/sing-box.
    SB_IPK=sing-box_${SINGBOX_TAG#v}_openwrt_$ARCH_PACKAGES.ipk
    echo "==> sing-box $SINGBOX_TAG upstream build ($SB_IPK)"
    SB_DIR=$WORK_DIR/sing-box-ipk
    rm -rf "$SB_DIR"
    mkdir -p "$SB_DIR"
    curl -fsSL -o "$SB_DIR/$SB_IPK" "https://github.com/SagerNet/sing-box/releases/download/$SINGBOX_TAG/$SB_IPK"
    echo "$SINGBOX_IPK_SHA256  $SB_DIR/$SB_IPK" | sha256sum -c -
    # An .ipk is a gzip'd outer tar holding control.tar.gz + data.tar.gz + debian-binary
    tar -xzf "$SB_DIR/$SB_IPK" -C "$SB_DIR" data.tar.gz
    tar -xzf "$SB_DIR/data.tar.gz" -C "$SB_DIR" ./usr/bin/sing-box
    mv "$SB_DIR/usr/bin/sing-box" "$WORK_DIR/sing-box.bin"
    SB_INFO="$SINGBOX_TAG upstream $SB_IPK ($SINGBOX_IPK_SHA256)"
fi

echo "==> ImageBuilder $OPENWRT_VERSION $TARGET"
IB_BASE=https://downloads.openwrt.org/releases/$OPENWRT_VERSION/targets/$TARGET
IB_NAME=openwrt-imagebuilder-$OPENWRT_VERSION-${TARGET//\//-}.Linux-x86_64
if [ ! -d "$WORK_DIR/$IB_NAME" ]; then
    curl -fsSL -o "$WORK_DIR/ib.tar.zst" "$IB_BASE/$IB_NAME.tar.zst"
    curl -fsSL "$IB_BASE/sha256sums" | grep " \*$IB_NAME.tar.zst\$" | awk '{print $1"  ib.tar.zst"}' > "$WORK_DIR/ib.sha256"
    (cd "$WORK_DIR" && sha256sum -c ib.sha256)
    tar --zstd -xf "$WORK_DIR/ib.tar.zst" -C "$WORK_DIR"
    rm -f "$WORK_DIR/ib.tar.zst"
fi
# Image file names without the version (it is in the release tag), so a file keeps its name across releases
sed -i 's/^CONFIG_VERSION_FILENAMES=y$/# CONFIG_VERSION_FILENAMES is not set/' "$WORK_DIR/$IB_NAME/.config"

AWG_INFO=none
rm -f "$WORK_DIR/$IB_NAME"/packages/kmod-amneziawg-*.apk "$WORK_DIR/$IB_NAME"/packages/amneziawg-tools-*.apk
if [ -n "${AWG_TAG:-}" ]; then
    echo "==> AmneziaWG packages (awg-openwrt $AWG_TAG) into the ImageBuilder's local repository"
    AWG_SUFFIX=${AWG_TAG}_${ARCH_PACKAGES}_${TARGET//\//_}.apk
    mkdir -p "$WORK_DIR/$IB_NAME/packages"
    for p in "kmod-amneziawg:$AWG_KMOD_SHA256" "amneziawg-tools:$AWG_TOOLS_SHA256"; do
        f="$WORK_DIR/$IB_NAME/packages/${p%%:*}_$AWG_SUFFIX"
        curl -fsSL -o "$f" "https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/$AWG_TAG/${p%%:*}_$AWG_SUFFIX"
        echo "${p#*:}  $f" | sha256sum -c -
        # apk finds local packages by their canonical <name>-<version>.apk file name, not the release asset name
        v=$("$WORK_DIR/$IB_NAME/staging_dir/host/bin/apk" adbdump "$f" | awk '$1 == "version:" {print $2; exit}')
        mv -f "$f" "$WORK_DIR/$IB_NAME/packages/${p%%:*}-$v.apk"
    done
    AWG_INFO="awg-openwrt $AWG_TAG (kmod $AWG_KMOD_SHA256, tools $AWG_TOOLS_SHA256)"
fi
rm -f "$WORK_DIR/$IB_NAME/packages/packages.adb"   # re-indexed by the image build

echo "==> overlay files: $OVERLAYS + images/$IMAGE/files"
FILES=$WORK_DIR/files
rm -rf "$FILES"
mkdir -p "$FILES"
for o in $OVERLAYS; do
    rsync -a "$REPO_DIR/overlays/$o/" "$FILES/"
done
[ -d "$IMAGE_DIR/files" ] && rsync -a "$IMAGE_DIR/files/" "$FILES/"
[ -f "$WORK_DIR/sing-box.bin" ] && install -D -m 0755 "$WORK_DIR/sing-box.bin" "$FILES/usr/bin/sing-box"

echo "==> image"
PACKAGES=$(for l in $LISTS; do cat "$REPO_DIR/lists/$l.txt"; done | cat - "$IMAGE_DIR/packages.txt" \
    | grep -v -E '^\s*(#|$)' | tr '\n' ' ')
# Only the options the image sets: an empty ROOTFS_PARTSIZE= still changes the image build
make -C "$WORK_DIR/$IB_NAME" image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="$FILES" BIN_DIR="$OUT_DIR" \
    ${EXTRA_IMAGE_NAME:+EXTRA_IMAGE_NAME="$EXTRA_IMAGE_NAME"} ${ROOTFS_PARTSIZE:+ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"}
if ls "$OUT_DIR" | grep -F -- "$OPENWRT_VERSION"; then
    echo "the version is still in these file names"
    exit 1
fi

{
    echo "image: $IMAGE"
    echo "openwrt: $OPENWRT_VERSION $TARGET $PROFILE${ROOTFS_PARTSIZE:+, rootfs ${ROOTFS_PARTSIZE} MB}"
    echo "lists: ${LISTS:-none}; overlays: $OVERLAYS"
    echo "packages: $PACKAGES"
    echo "sing-box: $SB_INFO"
    echo "amneziawg: $AWG_INFO"
    echo "repo: $(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
} > "$OUT_DIR/BUILDINFO"
cat "$OUT_DIR/BUILDINFO"
ls -l "$OUT_DIR"
