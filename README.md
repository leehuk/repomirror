# repomirror
## Overview
Tool for mirroring RPM based repositories via HTTP(s) in a reasonably 
intelligent manner.

repomirror syncs an upstream  repository to local disk via HTTP(s).  Its 
intelligent in that unlike using wget in recursive mode (which is horribly 
inelegant), it will actually parse the repodata within the repository to 
determine the contents and then sync those.

It will compare the data from the repository to determine what if anything
it needs to download, then optionally cleans up orphaned files from the local
directory.

Its effectively a perl variant of the reposync tool that isnt dependent in
any way on yum.  It can therefore sync repos that arent listed in yum.repos.d
and can also run on other distributions like Debian.

## Repositories available via rsync
If the repository you wish to sync is available via rsync, you **really**
should sync it that way, its a lot more efficient.

## Requirements

## Installation

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
