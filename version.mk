####################
# afreq versioning #
####################

# version determined by git
GITTAG = $(shell git describe --tags 2>/dev/null)
# last release tag
VERS = 0.5.0
# actual version number that will be used
VERSION = $(if $(GITTAG),$(GITTAG),$(VERS))
