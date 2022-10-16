NAME = acpufreq
SERVICE_LOCATION_SYSV = /etc/init.d
SERVICE_LOCATION_SYSD = /etc/systemd/system
PREFIX = /usr/local

sysvserv:
	sed "s|acpufreq|$(NAME)|; s|placeholder|$(PREFIX)sbin|" acpufreq.is > $(NAME)

sysdserv:
	sed "s|acpufreq|$(NAME)|; s|placeholder|$(PREFIX)sbin|" acpufreq.sysd > $(NAME).service

install:
	mkdir -p $(PREFIX)/sbin
	cp afreq.sh $(PREFIX)/sbin/afreq
	chmod 755 $(PREFIX)/sbin/afreq
	echo afreq installed in $(PREFIX)/sbin
	mkdir -p $(PREFIX)/bin
	cp perfmod.sh $(PREFIX)/bin/perfmod
	chmod 755 $(PREFIX)/bin/perfmod
	echo perfmod installed in $(PREFIX)/bin

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
	echo afreq uninstalled from $(PREFIX)sbin
	rm -v $(SERVICE_LOCATION_SYSV)/$(NAME)
	echo $(NAME) uninstalled from $(SERVICE_LOCATION_SYSV)
	rm -v $(SERVICE_LOCATION_SYSD)/$(NAME).service
	echo $(NAME).service uninstalled from $(SERVICE_LOCATION_SYSD)

.PHONY: install uninstall
