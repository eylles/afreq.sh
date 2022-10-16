NAME = acpufreq
SERVICE_LOCATION_SYSV = /etc/init.d
SERVICE_LOCATION_SYSD = /etc/systemd/system
PREFIX = /usr/local
BIN_LOCATION = /sbin

$(NAME):
	sed "s|acpufreq|$(NAME)|; s|placeholder|$(PREFIX)$(BIN_LOCATION)|" acpufreq.is > $(NAME)
	sed "s|acpufreq|$(NAME)|; s|placeholder|$(PREFIX)$(BIN_LOCATION)|" acpufreq.sysd > $(NAME).service

install: $(NAME)
	mkdir -p $(SERVICE_LOCATION_SYSV)
	cp $(NAME) $(SERVICE_LOCATION_SYSV)/
	chmod 755 $(SERVICE_LOCATION_SYSV)/$(NAME)
	echo sysvinit service: $(NAME) installed in $(SERVICE_LOCATION_SYSV)
	mkdir -p $(SERVICE_LOCATION_SYSD)
	cp $(NAME).service $(SERVICE_LOCATION_SYSD)/
	chmod 755 $(SERVICE_LOCATION_SYSD)/$(NAME).service
	echo systemd unit $(NAME).service installed in $(SERVICE_LOCATION_SYSD)
	mkdir -p $(PREFIX)$(BIN_LOCATION)
	cp afreq.sh $(PREFIX)$(BIN_LOCATION)/afreq
	chmod 755 $(PREFIX)$(BIN_LOCATION)/afreq
	echo afreq installed in $(PREFIX)$(BIN_LOCATION)

uninstall:
	rm -v $(SERVICE_LOCATION_SYSV)/$(NAME)
	echo $(NAME) uninstalled from $(SERVICE_LOCATION_SYSV)
	rm $(PREFIX)$(BIN_LOCATION)/afreq
	echo afreq uninstalled from $(PREFIX)$(BIN_LOCATION)

.PHONY: install uninstall
