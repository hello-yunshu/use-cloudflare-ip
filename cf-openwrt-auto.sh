#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_VERSION="1.5.1"
MIN_CONFIG_VERSION="1.3.0"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "${BASH_SOURCE[0]}")"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/cf-openwrt-auto.conf}"

MODE="passwall"
CONFIG_VERSION=""
WORK_DIR="$SCRIPT_DIR"
CFST_DIR=""
IP_COUNT="4"
IP_TYPE="ipv4"
RESULT_FILE=""
IP_HISTORY_FILE=""
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
OPENCLASH_BACKUP_COUNT="3"
AUTO_UPDATE="true"
SELF_UPDATE_URL="https://raw.githubusercontent.com/hello-yunshu/use-cloudflare-ip/main/cf-openwrt-auto.sh"
DOWNLOAD_RETRIES="3"
DOWNLOAD_RETRY_DELAY="5"
VERBOSE="false"
CLI_VERBOSE="false"
GITHUB_MIRROR=""
STOP_SERVICE_BEFORE_SPEEDTEST="true"
STARTUP_DELAY=""
_STOPPED_SERVICE=""
_OPENCLASH_ENABLE_SAVED=""

declare -A OPENCLASH_TEMPLATE_TEXT=()
declare -A OPENCLASH_TEMPLATE_BASE_NAME=()
declare -A OPENCLASH_SEEN=()
OPENCLASH_MATCHED_DOMAIN=""

RELEASE_API="${RELEASE_API:-https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest}"
RELEASE_DOWNLOAD_BASE="${RELEASE_DOWNLOAD_BASE:-https://github.com/XIU2/CloudflareSpeedTest/releases/download}"
BINARY_NAME="cfst"
GITHUB_USER_AGENT="cf-openwrt-auto/${SCRIPT_VERSION}"

log() {
	[[ "$VERBOSE" == "true" ]] || return 0
	printf '[cloudflare-ip] %s\n' "$*" >&2
}

die() {
	printf '[cloudflare-ip] ERROR: %s\n' "$*" >&2
	exit 1
}

curl_fetch() {
	local output="$1" url="$2" attempt

	for ((attempt = 1; attempt <= DOWNLOAD_RETRIES; attempt++)); do
		if curl -fsSL --connect-timeout 30 --max-time 600 -A "$GITHUB_USER_AGENT" -o "$output" "$url"; then
			return 0
		fi
		((attempt < DOWNLOAD_RETRIES)) || break
		log "download failed, retrying in ${DOWNLOAD_RETRY_DELAY}s (${attempt}/${DOWNLOAD_RETRIES}): $url"
		sleep "$DOWNLOAD_RETRY_DELAY"
	done

	return 1
}

mirror_url() {
	if [[ -n "$GITHUB_MIRROR" && "$1" == https://*github.com/* ]]; then
		printf '%s%s\n' "$GITHUB_MIRROR" "$1"
	else
		printf '%s\n' "$1"
	fi
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
	log "checking script update: $SELF_UPDATE_URL"
	if ! curl_fetch "$tmp" "$(mirror_url "$SELF_UPDATE_URL")"; then
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
	if [[ "$CLI_VERBOSE" == "true" ]]; then
		exec "$SCRIPT_PATH" --verbose
	fi
	exec "$SCRIPT_PATH"
}

ensure_jq() {
	if command -v jq >/dev/null 2>&1; then
		return
	fi

	if command -v apk >/dev/null 2>&1; then
		log "jq not found, installing it with apk"
		apk add jq >/dev/null
	elif command -v opkg >/dev/null 2>&1; then
		log "jq not found, installing it with opkg"
		opkg install jq >/dev/null
	else
		die "jq not found and no supported package manager (apk or opkg) available"
	fi
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
	local ip="$1" domain="$2" curl_proto=()
	local resolve_ip="$ip"
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

rotate_openclash_backups() {
	local config="$1" keep="$2"
	local config_dir config_base i=0 file
	config_dir="$(dirname "$config")"
	config_base="$(basename "$config")"

	while IFS= read -r file; do
		[[ -f "$file" ]] || continue
		i=$((i + 1))
		((i > keep)) && rm -f "$file"
	done < <(ls -t "${config_dir}/${config_base}.bak."* 2>/dev/null)
	return 0
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
	mkdir -p "$CFST_DIR"
	cd "$WORK_DIR" || die "failed to enter work directory: $WORK_DIR"
}

install_speedtest_archive() {
	local archive="$1" version="${2:-}"

	log "using local CloudflareSpeedTest archive: $archive"
	if ! tar -tzf "$archive" >/dev/null 2>&1; then
		die "local CloudflareSpeedTest archive is not a valid tar.gz: $archive"
	fi
	tar -xzf "$archive" -C "$CFST_DIR" || die "failed to extract CloudflareSpeedTest archive: $archive"
	[[ -f "${CFST_DIR}/${BINARY_NAME}" ]] || die "archive did not contain $BINARY_NAME"
	chmod +x "${CFST_DIR}/${BINARY_NAME}"
	if [[ -n "$version" ]]; then
		printf '%s\n' "$version" >"${CFST_DIR}/${BINARY_NAME}_version.txt"
	fi
}

download_speedtest() {
	local tag version old_version asset archive url download_url tmp_archive release_json release_tmp file_size

	need_cmd curl
	need_cmd tar
	ensure_jq

	tag="$(detect_arch_tag)"
	asset="${BINARY_NAME}_linux_${tag}.tar.gz"
	archive="${CFST_DIR}/${BINARY_NAME}_linux_${tag}.tar.gz"
	log "detected architecture tag: $tag"
	log "checking CloudflareSpeedTest release: $RELEASE_API"
	release_tmp="$(mktemp "${TMPDIR:-/tmp}/${BINARY_NAME}_release.XXXXXX")" || die "failed to create temporary release metadata file"
	if ! curl_fetch "$release_tmp" "$RELEASE_API"; then
		rm -f "$release_tmp"
		if [[ -f "$archive" ]]; then
			log "release metadata unavailable, falling back to local archive"
			install_speedtest_archive "$archive"
			return
		fi
		if [[ -x "${CFST_DIR}/${BINARY_NAME}" ]]; then
			log "release metadata unavailable, using existing $BINARY_NAME"
			return
		fi
		die "failed to fetch CloudflareSpeedTest release metadata: $RELEASE_API"
	fi
	release_json="$(<"$release_tmp")"
	rm -f "$release_tmp"
	version="$(printf '%s\n' "$release_json" | jq -r '.tag_name // empty')"
	[[ -n "$version" && "$version" != "null" ]] || die "failed to get latest CloudflareSpeedTest version"

	old_version=""
	[[ -f "${CFST_DIR}/${BINARY_NAME}_version.txt" ]] && old_version="$(<"${CFST_DIR}/${BINARY_NAME}_version.txt")"

	url="$(printf '%s\n' "$release_json" | jq -r --arg name "$asset" '.assets[] | select(.name == $name) | .browser_download_url // empty' | head -n 1)"
	if [[ -z "$url" || "$url" == "null" ]]; then
		url="${RELEASE_DOWNLOAD_BASE}/${version}/${asset}"
	fi
	download_url="$(mirror_url "$url")"

	if [[ ! -x "${CFST_DIR}/${BINARY_NAME}" || "$version" != "$old_version" ]]; then
		log "downloading CloudflareSpeedTest $version for $tag"
		tmp_archive="$(mktemp "${archive}.XXXXXX")" || die "failed to create temporary archive"
		if ! curl_fetch "$tmp_archive" "$download_url"; then
			rm -f "$tmp_archive"
			if [[ -f "$archive" ]]; then
				log "download failed, falling back to local archive"
				install_speedtest_archive "$archive" "$version"
				return
			fi
			if [[ -x "${CFST_DIR}/${BINARY_NAME}" ]]; then
				log "download failed, using existing $BINARY_NAME"
				return
			fi
			die "failed to download CloudflareSpeedTest asset: $url"
		fi
		if ! tar -tzf "$tmp_archive" >/dev/null 2>&1; then
			file_size="$(wc -c < "$tmp_archive" 2>/dev/null || printf 'unknown')"
			local invalid_download_error="downloaded CloudflareSpeedTest asset is not a valid tar.gz (size=${file_size} bytes): $url"
			if head -c 512 "$tmp_archive" 2>/dev/null | grep -qi '<!doctype\|<html'; then
				invalid_download_error="downloaded file is HTML instead of tar.gz (likely network interception or proxy); size=${file_size} bytes; url=$url"
			fi
			rm -f "$tmp_archive"
			if [[ -f "$archive" ]]; then
				log "downloaded archive is invalid, falling back to local archive"
				install_speedtest_archive "$archive" "$version"
				return
			fi
			if [[ -x "${CFST_DIR}/${BINARY_NAME}" ]]; then
				log "downloaded archive is invalid, using existing $BINARY_NAME"
				return
			fi
			die "$invalid_download_error"
		fi
		mv "$tmp_archive" "$archive" || {
			rm -f "$tmp_archive"
			die "failed to save CloudflareSpeedTest archive: $archive"
		}
		install_speedtest_archive "$archive" "$version"
		log "CloudflareSpeedTest $version installed successfully"
	else
		log "CloudflareSpeedTest $version already exists"
	fi
}

run_speedtest() {
	local ip all_ips=() verified_ips=() ips=() cfst_files=() result_files=()
	local cfst_proto_args=()

	case "$SPEEDTEST_PROTOCOL" in
		http)
			cfst_proto_args+=("-httping")
			[[ -n "$SPEEDTEST_CFCOLO" ]] && cfst_proto_args+=("-cfcolo" "$SPEEDTEST_CFCOLO")
			;;
	esac

	case "$IP_TYPE" in
		ipv4) cfst_files=("${CFST_DIR}/ip.txt") ;;
		ipv6) cfst_files=("${CFST_DIR}/ipv6.txt") ;;
		both) cfst_files=("${CFST_DIR}/ip.txt" "${CFST_DIR}/ipv6.txt") ;;
	esac

	rm -f "$RESULT_FILE"
	for cfst_file in "${cfst_files[@]}"; do
		local partial_result
		partial_result="$(mktemp "${RESULT_FILE}.XXXXXX")"
		log "running speedtest with $cfst_file"
		"${CFST_DIR}/${BINARY_NAME}" -f "$cfst_file" -dn "$SPEEDTEST_DN" -tll "$SPEEDTEST_TLL" "${cfst_proto_args[@]}" -o "$partial_result" >/dev/null || true
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

	local target_domains=()
	case "$MODE" in
		passwall) IFS=',' read -r -a target_domains <<< "$PASSWALL_TARGET_DOMAIN" ;;
		openclash) IFS=',' read -r -a target_domains <<< "$OPENCLASH_TARGET_DOMAIN" ;;
	esac

	if ((${#target_domains[@]} > 0)); then
		log "verifying selected IPs against ${target_domains[*]}"
		for ip in "${all_ips[@]}"; do
			((${#verified_ips[@]} >= IP_COUNT)) && break
			local all_pass=true domain
			for domain in "${target_domains[@]}"; do
				if ! verify_ip "$ip" "$domain"; then
					all_pass=false
					break
				fi
			done
			if $all_pass; then
				verified_ips+=("$ip")
			else
				log "skip unreachable IP: $ip"
			fi
		done
	fi

	if ((${#verified_ips[@]} > 0)); then
		ips=("${verified_ips[@]}")
	else
		if ((${#target_domains[@]} > 0)); then
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
	if [[ "$service" == "openclash" && -n "$_OPENCLASH_ENABLE_SAVED" ]]; then
		uci -q set "openclash.config.enable=$_OPENCLASH_ENABLE_SAVED"
		uci -q commit openclash
	fi
	log "restarting service: $service"
	"/etc/init.d/${service}" restart >/dev/null || die "failed to restart $service"
	if [[ "$service" == "openclash" ]]; then
		local i
		for i in $(seq 1 30); do
			pidof clash >/dev/null 2>&1 && break
			sleep 1
		done
		if ! pidof clash >/dev/null 2>&1; then
			log "warning: openclash core not running after restart (start_fail may have been triggered)"
		fi
	fi
}

stop_service() {
	local service="$1"

	[[ -x "/etc/init.d/${service}" ]] || return 0
	if [[ "$service" == "openclash" ]]; then
		_OPENCLASH_ENABLE_SAVED="$(uci -q get openclash.config.enable || echo "1")"
		uci -q set openclash.config.enable=0
		uci -q commit openclash
	fi
	log "stopping service for speedtest: $service"
	"/etc/init.d/${service}" stop >/dev/null 2>&1 || die "failed to stop $service"
	if [[ "$service" == "openclash" ]]; then
		local i clash_pids
		for i in $(seq 1 15); do
			clash_pids="$(pidof clash 2>/dev/null)" || clash_pids=""
			[[ -z "$clash_pids" ]] && break
			sleep 1
		done
		clash_pids="$(pidof clash 2>/dev/null)" || clash_pids=""
		if [[ -n "$clash_pids" ]]; then
			log "openclash core still running after stop, force killing"
			# shellcheck disable=SC2086
			kill -9 $clash_pids 2>/dev/null || true
		fi
	fi
	_STOPPED_SERVICE="$service"
}

cleanup_stopped_service() {
	if [[ -n "$_STOPPED_SERVICE" ]]; then
		log "restarting stopped service on exit: $_STOPPED_SERVICE"
		if [[ "$_STOPPED_SERVICE" == "openclash" && -n "$_OPENCLASH_ENABLE_SAVED" ]]; then
			uci -q set "openclash.config.enable=$_OPENCLASH_ENABLE_SAVED"
			uci -q commit openclash
		fi
		"/etc/init.d/${_STOPPED_SERVICE}" restart >/dev/null 2>&1 || true
		_STOPPED_SERVICE=""
		_OPENCLASH_ENABLE_SAVED=""
	fi
}

update_passwall() {
	local sections=() section idx ip old_remarks new_remarks

	need_cmd uci
	while IFS= read -r section; do
		sections+=("$section")
	done < <(find_passwall_sections)
	((${#sections[@]} > 0)) || die "no PassWall nodes matched address: $PASSWALL_TARGET_DOMAIN"
	log "matched PassWall node count: ${#sections[@]}"

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
	local line key value section domain _domains=()

	IFS=',' read -r -a _domains <<< "$PASSWALL_TARGET_DOMAIN"
	while IFS= read -r line; do
		[[ "$line" == passwall.*.address=* ]] || continue
		key="${line%%=*}"
		value="$(uci_unquote "${line#*=}")"
		for domain in "${_domains[@]}"; do
			[[ "$value" == "$domain" ]] || continue
			section="${key#passwall.}"
			section="${section%.address}"
			[[ -n "$section" ]] && printf '%s\n' "$section"
			break
		done
	done < <(uci show passwall)
}

trim_scalar() {
	local value="$1"

	value="${value%%#*}"
	value="${value%$'\r'}"
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
	# BusyBox tr treats [:upper:]/[:lower:] as literal sets in some OpenWrt builds.
	# shellcheck disable=SC2018,SC2019
	printf '%s' "$1" | tr 'A-Z' 'a-z'
}

openclash_network_supported() {
	case "$(lower "$1")" in
		ws|xhttp|grpc|h2|http)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

openclash_protocol_supported() {
	local type="$1" tls="$2" network="$3"

	type="$(lower "$type")"
	tls="$(lower "$tls")"

	case "$type" in
		vless|vmess|trojan)
			;;
		*)
			return 1
			;;
	esac

	case "$tls" in
		"true")
			return 0
			;;
	esac

	openclash_network_supported "$network"
}

line_indent() {
	local line="$1"
	printf '%s' "${line%%[![:space:]]*}"
}

write_openclash_line() {
	local line="$1"

	printf '%s\n' "$line" >>"$TMP_CONFIG"
	if [[ "$line" =~ ^[[:space:]]*$ ]]; then
		OPENCLASH_LAST_LINE_BLANK=true
	else
		OPENCLASH_LAST_LINE_BLANK=false
	fi
}

write_openclash_proxy_separator() {
	if [[ "${OPENCLASH_WROTE_PROXY:-false}" == "true" && "${OPENCLASH_LAST_LINE_BLANK:-false}" != "true" ]]; then
		printf '\n' >>"$TMP_CONFIG"
		OPENCLASH_LAST_LINE_BLANK=true
	fi
}

write_block_original() {
	local line
	local is_proxy=false

	for line in "${BLOCK_LINES[@]}"; do
		if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+name:[[:space:]]*.+$ ]]; then
			is_proxy=true
			break
		fi
	done

	[[ "$is_proxy" == "true" ]] && write_openclash_proxy_separator

	for line in "${BLOCK_LINES[@]}"; do
		write_openclash_line "$line"
	done
	if [[ "$is_proxy" == "true" ]]; then
		OPENCLASH_WROTE_PROXY=true
	fi
}

expand_suffix() {
	local suffix="$1" seq="$2" ip_addr="$3"
	suffix="${suffix//\{n\}/${seq}}"
	suffix="${suffix//\{ip\}/${ip_addr}}"
	printf '%s' "$suffix"
}

openclash_variant_count() {
	if [[ -n "$OPENCLASH_NAME_SUFFIX" ]]; then
		printf '%s' "$IP_COUNT"
	else
		printf '1'
	fi
}

openclash_generated_index() {
	local proxy_name="$1"

	if [[ "$proxy_name" =~ [[:space:]]\[CF-([0-9]+)\][[:space:]]*$ ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
		return 0
	fi
	return 1
}

openclash_base_name() {
	local proxy_name="$1"

	if [[ "$proxy_name" =~ ^(.*)[[:space:]]\[CF-[0-9]+\][[:space:]]*$ ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
	else
		printf '%s' "$proxy_name"
	fi
}

openclash_domain_matches() {
	local server="$1" servername="$2" host="$3" domain _domains=()

	IFS=',' read -r -a _domains <<< "$OPENCLASH_TARGET_DOMAIN"
	for domain in "${_domains[@]}"; do
		if [[ "$server" == "$domain" || "$servername" == "$domain" || "$host" == "$domain" ]]; then
			OPENCLASH_MATCHED_DOMAIN="$domain"
			return 0
		fi
	done
	return 1
}

remember_openclash_template() {
	local base_name="$1" domain="$2"

	[[ -z "${OPENCLASH_TEMPLATE_TEXT[$domain]:-}" ]] || return 0
	OPENCLASH_TEMPLATE_TEXT[$domain]="$(printf '%s\n' "${BLOCK_LINES[@]}")"
	OPENCLASH_TEMPLATE_BASE_NAME[$domain]="$base_name"
}

restore_openclash_template() {
	local domain="$1" line

	BLOCK_LINES=()
	while IFS= read -r line || [[ -n "$line" ]]; do
		BLOCK_LINES+=("$line")
	done <<<"${OPENCLASH_TEMPLATE_TEXT[$domain]}"
}

emit_openclash_variant() {
	local seq="$1" ip="$2" base_name="$3" domain="$4"
	local line idx
	local name="" tls="" network=""
	local name_idx=-1 server_idx=-1 tls_idx=-1 network_idx=-1 servername_idx=-1 ws_opts_idx=-1 xhttp_opts_idx=-1 headers_idx=-1 host_idx=-1
	local prop_indent="" new_name
	local normalized_network opts_idx opt_key
	local updated=false

	for idx in "${!BLOCK_LINES[@]}"; do
		line="${BLOCK_LINES[$idx]}"
		if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+name:[[:space:]]*(.+)$ ]]; then
			name="$(trim_scalar "${BASH_REMATCH[1]}")"
			name_idx="$idx"
		elif [[ "$line" =~ ^[[:space:]]*server:[[:space:]]*(.+)$ ]]; then
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

	if [[ -n "$OPENCLASH_NAME_SUFFIX" && -n "$base_name" ]]; then
		new_name="${base_name}$(expand_suffix "$OPENCLASH_NAME_SUFFIX" "$seq" "$ip")"
	else
		new_name="$base_name"
	fi

	write_openclash_proxy_separator

	for idx in "${!BLOCK_LINES[@]}"; do
		line="${BLOCK_LINES[$idx]}"
		if ((idx == name_idx)) && [[ "$new_name" != "$name" ]]; then
			write_openclash_line "$(printf '%s- name: %s' "$(line_indent "$line")" "$new_name")"
		elif ((idx == server_idx)); then
			write_openclash_line "$(printf '%sserver: %s' "$prop_indent" "$ip")"
			updated=true
		elif ((idx == servername_idx)); then
			write_openclash_line "$(printf '%sservername: %s' "$prop_indent" "$domain")"
		elif ((idx == host_idx)); then
			write_openclash_line "$(printf '%sHost: %s' "$(line_indent "$line")" "$domain")"
		else
			write_openclash_line "$line"
		fi

		if ((idx == tls_idx && servername_idx < 0)) && [[ "$(lower "$tls")" == "true" ]]; then
			write_openclash_line "$(printf '%sservername: %s' "$prop_indent" "$domain")"
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
				write_openclash_line "$(printf '%sHost: %s' "${prop_indent}    " "$domain")"
			elif ((idx == opts_idx && headers_idx < 0)); then
				write_openclash_line "$(printf '%sheaders:' "${prop_indent}  ")"
				write_openclash_line "$(printf '%sHost: %s' "${prop_indent}    " "$domain")"
			elif ((idx == network_idx && opts_idx < 0)); then
				write_openclash_line "$(printf '%s%s:' "$prop_indent" "$opt_key")"
				write_openclash_line "$(printf '%sheaders:' "${prop_indent}  ")"
				write_openclash_line "$(printf '%sHost: %s' "${prop_indent}    " "$domain")"
			fi
		fi
	done

	OPENCLASH_WROTE_PROXY=true
	OPENCLASH_UPDATED=$((OPENCLASH_UPDATED + 1))
	OPENCLASH_SEEN["${domain}:${seq}"]=1
	if [[ "$updated" == "true" ]]; then
		if [[ "$new_name" != "$name" ]]; then
			log "OpenClash proxy '${name:-unknown}' -> '${new_name}'; server -> ${ip}; domain kept as ${domain}"
		else
			log "OpenClash proxy '${name:-unknown}' server -> ${ip}; domain kept as ${domain}"
		fi
	fi
}

append_missing_openclash_variants() {
	local domain seq ip variant_count _domains=()

	IFS=',' read -r -a _domains <<< "$OPENCLASH_TARGET_DOMAIN"
	for domain in "${_domains[@]}"; do
		[[ -n "${OPENCLASH_TEMPLATE_TEXT[$domain]:-}" ]] || continue
		variant_count="$(openclash_variant_count)"
		for ((seq = 1; seq <= variant_count; seq++)); do
			[[ -z "${OPENCLASH_SEEN[${domain}:${seq}]:-}" ]] || continue
			restore_openclash_template "$domain"
			ip="${FAST_IPS[$(((seq - 1) % IP_COUNT))]}"
			emit_openclash_variant "$seq" "$ip" "${OPENCLASH_TEMPLATE_BASE_NAME[$domain]}" "$domain"
		done
	done
}

process_openclash_block() {
	local line idx
	local name="" type="" server="" tls="" network="" servername="" host=""
	local generated_seq="" base_name variant_count

	((${#BLOCK_LINES[@]} > 0)) || return

	for idx in "${!BLOCK_LINES[@]}"; do
		line="${BLOCK_LINES[$idx]}"
		if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+name:[[:space:]]*(.+)$ ]]; then
			name="$(trim_scalar "${BASH_REMATCH[1]}")"
		elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]*(.+)$ ]]; then
			type="$(trim_scalar "${BASH_REMATCH[1]}")"
		elif [[ "$line" =~ ^[[:space:]]*server:[[:space:]]*(.+)$ ]]; then
			server="$(trim_scalar "${BASH_REMATCH[1]}")"
		elif [[ "$line" =~ ^[[:space:]]*tls:[[:space:]]*(.+)$ ]]; then
			tls="$(trim_scalar "${BASH_REMATCH[1]}")"
		elif [[ "$line" =~ ^[[:space:]]*network:[[:space:]]*(.+)$ ]]; then
			network="$(trim_scalar "${BASH_REMATCH[1]}")"
		elif [[ "$line" =~ ^[[:space:]]*servername:[[:space:]]*(.*)$ ]]; then
			servername="$(trim_scalar "${BASH_REMATCH[1]}")"
		elif [[ "$line" =~ ^[[:space:]]*Host:[[:space:]]*(.*)$ ]]; then
			host="$(trim_scalar "${BASH_REMATCH[1]}")"
		fi
	done

	if [[ -z "$name" ]]; then
		write_block_original
		return
	fi

	if ! openclash_domain_matches "$server" "$servername" "$host"; then
		write_block_original
		return
	fi

	local matched_domain="$OPENCLASH_MATCHED_DOMAIN"

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

	base_name="$(openclash_base_name "$name")"
	remember_openclash_template "$base_name" "$matched_domain"
	if generated_seq="$(openclash_generated_index "$name")"; then
		if ((generated_seq < 1)); then
			write_block_original
			return
		fi
		emit_openclash_variant "$generated_seq" "${FAST_IPS[$(((generated_seq - 1) % IP_COUNT))]}" "$base_name" "$matched_domain"
	else
		variant_count="$(openclash_variant_count)"
		log "OpenClash proxy '${name:-unknown}' selected as template for ${matched_domain}; generating ${variant_count} marked variant(s)"
	fi
}

update_openclash() {
	local line backup backup_ts backup_seq=0

	[[ -f "$OPENCLASH_CONFIG" ]] || die "OpenClash config not found: $OPENCLASH_CONFIG"
	[[ -n "$OPENCLASH_TARGET_DOMAIN" ]] || die "OPENCLASH_TARGET_DOMAIN is empty"
	log "updating OpenClash config: $OPENCLASH_CONFIG"

	TMP_CONFIG="$(mktemp "${OPENCLASH_CONFIG}.tmp.XXXXXX")"
	OPENCLASH_UPDATED=0
	OPENCLASH_TEMPLATE_TEXT=()
	OPENCLASH_TEMPLATE_BASE_NAME=()
	OPENCLASH_SEEN=()
	OPENCLASH_WROTE_PROXY=false
	OPENCLASH_LAST_LINE_BLANK=true
	BLOCK_LINES=()

	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"
		if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+name:[[:space:]]*.+$ && ${#BLOCK_LINES[@]} -gt 0 ]]; then
			process_openclash_block
			BLOCK_LINES=("$line")
		else
			BLOCK_LINES+=("$line")
		fi
	done <"$OPENCLASH_CONFIG"
	process_openclash_block
	append_missing_openclash_variants

	((OPENCLASH_UPDATED > 0)) || {
		rm -f "$TMP_CONFIG"
		die "no supported OpenClash proxy matched server: $OPENCLASH_TARGET_DOMAIN"
	}

	backup_ts="$(date +%Y%m%d%H%M%S)"
	backup="${OPENCLASH_CONFIG}.bak.${backup_ts}"
	while [[ -e "$backup" ]]; do
		backup_seq=$((backup_seq + 1))
		backup="${OPENCLASH_CONFIG}.bak.${backup_ts}.${backup_seq}"
	done
	cp "$OPENCLASH_CONFIG" "$backup"
	rotate_openclash_backups "$OPENCLASH_CONFIG" "$OPENCLASH_BACKUP_COUNT"
	mv "$TMP_CONFIG" "$OPENCLASH_CONFIG"
	log "OpenClash config updated, backup saved to $backup"

	restart_service openclash
}

usage() {
	cat <<'EOF'
Usage:
  cf-openwrt-auto.sh [--verbose]

Config:
  Copy cf-openwrt-auto.conf.example to cf-openwrt-auto.conf in the same
  directory as this script, then edit that config file.

Options:
  -v, --verbose  Print progress logs to stderr for manual terminal runs.
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
	[[ "$DOWNLOAD_RETRIES" =~ ^[1-9][0-9]*$ ]] || die "DOWNLOAD_RETRIES must be a positive integer"
	[[ "$DOWNLOAD_RETRY_DELAY" =~ ^[0-9]+$ ]] || die "DOWNLOAD_RETRY_DELAY must be a non-negative integer"
	[[ "$VERBOSE" == "true" || "$VERBOSE" == "false" ]] || die "VERBOSE must be true or false"
	[[ "$STOP_SERVICE_BEFORE_SPEEDTEST" == "true" || "$STOP_SERVICE_BEFORE_SPEEDTEST" == "false" ]] || die "STOP_SERVICE_BEFORE_SPEEDTEST must be true or false"
	if [[ -n "$STARTUP_DELAY" && "$STARTUP_DELAY" != "random" ]]; then
		[[ "$STARTUP_DELAY" =~ ^[0-9]+$ ]] || die "STARTUP_DELAY must be a non-negative integer or random"
	fi
	if [[ -n "$GITHUB_MIRROR" ]]; then
		[[ "$GITHUB_MIRROR" == http://* || "$GITHUB_MIRROR" == https://* ]] || die "GITHUB_MIRROR must start with http:// or https://"
		[[ "$GITHUB_MIRROR" == */ ]] || die "GITHUB_MIRROR must end with /"
	fi

	case "$MODE" in
		passwall)
			[[ -n "$PASSWALL_TARGET_DOMAIN" ]] || die "PASSWALL_TARGET_DOMAIN is empty"
			local _domain _domains=()
			IFS=',' read -r -a _domains <<< "$PASSWALL_TARGET_DOMAIN"
			for _domain in "${_domains[@]}"; do
				[[ "$_domain" == *.* ]] || die "PASSWALL_TARGET_DOMAIN contains invalid domain: $_domain"
			done
			;;
		openclash)
			[[ -n "$OPENCLASH_CONFIG" ]] || die "OPENCLASH_CONFIG is empty"
			[[ -n "$OPENCLASH_TARGET_DOMAIN" ]] || die "OPENCLASH_TARGET_DOMAIN is empty"
			[[ -f "$OPENCLASH_CONFIG" ]] || die "OpenClash config not found: $OPENCLASH_CONFIG"
			[[ "$OPENCLASH_BACKUP_COUNT" =~ ^[1-9][0-9]*$ ]] || die "OPENCLASH_BACKUP_COUNT must be a positive integer"
			local _domain _domains=()
			IFS=',' read -r -a _domains <<< "$OPENCLASH_TARGET_DOMAIN"
			for _domain in "${_domains[@]}"; do
				[[ "$_domain" == *.* ]] || die "OPENCLASH_TARGET_DOMAIN contains invalid domain: $_domain"
			done
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
	while (($# > 0)); do
		case "$1" in
			-h|--help)
				usage
				return 0
				;;
			-v|--verbose)
				CLI_VERBOSE="true"
				;;
			*)
				die "unexpected argument: $1; edit MODE in cf-openwrt-auto.conf"
				;;
		esac
		shift
	done

	load_config
	[[ "$CLI_VERBOSE" == "true" ]] && VERBOSE="true"
	normalize_mode "$MODE"
	validate_config

	local _max_delay=300
	if [[ -n "$STARTUP_DELAY" && "$STARTUP_DELAY" != "random" ]]; then
		_max_delay="$STARTUP_DELAY"
	fi
	if ((_max_delay > 0)) && [[ "$CLI_VERBOSE" != "true" ]]; then
		STARTUP_DELAY=$((RANDOM % (_max_delay + 1)))
		log "startup delay (0~${_max_delay}s): ${STARTUP_DELAY}s"
		sleep "$STARTUP_DELAY"
	fi

	CFST_DIR="${WORK_DIR}/cfst"
	[[ -z "$RESULT_FILE" ]] && RESULT_FILE="${CFST_DIR}/cf_result.txt"
	[[ -z "$IP_HISTORY_FILE" ]] && IP_HISTORY_FILE="${CFST_DIR}/ip-all.txt"
	log "starting cf-openwrt-auto $SCRIPT_VERSION"
	log "mode=$MODE ip_type=$IP_TYPE ip_count=$IP_COUNT protocol=$SPEEDTEST_PROTOCOL"
	self_update "$@"
	need_cmd awk
	need_cmd sed
	need_cmd tr
	log "using work directory: $WORK_DIR"
	prepare_work_dir
	download_speedtest

	if [[ "$STOP_SERVICE_BEFORE_SPEEDTEST" == "true" ]]; then
		case "$MODE" in
			passwall) stop_service passwall ;;
			openclash) stop_service openclash ;;
		esac
		trap cleanup_stopped_service EXIT
	fi

	run_speedtest

	case "$MODE" in
		passwall)
			update_passwall
			;;
		openclash)
			update_openclash
			;;
	esac

	_STOPPED_SERVICE=""
	trap - EXIT

	log "done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
