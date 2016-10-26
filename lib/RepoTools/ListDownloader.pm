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
	confess "Missing 'pb' option" unless(defined($options->{'pb'}));
	confess "Missing 'uri_file' option" unless(defined($options->{'uri_file'}));
	confess "Missing 'uri_url' option" unless(defined($options->{'uri_url'}));

	$self->{'list'} = $options->{'list'};
	$self->{'pb'} = $options->{'pb'};
	$self->{'uri_file'} = $options->{'uri_file'};
	$self->{'uri_url'} = $options->{'uri_url'};

	return $self;
}

sub sync
{
	my $self = shift;

	foreach my $entry (@{$self->{'list'}})
	{
		$self->{'pb'}->message("Downloading $entry->{'location'}");

		my $file = $self->{'uri_file'}->generate($entry->{'location'});
		my $url = $self->{'uri_url'}->generate($entry->{'location'});

		$file->retrieve();
		# determine if our on disk contents match whats listed in repomd.xml
		unless(-f $file->path() && $file->xcompare($entry))
		{
			$url->retrieve();

			throw Error::Simple("Size/hash mismatch vs metadata downloading: " . $url->path())
				unless($url->xcompare($entry));

			RepoTools::Helper->file_write($file->path(), $url->retrieve());
		}

		$self->{'pb'}->update("Downloaded $entry->{'location'}");
	}
}

1;
