package RepoTools::URI;

use strict;
use Carp;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Find qw(find);
use File::Path qw(make_path);

use RepoTools::URIObject;

sub new
{
	my ($name, $uri) = (shift, shift);

	confess "Missing URI parameter"
		unless(defined($uri));

	my $self = bless({}, $name);

	if($uri =~ /^https?:\/\//)
	{
		$self->{'path'} = $uri;
		$self->{'type'} = 'url';
	}
	else
	{
		$self->{'path'} = $uri;
		$self->{'type'} = 'file';
	}

	confess "Safety hat: Refusing to use root filesystem as a sync location"
		if($self->{'type'} eq 'file' && abs_path($self->{'path'}) eq '/');

	# rework the path to be absolute if its on disk and ensure it exists
	if($self->{'type'} eq 'file')
	{
		make_path($self->{'path'});
		$self->{'path'} = abs_path($self->{'path'}) . '/';
	}

	return $self;
}

sub generate
{
	my $self = shift;
	my $path = shift;

	if($self->{'type'} eq 'file')
	{
		# Safety Dance Time.  We want to take some basic precautions as we're effectively
		# allowing an arbitrary XML file to dictate a folder structure.  Ideally, we'd first
		# validate the generated path is within our base folder, but abs_path() will return
		# nothing if one of the folders in that generated path doesnt actually exist.
		#
		# So, validate first for special characters, basic traversal checks, then create 
		# the required parent folders so we can validate with abs_path() its in our base.
		confess "Safety hat: Path contains strange characters: $path"
			unless($path =~ /^[a-zA-Z0-9\.\-\_\/]+$/);
		confess "Safety hat: Path traverses upwards: $path"
			if($path =~ /\.\.\//);

		my $genpath = $self->{'path'} . $path;
		my $dirname = dirname($genpath);
		make_path($dirname);
		my $abspath = abs_path($genpath);

		confess "Safety hat: Generated path is outside the base folder $self->{'path'}: $genpath -> $abspath"
			if(substr($abspath, 0, length($self->{'path'})) ne $self->{'path'});

		return RepoTools::URIObject->new({ 'path' => $abspath, 'type' => $self->{'type'} });
	}
	elsif($self->{'type'} eq 'url')
	{
		return RepoTools::URIObject->new({ 'path' => $self->{'path'} . $path, 'type' => $self->{'type'} });
	}
}

sub list_builder
{
	my $self = shift;
	push(@{$self->{'files'}}, $File::Find::name) if(-f "$_");
}

sub list
{
	my $self = shift;

	confess "RepoTools::URI->list() called on non-file" unless($self->{'type'} eq 'file');

	$self->{'files'} = [];
	find(sub { $self->list_builder($_) }, $self->{'path'});
	return $self->{'files'};
}

1;
