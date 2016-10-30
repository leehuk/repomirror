# repomirrortools
## Overview
Collection of tools for assisting with the mirroring of RPM based repos consumed
by yum or dnf.

These tools are intended mainly for situations where you wish to manage an internal
mirror of public repositories, some of which may only be available via HTTP(s).

## repomirror
repomirror mirrors RPM repositories consumed by yum/dnf to local disk.  As well
as running an ad-hoc sync, it can also be used as a simple platform for managing
the mirroring of several repos in a structured manner.

repomirror supports mirroring from a folder and rsync sources, as well as http/https
repos in a much more intelligent manner than a tool like wget can.

Further information: [repomirror documentation](docs/repomirror.md)
