# repomirror
## Overview
Tool for mirroring RPM based repositories via HTTP(s) in a reasonably 
intelligent manner.

repomirror syncs an upstream repository to local disk via HTTP(s).  Its 
intelligent in that unlike using wget in recursive mode (which is frankly just
horrible), it will actually parse the metadata within the repository to 
determine the contents and sync only whats required.

It will compare the data from the repository to determine what if anything
it needs to download, then **optionally and not by default** cleans up orphaned 
files from the local directory.

Its effectively a perl variant of the reposync tool that isnt dependent in
any way on yum.  It can therefore sync repos that arent listed in yum.repos.d
and can also run on other distributions like Debian.

## Repositories available via rsync
If the repository you wish to sync is available via rsync, you **really**
should sync it that way, its a lot more efficient.

## Requirements
repomirror tries to focus on using only modules that are available by default
in CentOS-6 and CentOS-7:

* perl
* perl-Carp
* perl-Cwd
* perl-Digest-SHA
* perl-Error
* perl-File-Basename
* perl-File-Path
* perl-Getopt-Std
* perl-HTTP-Tiny
* perl-IO-String
* perl-XML-Tiny

For CentOS this would be:
```
yum install perl perl-Carp perl-Digest-SHA perl-Error perl-File-Path perl-HTTP-Tiny \
  perl-IO-String perl-PathTools
```

For Debian this would be:
```
apt-get update && apt-get install perl perl-modules liberror-perl libio-string-perl
```

Unfortunately perl-XML-Tiny isnt available on CentOS or Debian and theres probably a
reason for that, but the intent is to bundle it in the near future.  Unfortunately all
of the other perl XML libraries are somewhat heavyweight for what this tool needs.

## Installation
Install the requirements above, download it and run it.

Preferably dont run it as root, particularly if you've told it to remove orphaned files.

## Usage
```
[19:20 repo@repo:~]$ ./repomirror.pl 
Usage: ./repomirror.pl [-fhrs] -d <directory> -u <url>
     * -d: Directory to mirror to (required).
       -f: Force repodata/rpm sync when up to date.
       -h: Show this help.
       -r: Remove local files that are no longer on the mirror.
       -s: Be silent other than for errors.
     * -u: Sets the base URL for the repository (required).
           This should be the same path used in a yum.repos.d file,
           but without any variables like $releasever etc.
```

## Technical Details
repomirror basically works as follows:

1. Download BASE_URL/repodata/repomd.xml and parse it.  
   This file contains a list of all the other files in repodata/ which form the 
   metadata about the repository.
2. Compare the downloaded repomd.xml against the local copy.  
   If they match, repomirror exits as the repository must be in sync.
3. Verify we have a 'primary' metadata object within repomd.xml.
4. Sync all the metadata listed in repomd.xml.
5. Parse the 'primary' metadata.  
   This file contains a list of all the content within the repository.
6. Sync all the RPMs listed in the primary metadata.
7. Optionally remove local files that arent listed in repomd.xml or primary
   metadata.
