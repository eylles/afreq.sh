# afreq.sh

A simple daemon for setting cpu frequency governor

<p align="center">
<a href="./LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-green.svg"></a>
<a href="https://liberapay.com/eylles/donate"><img alt="Donate using Liberapay" src="https://img.shields.io/liberapay/receives/eylles.svg?logo=liberapay"></a>
<a href="https://liberapay.com/eylles/donate"><img alt="Donate using Liberapay" src="https://img.shields.io/liberapay/patrons/eylles.svg?logo=liberapay"></a>
</p>

Inspired by [auto-cpufreq](https://github.com/AdnanHodzic/auto-cpufreq),
afreq.sh is a minimal daemon built on posix shell and core utils, it is intended
to be extensible, lean and have the least amount of dependencies possible.

As of now afreq depends only on:

- core utils (grep, sleep, tail, awk, head) however a sleep command that supports float values is needed
- built ins (printf, command)
- procps (vmstat, pgrep)


## installation

  Install everything:
  ```sh
  sudo make install-all
  ```
  this will provide:
  |component|default location|description|
  |----|----|----|
  |afreq|`/usr/local/sbin/afreq`|the actual daemon doing the work|
  |perfmod|`/usr/local/sbin/perfmod`|thin wrapper to force performance governor when a program runs|
  |acpufreq|`/etc/init.d/acpufreq`|sysvinit initscript|
  |acpufreq.service|`/etc/systemd/system/acpufreq.service`|systemd unit|


### install config

  Edit the config.mk file to tweak installation options.

#### SysV init script

  This repo provides 2 sysvinit init scripts, a hand written one and one that uses
  Debian's init-d-script framework that provides a Debian and LSB compliant init.d
  script that may be preferred on some environments, you can choose with the
  config.mk file.

## Usage

### sysvinit

  The makefile should put the script in `/etc/init.d/acpufreq` by default, after that
  a simple ```sudo update-rc.d acpufreq defaults``` should be enough to activate
  it for the next boot

  The service script supports the standard actions.

  A simple `sudo service acpufreq start` will initiate the daemon.


### systemd

  The makefile should put the unit in `/etc/systemd/system/acpufreq.service` by
  default, all you need is run ```sudo systemctl enable acpufreq``` to activate the
  service for the next boot.

  Initiate the service with `sudo systemctl start acpufreq`


