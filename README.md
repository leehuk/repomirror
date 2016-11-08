# rpmrepomirror
## Overview
rpmrepomirror mirrors RPM repositories consumed by yum/dnf to local disk.  As well
as running an ad-hoc sync, it can also be used as a simple platform for managing
the mirroring of several repos in a structured manner.

rpmrepomirror supports mirroring from a folder and rsync sources, as well as http/https 
repos in a much more intelligent manner than a tool like wget can.

When mirroring via http(s), rpmrepomirror will parse the XML metadata contained within 
the repo to determine the contents of the repo and will then compare that to the
local copy (using file sizes and checksums) to work out what needs to be synced.

Its effectively rsync-via-http for rpm repos and a perl variant of the reposync 
tool that isnt dependent in any way on yum and can therefore sync repos that arent 
listed in yum.repos.d or run on other distributions like Debian.

## Efficiency of rsync via http
If the repository you wish to sync is available via rsync, you **really**
should sync it that way.  An rsync negates the need to parse the XML metadata, which
can be quite memory intensive and is also more efficient network wise.

## Requirements
rpmrepomirror tries to focus on using only modules that are available by default
in CentOS-6 and CentOS-7:

* perl
* perl-Carp
* perl-Capture-Tiny
* perl-Config-Tiny
* perl-Cwd
* perl-Digest-SHA
* perl-Error
* perl-File-Basename
* perl-File-Path
* perl-Getopt-Std
* perl-HTTP-Tiny
* perl-IO-Socket-SSL
* perl-XML-Parser
* rsync

For CentOS this would be:
```
yum install perl perl-Carp perl-Capture-Tiny perl-Config-Tiny perl-Digest-SHA perl-Error \
  perl-File-Path perl-HTTP-Tiny perl-IO-Socket-SSL perl-PathTools perl-XML-Parser rsync
```

For Debian this would be:
```
apt-get update && apt-get install perl perl-modules libcapture-tiny-perl ibconfig-tiny-perl \
  liberror-perl libio-socket-ssl-perl libxml-parser-perl rsync
```

## Installation
Install the requirements above, download it and run it.

Preferably dont run it as root, particularly if you've told it to remove orphaned files.

## Usage
```
[17:01 repo@repo:~/repotools]$ ./rpmrepomirror.pl -h
Configuration Mode
Usage: ./rpmrepomirror.pl [-fhrs] -c <config> [-n name]
     * -c: Configuration file to use.
       -n: Name of repo to sync.  If this option is not specified then
           all repos within the configuration file are synced.

Parameter Mode
Usage: ./rpmrepomirror.pl [-fhrs] -s <source> -d <dest>
     * -s: Source URI for the repository (required).
           This should be the same path used in a yum.repos.d file,
           but without any variables like $releasever etc.
     * -d: Destination directory to mirror to (required).
           When -r (remove) is specified, *everything* within this folder
           thats not listed in the repo will be *deleted*.

Common Options
       -f: Force repodata/rpm sync when up to date.
       -h: Show this help.
       -r: Remove local files that are no longer on the mirror.
           Its *strongly* recommended you run a download first without
           this option to ensure you have your pathing correct.
       -q: Be quiet other than for errors.
```

### Configuration Mode
In Configuration Mode, rpmrepomirror will parse the given configuration file and sync the repo
passed in via the "-n" parameter.  If there is no named repo parameter, rpmrepomirror will sync
all repos in the configuration file that are not disabled.

A sample configuration file is contained within the docs directory.

### Parameter Mode
In Parameter Mode, rpmrepomirror will run an ad-hoc sync of the repo from the given source (-s)
to the given dest directory (-d).

## HTTP(S) Mirroring Technical Details
rpmrepomirror basically works as follows:

1. Download BASE_URL/repodata/repomd.xml and parse it.  
   This file contains a list of all the other files in repodata/ which form the 
   metadata about the repository.
2. Compare the downloaded repomd.xml against the local copy.  
   If they match, rpmrepomirror exits as the repository must be in sync.
3. Verify we have a 'primary' metadata object within repomd.xml.
4. Sync all the metadata listed in repomd.xml.
5. Parse the 'primary' metadata.  
   This file contains a list of all the content within the repository.
6. Sync all the RPMs listed in the primary metadata.
7. Optionally remove local files that arent listed in repomd.xml or primary
   metadata.
