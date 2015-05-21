Clean debian for the RaspberryPi 2
==================================

``armin`` is a script to create your own minimal debian image for the Raspberry
Pi. You can also use a prebuilt image, knowing exactly what went in. Contrary
to many other "minimal" images, it is not a raspbian image with packages
removed, but rather built up from scratch.

All images are built using `multistrap <https://wiki.debian.org/Multistrap>`_
with a few necessary configuration options added. Firmware is downloaded
directly from the `official repository
<https://github.com/raspberrypi/firmware>`_, without any additional scripts
like ``raspi-config`` or firmware updaters.



The "server" flavor
-------------------

The server images are meant to be a minimal starting point for
customizing a server from a secure starting point. The following components
(and nothing else) are included:

* Includes the latest (image date) firmware from
  https://github.com/raspberrypi/firmware and a patched kernel (stock won't
  boot) from `collabora <http://collabora.com>`_.
* Bases on debian Jessie. In addition to the bare minimum of packages required
  to boot, the following features are installed:
* Apt: Allows installation of packages from apt repositories. Packages:
  ``apt``, ``apt-transport-https`` and ``ca-certificates``.
* Network: Network autoconfigured via DHCP (``eth0``), also
  includes all necessary tools for manual configuration.
  Packages: ``iproute2``, ``iputils-ping``, ``ifupdown``, ``isc-dhcp-client``
  and ``wpasupplicant``.
* OpenSSH: Started on bootup. Host-keys will be regenerated on first boot
  using the hardware random number generator and included script and shown on
  every tty to allow for a secure connection. Packages: ``openssh-server`` and
  ``rng-tools``.
* Resize: On first boot, the root partition is extend to the full extend of the
  SD card automatically.

The root password is set to ``raspberry`` (and should be changed). The
compressed image is 60M in size, on SD card the first 512M will initially be
used (out of which a little under 220M are in use).

You can find a current snapshot in this repository as
``server-YYYY-MM-DD.img``.



Building your own images
------------------------

Building your own images is easy:

1. Read the script. It needs to be run using sudo (due to fakechroot
insufficiencies), to double check no ``rm`` command will run amok.

2. Run ``sudo sh new_dist.sh server myimg``. This will create the
   necessary files in ``myimg``, apply all customizations and ultimately
   generated a new image as ``myimg/server-YYYY-MM-DD.img``.

``new_dist.sh`` is quite short and readable; a lot of work is done using
profiles. A profile is a set of components that should be included in an image
(through various hooks) and defines is feature set.

To create a new profile named ``myprofile``, create the folder
``profiles/myprofile`` and then link any number of folders from the
``components`` folder into it.


Future work
-----------

Goals for future improvements are:

* Read-only images. These are already a low-hanging fruit because the system
  has so few components and allow for extra stability on embedded systems.
* Improvements to the profile-based component system, making it easier to
  create smaller images and including custom software.


Sources
-------

Bits of information to create this script and image are taken from:

* http://www.kaibader.de/homemade-minimal-raspberry-pi-raspbian-image/
* https://wiki.debian.org/Multistrap
* http://sjoerd.luon.net/posts/2015/02/debian-jessie-on-rpi2/
* https://unix.stackexchange.com/questions/41889/how-can-i-chroot-into-a-filesystem-with-a-different-architechture
* https://raspberrypi.stackexchange.com/questions/10442/what-is-the-boot-sequence
* http://3gfp.com/wp/2014/07/formatting-sd-cards-for-speed-and-lifetime/
