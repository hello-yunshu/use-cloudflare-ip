include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-cloudflare-ip
PKG_VERSION:=1.5.2
PKG_RELEASE:=1

PKG_MAINTAINER:=yunshu
PKG_LICENSE:=GPL-3.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-cloudflare-ip
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Cloudflare IP - Optimize Cloudflare IPs for PassWall/OpenClash on OpenWrt
  DEPENDS:=+luci-base +bash +curl +tar +jq +ca-bundle +ca-certificates
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
	sed -i 's/^SCRIPT_VERSION="[^"]*"/SCRIPT_VERSION="$(PKG_VERSION)"/' $(PKG_BUILD_DIR)/root/usr/bin/cf-ip-auto
	sed -i 's/@PKG_VERSION@/$(PKG_VERSION)/g' $(PKG_BUILD_DIR)/root/usr/libexec/rpcd/cf_ip
endef

define Package/luci-app-cloudflare-ip/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/cf-ip-auto $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/root/etc/config/cf_ip $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/etc/init.d/cf_ip $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/libexec/rpcd/cf_ip $(1)/usr/libexec/rpcd/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/cloudflare-ip
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/cloudflare-ip/*.js $(1)/www/luci-static/resources/view/cloudflare-ip/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/cloudflare-ip
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/cloudflare-ip/*.js $(PKG_BUILD_DIR)/htdocs/luci-static/resources/cloudflare-ip/*.css $(1)/www/luci-static/resources/cloudflare-ip/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/luci/menu.d/luci-app-cloudflare-ip.json $(1)/usr/share/luci/menu.d/
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
	exit 0; \
}
endef

define Package/luci-app-cloudflare-ip/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { \
	/etc/init.d/cf_ip stop 2>/dev/null; \
	/etc/init.d/cf_ip disable 2>/dev/null; \
	rm -f /tmp/luci-indexcache.*; \
	rm -rf /tmp/luci-modulecache/; \
	exit 0; \
}
endef

$(eval $(call BuildPackage,luci-app-cloudflare-ip))
