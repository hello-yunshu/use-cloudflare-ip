#!/usr/bin/env bash
# shellcheck shell=bash

cfip_rill_asset_arch() {
    case "$(uname -m 2>/dev/null || true)" in
      x86_64|amd64) printf x86_64 ;; aarch64|arm64) printf aarch64 ;; riscv64*) printf riscv64 ;;
      armv7l|armv7*) printf armv7 ;; i386|i486|i586|i686) printf i686 ;; *) return 1 ;;
    esac
}

cfip_rill_download_url() {
    local url="$1"
    [[ -n "${CFIP_GITHUB_MIRROR:-}" ]] && printf '%s%s' "$CFIP_GITHUB_MIRROR" "$url" || printf '%s' "$url"
}

cfip_rill_install() (
    local arch version release tag asset base tmpdir sums_url asset_url expected actual probe_state staged
    arch="$(cfip_rill_asset_arch)" || { cfip_json_error "Rill adapter is not published for this architecture"; return 2; }
    version="$SCRIPT_VERSION"; release="${PACKAGE_RELEASE:-1}"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || { cfip_json_error "package version is not a release version"; return 2; }
    [[ "$release" =~ ^[0-9]+$ ]] || release=1
    tag="v${version}-${release}"; asset="cf-ip-rill-${version}-linux-${arch}-musl"
    base="https://github.com/hello-yunshu/luci-app-cloudflare-ip/releases/download/${tag}"
    sums_url="$(cfip_rill_download_url "${base}/sha256sums.txt")"; asset_url="$(cfip_rill_download_url "${base}/${asset}")"
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cfip-rill-install.XXXXXX")" || return 1
    trap 'rm -rf "$tmpdir"' EXIT
    curl -fL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 "$sums_url" -o "$tmpdir/sha256sums.txt" >/dev/null 2>&1 || { cfip_json_error "failed to download release checksums"; return 3; }
    curl -fL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 "$asset_url" -o "$tmpdir/$asset" >/dev/null 2>&1 || { cfip_json_error "failed to download Rill adapter asset"; return 3; }
    expected="$(awk -v n="$asset" '$2==n || $2=="./"n {print $1; exit}' "$tmpdir/sha256sums.txt")"
    [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || { cfip_json_error "release checksum entry missing"; return 4; }
    actual="$(sha256sum "$tmpdir/$asset" | awk '{print $1}')"; actual="$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')"; expected="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"; [[ "$actual" == "$expected" ]] || { cfip_json_error "Rill adapter checksum mismatch"; return 4; }
    chmod 755 "$tmpdir/$asset"; probe_state="$tmpdir/probe-state.json"
    "$tmpdir/$asset" status --state "$probe_state" >"$tmpdir/status.json" 2>/dev/null || { cfip_json_error "downloaded Rill adapter did not execute on this device"; return 5; }
    jq -e '.success==true and .rillVersion=="1.5.3" and .adapterProtocolVersion==1' "$tmpdir/status.json" >/dev/null 2>&1 || { cfip_json_error "Rill adapter identity/contract mismatch"; return 5; }
    mkdir -p "${CFIP_RILL_ADAPTER%/*}"; staged="${CFIP_RILL_ADAPTER}.new.$$"
    cp "$tmpdir/$asset" "$staged" && chmod 755 "$staged" && mv "$staged" "$CFIP_RILL_ADAPTER" || { rm -f "$staged"; cfip_json_error "failed to install Rill adapter"; return 6; }
    jq -cn --arg asset "$asset" --arg arch "$arch" '{success:true,installed:true,asset:$asset,arch:$arch,rillVersion:"1.5.3"}'
)

cfip_rill_remove() {
    rm -f "$CFIP_RILL_ADAPTER" || { cfip_json_error "failed to remove Rill adapter"; return 1; }
    jq -cn '{success:true,removed:true,statePreserved:true}'
}
