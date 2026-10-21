# sing-box, from net/sing-box in openwrt/packages: the upstream version, an init script that also takes
# a YAML conffile (converted with yq), and fixed build tags instead of menuconfig options.
include $(TOPDIR)/rules.mk

PKG_NAME:=sing-box
PKG_VERSION:=1.14.3
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/SagerNet/sing-box/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=9a8e3712a5f611ad95f1d16874bbdcdffbd3b8eed16dae2d71ce7042a33c3386

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/sagernet/sing-box
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/sing-box

# as in upstream's release/LDFLAGS
GO_PKG_LDFLAGS:=-checklinkname=0
GO_PKG_LDFLAGS_X:=$(GO_PKG)/constant.Version=$(PKG_VERSION) runtime.godebugDefault=multipathtcp=0,tlssha1=1

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/sing-box-default
  TITLE:=The universal proxy platform
  SECTION:=net
  CATEGORY:=Network
  URL:=https://sing-box.sagernet.org
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +kmod-inet-diag +kmod-tun
  USERID:=sing-box=5566:sing-box=5566
endef

define Package/sing-box
  $(Package/sing-box-default)
  TITLE+= (full)
  VARIANT:=full
  DEFAULT_VARIANT:=1
endef

define Package/sing-box/description
  Sing-box is a universal proxy platform. This build has the tags of upstream's release builds
  except with_naive_outbound, which needs cgo and cronet.
endef

define Package/sing-box-quic
  $(Package/sing-box-default)
  TITLE+= (QUIC only)
  PROVIDES:=sing-box
  VARIANT:=quic
  CONFLICTS:=sing-box
endef

define Package/sing-box-quic/description
  Sing-box with QUIC (Hysteria2, TUIC) and nothing else optional, for small flash.
endef

# full: upstream's release/DEFAULT_BUILD_TAGS minus with_naive_outbound
ifeq ($(BUILD_VARIANT),quic)
GO_PKG_TAGS:=with_quic,badlinkname,tfogo_checklinkname0
else
GO_PKG_TAGS:=with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale,with_ccm,with_ocm,with_cloudflared,with_usbip,with_openvpn,with_openconnect,badlinkname,tfogo_checklinkname0
endif

define Package/sing-box/conffiles
/etc/config/sing-box
/etc/sing-box/
endef

Package/sing-box-quic/conffiles=$(Package/sing-box/conffiles)

define Package/sing-box/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/sing-box $(1)/usr/bin/sing-box

	$(INSTALL_DIR) $(1)/etc/sing-box
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/release/config/config.json $(1)/etc/sing-box

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) ./files/sing-box.conf $(1)/etc/config/sing-box
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/sing-box.init $(1)/etc/init.d/sing-box
endef

Package/sing-box-quic/install=$(Package/sing-box/install)

$(eval $(call BuildPackage,sing-box))
$(eval $(call BuildPackage,sing-box-quic))
