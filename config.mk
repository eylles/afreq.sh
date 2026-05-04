# PREFIX for install
PREFIX = /usr/local
MANPREFIX = $(PREFIX)/share/man
EGPREFIX = $(PREFIX)/share/doc/afreq

# install locations

# sysvinit service
SYSV_LOC = /etc/init.d
# systemd service
SYSD_LOC = /etc/systemd/system
# binaries
BIN_LOC = $(DESTDIR)$(PREFIX)/bin
# system binaries
SBIN_LOC = $(DESTDIR)$(PREFIX)/sbin
# manpage
MAN_LOC = $(DESTDIR)$(MANPREFIX)/man1
# examples
EXAMP_LOC = $(DESTDIR)$(EGPREFIX)

# sysvinit scripts available
RAW_SYSV = acpufreq.is
INIT_LSB = acpufreq.init

# sysvinit script of choice
SYSV_SCRIPT = $(RAW_SYSV)

