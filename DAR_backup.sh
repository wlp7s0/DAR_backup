#!/bin/bash
#This script perform file backup using DAR utility
#Feel free to modify it for your personal purpose
#This script is destributed under GNU GPL license. 
#Originally written to use from crontab
#
#Please run ./DAR_backup.sh first_run to create necessary files and folders!!!!
#
#Depends on: dar, rsync, md5sum, umask, nice, find
#
#Ex: 30 00 1 * * $PATH_TO_SCRIPT/DAR_backup.sh full | mail -s "DAR backup full report" backupmaster@example.com
#EX2: 30 22 * * * $PATH_TO_SCRIPT/DAR_backup.sh diff | mail -s "DAR backup diff report" backupmaster@example.com
#For full list of DAR options, please visit http://dar.linux.free.fr/doc/man/dar.html
#For recovery files from backup see tutorial http://dar.linux.free.fr/doc/Tutorial.html

##################################################
#options
WHAT_TO_BACKUP="/"			#path to parent backup dir
LOCAL_BCK_STORAGE="/home/backup/file/"	#where to put local bacups
REMOTE_BCK_MNT="/mnt/NAS/site"		#NAS mount point. Or where you must put it. Don't store your backups on tha same disk!!
FULL_BCK_FILE_NAME="full_`date +%m-%Y`"	#To find last full back and perform diff, full backup file name has to has "full" in name
DIFF_BCK_FILE_NAME="diff_`date +%d-%m-%Y`"
COMPRESSION_OPTION="xz:9"		#--compression option
ENCR_KEY="-key bf:aeShae4peiFai6veib"	#encryption for archive. Leave blank to disable. See DAR man for all cipers available
EXCL_FILENAME=""			#; separated
EXCL_PATH="proc;sys;dev/pts;$LOCAL_BCK_STORAGE;mnt;tmp"				#Ralative WHAT_TO_BACK option. ;-separated
CREATE_EMPTY="-D"			#creates empty dir of EXCL_PATH. To disable - empty
SLICE="" 				#leave empty to ignore. Sets max file size of a backup file
NO_COMPRESSION="*.mp3;*.avi;*.mpg;*.mpeg;*.divx;*.wmv;*.wma;*.alaw;*.asf;*.ra;*.ulaw;*.gsm;*.wav;*.gif;*.jpg;*.jpeg;*.png;*.zip;*.tgz;*.gzip;*.bzip;*.gz;*.bzip2;*.rar;*.Z;*.bz2"
ALLOW_AS_USER=0				#If you want script to be run as user, change to 1
NICE_LVL=-5				#0-default. (Lover-more CPU time)
RSYNC_BANDWIDTH_LIMIT=""		#force rsync to copy backup to remote location using max I/O bandwidth. --bwlimit=KBPS
DAYS_TO_STORE_REMOTE="+160"		#in find format. Will delete all files older than this; Remote copy must store more or equal to local
DAYS_TO_STORE_LOCAL="+45"		#in find format. Will delete all files older than this
##################################################

#Chacking if script can be run as user. If not - exit1
if [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root" 1>&2
	ALLOW_NICE=0
	if [ $ALLOW_AS_USER == "0" ]; then
		exit 1
	fi
else
	ALLOW_NICE=1
fi

#Checking if DAR binary exists
DAR_BIN=`which dar`
if [ "$DAR_BIN" = "" ]; then
	echo "Can not find DAR binary file in your PATH" 1>&2
	exit 1
fi

#Checking rsync
RSYNC_BIN=`which rsync`
if [ "$RSYNC_BIN" = "" ]; then
	echo "Please install rsync programm. Can not find binary in your PATH" 1>&2
	exit 1
fi

#DAR option creation function
function optcr {

	#setting Nice level
	if [ $ALLOW_NICE == 0 ]; then
		NICE_LVL=0	
	fi

	#checking slice
	if [ "$SLICE" != "" ]; then
		SLICE="-s $SLICE"
	fi

	COMPRESSION_OPTION="--compression=$COMPRESSION_OPTION"
	
	#making exclusions if filled
	if [ "$EXCL_PATH" != "" ]; then
		EXCL_PATH_DAR=""
		for item in $(echo $EXCL_PATH | tr ";" "\n"); do 
			 EXCL_PATH_DAR="$EXCL_PATH_DAR-P $item "
		done		
	else
		EXCL_PATH_DAR=""
	fi

	if [ "$EXCL_FILENAME" != "" ]; then
		EXCL_FILENAME_DAR=""
		for item in $(echo $EXCL_FILENAME | tr ";" "\n"); do
			EXCL_FILENAME_DAR="$EXCL_FILENAME_DAR-X \"$item\" "
		done
	else
		EXCL_FILENAME_DAR=""
	fi

	if [ "$NO_COMPRESSION" != "" ]; then
		NO_COMPRESSION_DAR=""
        	for item in $(echo $NO_COMPRESSION | tr ";" "\n"); do
        	        NO_COMPRESSION_DAR="$NO_COMPRESSION_DAR-Z \"$item\" "
        	done	
	else 
		NO_COMPRESSION_DAR=""
	fi
	
}

function rsyn_start {
	#checking if first-run file exists in the mount-point. If it is not - rise error because there is no point to copy backup on the same disk again
	if [ ! -e $REMOTE_BCK_MNT/.mount_check ]; then
		echo "ERROR, remote directory mount file is not found!" 1>&2
		echo "No need to copy backup again." 1>&2
		echo "Please mount remote partition in $REMOTE_BCK_MNT" 1>&2
		echo "And start rsync from terminal -> " 1>&2
		echo $RSYNC_BIN -v $RSYNC_BANDWIDTH_LIMIT -r -P -h -a -z $LOCAL_BCK_STORAGE/ REMOTE_BCK_MNT/
		echo "Initializing local backup cleaner end exit with error code 1"
		clean_old local
		exit 1
	else
		echo "First-run mount file found. Proceed ..."
	fi
	
	echo "Starting copy backups on remote location"
	echo RSYNC_BIN -v $RSYNC_BANDWIDTH_LIMIT -r -P -h -a -z $LOCAL_BCK_STORAGE/* REMOTE_BCK_MNT/
	$RSYNC_BIN -v $RSYNC_BANDWIDTH_LIMIT -r -P -h -a -z $LOCAL_BCK_STORAGE/* REMOTE_BCK_MNT/
	echo "Copy finished. Checking MD5..."
	MD_CH=`md5sum REMOTE_BCK_MNT/$1  | cut -d" " -f1`
	if [ $2 != $MD_CH ]; then
		echo "MD5 checksum mismatch!!!" 1>&2
	else
		echo "MD5 check successful"
	fi
	echo "Remote sync complete."
}

function clean_old {
	case "$1" in
	local)
		echo "Removing files in $LOCAL_BCK_STORAGE with creation time more than $DAYS_TO_STORE_LOCAL days"
		`which find` $LOCAL_BCK_STORAGE -type f -ctime $DAYS_TO_STORE_LOCAL -exec rm -f {} \;
		#removes empty dir
		`which find` $LOCAL_BCK_STORAGE -type d -ctime $DAYS_TO_STORE_LOCAL -exec rmdir {} \;
	;;
	full)
		#local
		echo "Removing files in $LOCAL_BCK_STORAGE with creation time more than $DAYS_TO_STORE_LOCAL days"
		`which find` $LOCAL_BCK_STORAGE -ctime $DAYS_TO_STORE_LOCAL -exec rm -rf {} \;
		#removes empty dir
                `which find` $LOCAL_BCK_STORAGE -type d -ctime $DAYS_TO_STORE_LOCAL -exec rmdir {} \;
		#remote
		echo "Removing files in $REMOTE_BCK_MNT with creatin time more than $DAYS_TO_STORE_REMOTE days"
		`which find` $REMOTE_BCK_MNT -ctime $DAYS_TO_STORE_REMOTE ! -name ".mount_check" -exec rm -rf {} \;
		`which find` $REMOTE_BCK_MNT -type d -ctime $DAYS_TO_STORE_REMOTE -exec rmdir {} \;
	;;
	esac
}

#performing full backup
function full_backup {
	optcr
	UMASK_OLD=umask
	umask 0077
	if [ $? != 0 ]; then
		echo "Umask change failed! Please be careful, your backup can be read!";	
	else
		echo "Umask change success"
	fi

	#READY for back
	mkdir $LOCAL_BCK_STORAGE/`date +%m-%Y`
	echo `which nice` -n $NICE_LVL $DAR_BIN -c $LOCAL_BCK_STORAGE/`date +%m-%Y`/$FULL_BCK_FILE_NAME $ENCR_KEY $SLICE $CREATE_EMPTY $NO_COMPRESSION_DAR $EXCL_FILENAME_DAR $EXCL_PATH_DAR
	`which nice` -n $NICE_LVL $DAR_BIN -c $LOCAL_BCK_STORAGE/`date +%m-%Y`/$FULL_BCK_FILE_NAME $ENCR_KEY $SLICE $CREATE_EMPTY $NO_COMPRESSION_DAR $EXCL_FILENAME_DAR $EXCL_PATH_DAR
	if [ $? != 0 ]; then
                echo "Something went wrong. See errors above" 1>&2
                exit 1
        fi

	echo "Calculating MD5 sum..."
	MD_SUMM=$(md5sum $LOCAL_BCK_STORAGE/`date +%m-%Y`/$FULL_BCK_FILE_NAME.dar | cut -d" " -f1)
	echo $MD_SUMM
	echo "Checking archive with DAR build-in check algorithm"
	echo `which nice` -n $NICE_LVL $DAR_BIN -t  $LOCAL_BCK_STORAGE/`date +%m-%Y`/$FULL_BCK_FILE_NAME.dar
	`which nice` -n $NICE_LVL $DAR_BIN -t  $LOCAL_BCK_STORAGE/`date +%m-%Y`/$FULL_BCK_FILE_NAME.dar
	
	#Changing Umask back
	umask $UMASK_OLD

	#Starting rsync
	rsyn_start `date +%m-%Y`/$FULL_BCK_FILE_NAME.dar $MD_SUMM
	
	clean_old full

	exit 0
}

#preforming diff back
function diff_backup {
	optcr
	UMASK_OLD=umask
        umask 0077
        if [ $? != 0 ]; then
                echo "Umask change failed! Please be careful, your backup can be read!";         
        else
                echo "Umask change success"
        fi
	if [ ! -e $LOCAL_BCK_STORAGE/`date +%m-%Y` ]; then
		echo "Can't find working directory with full backup"
		echo "Trying to use old backup dir"
		if [ -e $LOCAL_BCK_STORAGE/`date --date "last month" +%m-%Y` ]; then
			echo "Previous dir exists. Trying to find full backup."
			cd $LOCAL_BCK_STORAGE/`date --date "last month" +%m-%Y`
			LS=`ls -t *full*`
			OLD_FULL=`echo $LS | cut -d" " -f1`
			if [ "$OLD_FULL" = "" ]; then 
				echo "Can not find old full back in previous month folder" 1>&2
				#rise error because no folder with full backup
				echo "Can not find $LOCAL_BCK_STORAGE/`date +%m-%Y` folder with full backup file" 1>&2
				echo "You should make full backup first!" 1>&2
				echo "Rising ERROR, can't perform diff backup without full one" 1>&2
				exit 1
			fi
			#change full backup ctime not to be removed on cleanup
			touch $LOCAL_BCK_STORAGE/`date --date "last month" +%m-%Y`/$OLD_FULL
			#creating symbolic link in current folder
			mkdir $LOCAL_BCK_STORAGE/`date +%m-%Y`
			ln -s $LOCAL_BCK_STORAGE/`date --date "last month" +%m-%Y`/$OLD_FULL $LOCAL_BCK_STORAGE/`date +%m-%Y`/$OLD_FULL
		else
			echo "No previous directory exists. Exiting..." 1>&2
			exit 1
		fi
	fi

	#check and find last full back
	cd $LOCAL_BCK_STORAGE/`date +%m-%Y`
	LS=`ls -t *full*`
	FULL_ARCH_NAME_LS=`echo $LS | cut -d" " -f1`
	
	echo "Performing DIFF backup using last found FULL $FULL_ARCH_NAME_LS"
	echo `which nice` -n $NICE_LVL $DAR_BIN -A $LOCAL_BCK_STORAGE/`date +%m-%Y`/$FULL_ARCH_NAME_LS -c $LOCAL_BCK_STORAGE/`date +%m-%Y`/DIFF_BCK_FILE_NAME $ENCR_KEY $SLICE $CREATE_EMPTY $NO_COMPRESSION_DAR $EXCL_FILENAME_DAR $EXCL_PATH_DAR
	`which nice` -n $NICE_LVL $DAR_BIN -A $LOCAL_BCK_STORAGE/`date +%m-%Y`/$FULL_ARCH_NAME_LS -c $LOCAL_BCK_STORAGE/`date +%m-%Y`/DIFF_BCK_FILE_NAME $ENCR_KEY $SLICE $CREATE_EMPTY $NO_COMPRESSION_DAR $EXCL_FILENAME_DAR $EXCL_PATH_DAR
	if [ $? != 0 ]; then
		echo "Something went wrong. See errors above" 1>&2
		exit 1
	fi
	
	echo "Starting backup test"
	echo `which nice` -n $NICE_LVL $DAR_BIN -t  $LOCAL_BCK_STORAGE/`date +%m-%Y`/$DIFF_BCK_FILE_NAME.dar
	`which nice` -n $NICE_LVL $DAR_BIN -t  $LOCAL_BCK_STORAGE/`date +%m-%Y`/$DIFF_BCK_FILE_NAME.dar

	echo "Calculating MD5 sum ..."
	MD_SUMM=$(md5sum $LOCAL_BCK_STORAGE/`date +%m-%Y`/$DIFF_BCK_FILE_NAME.dar | cut -d" " -f1)

        #Changing Umask back
        umask $UMASK_OLD

	rsyn_start `date +%m-%Y`/$DIFF_BCK_FILE_NAME.dar $MD_SUMM

	#clearning old
	clean_old full
	exit 0
}

#Checking input arguments
case "$1" in
        first_run)
                echo "Making directory if not exists"
                mkdir -p $LOCAL_BCK_STORAGE
                mkdir -p $REMOTE_BCK_MNT
                echo "Creating $REMOTE_BCK_MNT/.mount_check"
                touch $REMOTE_BCK_MNT/.mount_check
        ;;
        full)
                full_backup
        ;;
        diff)
                diff_backup
        ;;
        *)
                echo $"Usage: $0 {first_run|full|diff}"
                exit 1
        ;;
esac
