#!/bin/bash

count=0
tmp1=/tmp/.tmp1
tmp2=/tmp/.tmp2
>$tmp1
>$tmp2
fstab_file=/etc/fstab

#check lock file ,one time only let the script run one time 
LOCKfile=/tmp/.$(basename $0)
if [ -f "$LOCKfile" ]
then
  echo -e "\033[1;40;31mThe script is already exist,please manually delete the following files from your system: /tmp/.auto_fdisk.sh /tmp/.tmp1 /tmp/.tmp2 .\033[0m"
  exit
else
  echo -e "\033[40;32mStep 1.No lock file,begin to create lock file and continue.\033[40;37m"
  touch $LOCKfile
fi

trap "exit_fun" 1 2 3 15

#check user
if [ $(id -u) != "0" ]
then
  echo -e "\033[1;40;31mError: You must be root to run this script, please use root to install this script.\033[0m"
  exit_fun
fi

#check disk partition
check_disk()
{
  >$LOCKfile
  device_list=$(fdisk -l|grep "Disk"|grep "/dev"|awk '{print $2}'|awk -F: '{print $1}'|grep "vd")
  for i in `echo $device_list`
  do
    device_count=$(fdisk -l $i|grep "$i"|awk '{print $2}'|awk -F: '{print $1}'|wc -l)
    echo 
    if [ $device_count -lt 2 ]
    then
      now_mount=$(df -h)
      if echo $now_mount|grep -w "$i" >/dev/null 2>&1
      then
        echo -e "\033[40;32mThe $i disk is mounted.\033[40;37m"
      else
        echo $i >>$LOCKfile
        echo "You have a free disk,Now will fdisk it and mount it."
      fi
	else
		echo -e "\033[40;32mThe $i disk is fdisk.\033[40;37m"
	fi
  done
  disk_list=$(cat $LOCKfile)
  if [ "X$disk_list" == "X" ]
  then
    echo -e "\033[1;40;31mNo free disk need to be fdisk.Exit script.\033[0m"
    exit_fun
  else
    echo -e "\033[40;32mThis system have free disk :\033[40;37m"
    for i in `echo $disk_list`
    do
      echo "$i"
      count=$((count+1))
    done
  fi
}

#fdisk ,formating and create the file system
fdisk_fun()
{
fdisk -S 56 $1 << EOF
n
p
1


wq
EOF

sleep 5
mkfs.ext4 ${1}1
}

#fdisk ,formating and create the file system with the parameters
fdisk_mkfs_fun()
{
fdisk -S 56 $1 << EOF
n
p
1


wq
EOF

sleep 5
mkfs.$2 ${1}1
if [ $? -ne 0 ]
then
	exit_fun
fi
}

#make directory
make_dir()
{
  echo -e "\033[40;32mStep 4.Begin to make directory\033[40;37m"
  now_dir_count=$(ls /|grep "jddata*"|awk -F "jddata" '{print $2}'|sort -n|tail -1)
  if [ "X$now_dir_count" ==  "X" ]
  then
    for j in `seq $count`
    do
      echo "/jddata$j" >>$tmp1
      mkdir /jddata$j
    done
  else
    for j in `seq $count`
    do
      k=$((now_dir_count+j))
      echo "/jddata$k" >>$tmp1
      mkdir /jddata$k
    done
  fi
 }

#config /etc/fstab and mount device
main()
{
  for i in `echo $disk_list`
  do
    echo -e "\033[40;32mStep 3.Begin to fdisk free disk.\033[40;37m"
    fdisk_fun $i
	uuid=$(blkid -s UUID "${i}1"|awk -F": " '{print $2}')
    echo $uuid >>$tmp2
  done
  make_dir
  >$LOCKfile
  paste $tmp2 $tmp1 >$LOCKfile
  echo -e "\033[40;32mStep 5.Begin to write configuration to /etc/fstab and mount device.\033[40;37m"
  while read a b
  do
    echo "${a}             $b                 ext4    defaults,nofail        0 0" >>$fstab_file
  done <$LOCKfile
  mount -a
}

exit_fun()
{
	rm -rf $LOCKfile $tmp1 $tmp2
	exit
}

#=========start script===========
if [ $# -eq 0 ]
then 
	echo -e "\033[40;32mStep 2.Begin to check free disk.\033[40;37m"
	check_disk
	main
	df -h
	exit_fun
fi

if [ $# -ne 3 ]
then
	echo -e "\033[1;40;31mParameter is invalid,please input device name,mount point and file system to this script.\033[0m"
	exit_fun
else
	echo -e "\033[40;32mStep 2.Begin to check input parameters.\033[40;37m"
fi
#check device name
devnamearr=(/dev/vda /dev/vdb /dev/vdc /dev/vdd /dev/vde)
if echo "${devnamearr[@]}" | grep -w "$1"  >/dev/null 2>&1
then
	device_count=$(fdisk -l $1|grep "$1"|awk '{print $2}'|awk -F: '{print $1}'|wc -l)
	if [ $device_count -lt 2 ]
	then		
		devname=$1
		echo "The $1 a free disk,Now will fdisk it and mount it."
	else
		echo -e "\033[40;32mThe $1 disk is fdisk.\033[40;37m"
		exit_fun
	fi
else
	echo -e "\033[1;40;31mDevice name is invalid!\033[0m"
	exit_fun
fi
#check mount point
if [ -d "$2" ]
then
	num=2
	while :
	do
		echo -n "Warning：This directory exists , is this ok ? [Y/N]"
		read flag
		case "$flag" in
			Y|y) moupoint=$2
				echo $moupoint >>$tmp1 
				break ;;
			N|n) exit_fun ;;
			*) let "num--" ;;
		esac
			
		if [ $num -lt 0 ]
		then
			exit_fun
		fi
	done
else
	mkdir $2
	if [ $? -eq 0 ]
	then
		moupoint=$2
		echo $moupoint >>$tmp1
	else
		exit_fun
	fi
fi
#check file system
filesystemarr=(btrfs cachefiles ceph cifs cramfs dlm exofs ext2 ext3 ext4 fat fscache fuse gfs2 isofs jbd2 lockd nfs nfs_common nfsd nls overlayfs pstore squashfs udf xfs configfs ecryptfs exportfs freevxfs hfs hfsplus jbd jffs2 msdos vfat)
if echo "${filesystemarr[@]}" | grep -w "$3" &>/dev/null
then
	filesystem=$3
else
	echo -e "\033[1;40;31mFile system is invalid!\033[0m"
	exit_fun
fi
fdisk_mkfs_fun $devname $filesystem
uuid=$(blkid -s UUID "${devname}1"|awk -F": " '{print $2}')
echo $uuid >>$tmp2
>$LOCKfile
paste $tmp2 $tmp1 >$LOCKfile
echo -e "\033[40;32mStep 5.Begin to write configuration to /etc/fstab and mount device.\033[40;37m"
while read a b
do
	echo "${a}             $b                 $filesystem    defaults,nofail        0 0">>$fstab_file
done <$LOCKfile
mount -a
df -h
exit_fun
