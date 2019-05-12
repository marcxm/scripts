#!/bin/sh

# by marc
# Easy script that connects to remote btrfs-enabled machine, takes RO snapshots and rotates them, then send them
# to destination btrfs-enabled machine and rotates them there as well.
# Needs to have subvolumes already created on source and destination.
# Deletes snapshots older than 8 days [can be changed in a code], but this requires support for atime in mounted FS.

# CONFIG
SSH_USER="root"
SSH_PORT="22"
SOURCE_IP="192.168.2.4"
SOURCE_DIR="/"
SOURCE_SNAP_DIR="/.snapshots"
DESTINATION_DIR="/mnt/hdd/backups/rfs"
TIMESTAMP=`date +%Y-%m-%d_%H%M%S`
LOG="/tmp/btrfs_backup_src_to_dest_rfs.log"
# /CONFIG

# add start date to log file located @$LOG
echo "start@ `date +%Y-%m-%d_%H%M`" >> $LOG

# check if destination backup directory is empty. If yes, first do full btrfs send [not incremental]
if [ -z "$(ls -A $DESTINATION_DIR)" ]; then
   echo "Empty"
   # make RO snap on SOURCE
   # rotate snapshots - current => last, previous last => original TIMESTAMP:
   # rename on stable Debian [SOURCE] requires sed syntax: 's/replace_this/with_this/' $filename
   ssh $SSH_USER@$SOURCE_IP "rename 's/_last//' "$SOURCE_SNAP_DIR""/"*last"
   ssh $SSH_USER@$SOURCE_IP "rename 's/_current/_last/' "$SOURCE_SNAP_DIR""/"*current"
   # make read-only [required by btrfs send] snapshot on SOURCE
   ssh $SSH_USER@$SOURCE_IP "btrfs sub snap -r "$SOURCE_DIR" "$SOURCE_SNAP_DIR"/"$TIMESTAMP"_current"
   # send that snapshot to from SOURCE to DESTINATION
   ssh $SSH_USER@$SOURCE_IP "btrfs send "$SOURCE_SNAP_DIR""/"*_current" | pv | btrfs receive $DESTINATION_DIR
   # clean old snapshots [older than 8 days, can be adjusted with -mtime +8] - requires OS to save atime
   ssh $SSH_USER@$SOURCE_IP "find $SOURCE_SNAP_DIR -maxdepth 1 -mtime +8 -type d -print -exec btrfs sub del {} \;"
else
# if directory is not empty, then do incremental backup [transfer only changes made recently]   
   # rotate snapshots - current => last, previous last => original TIMESTAMP:
   # rename on openSUSE [DESTINATION] requires syntax: rename 'replace_this' 'with this' $filename
   rename '_last' '' "$DESTINATION_DIR"/*
   rename '_current' '_last' "$DESTINATION_DIR"/*
   # rename on stable Debian [SOURCE] requires sed syntax: 's/replace_this/with_this/' $filename
   ssh $SSH_USER@$SOURCE_IP "rename 's/_last//' "$SOURCE_SNAP_DIR""/"*last"
   ssh $SSH_USER@$SOURCE_IP "rename 's/_current/_last/' "$SOURCE_SNAP_DIR""/"*current"
   # make incremental RO snap on SOURCE
   ssh $SSH_USER@$SOURCE_IP "btrfs sub snap -r "$SOURCE_DIR" "$SOURCE_SNAP_DIR"/"$TIMESTAMP"_current"
   # send that snapshot from SOURCE to DESTINATION
   ssh $SSH_USER@$SOURCE_IP "btrfs send -p "$SOURCE_SNAP_DIR""/"*_last "$SOURCE_SNAP_DIR""/"*_current" | pv | btrfs receive $DESTINATION_DIR
   # cleanup
   find $DESTINATION_DIR -maxdepth 1 -mtime +8 -type d -print -exec btrfs sub del {} \;
fi

# add end date to log file located @$LOG
echo "done@ `date +%Y-%m-%d_%H%M`" >> $LOG
