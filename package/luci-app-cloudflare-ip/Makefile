include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-cloudflare-ip
PKG_VERSION:=2.6.0
PKG_RELEASE:=2

PKG_MAINTAINER:=yunshu
PKG_LICENSE:=GPL-3.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-cloudflare-ip
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Cloudflare IP - Safe endpoint orchestration for PassWall/OpenClash on OpenWrt
  DEPENDS:=+luci-base +bash +curl +tar +jq +ca-bundle +ca-certificates +uhttpd
  PKGARCH:=all
endef

define Package/luci-app-cloudflare-ip/description
OpenWrt plugin for automatically selecting the fastest Cloudflare IPs
using CloudflareSpeedTest, and updating PassWall or OpenClash proxy
configurations. Includes LuCI web interface with Chinese and English
translations.
endef

define Package/luci-app-cloudflare-ip/conffiles
/etc/config/cf_ip
/etc/cf_ip
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./root ./htdocs $(PKG_BUILD_DIR)/
endef

define Build/Compile
	mkdir -p $(PKG_BUILD_DIR)/lmo; \
	for po_dir in $(CURDIR)/po/*/; do \
		[ -d "$$$$po_dir" ] || continue; \
		lang=$$$$(basename "$$$$po_dir"); \
		[ "$$$$lang" = "templates" ] && continue; \
		[ -f "$$$$po_dir/cloudflare-ip.po" ] || continue; \
		lmo_lang="$$$$lang"; \
		[ "$$$$lmo_lang" = "zh_Hans" ] && lmo_lang="zh-cn"; \
		if [ -x "$(STAGING_DIR_HOSTPKG)/bin/po2lmo" ]; then \
			"$(STAGING_DIR_HOSTPKG)/bin/po2lmo" "$$$$po_dir/cloudflare-ip.po" "$(PKG_BUILD_DIR)/lmo/cloudflare-ip.$$$$lmo_lang.lmo"; \
		fi; \
	done; \
	sed -i 's/@PKG_VERSION@/$(PKG_VERSION)/g; s/@PKG_RELEASE@/$(PKG_RELEASE)/g' $(PKG_BUILD_DIR)/root/usr/bin/cf-ip-auto-v2
	sed -i 's/@PKG_VERSION@/$(PKG_VERSION)/g' $(PKG_BUILD_DIR)/root/usr/bin/cf-ip-auto-legacy
	sed -i 's/@PKG_VERSION@/$(PKG_VERSION)/g' $(PKG_BUILD_DIR)/root/usr/bin/cf-ip-auto
	sed -i 's/@PKG_VERSION@/$(PKG_VERSION)/g' $(PKG_BUILD_DIR)/root/usr/libexec/rpcd/cf_ip
	sed -i 's/@PKG_VERSION@/$(PKG_VERSION)/g' $(PKG_BUILD_DIR)/htdocs/luci-static/resources/cloudflare-ip/utils.js
endef

define Package/luci-app-cloudflare-ip/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/cf-ip-auto-v2 $(1)/usr/bin/cf-ip-auto
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/cf-ip-auto-legacy $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/root/etc/config/cf_ip $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/etc/init.d/cf_ip $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/libexec/rpcd/cf_ip $(1)/usr/libexec/rpcd/
	$(INSTALL_DIR) $(1)/usr/libexec/cf-ip
	for script in common.sh config.sh status.sh source.sh scheduler.sh cfst.sh observe.sh adaptive-measurement.sh context-policy.sh transaction.sh openclash-transform.sh openclash-readback.sh publisher.sh rill-disabled.sh reuse.sh operational-health.sh; do \
		$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/libexec/cf-ip/$$$$script $(1)/usr/libexec/cf-ip/; \
	done
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/etc/init.d/cf_ip_publisher $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/cloudflare-ip
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/cloudflare-ip/*.js $(1)/www/luci-static/resources/view/cloudflare-ip/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/cloudflare-ip
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/cloudflare-ip/*.js $(PKG_BUILD_DIR)/htdocs/luci-static/resources/cloudflare-ip/*.css $(1)/www/luci-static/resources/cloudflare-ip/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/luci/menu.d/luci-app-cloudflare-ip.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/lib/lua/luci/controller/cloudflare-ip.lua $(1)/usr/lib/lua/luci/controller/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/rpcd/acl.d/luci-app-cloudflare-ip.json $(1)/usr/share/rpcd/acl.d/
	if [ -n "$$$$(ls $(PKG_BUILD_DIR)/lmo/*.lmo 2>/dev/null)" ]; then \
		$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n; \
		$(INSTALL_DATA) $(PKG_BUILD_DIR)/lmo/*.lmo $(1)/usr/lib/lua/luci/i18n/; \
	fi
endef

define Package/luci-app-cloudflare-ip/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { \
	[ -x /etc/init.d/cf_ip ] && /etc/init.d/cf_ip enable 2>/dev/null; \
	uci -q get luci.languages.zh_cn >/dev/null || uci -q set luci.languages.zh_cn='简体中文'; \
	uci -q commit luci; \
	rm -f /tmp/luci-indexcache.*; \
	rm -rf /tmp/luci-modulecache/; \
	/etc/init.d/rpcd reload 2>/dev/null; \
	if [ -f /tmp/cf_ip/status.json ] && [ ! -f /etc/cf_ip/status.json ]; then \
		mkdir -p /etc/cf_ip; \
		mv /tmp/cf_ip/status.json /etc/cf_ip/status.json; \
		[ -f /tmp/cf_ip/env_cache.json ] && mv /tmp/cf_ip/env_cache.json /etc/cf_ip/env_cache.json; \
	fi; \
	exit 0; \
}
endef

define Package/luci-app-cloudflare-ip/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { \
	/etc/init.d/cf_ip stop 2>/dev/null; \
	/etc/init.d/cf_ip_publisher stop 2>/dev/null; \
	/etc/init.d/cf_ip disable 2>/dev/null; \
	rm -f /tmp/luci-indexcache.*; \
	rm -rf /tmp/luci-modulecache/; \
	exit 0; \
}
endef

$(eval $(call BuildPackage,luci-app-cloudflare-ip))

define Package/luci-app-cloudflare-ip-rill
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Cloudflare IP optional Rill contextual learner integration
  DEPENDS:=+luci-app-cloudflare-ip +rill-runtime-preview
  PKGARCH:=all
endef

define Package/luci-app-cloudflare-ip-rill/description
Optional consumer-owned mapping from Cloudflare IP observations to the exact
qualified Rill Preview contextual learner. The base Cloudflare IP package remains fully
functional and authoritative when this package is absent.
endef

define Package/luci-app-cloudflare-ip-rill/install
	$(INSTALL_DIR) $(1)/usr/libexec/cf-ip
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/libexec/cf-ip/rill.sh $(1)/usr/libexec/cf-ip/
	$(INSTALL_DIR) $(1)/usr/share/cf-ip
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/cf-ip/rill-feature-schema-v2.json $(1)/usr/share/cf-ip/
endef

$(eval $(call BuildPackage,luci-app-cloudflare-ip-rill))
