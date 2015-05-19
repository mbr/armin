A minimal, clean debian for the RaspberryPi 2
=============================================

``armin`` is a script to create your own minimal debian image for the Raspberry
Pi or use one generated with it while understanding what exactly went into it.



Issues
------

The ``raspberrypi-firmware-nokernel`` package unfortunately seems to be either
obsolete or buggy; the .postinst scripts deletes all the firmware it installed
from /boot/firmware.xchat

flash-kernel
~~~~~~~~~~~~

The current flash-kernel script does not properly install the kernel to
/boot/firmware/kernel7.img because it (rightfully) refuses to move the kernel
image managed by apt. Right now, as a workaround, flash-kernel is not
installed, but a small script added instead.


Sources
-------

Information taken from:

* http://www.kaibader.de/homemade-minimal-raspberry-pi-raspbian-image/
* https://wiki.debian.org/Multistrap
* http://sjoerd.luon.net/posts/2015/02/debian-jessie-on-rpi2/
* https://unix.stackexchange.com/questions/41889/how-can-i-chroot-into-a-filesystem-with-a-different-architechture
* https://raspberrypi.stackexchange.com/questions/10442/what-is-the-boot-sequence
* http://3gfp.com/wp/2014/07/formatting-sd-cards-for-speed-and-lifetime/
