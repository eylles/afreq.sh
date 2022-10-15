# afreq.sh

a simple daemon for setting cpu frequency governor

inspired by [auto-cpufreq](https://github.com/AdnanHodzic/auto-cpufreq),
afeq.sh is a minimal daemon built on posix shell and core utils, it is inteded
to be extensible, lean and have the least amount of dependencies.

as of now afreq depends only on:

- core utils (grep, sleep, tail, awk)
- built ins (printf)
- procps (vmstat)


currently afreq.sh is a proof of concept to demonstrate that such a program can
be written in a real unix way (not reinventing the wheel, using the tools
avaible), wiht the expectation that it may mature further.
