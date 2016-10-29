#!/usr/bin/perl -w
#
# repomirror.pl
# 	Tool for mirroring RPM based repositories via HTTP(s) in a reasonably intelligent manner.
#
# Copyright (C) 2016 Lee H <lee -at- leeh -dot- uk>
#
# Released under the MIT License

use strict;
use v5.10;

# add our lib directory
use FindBin qw($Bin);
use lib "$Bin/lib";

use Carp;
use Getopt::Std qw(getopts);

use RepoTools::ListDownloader;
use RepoTools::ListRemover;
use RepoTools::URI;
use RepoTools::XMLParser;

sub mirror_usage
{
	print "Configuration Mode\n";
	print "Usage: $0 [-fhrs] -c <config> [-n name]\n";
	print "     * -c: YAML configuration file to use.\n";
	print "       -n: Name of repo to sync.  If this option is not specified then\n";
	print "           all repos within the configuration file are synced.\n";
	print "\n";
	print "Parameter Mode\n";
	print "Usage: $0 [-fhrs] -s <source> -d <dest>\n";
	print "     * -s: Source URI for the repository (required).\n";
	print "           This should be the same path used in a yum.repos.d file,\n";
	print "           but without any variables like \$releasever etc.\n";
	print "     * -d: Destination directory to mirror to (required).\n";
	print "           When -r (remove) is specified, *everything* within this folder\n";
	print "           thats not listed in the repo will be *deleted*.\n";
	print "\n";
	print "Common Options\n";
	print "       -f: Force repodata/rpm sync when up to date.\n";
	print "       -h: Show this help.\n";
	print "       -r: Remove local files that are no longer on the mirror.\n";
	print "           Its *strongly* recommended you run a download first without\n";
	print "           this option to ensure you have your pathing correct.\n";
	print "       -q: Be quiet other than for errors.\n";
}

my $options_cli = {};
getopts('c:d:fhn:qrs:', $options_cli);

if(defined($options_cli->{'h'}))
{
	mirror_usage();
	exit(0);
}

# translate the short-form options into a longer form so we can more easily pass
# a sensible $options object around
my $options = {};
my $options_translate = {
	'c'		=> 'config',
	'd'		=> 'dest',
	'f'		=> 'force',
	'n'		=> 'name',
	'q'		=> 'quiet',
	'r'		=> 'remove',
	's'		=> 'source',
};

while(my($key, $value) = each(%{$options_cli}))
{
	$options->{$options_translate->{$key}} = $value;
}

if((defined($options->{'config'}) || defined($options->{'name'})) && (defined($options->{'source'}) || defined($options->{'dest'})))
{
	print "Invalid Usage: Configuration Mode (-c or -n) and Parameter Mode (-s or -d) options specified.\n";
	print "  Run '$0 -h' for usage information.\n";
	exit(1);
}

if((defined($options->{'source'}) && !defined($options->{'dest'})) || (!defined($options->{'source'}) && defined($options->{'dest'})))
{
	print "Invalid Usage: Parameter Mode requires -s (source) and -d (dest) options.\n";
	print "  Run '$0 -h' for usage information.\n";
	exit(1);
}

# initialise the base path and urls
my $uri_source = RepoTools::URI->new($options->{'source'});
my $uri_dest = RepoTools::URI->new($options->{'dest'});

if($uri_dest->{'type'} ne 'file')
{
	print "Invalid Usage: Destination (-d) option must be a directory.\n";
	exit(1);
}

# lets go grab our repomd.xml first and parse it into a tree
RepoTools::Helper->stdout_message('Downloading repomd.xml', $options);
my $repomd_url = $uri_source->generate('repodata/repomd.xml');
my $repomd_file = $uri_dest->generate('repodata/repomd.xml');
my $repomd_list = RepoTools::XMLParser->new({ 'mdtype' => 'repomd', 'filename' => 'repomd.xml', 'document' => $repomd_url->retrieve() })->parse();

# if our repomd.xml matches, the repo is fully synced
if(-f $repomd_file->path() && !$options->{'force'})
{
	# retrieve the on-disk file to get its sizing/checksums
	$repomd_file->retrieve();
	exit(0) if($repomd_url->size() == $repomd_file->size() && $repomd_url->checksum('sha256') eq $repomd_file->checksum('sha256'));
}

# before we continue, double check we have a 'primary' metadata object as that contains the list of rpms
my $primarymd_location;
foreach my $rd_entry (@{$repomd_list})
{
	if($rd_entry->{'type'} eq 'primary')
	{
		$primarymd_location = $rd_entry->{'location'};
		last;
	}
}

throw Error::Simple("Unable to locate 'primary' metadata within repomd.xml")
	unless(defined($primarymd_location));

# download all of the repodata files listed in repomd.xml
RepoTools::Helper->stdout_message('Downloading repodata', $options);
RepoTools::ListDownloader->new({ 'list' => $repomd_list, 'uri_source' => $uri_source, 'uri_dest' => $uri_dest })->sync();

# we should have pushed the primary metadata out to disk when we downloaded the repodata
my $primarymd = $uri_dest->generate($primarymd_location)->retrieve({ 'decompress' => 1 });
my $primarymd_list = RepoTools::XMLParser->new({ 'mdtype' => 'primary', 'filename' => $primarymd_location, 'document' => $primarymd })->parse();

# download all of the rpm files listed in the primary.xml variant
RepoTools::Helper->stdout_message('Downloading RPMs', $options);
RepoTools::ListDownloader->new({ 'list' => $primarymd_list, 'uri_source' => $uri_source, 'uri_dest' => $uri_dest })->sync();

# write the new repomd.xml at the end, now we've downloaded all the metadata and rpms it references
RepoTools::Helper->stdout_message('Writing repomd.xml', $options);
RepoTools::Helper->file_write($repomd_file->path(), $repomd_url->retrieve());

# obtain an up-to-date list of all files in our sync directory and then clear orphan content
if($options->{'remove'})
{
	my $filelist = $uri_dest->list();
	RepoTools::Helper->stdout_message('Removing orphan content', $options);
	RepoTools::ListRemover->new({ 'list' => [@{$repomd_list},@{$primarymd_list}], 'filelist' => $filelist, 'uri_dest' => $uri_dest })->sync();
}
