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
	confess "Missing 'uri_file' option" unless(defined($options->{'uri_file'}));

	$self->{'list'} = $options->{'list'};
	$self->{'filelist'} = $options->{'filelist'};
	$self->{'uri_file'} = $options->{'uri_file'};

	return $self;
}

sub sync
{
	my $self = shift;

	# generate an array of files listed in the metadata with full paths
	my $metadatalist = [$self->{'uri_file'}->generate('repodata/repomd.xml')->path()];
	foreach my $element (@{$self->{'list'}})
	{
		push(@{$metadatalist}, $self->{'uri_file'}->generate($element->{'location'})->path());
	}

	foreach my $element (@{$self->{'filelist'}})
	{
		unlink($element) unless(grep(/^$element$/, @{$metadatalist}));
	}
}

1;
