NAME = acpufreq
SERVICE_LOCATION_SYSV = /etc/init.d
SERVICE_LOCATION_SYSD = /etc/systemd/system
RAW_SYSV = acpufreq.is
INIT_LSB = acpufreq.init

SYSV_SCRIPT = $(RAW_SYSV)

PREFIX = /usr/local
MANPREFIX = $(PREFIX)/share/man
EGPREFIX = $(PREFIX)/share/doc/afreq

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
	mkdir -p $(PREFIX)/sbin
	cp afreq $(PREFIX)/sbin/afreq
	chmod 755 $(PREFIX)/sbin/afreq
	echo afreq installed in $(PREFIX)/sbin
	mkdir -p $(DESTDIR)$(MANPREFIX)/man1
	cp -f afreq.1   $(DESTDIR)$(MANPREFIX)/man1/afreq.1
	mkdir -p $(DESTDIR)$(EGPREFIX)
	cp -f afreqconfig $(DESTDIR)$(EGPREFIX)/afreqconfig
	mkdir -p $(PREFIX)/bin
	cp perfmod.sh $(PREFIX)/bin/perfmod
	chmod 755 $(PREFIX)/bin/perfmod
	echo perfmod installed in $(PREFIX)/bin

install-on_ac_power:
	mkdir -p $(PREFIX)/bin
	cp on_ac_power $(PREFIX)/bin/on_ac_power
	chmod 755 $(PREFIX)/bin/on_ac_power
	echo on_ac_power installed in $(PREFIX)/bin

install-sysv: sysvserv
	mkdir -p $(SERVICE_LOCATION_SYSV)
	cp $(NAME) $(SERVICE_LOCATION_SYSV)/
	chmod 755 $(SERVICE_LOCATION_SYSV)/$(NAME)
	echo sysvinit service: $(NAME) installed in $(SERVICE_LOCATION_SYSV)

install-sysd: sysdserv
	mkdir -p $(SERVICE_LOCATION_SYSD)
	cp $(NAME).service $(SERVICE_LOCATION_SYSD)/
	echo systemd unit $(NAME).service installed in $(SERVICE_LOCATION_SYSD)

install-all: install install-sysv install-sysd

uninstall:
	rm $(PREFIX)/sbin/afreq
	rm $(MANPREFIX)/man1/afreq.1
	rm -rf $(EGPREFIX)
	rm $(EGPREFIX)/afreqconfig
	echo afreq uninstalled from $(PREFIX)sbin
	rm $(PREFIX)/bin/perfmod
	echo perfmod uninstalled from $(PREFIX)/bin
	rm -v $(SERVICE_LOCATION_SYSV)/$(NAME)
	echo $(NAME) uninstalled from $(SERVICE_LOCATION_SYSV)
	rm -v $(SERVICE_LOCATION_SYSD)/$(NAME).service
	echo $(NAME).service uninstalled from $(SERVICE_LOCATION_SYSD)

uninstall-on_ac_power:
	rm $(PREFIX)/bin/on_ac_power
	echo on_ac_power uninstalled from $(PREFIX)/bin

clean:
	rm -f $(NAME) $(NAME).service afreq afreq.1


.PHONY: install uninstall clean all
