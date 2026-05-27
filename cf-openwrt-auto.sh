#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_VERSION="1.3.0"
MIN_CONFIG_VERSION="1.3.0"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "${BASH_SOURCE[0]}")"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/cf-openwrt-auto.conf}"

MODE="passwall"
CONFIG_VERSION=""
WORK_DIR="$SCRIPT_DIR"
IP_COUNT="4"
IP_TYPE="ipv4"
RESULT_FILE="cf_result.txt"
IP_HISTORY_FILE="ip-all.txt"
SPEEDTEST_DN="10"
SPEEDTEST_TLL="40"
SPEEDTEST_PROTOCOL="tcp"
SPEEDTEST_CFCOLO=""
PASSWALL_TARGET_DOMAIN=""
PASSWALL_NAME_SUFFIX=" [CF-{n}]"
OPENCLASH_CONFIG="/etc/openclash/config/config.yaml"
OPENCLASH_TARGET_DOMAIN=""
OPENCLASH_NAME_SUFFIX=" [CF-{n}]"
OPENCLASH_TRANSPORT_FILTER=""
AUTO_UPDATE="true"
SELF_UPDATE_URL="https://raw.githubusercontent.com/hello-yunshu/use-cloudflare-ip/main/cf-openwrt-auto.sh"
VERBOSE="false"

RELEASE_API="${RELEASE_API:-https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest}"
RELEASE_DOWNLOAD_BASE="${RELEASE_DOWNLOAD_BASE:-https://github.com/XIU2/CloudflareSpeedTest/releases/download}"
BINARY_NAME="cfst"

log() {
	[[ "$VERBOSE" == "true" ]] || return 0
	printf '[cloudflare-ip] %s\n' "$*" >&2
}

die() {
	printf '[cloudflare-ip] ERROR: %s\n' "$*" >&2
	exit 1
}

load_config() {
	[[ -f "$CONFIG_FILE" ]] || die "missing config file: $CONFIG_FILE; copy cf-openwrt-auto.conf.example to cf-openwrt-auto.conf"
	# shellcheck source=/dev/null
	. "$CONFIG_FILE"
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

extract_script_version() {
	local file="$1"

	sed -n 's/^SCRIPT_VERSION="\([^"]*\)".*/\1/p' "$file" | head -n 1
}

version_gt() {
	local newer="$1" current="$2" i max newer_part current_part
	local newer_parts=() current_parts=()

	IFS='.' read -r -a newer_parts <<<"$newer"
	IFS='.' read -r -a current_parts <<<"$current"

	max="${#newer_parts[@]}"
	((${#current_parts[@]} > max)) && max="${#current_parts[@]}"

	for ((i = 0; i < max; i++)); do
		newer_part="${newer_parts[$i]:-0}"
		current_part="${current_parts[$i]:-0}"
		[[ "$newer_part" =~ ^[0-9]+$ && "$current_part" =~ ^[0-9]+$ ]] || return 1
		if ((10#$newer_part > 10#$current_part)); then
			return 0
		elif ((10#$newer_part < 10#$current_part)); then
			return 1
		fi
	done

	return 1
}

valid_version() {
	[[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]
}

self_update() {
	local tmp remote_version

	[[ "$AUTO_UPDATE" == "true" ]] || return 0
	[[ -n "$SELF_UPDATE_URL" ]] || return 0
	command -v curl >/dev/null 2>&1 || {
		log "skip self update: curl not found"
		return 0
	}

	tmp="$(mktemp "${TMPDIR:-/tmp}/cf-openwrt-auto.XXXXXX")" || return 0
	if ! curl -fsSL "$SELF_UPDATE_URL" -o "$tmp"; then
		rm -f "$tmp"
		log "skip self update: failed to fetch $SELF_UPDATE_URL"
		return 0
	fi

	remote_version="$(extract_script_version "$tmp")"
	if [[ -z "$remote_version" ]]; then
		rm -f "$tmp"
		log "skip self update: remote script has no version"
		return 0
	fi

	if ! version_gt "$remote_version" "$SCRIPT_VERSION"; then
		rm -f "$tmp"
		return 0
	fi

	if ! bash -n "$tmp"; then
		rm -f "$tmp"
		die "downloaded update has invalid shell syntax"
	fi

	chmod +x "$tmp"
	if ! mv "$tmp" "$SCRIPT_PATH"; then
		rm -f "$tmp"
		die "failed to replace script with version $remote_version"
	fi

	log "updated script from $SCRIPT_VERSION to $remote_version"
	exec "$SCRIPT_PATH" "$@"
}

ensure_jq() {
	if command -v jq >/dev/null 2>&1; then
		return
	fi

	need_cmd opkg
	log "jq not found, installing it with opkg"
	opkg install jq >/dev/null
	need_cmd jq
}

is_valid_ip() {
	local ip="$1"
	if [[ "$ip" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
		local i
		for i in 1 2 3 4; do
			((10#${BASH_REMATCH[$i]} <= 255)) || return 1
		done
		return 0
	fi
	if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$ip" == *:* ]]; then
		return 0
	fi
	return 1
}

verify_ip() {
	local ip="$1" domain="$2" resolve_ip="$ip" curl_proto=()
	[[ -n "$domain" ]] || return 0
	[[ "$ip" == *:* ]] && resolve_ip="[${ip}]"
	case "$IP_TYPE" in
		ipv4) curl_proto=("-4") ;;
		ipv6) curl_proto=("-6") ;;
	esac
	curl -s "${curl_proto[@]}" --max-time 3 --resolve "${domain}:443:${resolve_ip}" "https://${domain}" -o /dev/null 2>/dev/null
}

rotate_history_file() {
	local file="$1" max_lines="${2:-1000}"
	[[ -f "$file" ]] || return 0
	local lines
	lines="$(wc -l < "$file")" || return 0
	((lines > max_lines)) || return 0
	local tmp
	tmp="$(mktemp "${file}.XXXXXX")" || return 0
	tail -n "$max_lines" "$file" > "$tmp" && mv "$tmp" "$file"
}

normalize_mode() {
	case "${1:-$MODE}" in
		passwall|openclash)
			MODE="$1"
			;;
		*)
			die "unsupported mode: ${1:-$MODE}; use passwall or openclash"
			;;
	esac
}

detect_arch_tag() {
	local arch

	arch="$(uname -m)"
	# Keep these tags aligned with CloudflareSpeedTest Linux release assets.
	case "$arch" in
		x86_64|amd64)
			printf 'amd64'
			;;
		i386|i686)
			printf '386'
			;;
		aarch64|arm64)
			printf 'arm64'
			;;
		armv7l|armv7*)
			printf 'armv7'
			;;
		armv6l|armv6*)
			printf 'armv6'
			;;
		armv5*|arm)
			printf 'armv5'
			;;
		mips64el|mips64le)
			printf 'mips64le'
			;;
		mips64)
			printf 'mips64'
			;;
		mipsel|mipsle)
			printf 'mipsle'
			;;
		mips)
			printf 'mips'
			;;
		*)
			die "unsupported architecture: $arch"
			;;
	esac
}

prepare_work_dir() {
	mkdir -p "$WORK_DIR"
	cd "$WORK_DIR" || die "failed to enter work directory: $WORK_DIR"
}

download_speedtest() {
	local tag version old_version asset archive

	need_cmd curl
	need_cmd wget
	need_cmd tar
	ensure_jq

	tag="$(detect_arch_tag)"
	version="$(curl -fsSL "$RELEASE_API" | jq -r '.tag_name // empty')"
	[[ -n "$version" && "$version" != "null" ]] || die "failed to get latest CloudflareSpeedTest version"

	old_version=""
	[[ -f "${BINARY_NAME}_version.txt" ]] && old_version="$(<"${BINARY_NAME}_version.txt")"

	asset="${BINARY_NAME}_linux_${tag}.tar.gz"
	archive="${BINARY_NAME}_linux_${tag}.tar.gz"

	if [[ ! -x "$BINARY_NAME" || "$version" != "$old_version" ]]; then
		log "downloading CloudflareSpeedTest $version for $tag"
		rm -f "$archive"
		wget -q -O "$archive" "${RELEASE_DOWNLOAD_BASE}/${version}/${asset}"
		tar -xzf "$archive" >/dev/null
		[[ -f "$BINARY_NAME" ]] || die "archive did not contain $BINARY_NAME"
		chmod +x "$BINARY_NAME"
		printf '%s\n' "$version" >"${BINARY_NAME}_version.txt"
	fi
}

run_speedtest() {
	local ip all_ips=() verified_ips=() ips=() target_domain cfst_files=() result_files=()
	local cfst_proto_args=()

	case "$SPEEDTEST_PROTOCOL" in
		http)
			cfst_proto_args+=("-httping")
			[[ -n "$SPEEDTEST_CFCOLO" ]] && cfst_proto_args+=("-cfcolo" "$SPEEDTEST_CFCOLO")
			;;
	esac

	case "$IP_TYPE" in
		ipv4) cfst_files=("ip.txt") ;;
		ipv6) cfst_files=("ipv6.txt") ;;
		both) cfst_files=("ip.txt" "ipv6.txt") ;;
	esac

	rm -f "$RESULT_FILE"
	for cfst_file in "${cfst_files[@]}"; do
		local partial_result
		partial_result="$(mktemp "${RESULT_FILE}.XXXXXX")"
		"./${BINARY_NAME}" -f "$cfst_file" -dn "$SPEEDTEST_DN" -tll "$SPEEDTEST_TLL" "${cfst_proto_args[@]}" -o "$partial_result" >/dev/null || true
		result_files+=("$partial_result")
	done

	if ((${#result_files[@]} > 0)); then
		cat "${result_files[@]}" > "$RESULT_FILE"
	fi

	for rf in "${result_files[@]}"; do
		while IFS= read -r ip; do
			[[ -n "$ip" ]] || continue
			if ! is_valid_ip "$ip"; then
				log "skip invalid IP format: $ip"
				continue
			fi
			if [[ "$IP_TYPE" == "ipv4" && "$ip" == *:* ]]; then
				continue
			fi
			if [[ "$IP_TYPE" == "ipv6" && "$ip" != *:* ]]; then
				continue
			fi
			all_ips+=("$ip")
		done < <(awk -F ',' 'NR > 1 && $1 != "" { print $1 }' "$rf")
		rm -f "$rf"
	done

	((${#all_ips[@]} > 0)) || die "no valid IPs found in speedtest results"

	case "$MODE" in
		passwall) target_domain="$PASSWALL_TARGET_DOMAIN" ;;
		openclash) target_domain="$OPENCLASH_TARGET_DOMAIN" ;;
	esac

	if [[ -n "$target_domain" ]]; then
		for ip in "${all_ips[@]}"; do
			((${#verified_ips[@]} >= IP_COUNT)) && break
			if verify_ip "$ip" "$target_domain"; then
				verified_ips+=("$ip")
			else
				log "skip unreachable IP: $ip"
			fi
		done
	fi

	if ((${#verified_ips[@]} > 0)); then
		ips=("${verified_ips[@]}")
	else
		if [[ -n "$target_domain" ]]; then
			log "warning: connectivity check failed for all IPs, using speedtest results directly"
		fi
		ips=("${all_ips[@]:0:IP_COUNT}")
	fi

	if ((${#ips[@]} < IP_COUNT)); then
		log "warning: only ${#ips[@]} usable IP(s) found, filling with first IP to reach $IP_COUNT"
		while ((${#ips[@]} < IP_COUNT)); do
			ips+=("${ips[0]}")
		done
	fi

	rotate_history_file "$IP_HISTORY_FILE"
	printf '%s\n' "${ips[@]:0:IP_COUNT}" >>"$IP_HISTORY_FILE"
	FAST_IPS=("${ips[@]:0:IP_COUNT}")
	log "selected IPs: ${FAST_IPS[*]}"
}

restart_service() {
	local service="$1"

	[[ -x "/etc/init.d/${service}" ]] || die "service init script not found: $service"
	"/etc/init.d/${service}" restart >/dev/null || die "failed to restart $service"
}

update_passwall() {
	local sections=() section idx ip old_remarks new_remarks

	need_cmd uci
	while IFS= read -r section; do
		sections+=("$section")
	done < <(find_passwall_sections)
	((${#sections[@]} > 0)) || die "no PassWall nodes matched address: $PASSWALL_TARGET_DOMAIN"

	idx=0
	for section in "${sections[@]}"; do
		ip="${FAST_IPS[$((idx % IP_COUNT))]}"
		uci set "passwall.${section}.address=${ip}" >/dev/null || die "failed to update passwall.${section}.address"
		if [[ -n "$PASSWALL_NAME_SUFFIX" ]]; then
			old_remarks="$(uci_unquote "$(uci get "passwall.${section}.remarks" 2>/dev/null || printf '')")"
			if [[ -n "$old_remarks" ]]; then
				new_remarks="${old_remarks}$(expand_suffix "$PASSWALL_NAME_SUFFIX" "$((idx + 1))" "$ip")"
				uci set "passwall.${section}.remarks=${new_remarks}" >/dev/null || die "failed to update passwall.${section}.remarks"
				log "PassWall ${section}.remarks '${old_remarks}' -> '${new_remarks}'; address -> ${ip}"
			else
				log "PassWall ${section}.address -> ${ip}"
			fi
		else
			log "PassWall ${section}.address -> ${ip}"
		fi
		idx=$((idx + 1))
	done

	uci commit passwall >/dev/null || die "failed to commit passwall"
	restart_service passwall
}

uci_unquote() {
	local value="$1"

	if [[ "$value" == \'*\' && "$value" == *\' ]]; then
		value="${value:1:${#value}-2}"
	elif [[ "$value" == \"*\" && "$value" == *\" ]]; then
		value="${value:1:${#value}-2}"
	fi
	printf '%s' "$value"
}

find_passwall_sections() {
	local line key value section

	while IFS= read -r line; do
		[[ "$line" == passwall.*.address=* ]] || continue
		key="${line%%=*}"
		value="$(uci_unquote "${line#*=}")"
		[[ "$value" == "$PASSWALL_TARGET_DOMAIN" ]] || continue

		section="${key#passwall.}"
		section="${section%.address}"
		[[ -n "$section" ]] && printf '%s\n' "$section"
	done < <(uci show passwall)
}

trim_scalar() {
	local value="$1"

	value="${value%%#*}"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	if [[ "$value" == \"*\" && "$value" == *\" ]]; then
		value="${value:1:${#value}-2}"
	elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
		value="${value:1:${#value}-2}"
	fi
	printf '%s' "$value"
}

lower() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

openclash_protocol_supported() {
	local type="$1" tls="$2" network="$3"

	type="$(lower "$type")"
	tls="$(lower "$tls")"
	network="$(lower "$network")"

	case "$type" in
		vless|vmess|trojan)
			[[ "$tls" == "true" || "$network" == "ws" || "$network" == "xhttp" || "$network" == "grpc" || "$network" == "h2" || "$network" == "http" ]]
			;;
		*)
			return 1
			;;
	esac
}

line_indent() {
	local line="$1"
	printf '%s' "${line%%[![:space:]]*}"
}

write_block_original() {
	local line

	for line in "${BLOCK_LINES[@]}"; do
		printf '%s\n' "$line" >>"$TMP_CONFIG"
	done
}

expand_suffix() {
	local suffix="$1" seq="$2" ip_addr="$3"
	suffix="${suffix//\{n\}/${seq}}"
	suffix="${suffix//\{ip\}/${ip_addr}}"
	printf '%s' "$suffix"
}

process_openclash_block() {
	local line idx
	local name="" type="" server="" tls="" network=""
	local name_idx=-1 server_idx=-1 tls_idx=-1 network_idx=-1 servername_idx=-1 ws_opts_idx=-1 xhttp_opts_idx=-1 headers_idx=-1 host_idx=-1
	local prop_indent="" ip new_name
	local updated=false
	local normalized_network opts_idx opt_key

	((${#BLOCK_LINES[@]} > 0)) || return

	for idx in "${!BLOCK_LINES[@]}"; do
		line="${BLOCK_LINES[$idx]}"
		if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+name:[[:space:]]*(.+)$ ]]; then
			name="$(trim_scalar "${BASH_REMATCH[1]}")"
			name_idx="$idx"
		elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]*(.+)$ ]]; then
			type="$(trim_scalar "${BASH_REMATCH[1]}")"
			[[ -n "$prop_indent" ]] || prop_indent="$(line_indent "$line")"
		elif [[ "$line" =~ ^[[:space:]]*server:[[:space:]]*(.+)$ ]]; then
			server="$(trim_scalar "${BASH_REMATCH[1]}")"
			server_idx="$idx"
			[[ -n "$prop_indent" ]] || prop_indent="$(line_indent "$line")"
		elif [[ "$line" =~ ^[[:space:]]*tls:[[:space:]]*(.+)$ ]]; then
			tls="$(trim_scalar "${BASH_REMATCH[1]}")"
			tls_idx="$idx"
			[[ -n "$prop_indent" ]] || prop_indent="$(line_indent "$line")"
		elif [[ "$line" =~ ^[[:space:]]*network:[[:space:]]*(.+)$ ]]; then
			network="$(trim_scalar "${BASH_REMATCH[1]}")"
			network_idx="$idx"
			[[ -n "$prop_indent" ]] || prop_indent="$(line_indent "$line")"
		elif [[ "$line" =~ ^[[:space:]]*servername:[[:space:]]*(.*)$ ]]; then
			servername_idx="$idx"
			[[ -n "$prop_indent" ]] || prop_indent="$(line_indent "$line")"
		elif [[ "$line" =~ ^[[:space:]]*ws-opts:[[:space:]]*$ ]]; then
			ws_opts_idx="$idx"
		elif [[ "$line" =~ ^[[:space:]]*xhttp-opts:[[:space:]]*$ ]]; then
			xhttp_opts_idx="$idx"
		elif [[ "$line" =~ ^[[:space:]]*headers:[[:space:]]*$ ]]; then
			headers_idx="$idx"
		elif [[ "$line" =~ ^[[:space:]]*Host:[[:space:]]*(.*)$ ]]; then
			host_idx="$idx"
		fi
	done

	if [[ "$server" != "$OPENCLASH_TARGET_DOMAIN" ]]; then
		write_block_original
		return
	fi

	if ! openclash_protocol_supported "$type" "$tls" "$network"; then
		log "skip OpenClash proxy '${name:-unknown}': type=${type:-unknown}, tls=${tls:-false}, network=${network:-unknown} is not supported"
		write_block_original
		return
	fi

	if [[ -n "$OPENCLASH_TRANSPORT_FILTER" ]]; then
		local normalized_filter_net
		normalized_filter_net="$(lower "${network:-}")"
		if [[ -z "$normalized_filter_net" || ",${OPENCLASH_TRANSPORT_FILTER}," != *",${normalized_filter_net},"* ]]; then
			log "skip OpenClash proxy '${name:-unknown}': network=${network:-unknown} not in OPENCLASH_TRANSPORT_FILTER (${OPENCLASH_TRANSPORT_FILTER})"
			write_block_original
			return
		fi
	fi

	ip="${FAST_IPS[$((OPENCLASH_UPDATED % IP_COUNT))]}"
	OPENCLASH_UPDATED=$((OPENCLASH_UPDATED + 1))

	if [[ -n "$OPENCLASH_NAME_SUFFIX" && -n "$name" ]]; then
		new_name="${name}$(expand_suffix "$OPENCLASH_NAME_SUFFIX" "$OPENCLASH_UPDATED" "$ip")"
	else
		new_name="$name"
	fi

	for idx in "${!BLOCK_LINES[@]}"; do
		line="${BLOCK_LINES[$idx]}"
		if ((idx == name_idx)) && [[ "$new_name" != "$name" ]]; then
			printf '%s- name: %s\n' "$(line_indent "$line")" "$new_name" >>"$TMP_CONFIG"
		elif ((idx == server_idx)); then
			printf '%sserver: %s\n' "$prop_indent" "$ip" >>"$TMP_CONFIG"
			updated=true
		elif ((idx == servername_idx)); then
			printf '%sservername: %s\n' "$prop_indent" "$OPENCLASH_TARGET_DOMAIN" >>"$TMP_CONFIG"
		elif ((idx == host_idx)); then
			printf '%sHost: %s\n' "$(line_indent "$line")" "$OPENCLASH_TARGET_DOMAIN" >>"$TMP_CONFIG"
		else
			printf '%s\n' "$line" >>"$TMP_CONFIG"
		fi

		if ((idx == tls_idx && servername_idx < 0)) && [[ "$(lower "$tls")" == "true" ]]; then
			printf '%sservername: %s\n' "$prop_indent" "$OPENCLASH_TARGET_DOMAIN" >>"$TMP_CONFIG"
		fi

		normalized_network="$(lower "$network")"
		if [[ "$normalized_network" == "ws" || "$normalized_network" == "xhttp" ]]; then
			if [[ "$normalized_network" == "xhttp" ]]; then
				opts_idx="$xhttp_opts_idx"
				opt_key="xhttp-opts"
			else
				opts_idx="$ws_opts_idx"
				opt_key="ws-opts"
			fi

			if ((idx == headers_idx && host_idx < 0)); then
				printf '%sHost: %s\n' "${prop_indent}    " "$OPENCLASH_TARGET_DOMAIN" >>"$TMP_CONFIG"
			elif ((idx == opts_idx && headers_idx < 0)); then
				printf '%sheaders:\n' "${prop_indent}  " >>"$TMP_CONFIG"
				printf '%sHost: %s\n' "${prop_indent}    " "$OPENCLASH_TARGET_DOMAIN" >>"$TMP_CONFIG"
			elif ((idx == network_idx && opts_idx < 0)); then
				{
					printf '%s%s:\n' "$prop_indent" "$opt_key"
					printf '%sheaders:\n' "${prop_indent}  "
					printf '%sHost: %s\n' "${prop_indent}    " "$OPENCLASH_TARGET_DOMAIN"
				} >>"$TMP_CONFIG"
			fi
		fi
	done

	if [[ "$updated" == "true" ]]; then
		if [[ "$new_name" != "$name" ]]; then
			log "OpenClash proxy '${name:-unknown}' -> '${new_name}'; server -> ${ip}; domain kept as ${OPENCLASH_TARGET_DOMAIN}"
		else
			log "OpenClash proxy '${name:-unknown}' server -> ${ip}; domain kept as ${OPENCLASH_TARGET_DOMAIN}"
		fi
	fi
}

update_openclash() {
	local line backup

	[[ -f "$OPENCLASH_CONFIG" ]] || die "OpenClash config not found: $OPENCLASH_CONFIG"
	[[ -n "$OPENCLASH_TARGET_DOMAIN" ]] || die "OPENCLASH_TARGET_DOMAIN is empty"

	backup="${OPENCLASH_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
	cp "$OPENCLASH_CONFIG" "$backup"
	TMP_CONFIG="$(mktemp "${OPENCLASH_CONFIG}.tmp.XXXXXX")"
	OPENCLASH_UPDATED=0
	BLOCK_LINES=()

	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+name:[[:space:]]*.+$ && ${#BLOCK_LINES[@]} -gt 0 ]]; then
			process_openclash_block
			BLOCK_LINES=("$line")
		else
			BLOCK_LINES+=("$line")
		fi
	done <"$OPENCLASH_CONFIG"
	process_openclash_block

	((OPENCLASH_UPDATED > 0)) || {
		rm -f "$TMP_CONFIG"
		die "no supported OpenClash proxy matched server: $OPENCLASH_TARGET_DOMAIN"
	}

	mv "$TMP_CONFIG" "$OPENCLASH_CONFIG"
	log "OpenClash config updated, backup saved to $backup"

	restart_service openclash
}

usage() {
	cat <<'EOF'
Usage:
  cf-openwrt-auto.sh

Config:
  Copy cf-openwrt-auto.conf.example to cf-openwrt-auto.conf in the same
  directory as this script, then edit that config file.
EOF
}

validate_config() {
	[[ -n "$WORK_DIR" ]] || WORK_DIR="$SCRIPT_DIR"
	[[ -n "$CONFIG_VERSION" ]] || die "CONFIG_VERSION is missing; copy cf-openwrt-auto.conf.example to refresh your config"
	valid_version "$CONFIG_VERSION" || die "CONFIG_VERSION has invalid format: $CONFIG_VERSION"
	if version_gt "$MIN_CONFIG_VERSION" "$CONFIG_VERSION"; then
		die "config version $CONFIG_VERSION is lower than required $MIN_CONFIG_VERSION; update cf-openwrt-auto.conf from cf-openwrt-auto.conf.example"
	fi
	[[ "$MODE" == "passwall" || "$MODE" == "openclash" ]] || die "unsupported mode: $MODE; use passwall or openclash"
	[[ "$IP_COUNT" =~ ^[1-9][0-9]*$ ]] || die "IP_COUNT must be a positive integer"
	[[ "$IP_TYPE" == "ipv4" || "$IP_TYPE" == "ipv6" || "$IP_TYPE" == "both" ]] || die "IP_TYPE must be ipv4, ipv6, or both"
	[[ "$SPEEDTEST_PROTOCOL" == "tcp" || "$SPEEDTEST_PROTOCOL" == "http" ]] || die "SPEEDTEST_PROTOCOL must be tcp or http"
	[[ "$AUTO_UPDATE" == "true" || "$AUTO_UPDATE" == "false" ]] || die "AUTO_UPDATE must be true or false"

	case "$MODE" in
		passwall)
			[[ -n "$PASSWALL_TARGET_DOMAIN" ]] || die "PASSWALL_TARGET_DOMAIN is empty"
			;;
		openclash)
			[[ -n "$OPENCLASH_CONFIG" ]] || die "OPENCLASH_CONFIG is empty"
			[[ -n "$OPENCLASH_TARGET_DOMAIN" ]] || die "OPENCLASH_TARGET_DOMAIN is empty"
			[[ -f "$OPENCLASH_CONFIG" ]] || die "OpenClash config not found: $OPENCLASH_CONFIG"
			if [[ -n "$OPENCLASH_TRANSPORT_FILTER" ]]; then
				local _item _items
				IFS=',' read -r -a _items <<<"$OPENCLASH_TRANSPORT_FILTER"
				for _item in "${_items[@]}"; do
					[[ "$_item" == "ws" || "$_item" == "grpc" || "$_item" == "xhttp" || "$_item" == "h2" || "$_item" == "http" ]] || die "OPENCLASH_TRANSPORT_FILTER contains invalid value: $_item; allowed: ws, grpc, xhttp, h2, http"
				done
			fi
			;;
	esac
}

main() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		usage
		return 0
	fi
	(($# == 0)) || die "unexpected argument: $1; edit MODE in cf-openwrt-auto.conf"

	load_config
	normalize_mode "$MODE"
	validate_config
	self_update "$@"
	need_cmd awk
	need_cmd sed
	need_cmd tr
	prepare_work_dir
	download_speedtest
	run_speedtest

	case "$MODE" in
		passwall)
			update_passwall
			;;
		openclash)
			update_openclash
			;;
	esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
