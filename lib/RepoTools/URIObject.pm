# RepoTools::URIObject
# 	Module to interact with a specific URI object (e.g. a file or http link)
#
# Copyright (C) 2016 Lee H <lee@leeh.co.uk>
# Released under the BSD 2-Clause License
package RepoTools::URIObject;

use strict;
use Carp;
use Digest::SHA qw(sha1_hex sha256_hex);
use HTTP::Tiny;

sub new
{
	my $name = shift;
	my $options = shift || {};

	confess "Missing option: path:$options->{'path'} type:$options->{'type'}"
		unless(defined($options->{'path'}) && defined($options->{'type'}));

	my $self = bless({}, $name);
	$self->{'path'} = $options->{'path'};
	$self->{'type'} = $options->{'type'};

	return $self;
}

sub checksum
{
	my $self = shift;
	my $cksumtype = shift;
	return (defined($self->{'checksum'}) && defined($self->{'checksum'}->{$cksumtype}) ? $self->{'checksum'}->{$cksumtype} : undef);
}

sub path
{
	my $self = shift;
	return $self->{'path'};
}

sub retrieve
{
	my $self = shift;
	my $options = shift || {};

	if($self->{'type'} eq 'file')
	{
		my $path = $self->{'path'};

		return unless(-f $path);

		# get the size before any decompression
		my @stat = stat($path);
		$self->{'size'} = $stat[7];

		if($options->{'decompress'})
		{
			$path = "gunzip -c $path |" if($path =~ /\.gz$/);
			$path = "bunzip2 -c $path |" if($path =~ /\.bz2$/);
		}

		my $contents;

		open(my $file, $path) or confess "Unable to open: $path";
		{ local $/; $contents = <$file>; }
		close($file);

		# calculate checksums
		$self->{'checksum'}->{'sha1'} = sha1_hex($contents);
		$self->{'checksum'}->{'sha256'} = sha256_hex($contents);

		return $contents;
	}
	elsif($self->{'type'} eq 'url')
	{
		# simple cache
		return $self->{'content'} if(defined($self->{'content'}));

		my $response = HTTP::Tiny->new()->get($self->{'path'});

		confess "Error: Unable to retrieve $self->{'path'}: $response->{'status'}: $response->{'reason'}"
			unless($response->{'success'} && $response->{'status'} == 200);

		$self->{'content'} = $response->{'content'};
		
		# calculate sizes and checksums
		$self->{'size'} = length($self->{'content'});
		$self->{'checksum'}->{'sha1'} = sha1_hex($self->{'content'});
		$self->{'checksum'}->{'sha256'} = sha256_hex($self->{'content'});

		return $self->{'content'};
	}
}

sub size
{
	my $self = shift;
	return (defined($self->{'size'}) ? $self->{'size'} : undef);
}

# xcompare()
# 	Compares a URIObjects size/checksums against a specially structured hash
# 	Note: The retrieve() method needs to have been called on the object first to load sizes and checksums.
#
# inputs	- hash comparison entry in form: { 'size' => 2048, 'checksum' => [{ 'type' => 'sha1', 'value' => 'deadbeef..' }] }
# outputs	-
# returns	- 1 if size and checksums match, otherwise 0
sub xcompare
{
	my $self = shift;
	my $entry = shift;

	return 0 unless(defined($self->{'size'}) && defined($self->{'checksum'}));
	return 0 unless($self->{'size'} == $entry->{'size'});

	foreach my $checksum (@{$entry->{'checksum'}})
	{
		return 0 unless($self->{'checksum'}->{$checksum->{'type'}} eq $checksum->{'value'});
	}

	return 1;

}

1;
