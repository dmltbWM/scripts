#!/bin/bash
## License: BSD 3
## It can reinstall debian to current stable version !.
## Written By htttps://github.com/dmltbWM

function sim::log() { local _date=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\e[0;32m[${_date}]\e[0m $@" >&2; }
function sim::fatal() { sim::log "$@"; sim::log "Exiting."; exit 1; }
function sim::command_exists() { command -v "$1" > /dev/null 2>&1; }
function sim::module_exists() { lsmod | grep -q "^$1\b" && return 0 || return 1; }
function sim::load_kernel_module() { modprobe "$1" 2>/dev/null; sim::module_exists "$1" || sim::fatal "[!] Module '$1' failed to load."; }
function sim::_install_command(){
  local command="$1"
  sim::log "[*] Installing $command..."
  apt update -qq -y
  apt install -qq -y "${command}" && sim::log "[*] '$command' has been installed successfully." || sim::fatal "[!] Failed to install '$command'."
}
function sim::install_command(){
  local command="$1"
  case "$1" in
    xz)
      sim::log "[*] Installing $command..."
       sim::_install_command 'xz-utils' 
      ;;
    wget)
      sim::_install_command 'wget'
      ;;
    mkfs.ext4)
      sim::_install_command 'e2fsprogs'
      ;;
    mkfs.vfat)
      sim::_install_command 'dosfstools'
      ;;
    *)
      sim::fatal "[!] Unknown command: $command"
    ;;
    esac
}

function sim::ensure_command_exist(){
  sim::log "[*] Installing missing command..."
  local need_commands=(xz wget mkfs.ext4)
  for cmd in "${need_commands[@]}"; do
       if ! sim::command_exists "$cmd"; then sim::install_command "$cmd"; fi
  done
}

function sim::ensure_load_kernerl_modules(){
  sim::log "[*] Loading kernel modules..."
  local ext4_need_modules=(ext4 crc16 mbcache jbd2)
  for module in "${ext4_need_modules[@]}"; do
        sim::load_kernel_module "$module"
  done
  
  local vfat_need_modules=(vfat nls_cp437 nls_ascii nls_utf8)
  for module in "${need_modules[@]}"; do
        sim::load_kernel_module "$module"
  done
}


[ ${EUID} -eq 0 ] || sim::fatal '[!] This script must be run as root.'
[ ${UID} -eq 0 ] || sim::fatal '[!] This script must be run as root.'
[ "$(grep -q "ID=debian" /etc/os-release; echo $?)" -eq 0 ] || sim::fatal '[-] This script only supports Debian systems.'
sim::ensure_command_exist
sim::ensure_load_kernerl_modules

sim_root='/sim'
password='sim@@@'
ver=$(wget -qO - 'https://deb.debian.org/debian/dists/stable/InRelease' | grep 'Codename:' | awk '{print $2}')
mirror='https://deb.debian.org'
base_packages='e2fsprogs dosfstools openssh-server sudo'
extra_packages='curl wget bash-completion tmux'
dhcp=false
uefi=$([ -d /sys/firmware/efi ] && echo true || echo false)
disk="/dev/$(lsblk -no PKNAME "$(df /boot | grep -Eo '/dev/[a-z0-9]+')")"
interface=$(ip route get 8.8.8.8 | awk -- '{print $5}')
ip_mac=$(ip link show "${interface}" | awk '/link\/ether/{print $2}')
ip4_addr=$(ip -o -4 addr show dev "${interface}" | awk '{print $4}' | head -n 1)
ip4_gw=$(ip route show dev "${interface}" | awk '/default/{print $3}' | head -n 1)
ip6_addr=$(ip -o -6 addr show dev "${interface}" | awk '{print $4}' | head -n 1)
ip6_gw=$(ip -6 route show dev "${interface}" | awk '/default/{print $3}' | head -n 1)

machine=$(uname -m)
case ${machine} in
  aarch64|arm64) machine_warp="arm64";;
  x86_64|amd64) machine_warp="amd64";;
  *) machine_warp="";;
esac

function sim::cleanup_exit(){
  sim::log "[*] Clearing temporary files..."
  swapoff -a
  losetup -D || true
  #fuser -kvm "${sim_root}" -15
  if mountpoint -q ${sim_root}; then
    umount -d ${sim_root}
  fi
  rm -rf --one-file-system ${sim_root}
}
function sim::cleanup_warp_exit(){ set +e;sim::cleanup_exit; }

function sim::copy_important_config(){ 
  sim::log "[*] Copying important config into new system and more configuration..."
  mkdir -p "${sim_root}/etc"
  #cp -axL --remove-destination /etc/resolv.conf "${sim_root}/etc"
  sim::log "[*] Copying or user custom resolv.conf..."
  local nameserver="nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 2606:4700:4700::1111"
  echo -e "${nameserver}" > "${sim_root}/etc/resolv.conf"
  return 0
}

function sim::_download_ramos_and_extract(){
  local mirror='https://images.linuxcontainers.org'
  sim::log "[*] Get latest download link..."
  local response=$(wget -qO- "${mirror}/images/alpine/edge/${machine_warp}/default/?C=M;O=D")
  local build_time=$(echo "$response" | grep -oP '(\d{8}_\d{2}:\d{2})' | tail -n 1)
  local link="${mirror}/images/alpine/edge/${machine_warp}/default/${build_time}/rootfs.tar.xz"

  sim::log "[*] Downloading temporary and extract..."
  local tmp_file=$(mktemp /tmp/rootfs.tar.xz.XXXXXX)
  if wget --continue -q --show-progress -O "${tmp_file}" "${link}"; then
    if [ -s "${tmp_file}" ]; then
      tar -xJf "${tmp_file}" --directory="${sim_root}" --strip-components=1
      sim::log "[*] Download and extract completed successfully."
    else
      sim::fatal "[!] Downloaded file is empty."
    fi
  else
      sim::fatal "[!] Failed to download from '${link}'."
  fi
  rm -f "${tmp_file}"
}

function sim::install_ramos_packages(){
  sim::log "[*] Installing dropbear and depends into ramos..."
  chroot ${sim_root} apk update
  # e2fsprogs = mkfs.ext2, mkfs.ext3, mkfs.ext4
  chroot ${sim_root} apk -q add eudev bash dropbear sgdisk zstd dosfstools e2fsprogs debootstrap arch-install-scripts
  chroot ${sim_root} mkdir -p /etc/dropbear
  chroot ${sim_root} dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key
  chroot ${sim_root} dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
  chroot ${sim_root} bash -c 'echo "DROPBEAR_PORT=22" >> /etc/conf.d/dropbear'
  chroot ${sim_root} bash -c 'echo "DROPBEAR_EXTRA_ARGS=\"-w -K 5\"" >> /etc/conf.d/dropbear'
  chroot ${sim_root} bash -c "echo 'root:${password}' | chpasswd"
}

function sim::inject_init(){
  sim::log "[*] Injecting init to temporary ramos..."
  cat >${sim_root}/init<<EOF
#!/bin/bash
export PATH="\$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

uefi="${uefi}"
interface="${interface}"
ip4_addr="${ip4_addr}"
ip4_gw="${ip4_gw}"
ip6_addr="${ip6_addr}"
ip6_gw="${ip6_gw}"
password="${password}"
dhcp="${dhcp}"
disk="${disk}"
machine="${machine}"
ver="${ver}"
mirror="${mirror}"
base_packages="${base_packages}"
extra_packages="${extra_packages}"

function ramos_exit() { echo '[!] Reinstall Error! Force reboot by reboot -f . '; /bin/bash; }
exec </dev/tty0 && exec >/dev/tty0 && exec 2>/dev/tty0
trap ramos_exit EXIT

echo "[*] Ensure other processes exit ..."
sysctl -w kernel.sysrq=1 >/dev/null
echo i > /proc/sysrq-trigger

echo "[*] Reset network..."
if [ -n "\$ip4_addr" ]; then
  /sbin/ip addr flush dev "${interface}"
  /sbin/ip route flush dev "${interface}"
  /sbin/ip addr add "${ip4_addr}" dev "${interface}"
  /sbin/ip route add default via "${ip4_gw}" dev "${interface}" onlink
fi
if [ -n "\$ip6_addr" ]; then
  /sbin/ip -6 addr flush dev "${interface}"
  /sbin/ip -6 route flush dev "${interface}"
  /sbin/ip -6 addr add "${ip6_addr}" dev "${interface}"
  /sbin/ip -6 route add default via "${ip6_gw}" dev "${interface}" onlink
fi

/usr/sbin/dropbear
udevadm info -n ${disk} -q property

# Partition & Formatting & Mounting
if [ "\${uefi}" = "true" ]; then
  sgdisk -g --align-end --clear \
    --new 0:0:+100M --typecode=0:ef00 --new 0:0:0 --typecode=0:8300 \${disk}
else
  sgdisk -g --align-end --clear \
    --new 0:0:+1M --typecode=0:ef02 --new 0:0:0 --typecode=0:8300 \${disk}
fi

partprobe
[[ \$disk == /dev/nvme* ]] && disk="\${disk}p"

mkfs.ext4 -F -L LINUX \${disk}2
mount \${disk}2 /mnt

# Mounting EFI
if [ "\${uefi}" = "true" ]; then
  mkfs.vfat -F32 -n EFI \${disk}1
  mkdir -p /mnt/boot/efi
  mount \${disk}1 /mnt/boot/efi
fi

# Downloading bootstrap...
debootstrap --arch=${machine_warp} ${ver} /mnt "${mirror}/debian"

# Mounting for chroot
mount -t proc /proc /mnt/proc
mount --rbind /dev /mnt/dev
mount --rbind /sys /mnt/sys

# Genfstab
genfstab -U /mnt >> /mnt/etc/fstab
cp /etc/resolv.conf /mnt/etc/resolv.conf

# Setup systemd-networkd
if [ "\$dhcp" = "true" ]; then
  cat > /mnt/etc/systemd/network/default.network <<EOFIN
[Match]
Name=en* eth*
[Network]
DHCP=yes
[DHCP]
UseMTU=yes
UseDNS=yes
UseDomains=yes
EOFIN
else
  cat > /mnt/etc/systemd/network/default.network <<EOFIN
[Match]
Name=en* eth*

[Network]
Address=${ip4_addr}
DNS=8.8.8.8
[Route]
Gateway=${ip4_gw}
GatewayOnlink=true

[Network]
IPv6AcceptRA=0
Address=${ip6_addr}
DNS=2606:4700:4700::1111
[Route]
Gateway=${ip6_gw}
GatewayOnlink=true
EOFIN
fi

# Setup APT
cat > /mnt/etc/apt/sources.list <<EOFIN
deb ${mirror}/debian ${ver} main contrib non-free non-free-firmware
deb ${mirror}/debian ${ver}-updates main contrib non-free non-free-firmware
deb ${mirror}/debian ${ver}-backports main contrib non-free non-free-firmware
deb ${mirror}/debian-security ${ver}-security main contrib non-free non-free-firmware
EOFIN

# Install base system
export DEBIAN_FRONTEND=noninteractive
chroot /mnt apt update
chroot /mnt apt full-upgrade -y
chroot /mnt apt install -q $base_packages $extra_packages locales -y
chroot /mnt apt install -q "linux-image-${machine_warp}" -y
if [ "\$uefi" = "true" ]; then
  chroot /mnt apt install -q grub-efi efibootmgr -y
else
  chroot /mnt apt install -q grub-pc -y
fi

# Setup locale & hostname
sed -ri 's/^#\s*en_US/en_US/' /mnt/etc/locale.gen
echo -e "LANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\nLANG=en_US.UTF-8" > /mnt/etc/default/locale
chroot /mnt locale-gen
chroot /mnt ln -sf /usr/share/zoneinfo/UTC /etc/localtime
echo 'localhost'> /mnt/etc/hostname

# Setting Account
chroot /mnt systemctl set-default multi-user.target
echo "root:${password}" |  chroot /mnt chpasswd
chroot /mnt ssh-keygen -t ed25519 -f /etc/ssh/ed25519_key -N ""
chroot /mnt ssh-keygen -t rsa -b 4096 -f /etc/ssh/rsa_key -N ""

# Enable systemd-timesyncd
chroot /mnt apt install -q systemd-timesyncd -y

cat > /mnt/etc/systemd/timesyncd.conf <<EOFIN
[Time]
NTP=0.debian.pool.ntp.org 1.debian.pool.ntp.org
EOFIN

# Enable systemd services
chroot /mnt systemctl enable systemd-timesyncd.service
chroot /mnt systemctl enable systemd-networkd.service
chroot /mnt systemctl enable ssh.service

# Enable root login and Optimizing system parameters
chroot /mnt /bin/bash -c "echo 'IyEvYmluL2Jhc2gKCmNhdCA+IC9ldGMvc3NoL3NzaGRfY29uZmlnIDw8RU9GCiNJbmNsdWRlIC9ldGMvc3NoL3NzaGRfY29uZmlnLmQvKi5jb25mClBvcnQgIDIyClBlcm1pdFJvb3RMb2dpbiB5ZXMKUGFzc3dvcmRBdXRoZW50aWNhdGlvbiB5ZXMKUHVia2V5QXV0aGVudGljYXRpb24geWVzCkNoYWxsZW5nZVJlc3BvbnNlQXV0aGVudGljYXRpb24gbm8KS2JkSW50ZXJhY3RpdmVBdXRoZW50aWNhdGlvbiBubwpBdXRob3JpemVkS2V5c0ZpbGUgIC9yb290Ly5zc2gvYXV0aG9yaXplZF9rZXlzClgxMUZvcndhcmRpbmcgeWVzCkFsbG93VXNlcnMgcm9vdApQcmludE1vdGQgbm8KQWNjZXB0RW52IExBTkcgTENfKgpFT0YKCl9mdHA9JChmaW5kIC91c3IgLW5hbWUgInNmdHAtc2VydmVyIiAyPi9kZXYvbnVsbCB8IGhlYWQgLW4gMSkKWyAtbiAiJHtfZnRwfSIgXSAmJiBlY2hvICJTdWJzeXN0ZW0gc2Z0cCAke19mdHB9IiA+PiAvZXRjL3NzaC9zc2hkX2NvbmZpZwoKY2F0ID4+IC9ldGMvYmFzaC5iYXNocmMgPDxFT0YKZXhwb3J0IFBTMT0nXFtcZVswOzMybVxdXHVAXGggXFtcZVswOzM0bVxdXHdcW1xlWzA7MzZtXF1cblwkIFxbXGVbMG1cXScKYWxpYXMgZ2V0aXA9J2N1cmwgLS1jb25uZWN0LXRpbWVvdXQgMyAtTHMgaHR0cHM6Ly9pcHY0LWFwaS5zcGVlZHRlc3QubmV0L2dldGlwJwphbGlhcyBnZXRpcDY9J2N1cmwgLS1jb25uZWN0LXRpbWVvdXQgMyAtTHMgaHR0cHM6Ly9pcHY2LWFwaS5zcGVlZHRlc3QubmV0L2dldGlwJwphbGlhcyBuZXRjaGVjaz0ncGluZyAtYzIgMS4xLjEuMScKYWxpYXMgbHM9J2xzIC0tY29sb3I9YXV0bycKYWxpYXMgZ3JlcD0nZ3JlcCAtLWNvbG9yPWF1dG8nIAphbGlhcyBmZ3JlcD0nZmdyZXAgLS1jb2xvcj1hdXRvJwphbGlhcyBlZ3JlcD0nZWdyZXAgLS1jb2xvcj1hdXRvJwphbGlhcyBybT0ncm0gLWknCmFsaWFzIGNwPSdjcCAtaScKYWxpYXMgbXY9J212IC1pJwphbGlhcyBsbD0nbHMgLWxoJwphbGlhcyBsYT0nbHMgLWxBaCcKYWxpYXMgLi49J2NkIC4uLycKYWxpYXMgLi4uPSdjZCAuLi8uLi8nCmFsaWFzIHBnPSdwcyBhdXggfGdyZXAgLWknCmFsaWFzIGhnPSdoaXN0b3J5IHxncmVwIC1pJwphbGlhcyBsZz0nbHMgLUEgfGdyZXAgLWknCmFsaWFzIGRmPSdkZiAtVGgnCmFsaWFzIGZyZWU9J2ZyZWUgLWgnCmV4cG9ydCBISVNUVElNRUZPUk1BVD0iJUYgJVQgXGB3aG9hbWlcYCAiCmV4cG9ydCBMQU5HPWVuX1VTLlVURi04CmV4cG9ydCBQQVRIPVwkUEFUSDouCkVPRgoKY2F0ID4+IC9ldGMvc2VjdXJpdHkvbGltaXRzLmNvbmYgPDxFT0YKKglzb2Z0CW5vZmlsZQk2NTUzNQoqCWhhcmQJbm9maWxlCTY1NTM1CioJc29mdAlub3Byb2MJNjU1MzUKKgloYXJkIG5vcHJvYwk2NTUzNQpyb290CXNvZnQJbm9maWxlCTY1NTM1CnJvb3QJaGFyZAlub2ZpbGUJNjU1MzUKcm9vdAlzb2Z0CW5vcHJvYwk2NTUzNQpyb290CWhhcmQJbm9wcm9jCTY1NTM1CkVPRgoKY2F0ID4+IC9ldGMvc2VjdXJpdHkvbGltaXRzLmQvOTAtbnByb2MuY29uZiA8PEVPRgoqCXNvZnQJbnByb2MJNjU1MzUKcm9vdAlzb2Z0CW5wcm9jCTY1NTM1CkVPRgoKWyAtZiAvZXRjL3N5c3RlbWQvc3lzdGVtLmNvbmYgXSAmJiBzZWQgLWkgJ3MvI1w/RGVmYXVsdExpbWl0Tk9GSUxFPS4qL0RlZmF1bHRMaW1pdE5PRklMRT02NTUzNS8nIC9ldGMvc3lzdGVtZC9zeXN0ZW0uY29uZjsKCmNhdCA+IC9ldGMvc3lzdGVtZC9qb3VybmFsZC5jb25mICA8PEVPRgpbSm91cm5hbF0KU3RvcmFnZT1hdXRvCkNvbXByZXNzPXllcwpGb3J3YXJkVG9TeXNsb2c9bm8KU3lzdGVtTWF4VXNlPThNClJ1bnRpbWVNYXhVc2U9OE0KUmF0ZUxpbWl0SW50ZXJ2YWxTZWM9MzBzClJhdGVMaW1pdEJ1cnN0PTEwMApFT0YKCmNhdCA+IC9ldGMvc3lzY3RsLmQvOTktc3lzY3RsLmNvbmYgIDw8RU9GCm5ldC5pcHY0LnRjcF90aW1lc3RhbXBzPTEKbmV0LmlwdjQudGNwX2Fkdl93aW5fc2NhbGU9LTIKbmV0LmlwdjQudGNwX2NvbGxhcHNlX21heF9ieXRlcz02MjkxNDU2Cm5ldC5pcHY0LnRjcF9ub3RzZW50X2xvd2F0PTEzMTA3MgpuZXQuY29yZS5uZXRkZXZfbWF4X2JhY2tsb2c9MTAyNDAKbmV0LmlwdjQudGNwX21heF9zeW5fYmFja2xvZz0xMDI0MApuZXQuY29yZS5zb21heGNvbm49MzI3NjgwMApuZXQuaXB2NC50Y3BfYWJvcnRfb25fb3ZlcmZsb3c9MQpuZXQuY29yZS5uZXRkZXZfYnVkZ2V0ID0gNjAwCm5ldC5pcHY0LnRjcF93aW5kb3dfc2NhbGluZz0xCm5ldC5pcHY0LnRjcF9zbG93X3N0YXJ0X2FmdGVyX2lkbGU9MQpuZXQubmZfY29ubnRyYWNrX21heD0xMDAwMDAwCm5ldC5uZXRmaWx0ZXIubmZfY29ubnRyYWNrX21heD0xMDAwMDAwCm5ldC5uZXRmaWx0ZXIubmZfY29ubnRyYWNrX3RjcF90aW1lb3V0X2Zpbl93YWl0PTMwCm5ldC5uZXRmaWx0ZXIubmZfY29ubnRyYWNrX3RjcF90aW1lb3V0X3RpbWVfd2FpdD0zMApuZXQubmV0ZmlsdGVyLm5mX2Nvbm50cmFja190Y3BfdGltZW91dF9jbG9zZV93YWl0PTE1Cm5ldC5uZXRmaWx0ZXIubmZfY29ubnRyYWNrX3RjcF90aW1lb3V0X2VzdGFibGlzaGVkPTMwMApuZXQuaXB2NC5uZXRmaWx0ZXIuaXBfY29ubnRyYWNrX3RjcF90aW1lb3V0X2VzdGFibGlzaGVkPTcyMDAKbmV0LmlwdjQudGNwX3R3X3JldXNlPTEKbmV0LmlwdjQudGNwX21heF90d19idWNrZXRzPTU1MDAwCm5ldC5pcHY0LnRjcF9zYWNrPTEKbmV0LmlwdjQudGNwX2ZhY2s9MQpuZXQuaXB2NC50Y3Bfc3luX3JldHJpZXM9MwpuZXQuaXB2NC50Y3Bfc3luYWNrX3JldHJpZXM9MwpuZXQuaXB2NC50Y3BfcmV0cmllczI9NQpuZXQuaXB2NC50Y3Bfc3luY29va2llcz0wCm5ldC5pcHY0LmNvbmYuZGVmYXVsdC5ycF9maWx0ZXI9MgpuZXQuaXB2NC5jb25mLmFsbC5ycF9maWx0ZXI9MgpuZXQuaXB2NC50Y3BfZmluX3RpbWVvdXQ9MTAKbmV0LmlwdjQudGNwX25vX21ldHJpY3Nfc2F2ZT0xCm5ldC51bml4Lm1heF9kZ3JhbV9xbGVuPTEwMjQKbmV0LmlwdjQucm91dGUuZ2NfdGltZW91dD0xMDAKbmV0LmlwdjQudGNwX210dV9wcm9iaW5nID0gMQpuZXQuaXB2NC5jb25mLmFsbC5sb2dfbWFydGlhbnM9MQpuZXQuaXB2NC5jb25mLmRlZmF1bHQubG9nX21hcnRpYW5zPTEKbmV0LmlwdjQuY29uZi5hbGwuYWNjZXB0X3NvdXJjZV9yb3V0ZT0wCm5ldC5pcHY0LmNvbmYuZGVmYXVsdC5hY2NlcHRfc291cmNlX3JvdXRlPTAKbmV0LmlwdjQudGNwX2tlZXBhbGl2ZV90aW1lPTYwMApuZXQuaXB2NC50Y3Bfa2VlcGFsaXZlX3Byb2Jlcz0zCm5ldC5pcHY0LnRjcF9rZWVwYWxpdmVfaW50dmw9MTUKbmV0LmlwdjQudGNwX3JldHJpZXMxID0gNQpuZXQuaXB2NC50Y3BfcmV0cmllczIgPSA1Cm5ldC5pcHY0LnRjcF9vcnBoYW5fcmV0cmllcyA9IDMKbmV0LmlwdjQudGNwX21heF9vcnBoYW5zPTMyNzY4MDAKbmV0LmlwdjQubmVpZ2guZGVmYXVsdC5nY190aHJlc2gxPTEyOApuZXQuaXB2NC5uZWlnaC5kZWZhdWx0LmdjX3RocmVzaDI9NTEyCm5ldC5pcHY0Lm5laWdoLmRlZmF1bHQuZ2NfdGhyZXNoMz00MDk2Cm5ldC5pcHY0Lm5laWdoLmRlZmF1bHQuZ2Nfc3RhbGVfdGltZT0xMjAKbmV0LmlwdjQuY29uZi5kZWZhdWx0LmFycF9hbm5vdW5jZT0yCm5ldC5pcHY0LmNvbmYubG8uYXJwX2Fubm91bmNlPTIKbmV0LmlwdjQuY29uZi5hbGwuYXJwX2Fubm91bmNlPTIKa2VybmVsLnBhbmljPTEwCmtlcm5lbC5waWRfbWF4PTMyNzY4Cmtlcm5lbC5zaG1tYXg9NDI5NDk2NzI5NgprZXJuZWwuc2htYWxsPTEwNzM3NDE4MjQKa2VybmVsLmNvcmVfcGF0dGVybj1jb3JlXyVlCnZtLnBhbmljX29uX29vbT0xCiMgdm0ubWluX2ZyZWVfa2J5dGVzPTEwNDg1NzYKdm0udmZzX2NhY2hlX3ByZXNzdXJlPTI1MAp2bS5zd2FwcGluZXNzPTEwCnZtLmRpcnR5X3JhdGlvPTEwCnZtLm92ZXJjb21taXRfbWVtb3J5PTEKZnMuZmlsZS1tYXg9NjU1MzUKZnMuaW5vdGlmeS5tYXhfdXNlcl9pbnN0YW5jZXM9ODE5Mgpmcy5pbm90aWZ5Lm1heF91c2VyX2luc3RhbmNlcz04MTkyCmtlcm5lbC5zeXNycT0xCnZtLnpvbmVfcmVjbGFpbV9tb2RlPTAKbmV0LmlwdjQudGNwX2ZydG8gPSAyCm5ldC5pcHY0LnRjcF9yZW9yZGVyaW5nID0gMzAwCm5ldC5pcHY0LnRjcF9yZXRyYW5zX2NvbGxhcHNlID0gMApuZXQuaXB2NC50Y3BfYXV0b2NvcmtpbmcgPSAxCm5ldC5pcHY0LnRjcF9tb2RlcmF0ZV9yY3ZidWYgPSAxCm5ldC5pcHY0LnRjcF90c29fd2luX2Rpdmlzb3IgPSAzCm5ldC5pcHY0LnRjcF9yZmMxMzM3ID0gMQpuZXQuaXB2NC5pY21wX2VjaG9faWdub3JlX2Jyb2FkY2FzdHMgPSAxCm5ldC5pcHY0LmljbXBfaWdub3JlX2JvZ3VzX2Vycm9yX3Jlc3BvbnNlcyA9IDEKCm5ldC5jb3JlLmRlZmF1bHRfcWRpc2M9IGNha2UKbmV0LmlwdjQudGNwX2Nvbmdlc3Rpb25fY29udHJvbD1iYnIKbmV0LmlwdjQudGNwX3dpbmRvd19zY2FsaW5nPTEKbmV0LmlwdjQucm91dGUuZmx1c2g9MQpuZXQuaXB2NC5pcF9mb3J3YXJkID0gMQojVENQIDE3MG1zLDFHYnBzCiNCRFA9KDEwMDAqIDAuMTcqMTAwMCoxMDAwKS84PTIxMjUwMDAwCm5ldC5jb3JlLnJtZW1fbWF4PTIxMjUwMDAwCm5ldC5jb3JlLndtZW1fbWF4PTIxMjUwMDAwCm5ldC5pcHY0LnRjcF93bWVtPTQwOTYgMTYzODQgMjEyNTAwMDAKbmV0LmlwdjQudGNwX3JtZW09NDA5NiA4NzM4MCAyMTI1MDAwMApFT0YK' | base64 -d | bash"

# Setting GRUB ...
sed -ri 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=5/' /mnt/etc/default/grub
sed -ri 's/^#GRUB_TERMINAL_OUTPUT/GRUB_TERMINAL_OUTPUT/' /mnt/etc/default/grub
sed -ri "s/^GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=\"rootfs=compress-force=zstd net.ifnames=0 biosdevname=0 console=ttyS0 earlyprint=serial,ttyS0,keep loglevel=7 nomodeset audit=0\"/g" /mnt/etc/default/grub
sed -ri 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=true/' /mnt/etc/default/grub

# Setting Bootloader
if [ "\${uefi}" = "true" ]; then
  mkdir -p /mnt/sys/firmware/efi/efivars
  mount --rbind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars
  #chroot /mnt grub-install --efi-directory=/boot/efi --bootloader-id=GRUB --recheck --no-floppy --force --removable --no-nvram
  chroot /mnt grub-install --efi-directory=/boot/efi --bootloader-id=GRUB --recheck --no-floppy
  chroot /mnt efibootmgr
  umount /mnt/sys/firmware/efi/efivars
else
  chroot /mnt grub-install --recheck --force --removable  ${disk}
fi

#chroot /mnt update-grub
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# FIX!!! : Replace /boot/grub/grub.cfg to uuid boot
disk_uuid=\$( blkid -s UUID -o value  \${disk}2)
sed -i "s|root=/dev/[^ ]*|root=UUID=\$disk_uuid|g" /mnt/boot/grub/grub.cfg

# FIX!!! : Weak EFI implementation only recognizes the fallback bootloader
[ -d '/mnt/boot/efi/EFI/GRUB' ] && {
    mkdir -p /mnt/boot/efi/EFI/BOOT
    cp /mnt/boot/efi/EFI/GRUB/* /mnt/boot/efi/EFI/BOOT
}

sync

# All done !!!
for mountpoint in \$(find /mnt -type d | sort -r); do
  if mountpoint -q "\$mountpoint"; then
    echo "Unmounting \$mountpoint"
    umount -l "\$mountpoint"
  fi
done

sync
trap - EXIT
reboot -f
EOF

  chmod 0755 ${sim_root}/init
}

function sim::create_ramos(){

  sim::cleanup_exit
  trap 'sim::cleanup_warp_exit; exit $?' ERR
  trap 'sim::cleanup_warp_exit' EXIT
  
  sysctl -w kernel.panic=10  > /dev/null 2>&1 && sim::log "[*] Successfully set kernel.panic to 10"
  sysctl -w kernel.sysrq=1  > /dev/null 2>&1 && sim::log "[*] Successfully enabled kernel.sysrq"
   
  sim::log "[*] Creating workspace in '${sim_root}'..."
  mkdir -p "${sim_root}"
  
  sim::log "[*] Mounting temporary rootfs..."
  mount -t tmpfs  -o size=100%  mid "${sim_root}"
  
  sim::_download_ramos_and_extract
  sim::copy_important_config
  sim::install_ramos_packages
  sim::inject_init
  
  swapoff -a;losetup -D || true
  sim::log '[*] Now you will enter the installation process.'
	sim::log '[*] Machine processes with poor performance will be very slow!'
	sim::log "[*] You can try logging in with root and ${password} to check the situation..."
	sleep 1;trap - ERR;trap - EXIT
	systemctl switch-root ${sim_root} /init
}

function sim::hello_world() {
    sim::log '**************************************************************'
    sim::log '                      License: BSD 3'
    sim::log '            Written By: htttps://github.com/dmltbWM/scripts'
    sim::log '**************************************************************'
    sim::log "[*] e.g : --dhcp --pwd ${password} --mirror"
    sim::log "Machine: ${machine_warp:-N/A} Uefi: ${uefi:-N/A} Version: ${ver:-N/A}"
    sim::log "Dhcp: ${dhcp:-N/A}  Mirror: $mirror"
    sim::log 'If you use the --dhcp please make sure your VM supports it !!!'
    sim::log '**************************************************************'
}

function sim::parse_arguments() {
  while [ $# -gt 0 ]; do
    case $1 in
			--mirror)
				mirror="$2"
				shift
				;;
			--pwd)
				password="$2"
				shift
				;;
			--disk)
				disk="$2"
				shift
				;;
			--dhcp)
				dhcp='true'
				;;
			*)
				sim::fatal "Unsupported parameters: $1"
		esac
		shift
	done
	
	sim::hello_world
  read -r -p "${1:-[!] This operation will clear all data. Are you sure you want to continue? [y/N]} " _confirm
  case "$_confirm" in [yY][eE][sS]|[yY]) true ;; *) false ;; esac
  
}

if sim::parse_arguments "$@" ; then
  sim::create_ramos
  exit 1
else
  sim::log '[!] Congratulations! You win!'
  sim::log '[!] Oops! Did you mean "goodbye"? Don’t worry, installations can be tricky! 😂'
  sim::log '[!] Maybe try again with different arguments and see what happens?'
  exit 1
fi

