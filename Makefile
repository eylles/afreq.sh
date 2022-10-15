NAME = acpufreq
SERVICE_LOCATION = /etc/init.d
PREFIX = /usr/local
BIN_LOCATION = /sbin

$(NAME):
	sed "s/acpufreq/$(NAME)/" acpufreq.is > $(NAME)

install: $(NAME)
	mkdir -p $(SERVICE_LOCATION)
	mkdir -p $(PREFIX)$(BIN_LOCATION)
	cp $(NAME) $(SERVICE_LOCATION)/$(NAME)
	chmod 755 $(SERVICE_LOCATION)/$(NAME)
	echo $(NAME) installed in $(SERVICE_LOCATION)
	rm $(NAME)
	cp afreq.sh $(PREFIX)$(BIN_LOCATION)/afreq
	chmod 755 $(PREFIX)$(BIN_LOCATION)/afreq
	echo afreq installed in $(PREFIX)$(BIN_LOCATION)

uninstall:
	rm -v $(SERVICE_LOCATION)/$(NAME)
	echo $(NAME) uninstalled from $(SERVICE_LOCATION)
	rm $(PREFIX)$(BIN_LOCATION)/afreq
	echo afreq uninstalled from $(PREFIX)$(BIN_LOCATION)

.PHONY: install uninstall
