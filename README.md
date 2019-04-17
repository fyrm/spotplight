# spotPlight #
spotPlight automates the process of reading data indexed by Spotlight from a locked macOS device. The tool was created to exploit (at the time), a relatively quiet data leakage that appeared to at first be fixed, and then vulnerable in subsequent macOS versions. It was a fun exercise relying heavily on the Linux USB mass storage gadget, automating loopback filesystems and ramdisks.

For more information on the issue spotPlight exploits, see the post here: https://fyrmassociates.com/blog/2018/12/01/macos-spotlight-data-leak/


### spotplight.sh ###
spotPlight, create ramdisks on the fly, copies data from "seedfs" directory below

### seedf.tgz ###
Spotlight skeleton dir structure

### applestats.py: ###
Run this to display data on the screen, requires folder above.

### Errors ###
If you get errors running the script, kill any instances currently in progress.  The following commands will also need to be run in the event it's either still attached, or the tmpfs filesystem is still used.

```
# rmmod g_mass_storage
# umount /mnt/imgmnt
# losetup -d /dev/loop0
# umount /mnt/tmpfs
```

Author
-------------
Jeff Yestrumskas

LICENSE
-------------
GPL v3
