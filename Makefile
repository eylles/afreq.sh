NAME = acpufreq
SYSV_LOC = /etc/init.d
SYSD_LOC = /etc/systemd/system
RAW_SYSV = acpufreq.is
INIT_LSB = acpufreq.init

SYSV_SCRIPT = $(RAW_SYSV)

PREFIX = /usr/local
MANPREFIX = $(PREFIX)/share/man
EGPREFIX = $(PREFIX)/share/doc/afreq
BIN_LOC = $(DESTDIR)$(PREFIX)/bin
SBIN_LOC = $(DESTDIR)$(PREFIX)/sbin
MAN_LOC = $(DESTDIR)$(MANPREFIX)/man1
EXAMP_LOC = $(DESTDIR)$(EGPREFIX)

include version.mk config.mk

all: afreq sysvserv sysdserv

afreq: manpage
	sed "s|@VERSION@|$(VERSION)|" afreq.sh > afreq
	chmod 755 afreq

manpage:
	sed "s|@VERSION|$(VERSION)|;" afreq.1.in > afreq.1

sysvserv:
	sed "s|acpufreq|$(NAME)|; s|placeholder|$(PREFIX)|" $(SYSV_SCRIPT) > $(NAME)

sysdserv:
	sed "s|acpufreq|$(NAME)|; s|placeholder|$(PREFIX)|" acpufreq.sysd > $(NAME).service

install: afreq
	mkdir -p $(SBIN_LOC)
	cp afreq $(SBIN_LOC)/afreq
	chmod 755 $(SBIN_LOC)/afreq
	echo afreq installed in $(SBIN_LOC)
	mkdir -p $(MAN_LOC)
	cp -f afreq.1   $(MAN_LOC)/afreq.1
	mkdir -p $(EXAMP_LOC)
	cp -f afreqconfig $(EXAMP_LOC)/afreqconfig
	cp -f examples/wireless-power-management.sh $(EXAMP_LOC)/wireless-power-management.sh
	cp -f examples/wireless-power-management-ac.sh $(EXAMP_LOC)/wireless-power-management-ac.sh
	cp -f examples/wireless-power-management-bat.sh $(EXAMP_LOC)/wireless-power-management-bat.sh
	mkdir -p $(BIN_LOC)
	cp perfmod.sh $(BIN_LOC)/perfmod
	chmod 755 $(BIN_LOC)/perfmod
	echo perfmod installed in $(BIN_LOC)

install-on_ac_power:
	mkdir -p $(BIN_LOC)
	cp on_ac_power $(BIN_LOC)/on_ac_power
	chmod 755 $(BIN_LOC)/on_ac_power
	echo on_ac_power installed in $(BIN_LOC)

install-sysv: sysvserv
	mkdir -p $(SYSV_LOC)
	cp $(NAME) $(SYSV_LOC)/
	chmod 755 $(SYSV_LOC)/$(NAME)
	echo sysvinit service: $(NAME) installed in $(SYSV_LOC)

install-sysd: sysdserv
	mkdir -p $(SYSD_LOC)
	cp $(NAME).service $(SYSD_LOC)/
	echo systemd unit $(NAME).service installed in $(SYSD_LOC)

install-all: install install-sysv install-sysd

uninstall:
	rm $(SBIN_LOC)/afreq
	rm $(MAN_LOC)/afreq.1
	rm -f $(EXAMP_LOC)/afreqconfig
	rm -rf $(EXAMP_LOC)
	echo afreq uninstalled from $(SBIN_LOC)
	rm $(BIN_LOC)/perfmod
	echo perfmod uninstalled from $(BIN_LOC)
	rm -v $(SYSV_LOC)/$(NAME)
	echo $(NAME) uninstalled from $(SYSV_LOC)
	rm -v $(SYSD_LOC)/$(NAME).service
	echo $(NAME).service uninstalled from $(SYSD_LOC)

uninstall-on_ac_power:
	rm $(BIN_LOC)/on_ac_power
	echo on_ac_power uninstalled from $(BIN_LOC)

clean:
	rm -f $(NAME) $(NAME).service afreq afreq.1


.PHONY: install uninstall clean all
