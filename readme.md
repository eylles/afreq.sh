# afreq.sh

A simple daemon for setting cpu frequency governor

Inspired by [auto-cpufreq](https://github.com/AdnanHodzic/auto-cpufreq),
afreq.sh is a minimal daemon built on posix shell and core utils, it is intended
to be extensible, lean and have the least amount of dependencies.

As of now afreq depends only on:

- core utils (grep, sleep, tail, awk)
- built ins (printf)
- procps (vmstat)


Currently afreq.sh is a proof of concept to demonstrate that such a program can
be written in a real unix way (not reinventing the wheel, using the tools
available), with the expectation that it may mature further.
