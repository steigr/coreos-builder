#!/usr/bin/env bash

[[ "$TRACE" ]] && set -x
set -eo pipefail

vars() {
  export TARGET="/target"
  export TEMP="${TEMP:-$(mktemp -d)}"
  export CHANNELS="stable beta alpha"
  export BOARD="amd64-usr"
  export SRC_FILE="coreos_production_pxe_image.cpio.gz"
  export COMPRESS_MEMLIMIT="${COMPRESS_MEMLIMIT:-90}"
  export COMPRESS_MEMLIMIT="$(percent_of_free_memory "$COMPRESS_MEMLIMIT" )KiB"
  export COMPRESS="xz"
  export COMPRESS_ARGS="-c -f -T0 -e -M $COMPRESS_MEMLIMIT -9"
}

percent_of_free_memory() {
  local percent="$1"
  MEM_MAX="$(cat /proc/meminfo \
  | grep ^MemAvailable \
  | awk -F: '{print $2}' \
  | awk '{print $1}' )"
  printf "$((( $((( $MEM_MAX * $percent ))) / 100 )))"
}

url_of() {
  local channel="$1"
  local version="$2"
  printf "http://${channel}.release.core-os.net/${BOARD}/${version}/${SRC_FILE}"
}

http_exists() {
  local url="$1"
  curl --silent --head --fail "${url}" >/dev/null 2>/dev/null
}

channel_of() {
  local version="$1"
  for channel in ${CHANNELS}; do
    http_exists "$(url_of "$channel" "$version")" || continue
    echo "$channel"
    break
  done
}

remove() {
  local base_dir="$1"
  local to_unlink="$2"
  rm -rf "$base_dir/$to_unlink"
}

link() {
  local base_dir="$1"
  local dest="$2"
  local source="$3"
  [[ -e "$base_dir/$dest" ]] \
  && return 0
  [[ -d "$(dirname "$base_dir/$dest")" ]] \
  || mkdir -p "$(dirname "$base_dir/$dest")"
  ln -s "$source" "$base_dir/$dest"
}

enable_login_getty() {
  local base_dir="$1"
  local tty="$2"
  [[ -f "$base_dir/usr/lib64/systemd/system-generators/coreos-autologin-generator" ]] \
  || return 0
  echo "overlay_unit \"getty@${tty}.service\"" \
  >> "$base_dir/usr/lib64/systemd/system-generators/coreos-autologin-generator"
}

add_unit_partial() {
  local base_dir="$1"
  local unit="$2"
  local partial="$3"
  [[ -d "$base_dir//usr/lib64/systemd/system/${unit}.d" ]] \
  || mkdir -p "$base_dir//usr/lib64/systemd/system/${unit}.d"
  cat \
  | tee "$base_dir//usr/lib64/systemd/system/${unit}.d/${partial}.conf"
}

disable_unit() {
  local base_dir="$1"
  local unit="$2"
  [[ -f "$base_dir/usr/lib64/systemd/system/$unit" ]] \
  && rm "$base_dir/usr/lib64/systemd/system/$unit"
  link "$base_dir" "usr/lib64/systemd/system/$unit" "/dev/null"
}

prepare() {
  local temp="$1"
  
  remove "$temp" usr/boot
  remove "$temp" usr/lib64/modules
  remove "$temp" usr/lib64/modules
  
  link   "$temp" lib   /usr/lib
  link   "$temp" lib64 /usr/lib64
  link   "$temp" bin   /usr/bin
  link   "$temp" sbin  /usr/sbin
  
  touch  "$temp/usr/.noupdate"
  
  enable_login_getty "$temp" tty
  enable_login_getty "$temp" tty1

  cat <<'EO_PARTIAL' | add_unit_partial "$temp" "console-getty.service" "10-auto-login"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin core --noclear --keep-baud console 115200,38400,9600 $TERM
EO_PARTIAL

  disable_unit "$temp" "dev-hugepages.mount"
  disable_unit "$temp" "tmp.mount"
  disable_unit "$temp" "usr-share-oem.mount"
  disable_unit "$temp" "systemd-machine-id-commit.service"
  disable_unit "$temp" "audit-rules.service"
  disable_unit "$temp" "systemd-udevd-kernel.socket"
  disable_unit "$temp" "systemd-udevd-control.socket"
  disable_unit "$temp" "systemd-udevd.service"
  disable_unit "$temp" "systemd-udev-trigger.service"
  disable_unit "$temp" "systemd-udev-settle.service"
  disable_unit "$temp" "proc-sys-fs-binfmt_misc.automount"
}

compress() {
  local source="$1"
  local output="$2"
  tar -c -C "$source" . \
  | "$COMPRESS" $COMPRESS_ARGS \
  > "$output.tar.xz"
}

main() {
  local version="$1"
  local channel="$(channel_of "$version")"
  local temp="${TEMP}"
  curl -L "$(url_of "$channel" "$version")" \
  | gunzip \
  | ( cd "$temp"; cpio -i )
  for squashfs in $(find "$temp" -name "*.squashfs"); do
  	local target="$(basename "$squashfs")"
    local target="$(dirname "$squashfs")/${target%.*}"
    unsquashfs -dest "$target" "$squashfs"
    rm "$squashfs"
  done
  [[ -d "$temp/newroot" ]] \
  && temp="$temp/newroot"
  prepare "$temp"
  compress "$temp" "$TARGET/coreos-${version}"
}

vars
main $@
exit $?
