#!/bin/sh

simbsd_root='/simbsd'
dist="${simbsd_root}/dist"
root_dir="${simbsd_root}/sim"
boot_dir="${root_dir}/boot"
dest_dir=${root_dir}
arch='amd64'
version='14.1-RELEASE'

prune_list="
usr/bin/c++
usr/bin/c++filt
usr/bin/g++
usr/bin/c89
usr/bin/c99
usr/bin/CC
usr/bin/cc
usr/bin/clang
usr/bin/clang++
usr/bin/clang-cpp
usr/bin/clang-tblgen
usr/bin/cpp
usr/bin/gcc
usr/bin/yacc
usr/bin/f77
usr/bin/byacc
usr/bin/addr2line
usr/bin/ar
usr/bin/gnu-ar
usr/bin/gnu-ranlib
usr/bin/as
usr/bin/gasp
usr/bin/gcov
usr/bin/gdb
usr/bin/gdbreplay
usr/bin/kyua
usr/bin/ld
usr/bin/ld.bfd
usr/bin/ld.lld
usr/bin/lldb
usr/bin/lldb-tblgen
usr/bin/llvm-addr2line
usr/bin/llvm-ar
usr/bin/llvm-cov
usr/bin/llvm-cxxfilt
usr/bin/llvm-nm
usr/bin/llvm-objdump
usr/bin/llvm-profdata
usr/bin/llvm-ranlib
usr/bin/llvm-symbolizer
usr/bin/llvm-tblgen
usr/bin/nm
usr/bin/objcopy
usr/bin/objdump
usr/bin/ranlib
usr/bin/readelf
usr/bin/size
usr/bin/strip
usr/bin/svnlite
usr/bin/svnliteadmin
usr/bin/svnlitebench
usr/bin/svnlitedumpfilter
usr/bin/svnlitefsfs
usr/bin/svnlitelook
usr/bin/svnlitemucc
usr/bin/svnliterdump
usr/bin/svnliteserve
usr/bin/svnlitesync
usr/bin/svnliteversion
usr/bin/gdbtui
usr/bin/kgdb
usr/games
usr/include
usr/lib32
usr/lib/*.a
usr/lib/clang
usr/lib/private/*.a
usr/lib/private/libunbound*
usr/libexec/cc1
usr/libexec/cc1obj
usr/libexec/cc1plus
usr/libexec/f771
usr/sbin/unbound*
usr/share/dict
usr/share/doc
usr/share/examples
usr/share/info
usr/share/games
usr/share/man
usr/share/openssl
usr/share/nls
"

log() { local _date=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\e[0;32m[${_date}]\e[0m $@" >&2; }
fatal() { log "$@"; log "Exiting."; exit 1; }

download_and_extract_freebsd(){
	 chflags -R noschg ${simbsd_root}
	 rm -rf ${simbsd_root}
	 mkdir -p ${boot_dir} && chown root:wheel ${simbsd_root} && chown root:wheel ${boot_dir} 
	 mkdir -p ${boot_dir}/kernel ${boot_dir}/modules && chown -R root:wheel ${boot_dir}
	 
	 log "Downloading base and kernel ..."
	 fetch  -o - "https://download.freebsd.org/ftp/releases/${arch}/${version}/base.txz" > "${simbsd_root}/base.txz"
	 fetch  -o - "https://download.freebsd.org/ftp/releases/${arch}/${version}/kernel.txz" > "${simbsd_root}/kernel.txz"
	 log "Extracting base and kernel ..."
	 cat "${simbsd_root}/base.txz" | tar --unlink -xpzf - -C  "${dest_dir}"
	 cat "${simbsd_root}/kernel.txz" | tar --unlink -xpzf - -C "${root_dir}"
}

remove_selected_files(){
	 chflags -R noschg ${dest_dir} > /dev/null 2> /dev/null || exit 0
	 log "Removing selected files from distribution  ..."
	 for _file in $(echo "$prune_list"); do
		if [ -n "${_file}" ]; then
			_del="${dest_dir}/${_file}"
			#log "Delete select file : ${dest_dir}/${_file}"
			rm -rf $_del;
		fi
	done
}

copy_cdboot_and_efi_loader(){
	log 'Copying out cdboot and EFI loader ...'
	mkdir -p ${simbsd_root}/cdboot
	cp -f ${dest_dir}/boot/cdboot ${simbsd_root}/cdboot/
	cp -f ${dest_dir}/boot/loader_4th.efi ${simbsd_root}/cdboot/
	cp -f ${dest_dir}/boot/loader_lua.efi ${simbsd_root}/cdboot/
}

create_scripts_and_files(){
	log 'Installing configuration scripts and files ...'
	mkdir -p  ${dest_dir}/stand ${dest_dir}/etc/rc.conf.d
	cat > ${dest_dir}/boot.config<<EOF
-D
EOF

	cat > ${dest_dir}/boot/loader.conf<<EOF
mfs_load="YES"
mfs_type="mfs_root"
mfs_name="/simbsd"
ahci_load="YES"
console=comconsole
vfs.root.mountfrom="ufs:/dev/md0"
EOF

	cat > ${dest_dir}/etc/rc.local<<EOF
# rc.local
EOF

	cat > ${dest_dir}/etc/rc.conf<<EOF
sshd_enable="YES"
sendmail_enable="NONE"
cron_enable="NO"
local_enable="YES"
EOF

	cat > ${dest_dir}/etc/ttys<<EOF
console	none				unknown	off secure
ttyv0	"/usr/libexec/getty Pc"		xterm	on  secure
ttyv1	"/usr/libexec/getty Pc"		xterm	off secure
ttyv8	"/usr/local/bin/xdm -nodaemon"	xterm	off secure
ttyu0	"/usr/libexec/getty 3wire"	vt100	onifconsole secure
ttyu1	"/usr/libexec/getty 3wire"	vt100	onifconsole secure
dcons	"/usr/libexec/getty std.9600"	vt100	off secure
EOF

	cat > ${dest_dir}/etc/hosts<<EOF
::1             localhost localhost.my.domain
127.0.0.1       localhost localhost.my.domain
EOF

	cat > ${dest_dir}/etc/rc.conf.d/interfaces<<EOF
#mac_interfaces="vtnet0"
#ifconfig_vtnet0="inet 192.168.1.1/24"
EOF

	echo 'nameserver 1.1.1.1' > ${dest_dir}/etc/resolv.conf
		
	echo "/dev/md0 / ufs rw 0 0" > ${dest_dir}/etc/fstab
	echo "tmpfs /tmp tmpfs rw,mode=1777 0 0" >> ${dest_dir}/etc/fstab

	echo 'sim@@@'| openssl passwd -6 -stdin | pw -V ${dest_dir}/etc usermod root -H 0
	echo 'PermitRootLogin yes' >> ${dest_dir}/etc/ssh/sshd_config	
	
	log 'Generating SSH host keys ...'
	test -f ${dest_dir}/etc/ssh/ssh_host_key || ssh-keygen -t rsa -b 2048 -f ${dest_dir}/etc/ssh/ssh_host_key -N '' > /dev/null 2> /dev/null || true
	test -f ${dest_dir}/etc/ssh/ssh_host_dsa_key || ssh-keygen -t dsa -f ${dest_dir}/etc/ssh/ssh_host_dsa_key -N '' > /dev/null 2> /dev/null || true
	test -f ${dest_dir}/etc/ssh/ssh_host_rsa_key || ssh-keygen -t rsa -f ${dest_dir}/etc/ssh/ssh_host_rsa_key -N '' > /dev/null
	test -f ${dest_dir}/etc/ssh/ssh_host_ecdsa_key || ssh-keygen -t ecdsa -f ${dest_dir}/etc/ssh/ssh_host_ecdsa_key -N '' > /dev/null
	test -f ${dest_dir}/etc/ssh/ssh_host_ed25519_key || ssh-keygen -t ed25519 -f ${dest_dir}/etc/ssh/ssh_host_ed25519_key -N '' > /dev/null
	
	
	#
	cat > ${dest_dir}/etc/rc.d/mdinit<<"EOF"
#!/bin/sh
# $Id$

# PROVIDE: mdinit
# BEFORE: FILESYSTEMS
# REQUIRE: mountcritlocal
# KEYWORD: FreeBSD

. /etc/rc.subr

name="mdinit"
start_cmd="mdinit_start"
stop_cmd=":"

mdinit_start()
{
	if [ -f /.usr.tar.xz ]; then
		/sbin/mount -t tmpfs tmpfs /usr
		/rescue/xz -d -c /.usr.tar.xz | /rescue/tar -x -C / -f -
	elif [ -f /.usr.tar.bz2 ]; then
		/sbin/mount -t tmpfs tmpfs /usr
		/rescue/bzip2 -d -c /.usr.tar.bz2 | /rescue/tar -x -C / -f -
	elif [ -f /.usr.tar.gz ]; then
		/sbin/mount -t tmpfs tmpfs /usr
		/rescue/gzip -d -c /.usr.tar.gz | /rescue/tar -x -C / -f -
	fi
	
	# Check if we are using injectfs 
}

load_rc_config $name
run_rc_command "$1"
EOF
chmod 0555 ${dest_dir}/etc/rc.d/mdinit

	cat > ${dest_dir}/etc/rc.d/interfaces<<"EOF"
#!/bin/sh
# $Id$

# PROVIDE: interfaces
# BEFORE: NETWORKING netif
# REQUIRE: mdinit simbsd
# KEYWORD: FreeBSD

. /etc/rc.subr

name="interfaces"
start_cmd="interfaces_start"
stop_cmd=":"

interfaces_start()
{
	if [ -z "${mac_interfaces}" ]; then
	    exit 0
	fi
	for if in ${mac_interfaces}; do
		_cmac=`eval echo "\\$ifconfig_${if}_mac"`
		if [ -n "$_cmac" ]; then
			_dif=`/sbin/ifconfig -l | /usr/bin/sed -E 's/lo[0-9]+//g'`
			for i in $_dif; do
				_mac=`/sbin/ifconfig $i | /usr/bin/grep ether | /usr/bin/awk '{ print $2 }'`
				if [ "$_mac" = "$_cmac" ]; then
					_cif=`eval echo "\\$ifconfig_${if}"`
					if [ -n "$_cif" ]; then
						echo "ifconfig_$i=\"${_cif}\"" >> /etc/rc.conf.d/network
					fi
				fi
			done
		fi
	done
}

load_rc_config $name
run_rc_command "$1"
EOF
chmod 0555 ${dest_dir}/etc/rc.d/interfaces

	cat > ${dest_dir}/etc/rc.d/packages<<"EOF"
#!/bin/sh
# $Id$

# PROVIDE: packages
# BEFORE: LOGIN
# REQUIRE: mdinit tmp var
# KEYWORD: FreeBSD

. /etc/rc.subr

name="packages"
start_cmd="packages_start"
stop_cmd=":"

packages_start()
{
	PACKAGES=`/bin/ls -1 /packages/*.t?z 2>/dev/null`
	if /bin/test -n "$PACKAGES"; then
		MD=`/sbin/mdconfig -a -t swap -s 64m`
		/sbin/newfs -U /dev/$MD
		/sbin/mount /dev/$MD /usr/local
		cd /packages && /usr/sbin/pkg_add *.t?z > /dev/null 2> /dev/null
	fi
}

load_rc_config $name
run_rc_command "$1"
EOF
chmod 0555 ${dest_dir}/etc/rc.d/packages

	cat > ${dest_dir}/etc/rc.d/simbsd<<"EOF"
#!/bin/sh
# $Id$

# PROVIDE: simbsd
# BEFORE: NETWORKING netif routing hostname
# REQUIRE: mountcritlocal mdinit
# KEYWORD: FreeBSD

. /etc/rc.subr

name="simbsd"
start_cmd="simbsd_start"
stop_cmd=":"

simbsd_start()
{
	_hn=`/bin/kenv -q hostname`
	_clif=`/bin/kenv -q cloned_interfaces`
	_mif=`/bin/kenv -q mac_interfaces`
	_dhcp=`/bin/kenv -q autodhcp`
	_if=`/bin/kenv -q interfaces`
	_dr=`/bin/kenv -q defaultrouter`
	_sr=`/bin/kenv -q static_routes`
	_rootpw=`/bin/kenv -q rootpw`
	_rootpwhash=`/bin/kenv -q rootpwhash`
	if [ -n "$_hn" ]; then
		echo "hostname=\"$_hn\"" >> /etc/rc.conf.d/hostname
	fi
	if [ -n "$_clif" ]; then
		echo "cloned_interfaces=\"$_clif\"" >> /etc/rc.conf.d/network
	fi
	if [ -n "$_mif" ]; then
		echo "mac_interfaces=\"$_mif\"" >> /etc/rc.conf.d/interfaces
		for i in $_mif; do
			_mac=`/bin/kenv ifconfig_${i}_mac`
			if [ -n "$_mac" ]; then
				echo "ifconfig_${i}_mac=\"$_mac\"" >> /etc/rc.conf.d/interfaces
			fi
			_config=`/bin/kenv ifconfig_$i`
			if [ -n "$_config" ]; then
				echo "ifconfig_$i=\"$_config\"" >> /etc/rc.conf.d/interfaces
			fi
		done
	fi
	if [ -n "$_dhcp" ]; then
		if `checkyesno _dhcp`; then
			_dif=`/sbin/ifconfig -l | /usr/bin/sed -E 's/lo[0-9]+//g'`
			for i in $_dif; do
				echo "ifconfig_$i=\"DHCP\"" >> /etc/rc.conf.d/network
			done
		fi
	fi
	for i in $_if $_mif $_clif; do
		_config=`/bin/kenv ifconfig_$i`
		if [ -n "$_config" ]; then
			echo "ifconfig_$i=\"$_config\"" >> /etc/rc.conf.d/network
		fi
	done
	if [ -n "$_dr" ]; then
		echo "defaultrouter=\"$_dr\"" >> /etc/rc.conf.d/routing
	fi
	if [ -n "$_sr" ]; then
		echo "static_routes=\"$_sr\"" >> /etc/rc.conf.d/routing
		for i in $_sr; do
			_config=`/bin/kenv route_$i`
			if [ -n "$_config" ]; then
				echo "route_$i=\"$_config\"" >> /etc/rc.conf.d/routing
			fi
		done
	fi

    [ -n "$_rootpw" ] && echo $_rootpw | /usr/sbin/pw usermod root -h 0 && /bin/kenv -u rootpw
    [ -n "$_rootpwhash" ] && echo $_rootpwhash | /usr/bin/sed -e 's,%,$,g' | /usr/sbin/pw usermod root -H 0 && /bin/kenv -u rootpwhash
	[ -e "/tmp/inject.sh" ] && /tmp/inject.sh

}

load_rc_config $name
run_rc_command "$1"	
EOF
chmod 0555 ${dest_dir}/etc/rc.d/simbsd
	
}

create_boot_environment(){
	log 'Configuring boot environment ...'
	
	mkdir -p ${simbsd_root}/disk/boot/kernel && chown  root:wheel ${simbsd_root}/disk
	local exclude_file=$(mktemp)
	echo -e "kernel.debug\n*.symbols\n*.ko" > "$exclude_file"
	tar -c -X ${exclude_file} -C ${boot_dir}/kernel -f - . | tar -xv -C ${simbsd_root}/disk/boot/kernel -f -
	rm "$exclude_file"
	
	cp -f -rp ${dest_dir}/boot.config ${simbsd_root}/disk
	local files='defaults device.hints loader_lua lua'
	for _file in $(echo "$files"); do
		cp -f -rp ${dest_dir}/boot/${_file} ${simbsd_root}/disk/boot
	done
	
	mv -f ${simbsd_root}/disk/boot/loader_lua ${simbsd_root}/disk/boot/loader
	rm -rf ${simbsd_root}/disk/boot/kernel/*.ko  ${simbsd_root}/disk/boot/kernel/*.symbols
	
	log 'Copying acpi ...'
	find ${boot_dir}/kernel -name 'acpi*.ko' -exec install -m 0555 {} ${simbsd_root}/disk/boot/kernel \;
	
	log 'Copying BOOTMODULES ...'
	local BOOTMODULES='acpi ahci'
	for _file in $BOOTMODULES; do
		[ ! -f ${boot_dir}/kernel/${_file}.ko ] || \
			install -m 0555 ${boot_dir}/kernel/${_file}.ko ${simbsd_root}/disk/boot/kernel
	done
	
	log 'Installing modules ...'
	mkdir  -p ${dest_dir}/boot/modules
	local _MODULES='aesni crypto cryptodev ext2fs geom_eli geom_mirror geom_nop ipmi ntfs nullfs opensolaris smbus snp tmpfs zfs'
	for _file in $(echo "$_MODULES"); do
		[ ! -f "${boot_dir}/kernel/${_file}.ko" ] || \
		install -m 0555 "${boot_dir}/kernel/${_file}.ko" "${dest_dir}/boot/modules"
	done
	
	rm -rf ${boot_dir}/kernel ${boot_dir}/*.symbols
	mkdir -p ${simbsd_root}/boot
	cp -f -p ${dest_dir}/boot/pmbr ${dest_dir}/boot/gptboot ${simbsd_root}/boot
}

create_efi_boot_image(){
	log 'Creating EFI boot image ...'
	mkdir -p ${simbsd_root}/efiroot/EFI/BOOT
	cp -f ${simbsd_root}/cdboot/loader_lua.efi ${simbsd_root}/efiroot/EFI/BOOT/BOOTX64.efi
	makefs -t msdos -s 2048k -o fat_type=12,sectors_per_cluster=1 ${simbsd_root}/cdboot/efiboot.img ${simbsd_root}/efiroot
}

install_pkgng(){
	log 'Installing pkgng ...'
	mkdir -p "${dest_dir}/usr/local/sbin"

	local PKG_STATIC='/usr/local/sbin/pkg-static'
	install -o root -g wheel -m 0755 "${PKG_STATIC}" "${dest_dir}/usr/local/sbin/"
	ln -sf pkg-static "${dest_dir}/usr/local/sbin/pkg"

	local _pkgs='cpdup dmidecode indexinfo ipmitool libevent libiconv nano readline rsync smartmontools tmux utf8proc'
	local PKG_ABI="FreeBSD:$(uname -U | cut -c 1-2):$(uname -m)"
	
	ASSUME_ALWAYS_YES=yes \
	PKG_ABI="${PKG_ABI}" \
	PKG_CACHEDIR="${simbsd_root}/pkgcache" \
	pkg -r "${dest_dir}" install $_pkgs
}

compress_files(){
	log "Compressing usr ..."
	tar -c -J -C ${dest_dir} -f ${dest_dir}/.usr.tar.xz usr
	rm -rf ${dest_dir}/usr && mkdir ${dest_dir}/usr 
}

create_and_compress_simbsd(){
	log 'Creating and compressing simbsd ...'
	mkdir ${simbsd_root}/mnt
	local max_size='256m'
	local free_inodes='10%'
	local free_blocks='10%'
	makefs  -t ffs -m ${max_size} -f ${free_inodes} -b ${free_blocks} ${simbsd_root}/disk/simbsd ${root_dir} > /dev/null
	rm -rf ${simbsd_root}/mnt
	gzip -9 -f ${simbsd_root}/disk/simbsd
	gzip -9 -f ${simbsd_root}/disk/boot/kernel/kernel
	
	if [ -f "${dest_dir}/boot/loader.conf" ]; then
		install -m 0644 ${dest_dir}/boot/loader.conf ${simbsd_root}/disk/boot/loader.conf
	fi
}

create_img_simbsd(){
	log 'Creating image simbsd ...'
	#default gptpart or bsdpart
	local fssize=0
	local fslable='auto'
	local fsimg='simbsd.img'
	local fsproto="${simbsd_root}/disk"
	local tmpimg=$(mktemp -t ${fsimg})
	local efiimg="${simbsd_root}/cdboot/efiboot.img"
	
	local imgsize=0
	if [ ${fssize} -eq 0 -a ${fslable} = "auto" ]; then
		roundup() echo $((($1+$2-1)-($1+$2-1)%$2))
		local nf=$(find ${fsproto} |wc -l)
		local sk=$(du -skA ${fsproto} |cut -f1)
		fssize=$(roundup $(($sk*12/10)) 1024)
		imgsize=$((${fssize}+128))
	fi
	log "FSIMG ${fsimg} FSPROTO ${fsproto} FSSIZE ${fssize}"
	
	
	dd of=${fsimg} if=/dev/zero count=${imgsize} bs=1k
	dd of=${tmpimg} if=/dev/zero count=${fssize} bs=1k
	
	local _md=$(mdconfig -a -t vnode -f ${fsimg})
	
	gpart create -s gpt ${_md}
	gpart add -t freebsd-boot -b 40 -l boot -s 472 ${_md}
	gpart bootcode -b ${boot_dir}/pmbr -p ${boot_dir}/gptboot -i 1 ${_md}
	
	# efi support
	gpart add -t efi -s 2m ${_md}
	time dd if=${efiimg} of=/dev/${_md}p2 bs=128k
	
	# rootfs
	gpart add -t freebsd-ufs -l rootfs ${_md}
	time makefs -B little ${tmpimg} ${fsproto}
	time dd if=${tmpimg} of=/dev/${_md}p3 bs=128k
	
	#injectfs
	gpart add -t ms-dos -s 10M -l injectfs ${_md}
	
}

create_iso_simbsd(){
	log 'Creating ISO simbsd ...'
	makefs -t cd9660 -o rockridge,label=simbsd \
	-o bootimage=i386\;${simbsd_root}/cdboot/cdboot,no-emul-boot \
	-o bootimage=i386\;${simbsd_root}/cdboot/efiboot.img,no-emul-boot,platformid=efi \
	simbsd.iso ${simbsd_root}/disk
	
	#makefs -t cd9660 -o rockridge,label=simbsd \
	#-o bootimage=i386\;${simbsd_root}/cdboot/cdboot,no-emul-boot \
	#simbsd-bios.iso ${simbsd_root}/disk
}

download_and_extract_freebsd
remove_selected_files
copy_cdboot_and_efi_loader
create_scripts_and_files
create_boot_environment
create_efi_boot_image
install_pkgng
compress_files
create_and_compress_simbsd
create_img_simbsd
create_iso_simbsd


# apt install -y grub-imageboot
# rm /usr/local/www/nginx/simbsd* ;cp simbsd* /usr/local/www/nginx;ls /usr/local/www/nginx
# http://192.168.1.1/simbsd.img
# rm -rf /boot/images/* ; curl -o /boot/images/simbsd.iso http://192.168.1.1/simbsd.iso;update-grub

# make  BASE=/mnt/usr/freebsd-dist RELEASE=14.1-RELEASE NO_ROOTHACK=1 MFSROOT_MAXSIZE=256m V=1
# make iso  BASE=/mnt/usr/freebsd-dist RELEASE=14.1-RELEASE NO_ROOTHACK=1 MFSROOT_MAXSIZE=256m V=1
# make tar  BASE=/mnt/usr/freebsd-dist RELEASE=14.1-RELEASE NO_ROOTHACK=1 MFSROOT_MAXSIZE=256m V=1


#device=$(df / | awk 'NR==2 {print $1}')
#part_num=$(echo "$device" | grep -oE '[0-9]+$')
#echo $part_num
#
#cat >/etc/grub.d/40_custom<<"EOF"
#!/bin/sh
#exec tail -n +3 $0
#menuentry "SimBSD" {
#	insmod ufs2
#	insmod part_msdos
#	insmod part_gpt
#	set root=(hd0,gpt2)
#	set isofile="/@/boot/images/simbsd.iso"
#	loopback loop $isofile
#	kfreebsd (loop)/boot/kernel/kernel.gz -v
#	echo "kernel loaded"
#	kfreebsd_loadenv (loop)/boot/device.hints
#	kfreebsd_module (loop)/boot/kernel/ahci.ko
#	echo "ahci.ko loaded"
#	kfreebsd_module (loop)/simbsd.gz type=mfs_root
#	set kFreeBSD.vfs.root.mountfrom="ufs:/dev/md0"
#	set kFreeBSD.mfs_type="mfs_root"
#	set kFreeBSD.mfs_name="/simbsd"
#	set kFreeBSD.autodhcp="YES"
#} 
#EOF
#
#grub-mkconfig -o /boot/grub/grub.cfg
