#!/usr/bin/perl -w
#
# repomirror.pl
# 	Tool for mirroring RPM based repositories via HTTP(s) in a reasonably intelligent manner.
#
# Copyright (C) 2016 Lee H <lee@leeh.uk>
# Released under the BSD 2-Clause License

use strict;
use v5.10;

# add our lib directory
use FindBin qw($Bin);
use lib "$Bin/lib";

use Carp;
use Getopt::Std qw(getopts);

use RepoTools::Config;
use RepoTools::Sync;

sub mirror_usage
{
	print "Configuration Mode\n";
	print "Usage: $0 [-fhrs] -c <config> [-n name]\n";
	print "     * -c: Configuration file to use.\n";
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

my $synclist = [];
if(defined($options->{'config'}))
{
	my $config = RepoTools::Config->new({ filename => $options->{'config'} })->parse();

	if(defined($options->{'name'}))
	{
		croak "Configuration Error: No repo named '$options->{'name'}'"
			unless(defined($config->{$options->{'name'}}));

		my $repodata = $config->{$options->{'name'}};
		push(@{$synclist}, { name => $options->{'name'}, source => $repodata->{'source'}, dest => $repodata->{'dest'}, rsync_args => $repodata->{'rsync_args'} });
	}
	else
	{
		while(my($repo, $repodata) = each(%{$config}))
		{
			next if(defined($repodata->{'disabled'}) && $repodata->{'disabled'} =~ /^(1|yes|true)$/i);
			push(@{$synclist}, { name => $repo, source => $repodata->{'source'}, dest => $repodata->{'dest'}, rsync_args => $repodata->{'rsync_args'} });
		}

		croak "No repositories to sync"
			unless(scalar(@{$synclist}) > 0);
	}
}
else
{
	push(@{$synclist}, { source => $options->{'source'}, dest => $options->{'dest'} });
}

my $urisynclist = [];
foreach my $sync (@{$synclist})
{
	my $uri_source = RepoTools::URI->new($sync->{'source'});
	my $uri_dest = RepoTools::URI->new($sync->{'dest'});

	croak "Error: Destination is not a local folder"
		unless($uri_dest->{'type'} eq 'file');

	push(@{$urisynclist}, { name => $sync->{'name'}, source => $uri_source, dest => $uri_dest, rsync_args => $sync->{'rsync_args'} });
}

RepoTools::Sync->new({ 'synclist' => $urisynclist, 'options' => $options })->sync();
