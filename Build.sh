#!/bin/sh
#Build.sh 6.4.1 for netbootcd

## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License
## as published by the Free Software Foundation; either version 2
## of the License, or (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
##
## The full text of the GNU GPL, versions 2 or 3, can be found at
## <http://www.gnu.org/copyleft/gpl.html>, on the NetbootCD site at
## <http://netbootcd.tuxfamily.org>, or on the CD itself.

set -e
PATH=$PATH:/sbin
WORK=$(pwd)/work
DONE=$(pwd)/done
NBINIT=${WORK}/nbinit #for CD/USB
NBINIT2=${WORK}/nbinit2 #for floppy

#Set to false to not build floppy images
FLOPPY=true
NBCDVER=6.4.1
COREVER=6.4.1

NO=0
for i in CorePlus-$COREVER.iso \
nbscript.sh tc-config.diff kexec.tgz \
grub.exe \
dialog.tcz ncurses.tcz bash.tcz \
disksplit.sh;do
	if [ ! -e $i ];then
		echo "Couldn't find $i!"
		NO=1
	fi
done
if $FLOPPY && [ ! -e blank-bootable-1440-floppy.gz ];then
	echo "Couldn't find blank-bootable-1440-floppy.gz!"
	NO=1
fi
for i in zip mkdosfs unsquashfs genisoimage isohybrid;do
	if ! which $i > /dev/null;then
		echo "Please install $i!"
		NO=1
	fi
done
if [ $NO = 1 ];then
	exit 1
fi

#make sure we are root
if [ $(whoami) != "root" ];then
	echo "Please run as root."
	exit 1
fi

if [ -d ${WORK} ];then
	rm -r ${WORK}
fi

mkdir -p ${WORK} ${DONE} ${NBINIT}

#Extract TinyCore ISO to new dir
TCISO=${WORK}/tciso
mkdir ${TCISO} ${WORK}/tcisomnt
mount -o loop CorePlus-$COREVER.iso ${WORK}/tcisomnt
cp -rv ${WORK}/tcisomnt/* ${TCISO}
umount ${WORK}/tcisomnt
rmdir ${WORK}/tcisomnt

#Copy kernel - Core 5.0+ already built with kexec
cp ${TCISO}/boot/vmlinuz ${DONE}/vmlinuz
chmod +w ${DONE}/vmlinuz

#Make nbinit4.gz. NetbootCD itself won't use any separate TCZ files. It will all be in the initrd.
if [ -d ${NBINIT} ];then
	rm -r ${NBINIT}
fi
mkdir ${NBINIT}

FDIR=$(pwd)
cd ${NBINIT}
echo "Extracting..."
gzip -cd ${TCISO}/boot/core.gz | cpio -id
cd -
#write wrapper script
cat > ${NBINIT}/usr/bin/netboot << "EOF"
#!/bin/sh
if [ $(whoami) != "root" ];then
	exec sudo $0 $*
fi

echo "Waiting for internet connection (will keep trying indefinitely)"
echo -n "Testing example.com"
[ -f /tmp/internet-is-up ]
while [ $? != 0 ];do
	sleep 1
	echo -n "."
	wget --spider http://www.example.com &> /dev/null
done
echo > /tmp/internet-is-up

if [ -x /tmp/nbscript.sh ];then
	/tmp/nbscript.sh
else
	/usr/bin/nbscript.sh
fi
echo "Type \"netboot\" to return to the menu."
EOF
chmod +x ${NBINIT}/usr/bin/netboot
#patch /etc/init.d/tc-config
cd ${NBINIT}/..
patch -p0 < ${FDIR}/tc-config.diff
cd -
#copy nbscript
cp -v nbscript.sh ${NBINIT}/usr/bin

#copy dialog & ncurses
if [ -e squashfs-root ];then
	rm -r squashfs-root
fi
for i in dialog.tcz ncurses.tcz;do
	unsquashfs $i
	cp -a squashfs-root/* ${NBINIT}
	rm -r squashfs-root
done

tar -C ${NBINIT} -xvf kexec.tgz

#workaround for libraries. I don't remember what this was for.
#for i in ${NBINIT}/usr/local/lib/*;do
#	BASENAME=$(basename $i)
#	if [ ! -e ${NBINIT}/usr/lib/$BASENAME ];then
#		ln -s ../local/lib/$BASENAME ${NBINIT}/usr/lib/$BASENAME
#	fi
#done

if $FLOPPY;then
	#Make the floppy disk version of the initrd (without bash. bash is needed for read-cfg.sh but it is a big program.)
	cp -a ${NBINIT} ${NBINIT2}
	#now we remove things in a dirty way.
	#remove filesystem utils
	##rm ${NBINIT2}/sbin/*fsck*
	##rm ${NBINIT2}/sbin/mke2fs ${NBINIT2}/sbin/mkfs*
	##rm ${NBINIT2}/sbin/tune2fs
	#remove ext2/3/4 libraries
	##rm ${NBINIT2}/lib/libext2fs*
	#remove filesystem modules
	##rm -r ${NBINIT2}/lib/modules/*/kernel/fs
	#remove device drivers
	##for i in parport scsi usb;do
		##rm -r ${NBINIT2}/lib/modules/*tinycore/kernel/drivers/$i || true
	##done
	#Remove "script" option from nbscript.sh, because bash is not on the floppy disc (too many big dependencies)
	sed -i -e '/^script/d' ${NBINIT2}/usr/bin/nbscript.sh
	#NetbootCD > .profile
	echo "netboot" >> ${NBINIT2}/etc/skel/.profile
	cd ${NBINIT2}
	find . | cpio -o -H 'newc' | gzip -c > ${DONE}/nbflop4.gz
	cd -
	if which advdef 2> /dev/null;then
		advdef -z ${DONE}/nbflop4.gz #extra compression
	fi
	#rm -r ${NBINIT2}
	echo "Made smaller floppy initrd:" $(wc -c ${DONE}/nbflop4.gz)
fi

#copy bash to CD version (supports arrays for read-cfg.sh)
unsquashfs bash.tcz
cp -a squashfs-root/* ${NBINIT}
rm -r squashfs-root

#change background
if [ -f nbcd-bg.png ];then
	mkdir -p ${NBINIT}/usr/local/share/pixmaps/
	cp nbcd-bg.png ${NBINIT}/usr/local/share/pixmaps/
	echo "#!/bin/sh
	hsetroot -add \"#25972d\" -add \"#a2c18f\" -gradient 0 -center /usr/local/share/pixmaps/nbcd-bg.png
	" > ${NBINIT}/etc/skel/.set-nbcd-background
	chmod +x ${NBINIT}/etc/skel/.set-nbcd-background
	sed -i -e 's/startx/mv -f .set-nbcd-background .setbackground\nstartx||netboot\nsleep 5\necho \*\* Type \"netboot\" and press enter to launch the NetbootCD main menu. \*\*/g' ${NBINIT}/etc/skel/.profile
else
	echo "NOTE: will not be changing background logo"
fi

#Add pxe-kexec to nbinit, if it exists in this folder
if [ -f pxe-kexec.tgz ] && [ -f readline.tcz ] && \
   [ -f curl.tcz ] && [ -f openssl.tcz ] && \
   [ -f libgcrypt.tcz ] && [ -f libgpg-error.tcz ] && \
   [ -f libidn.tcz ] && [ -f libssh2.tcz ];then
	mkdir ${WORK}/pxe-kexec
	tar -C ${WORK}/pxe-kexec -xf pxe-kexec.tgz # an extra utility
	for i in readline.tcz curl.tcz openssl.tcz libgcrypt.tcz libgpg-error.tcz libidn.tcz libssh2.tcz;do #dependencies of pxe-kexec
		unsquashfs $i
		cp -a squashfs-root/* ${WORK}/pxe-kexec
		rm -r squashfs-root
	done
	#workaround for libraries
	mkdir ${WORK}/pxe-kexec/usr/lib
	for i in ${WORK}/pxe-kexec/usr/local/lib/*;do
		BASENAME=$(basename $i)
		if [ ! -e ${WORK}/pxe-kexec/usr/lib/$BASENAME ];then
			ln -s ../local/lib/$BASENAME ${WORK}/pxe-kexec/usr/lib/$BASENAME
		fi
	done
	cp -av ${WORK}/pxe-kexec/* ${NBINIT}
	rm -r ${WORK}/pxe-kexec
else
	echo "pxe-kexec not included"
	sleep 2
fi

cd ${NBINIT}
find . | cpio -o -H 'newc' | gzip -c > ${DONE}/nbinit4.gz
cd -
if which advdef 2> /dev/null;then
	advdef -z ${DONE}/nbinit4.gz
fi
#rm -r ${NBINIT}
echo "Made initrd:" $(wc -c ${DONE}/nbinit4.gz)

if $FLOPPY;then
	#Split up the kernel and floppy initrd for several disks
	./disksplit.sh ${DONE}/vmlinuz ${DONE}/nbflop4.gz
fi

if [ -d ${WORK}/iso ];then
	rm -r ${WORK}/iso
fi
mkdir -p ${WORK}/iso/boot/isolinux

cp ${TCISO}/boot/isolinux/isolinux.bin ${WORK}/iso/boot/isolinux #get ISOLINUX from the TinyCore disc
cp ${TCISO}/boot/isolinux/menu.c32 ${WORK}/iso/boot/isolinux #get menu.c32 from the TinyCore disc

cp grub.exe ${WORK}/iso/boot
for i in vmlinuz nbinit4.gz;do
	cp ${DONE}/$i ${WORK}/iso/boot
done

echo "DEFAULT menu.c32
PROMPT 0
TIMEOUT 100
ONTIMEOUT nbcd

LABEL hd
MENU LABEL Boot from hard disk
localboot 0x80

LABEL nbcd
menu label Start ^NetbootCD $NBCDVER
menu default
kernel /boot/vmlinuz
initrd /boot/nbinit4.gz
append quiet

LABEL grub4dos
menu label ^GRUB4DOS 0.4.6a-2015-12-16
kernel /boot/grub.exe
" >> ${WORK}/iso/boot/isolinux/isolinux.cfg

if which mkisofs>/dev/null;then
	CDRTOOLS=1
	MAKER=mkisofs
fi
if which genisoimage>/dev/null;then
	CDRKIT=1
	MAKER=genisoimage
fi
if [ -n $CDRKIT ] && [ -n $CDRTOOLS ];then
	echo "Using genisoimage over mkisofs. It shouldn't make any difference."
fi
$MAKER --no-emul-boot --boot-info-table --boot-load-size 4 \
-b boot/isolinux/isolinux.bin -c boot/isolinux/boot.cat -J -r \
-o ${DONE}/NetbootCD-$NBCDVER.iso ${WORK}/iso

chown -R 1000.1000 $DONE
isohybrid ${DONE}/NetbootCD-$NBCDVER.iso

cp -r ${TCISO}/cde ${WORK}/iso
cp ${TCISO}/boot/core.gz ${WORK}/iso/boot

echo "DEFAULT menu.c32
PROMPT 0

TIMEOUT 100
ONTIMEOUT nbcd

LABEL hd
MENU LABEL Boot from hard disk
localboot 0x80

LABEL nbcd-coreplus
menu label Start CorePlus $COREVER ^on top of NetbootCD $NBCDVER
menu default
kernel /boot/vmlinuz
initrd /boot/nbinit4.gz
append loglevel=3 cde showapps desktop=flwm_topside
text help
Uses the core of NetbootCD with the TCZ extensions of
CorePlus. The result is that CorePlus is loaded first,
and NetbootCD is run when you choose \"Exit To Prompt\".
endtext

LABEL nbcd
menu label Start ^NetbootCD $NBCDVER only
kernel /boot/vmlinuz
initrd /boot/nbinit4.gz
text help
Runs NetbootCD on its own, without loading GUI or extensions.
Boot media is removable.
endtext

LABEL coreplus
menu label Start Core $COREVER with default FLWM topside (Core^Plus)
TEXT HELP
Boot Core plus support extensions of networking, installation and remastering.
All extensions are loaded mount mode. Boot media is not removable.
ENDTEXT
kernel /boot/vmlinuz
initrd /boot/core.gz
append loglevel=3 cde showapps desktop=flwm_topside

LABEL tinycore
menu label Start Core $COREVER with only X/GUI (^TinyCore)
TEXT HELP
Boot Core with flwm_topside. Both user and support extensions are not loaded.
All X/GUI extensions are loaded mount mode. Boot media is not removable.
Use TAB to edit desktop= to boot to alternate window manager.
ENDTEXT
kernel /boot/vmlinuz
initrd /boot/core.gz
append loglevel=3 cde showapps lst=xbase.lst base desktop=flwm_topside

LABEL core
menu label Start ^Core $COREVER (no X/GUI or extensions)
TEXT HELP
Boot Core character text mode to ram. No user or support extensions are loaded.
Boot media is removable.
ENDTEXT
kernel /boot/vmlinuz
initrd /boot/core.gz
append loglevel=3 base

LABEL grub4dos
menu label ^GRUB4DOS 0.4.6a-2015-12-16
kernel /boot/grub.exe
" > ${WORK}/iso/boot/isolinux/isolinux.cfg
$MAKER --no-emul-boot --boot-info-table --boot-load-size 4 \
-b boot/isolinux/isolinux.bin -c boot/isolinux/boot.cat -J -r -l \
-o ${DONE}/NetbootCD-$NBCDVER+CorePlus-$COREVER.iso ${WORK}/iso

chown -R 1000.1000 $DONE
isohybrid ${DONE}/NetbootCD-$NBCDVER+CorePlus-$COREVER.iso
	
rm -r ${WORK}/iso
