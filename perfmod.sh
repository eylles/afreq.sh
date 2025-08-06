#!/bin/sh

# just run the program passed as argument
# we simply want the name perfmod to appear in the process list
# shellcheck disable=SC2091
$("$@")
