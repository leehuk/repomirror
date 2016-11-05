# RepoTools::ListRemover
# 	Module to remove all files not contained within a given list
#
# Copyright (C) 2016 Lee H <lee@leeh.co.uk>
# Released under the BSD 2-Clause License
package RepoTools::ListRemover;

use strict;
use Carp;

sub new
{
	my $name = shift;
	my $options = shift || {};

	my $self = bless({}, $name);

	confess "Missing 'list' option" unless(defined($options->{'list'}));
	confess "Missing 'filelist' option" unless(defined($options->{'filelist'}));
	confess "Missing 'uri_dest' option" unless(defined($options->{'uri_dest'}));

	$self->{'list'} = $options->{'list'};
	$self->{'filelist'} = $options->{'filelist'};
	$self->{'uri_dest'} = $options->{'uri_dest'};

	return $self;
}

sub sync
{
	my $self = shift;

	# generate an array of files listed in the metadata with full paths
	my $metadatalist = [$self->{'uri_dest'}->generate('repodata/repomd.xml')->path()];
	foreach my $element (@{$self->{'list'}})
	{
		push(@{$metadatalist}, $self->{'uri_dest'}->generate($element->{'location'})->path());
	}

	foreach my $element (@{$self->{'filelist'}})
	{
		unlink($element) unless(grep(/^$element$/, @{$metadatalist}));
	}
}

1;
