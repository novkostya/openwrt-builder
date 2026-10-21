# etcgit: /etc under git on a running router (files/etcgit), with its login banner, the boot-time
# clean-overlay and what sysupgrade needs to keep the repo.
include $(TOPDIR)/rules.mk

PKG_NAME:=etcgit
# The date of the last change; bump it (or PKG_RELEASE for a second change that day) with every change
PKG_VERSION:=2026.10.21
PKG_RELEASE:=1

PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/etcgit
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Git for /etc, tracking what differs from the image
  DEPENDS:=+git
  PKGARCH:=all
endef

define Package/etcgit/description
  etcgit keeps /etc in a git repo in /root/.etcgit and lists the files that differ from the image
  but aren't tracked. clean-overlay removes files from the overlay that match the image at boot.
endef

# Not installed by the package, so the build lists them in /lib/upgrade/keep.d/etcgit for sysupgrade
define Package/etcgit/conffiles
/root/.etcgit/
/root/.ssh/
/etc/.gitignore
endef

define Build/Compile
endef

define Package/etcgit/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/etcgit $(1)/usr/bin/etcgit
	$(INSTALL_BIN) ./files/clean-overlay-once $(1)/usr/bin/clean-overlay-once
	$(INSTALL_DIR) $(1)/etc/profile.d
	$(INSTALL_DATA) ./files/etcgit-banner.sh $(1)/etc/profile.d/99-etcgit-banner.sh
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/clean-overlay.init $(1)/etc/init.d/clean-overlay
	$(INSTALL_DIR) $(1)/lib/upgrade
	$(INSTALL_DATA) ./files/etcgit-drop-caches.sh $(1)/lib/upgrade/etcgit-drop-caches.sh
endef

$(eval $(call BuildPackage,etcgit))
