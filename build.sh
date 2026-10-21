#!/bin/bash
# Build one image with the official OpenWrt ImageBuilder. Usage: ./build.sh <image>, where images/<image>/
# holds image.env, versions.env, packages.txt and optionally files/.
# The image gets: the package lists named in LISTS (lists/<name>.txt) plus its packages.txt, AmneziaWG
# from awg-openwrt when versions.env pins it, and the overlays named in OVERLAYS (overlays/<name>/)
# followed by its own files/. Listed packages that packages/ defines are built with the OpenWrt SDK.
# Runs the same on a workstation and in GitHub Actions (.github/workflows/build.yml).
# Needs: git, curl, rsync, zstd, the ImageBuilder and SDK prerequisites (make, gawk, patch, ...) and, for
# packages in Go, go to bootstrap the SDK's Go (without it the SDK builds its own bootstrap chain).
# Output: .build/<image>/out with the images, manifest, sha256sums and BUILDINFO.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
IMAGE=${1:?usage: $0 <image>}
IMAGE_DIR=$REPO_DIR/images/$IMAGE
[ -f "$IMAGE_DIR/image.env" ] || { echo "no such image: $IMAGE"; exit 1; }
# TARGET, PROFILE, ARCH_PACKAGES, LISTS, OVERLAYS; optional EXTRA_IMAGE_NAME, ROOTFS_PARTSIZE
. "$IMAGE_DIR/image.env"
# OPENWRT_VERSION; optional AWG_TAG + *_SHA256
. "$IMAGE_DIR/versions.env"
WORK_DIR=${WORK_DIR:-$REPO_DIR/.build/$IMAGE}
OUT_DIR=$WORK_DIR/out
rm -rf "$OUT_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR"

PACKAGES=$(for l in $LISTS; do cat "$REPO_DIR/lists/$l.txt"; done | cat - "$IMAGE_DIR/packages.txt" \
    | grep -v -E '^\s*(#|$)' | tr '\n' ' ')
OWN_PACKAGES=
OWN_DIRS=
for p in $PACKAGES; do
    d=$(grep -l -x "define Package/$p" "$REPO_DIR"/packages/*/Makefile 2>/dev/null | head -n 1) || true
    [ -n "$d" ] || continue
    OWN_PACKAGES="$OWN_PACKAGES $p"
    d=$(basename "$(dirname "$d")")
    case " $OWN_DIRS " in *" $d "*) ;; *) OWN_DIRS="$OWN_DIRS $d" ;; esac
done

OWN_APKS=$WORK_DIR/own-packages
rm -rf "$OWN_APKS"
mkdir -p "$OWN_APKS"
if [ -n "$OWN_PACKAGES" ]; then
    echo "==> SDK $OPENWRT_VERSION $TARGET:$OWN_PACKAGES"
    SDK_BASE=https://downloads.openwrt.org/releases/$OPENWRT_VERSION/targets/$TARGET
    SDK_FILE=$(curl -fsSL "$SDK_BASE/sha256sums" | tee "$WORK_DIR/sdk.sha256sums" \
        | sed -n 's/^[0-9a-f]* \*\(openwrt-sdk-.*\.Linux-x86_64\.tar\.zst\)$/\1/p')
    SDK_DIR=$WORK_DIR/${SDK_FILE%.tar.zst}
    if [ ! -d "$SDK_DIR" ]; then
        curl -fsSL -o "$WORK_DIR/$SDK_FILE" "$SDK_BASE/$SDK_FILE"
        (cd "$WORK_DIR" && grep " \*$SDK_FILE\$" sdk.sha256sums | sha256sum -c -)
        tar --zstd -xf "$WORK_DIR/$SDK_FILE" -C "$WORK_DIR"
        rm -f "$WORK_DIR/$SDK_FILE"
    fi
    # The release's pinned packages feed (Go and its build rules) plus packages/ as the feed "own"
    { grep '^src-git packages ' "$SDK_DIR/feeds.conf.default"; echo "src-link own $REPO_DIR/packages"; } > "$SDK_DIR/feeds.conf"
    (cd "$SDK_DIR" && ./scripts/feeds update packages own && ./scripts/feeds install -p own $OWN_PACKAGES)
    {
        echo '# CONFIG_ALL is not set'
        echo '# CONFIG_ALL_KMODS is not set'
        echo '# CONFIG_ALL_NONSHARED is not set'
        for p in $OWN_PACKAGES; do echo "CONFIG_PACKAGE_$p=m"; done
        if command -v go >/dev/null; then
            echo "CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=\"$(go env GOROOT)\""
        fi
    } > "$SDK_DIR/.config"
    make -C "$SDK_DIR" defconfig
    for d in $OWN_DIRS; do
        make -C "$SDK_DIR" "package/$d/compile" -j"$(nproc)" || make -C "$SDK_DIR" "package/$d/compile" -j1 V=s
    done
    LOCAL_INFO=
    for p in $OWN_PACKAGES; do
        f=$(ls "$SDK_DIR/bin/packages/$ARCH_PACKAGES/own/$p"-[0-9]*.apk)
        cp "$f" "$OWN_APKS/"
        LOCAL_INFO="$LOCAL_INFO $(basename "$f" .apk)"
    done
    LOCAL_INFO="${LOCAL_INFO# } ($SDK_FILE)"
else
    LOCAL_INFO=none
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
for p in $(ls "$REPO_DIR"/packages/*/Makefile 2>/dev/null | xargs -r sed -n 's|^define Package/\([^/]*\)$|\1|p'); do
    rm -f "$WORK_DIR/$IB_NAME/packages/$p"-[0-9]*.apk
done
if [ -n "$OWN_PACKAGES" ]; then
    echo "==> own packages into the ImageBuilder's local repository"
    mkdir -p "$WORK_DIR/$IB_NAME/packages"
    cp "$OWN_APKS"/*.apk "$WORK_DIR/$IB_NAME/packages/"
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

echo "==> image"
# Only the options the image sets: an empty ROOTFS_PARTSIZE= still changes the image build
make -C "$WORK_DIR/$IB_NAME" image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="$FILES" BIN_DIR="$OUT_DIR" \
    ${EXTRA_IMAGE_NAME:+EXTRA_IMAGE_NAME="$EXTRA_IMAGE_NAME"} ${ROOTFS_PARTSIZE:+ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"}
if ls "$OUT_DIR" | grep -F -- "$OPENWRT_VERSION"; then
    echo "the version is still in these file names"
    exit 1
fi
# The feeds can carry a package of the same name: the image must have ours
for f in "$OWN_APKS"/*.apk; do
    [ -e "$f" ] || continue
    v=$("$WORK_DIR/$IB_NAME/staging_dir/host/bin/apk" adbdump "$f" | awk '$1 == "name:" {n=$2} $1 == "version:" {print n " - " $2; exit}')
    grep -q -x -F -- "$v" "$OUT_DIR"/*.manifest || { echo "the image doesn't have our $v"; exit 1; }
done

{
    echo "image: $IMAGE"
    echo "openwrt: $OPENWRT_VERSION $TARGET $PROFILE${ROOTFS_PARTSIZE:+, rootfs ${ROOTFS_PARTSIZE} MB}"
    echo "lists: ${LISTS:-none}; overlays: $OVERLAYS"
    echo "packages: $PACKAGES"
    echo "own packages: $LOCAL_INFO"
    echo "amneziawg: $AWG_INFO"
    echo "repo: $(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
} > "$OUT_DIR/BUILDINFO"
cat "$OUT_DIR/BUILDINFO"
ls -l "$OUT_DIR"
