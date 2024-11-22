# afreq.sh

A simple daemon for setting cpu frequency governor

<p align="center">
<a href="./LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-green.svg"></a>
<a href="https://liberapay.com/eylles/donate"><img alt="Donate using Liberapay" src="https://img.shields.io/liberapay/receives/eylles.svg?logo=liberapay"></a>
<a href="https://liberapay.com/eylles/donate"><img alt="Donate using Liberapay" src="https://img.shields.io/liberapay/patrons/eylles.svg?logo=liberapay"></a>
</p>

Inspired by [auto-cpufreq](https://github.com/AdnanHodzic/auto-cpufreq),
afreq.sh is a minimal daemon built on posix shell and core utils, it is intended
to be extensible, lean and have the least amount of dependencies.

As of now afreq depends only on:

- core utils (grep, sleep, tail, awk) however busybox and other posix compliant utils will work
- built ins (printf, command)
- procps (vmstat, pgrep)


Currently afreq.sh is a proof of concept to demonstrate that such a program can
be written in a real unix way (not reinventing the wheel, using the tools
available), with the expectation that it may mature further.
