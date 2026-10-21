# openwrt-builder

How I build and run the OpenWrt devices in my home network. It's a personal setup, public in case the
approach is useful to someone; no support implied.

## The idea

A router that has been tweaked by hand for years can't be rebuilt when it dies. So each device here is two
things that can be recreated at any time:

- an image, built by this repo from pinned versions with the official OpenWrt ImageBuilder;
- its `/etc`, kept in a private git repo per device. `etcgit` versions it live on the device: it tracks
  only the files you add, and lists the ones that differ from the image but aren't tracked.

Rebuilding a device means flashing the image, importing its `/etc` and rebooting.

## Layout

- `images/<name>/` is one device. `image.env` says what the device is and which shared lists and
  overlays it uses, `versions.env` pins OpenWrt, sing-box and AmneziaWG with their checksums,
  `packages.txt` adds packages (or removes defaults with `-name`), and `files/` holds files for this
  image only.
- `lists/` and `overlays/` hold packages and files shared by several images.
- `build.sh` is the whole build.

## Building

```sh
./build.sh <name>
```

It needs the ImageBuilder's prerequisites, and Go for an image that builds sing-box from source. The
images end up in `.build/<name>/out`.

The Build image workflow runs the same script on GitHub Actions and publishes each build as a release;
`.github/workflows/build.yml` describes the tags and how many are kept.

## Installing

- Upgrades use `sysupgrade`, keeping settings. Afterwards `etcgit status` shows what needs attention:
  files the upgrade didn't keep appear as deleted or changed, and stale defaults from the old image as
  differing from the image but not tracked.
- A fresh install boots with OpenWrt's defaults, minus the DHCP server and router advertisements, so it
  can sit on a live network until its `/etc` is imported
  ([99-safe-first-boot](overlays/base/etc/uci-defaults/99-safe-first-boot)).

## Credits

Built on [OpenWrt](https://openwrt.org) and its ImageBuilder, with AmneziaWG from
[awg-openwrt](https://github.com/Slava-Shchipunov/awg-openwrt) and
[sing-box](https://github.com/SagerNet/sing-box). It started as a fork of
[P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt).

## License

[MIT](LICENSE)
