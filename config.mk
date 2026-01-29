# PREFIX for install
PREFIX = /usr/local
MANPREFIX = $(PREFIX)/share/man
EGPREFIX = $(PREFIX)/share/doc/afreq

# sysvinit scripts available
RAW_SYSV = acpufreq.is
INIT_LSB = acpufreq.init

# sysvinit script of choice
SYSV_SCRIPT = $(RAW_SYSV)

