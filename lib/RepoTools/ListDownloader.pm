# RepoTools::ListDownloader
# 	Module to download all required files from a given list
#
# Copyright (C) 2016 Lee H <lee@leeh.co.uk>
# Released under the BSD 2-Clause License
package RepoTools::ListDownloader;

use strict;
use Carp;

use RepoTools::Helper;

sub new
{
	my $name = shift;
	my $options = shift || {};

	my $self = bless({}, $name);

	confess "Missing 'list' option" unless(defined($options->{'list'}));
	confess "Missing 'uri_source' option" unless(defined($options->{'uri_source'}));
	confess "Missing 'uri_dest' option" unless(defined($options->{'uri_dest'}));

	$self->{'list'} = $options->{'list'};
	$self->{'uri_source'} = $options->{'uri_source'};
	$self->{'uri_dest'} = $options->{'uri_dest'};

	return $self;
}

sub sync
{
	my $self = shift;

	foreach my $entry (@{$self->{'list'}})
	{
		my $source = $self->{'uri_source'}->generate($entry->{'location'});
		my $dest = $self->{'uri_dest'}->generate($entry->{'location'});

		$dest->retrieve();
		# determine if our on disk contents match whats listed in repomd.xml
		unless(-f $dest->path() && $dest->xcompare($entry))
		{
			$source->retrieve();

			throw Error::Simple("Size/hash mismatch vs metadata downloading: " . $source->path())
				unless($source->xcompare($entry));

			RepoTools::Helper->file_write($dest->path(), $source->retrieve());
		}
	}
}

1;
