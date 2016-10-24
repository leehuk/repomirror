#!/usr/bin/perl -w
#
# repomirror.pl
# 	Tool for mirroring RPM based repositories via HTTP(s) in a reasonably intelligent manner.
#
# Copyright (C) 2016 Lee H <lee -at- leeh -dot- uk>
#
# Released under the MIT License

####################
# RepoMirror::Helper
# 	Contains various helper functions
package RepoMirror::Helper;

use strict;
use Carp;

sub file_write
{
	my ($name, $path, $contents) = (shift, shift, shift);

	open(my $file, '>', $path) or confess "Unable to open file for writing: $path";
	print $file $contents;
	close($file);
}

############################
# RepoMirror::ListDownloader
# 	Class for downloading and syncing contents from a built list
#
package RepoMirror::ListDownloader;

use strict;
use Carp;

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

			RepoMirror::Helper->file_write($file->path(), $url->retrieve());
		}

		$self->{'pb'}->update("Downloaded $entry->{'location'}");
	}
}

#########################
# RepoMirror::ProgressBar
# 	Implements a simplistic progress bar for operations
# 
package RepoMirror::ProgressBar;

use strict;
use Carp;

sub new
{
	my $name = shift;
	my $options = shift || {};

	my $self = bless({}, $name);

	confess("Missing 'message' option")
		unless(defined($options->{'message'}));
	confess("Missing 'count' option")
		unless(defined($options->{'count'}));

	$self->{'message'}		= $options->{'message'};
	$self->{'current'}		= 0;
	$self->{'count'} 		= $options->{'count'};
	$self->{'silent'}		= $options->{'silent'};

	$|=1;

	$self->message();
	return $self;
}

sub message
{
	my $self = shift;
	my $message = shift;

	return if($self->{'silent'});

	my $percent = int(($self->{'current'}/$self->{'count'})*100);
	my $actmessage = ($percent == 100 ? $self->{'message'} : (defined($message) ? $message : $self->{'message'}));

	printf("\r\e[K[%3d%%] %s%s", $percent, $actmessage, ($percent == 100 ? "\n" : ""));
}

sub update
{
	my $self = shift;
	my $message = shift;

	$self->{'current'}++;
	$self->message($message);
}

#################
# RepoMirror::URI
# 	Parent class for generating RepoMirror::URIObject elements
#
package RepoMirror::URI;

use strict;
use Carp;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Find qw(find);
use File::Path qw(make_path);

sub new
{
	my $name = shift;
	my $options = shift || {};

	confess "Missing option: path:$options->{'path'} type:$options->{'type'}"
		unless(defined($options->{'path'}) && defined($options->{'type'}));
	confess "Invalid 'type' option: $options->{'type'}"
		unless($options->{'type'} eq 'file' || $options->{'type'} eq 'url');
	confess "Safety hat: Refusing to use root filesystem as a sync location"
		if($options->{'type'} eq 'file' && abs_path($options->{'path'}) eq '/');

	my $self = bless({}, $name);
	$self->{'path'} = $options->{'path'};
	$self->{'type'} = $options->{'type'};

	# rework the path to be absolute if its on disk and ensure it exists
	if($self->{'type'} eq 'file')
	{
		$self->{'path'} = abs_path($self->{'path'}) . '/';
		make_path($self->{'path'});
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

		return RepoMirror::URIObject->new({ 'path' => $abspath, 'type' => $self->{'type'} });
	}
	elsif($self->{'type'} eq 'url')
	{
		return RepoMirror::URIObject->new({ 'path' => $self->{'path'} . $path, 'type' => $self->{'type'} });
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

	confess "RepoMirror::URI->list() called on non-file" unless($self->{'type'} eq 'file');

	$self->{'files'} = [];
	find(sub { $self->list_builder($_) }, $self->{'path'});
	return $self->{'files'};
}

#################
# RepoMirror::URIObject
# 	Handles downloading and retrieving sub-URIs of a RepoMirror::URI object
#
package RepoMirror::URIObject;

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

#######################
# RepoMirror::XMLParser
#   Parses repomd and primary repodata XML files
#
package RepoMirror::XMLParser;

use strict;
use Carp;
use Data::Dumper;
use Error qw(:try);
use IO::String;
use XML::Tiny qw(parsefile);

sub new
{
	my $name = shift;
	my $options = shift || {};

	confess "Missing option: mdtype:$options->{'mdtype'} filename:$options->{'filename'} or document"
		unless(defined($options->{'mdtype'}) && defined($options->{'filename'}) && defined($options->{'document'}));
	confess "Invalid 'mdtype' option"
		unless($options->{'mdtype'} eq 'repomd' || $options->{'mdtype'} eq 'primary');

	my $self = bless({}, $name);
	$self->{'document'} = $options->{'document'};
	$self->{'filename'} = $options->{'filename'};
	$self->{'mdtype'} = $options->{'mdtype'};

	return $self;
}

sub parse
{
	my $self = shift;
	my $filename = shift;
	my $xmlcontent = shift;

	my $xml;
	try {
		$xml = parsefile(IO::String->new($self->{'document'}));
	}
	catch Error with {
		my $error = shift;
		chomp($error->{'-text'});

		confess "XML Parse Error: $filename $error->{'-text'}";
	};

	confess "XML Error: $filename Root structure is not an array"
		unless(ref($xml) eq "ARRAY");
	confess "XML Error: $filename Duplicate root elements"
		unless(scalar(@{$xml}) == 1);

	# nest down into our first element
	$xml = @{$xml}[0];

	confess "XML Error: $self->{'filename'} Root element does not have a name"
		unless(defined($xml->{'name'}));
	confess "XML Error: $self->{'filename'} Root element is not 'repomd': $xml->{'name'}"
		if($self->{'mdtype'} eq 'repomd' && $xml->{'name'} ne 'repomd');
	confess "XML Error: $self->{'filename'} Root element is not 'metadata': $xml->{'name'}"
		if($self->{'mdtype'} eq 'primary' && $xml->{'name'} ne 'metadata');
	confess "XML Error: $self->{'filename'} Root element does not have nested data"
		unless(ref($xml->{'content'}) eq 'ARRAY');

	return $self->parse_content_root($xml->{'content'});
}

sub parse_content_root
{
	my $self = shift;
	my $xml = shift;

	my $filelist = [];

	foreach my $element (@{$xml})
	{
		confess "XML Error: $self->{'filename'} Data block has no name"
			unless(defined($element->{'name'}));

		# skip elements that arent relevant
		if($self->{'mdtype'} eq 'repomd')
		{
			next unless($element->{'name'} eq 'data');
		}
		elsif($self->{'mdtype'} eq 'primary')
		{
			next unless($element->{'name'} eq 'package');
			next unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'type'}) && $element->{'attrib'}->{'type'} eq 'rpm');
		}

		push(@{$filelist}, $self->parse_content_object($element->{'content'}, $element->{'attrib'}->{'type'}));
	}

	return $filelist;
}

sub parse_content_object
{
	my $self = shift;
	my $xml = shift;
	my $type = shift;

	my $contentobj = {};
	$contentobj->{'type'}		= $type;

	foreach my $element (@{$xml})
	{
		if($element->{'name'} eq 'checksum')
		{
			throw Error::Simple("Unable to locate checksum type for data block '$type'")
				unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'type'}));
			throw Error::Simple("Unable to locate checksum value for data block '$type'")
				unless(defined($element->{'content'}) && ref($element->{'content'}) eq 'ARRAY' && scalar(@{$element->{'content'}}) == 1 && defined($element->{'content'}[0]->{'content'}));
			throw Error::Simple("Unknown checksum type '$element->{'attrib'}->{'type'}' for data block '$type'")
				unless($element->{'attrib'}->{'type'} eq 'sha1' || $element->{'attrib'}->{'type'} eq 'sha256');

			push(@{$contentobj->{'checksum'}}, {
				'type'		=> $element->{'attrib'}->{'type'},
				'value'		=> $element->{'content'}[0]->{'content'},
			});
		}
		elsif($element->{'name'} eq 'location')
		{
			throw Error::Simple("Unable to locate location href for data block '$type'")
				unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'href'}));

			$contentobj->{'location'} = $element->{'attrib'}->{'href'};
		}
		elsif($element->{'name'} eq 'size')
		{
			if($self->{'mdtype'} eq 'repomd')
			{
				throw Error::Simple("Unable to locate size value for data block '$type'")
					unless(defined($element->{'content'}) && ref($element->{'content'}) eq 'ARRAY' && scalar(@{$element->{'content'}}) == 1 && defined($element->{'content'}[0]->{'content'}));

				$contentobj->{'size'} = $element->{'content'}[0]->{'content'};
			}
			elsif($self->{'mdtype'} eq 'primary')
			{
				throw Error::Simple("Unable to locate size value for data block '$type'")
					unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'package'}));

				$contentobj->{'size'} = $element->{'attrib'}->{'package'};
			}
		}
	}

	return $contentobj;
}

######
# main
#   Main program
#
package main;

use strict;
use v5.10;

use Carp;
use Data::Dumper;
use Getopt::Std qw(getopts);

sub mirror_usage
{
	print "Usage: $0 [-fhrs] -d <directory> -u <url>\n";
	print "     * -d: Directory to mirror to (required).\n";
	print "           When -r(emove) is specified, *everything* within this folder\n";
	print "           thats not listed in the repo will be *deleted*.\n";
	print "       -f: Force repodata/rpm sync when up to date.\n";
	print "       -h: Show this help.\n";
	print "       -r: Remove local files that are no longer on the mirror.\n";
	print "           Its *strongly* recommended you run a download first without\n";
	print "           this option to ensure you have your pathing correct.\n";
	print "       -s: Be silent other than for errors.\n";
	print "     * -u: Sets the base URL for the repository (required).\n";
	print "           This should be the same path used in a yum.repos.d file,\n";
	print "           but without any variables like \$releasever etc.\n";
}

my $option_force = 0;
my $option_silent = 0;

my $options = {};
getopts('d:fhsu:v', $options);

if(defined($options->{'h'}) || !defined($options->{'u'}) || !defined($options->{'d'}))
{
	mirror_usage();
	exit(1);
}

$option_force = 1 if(defined($options->{'f'}));
$option_silent = 1 if(defined($options->{'s'}));

# initialise the base path and urls
my $uri_file = RepoMirror::URI->new({ 'path' => $options->{'d'}, 'type' => 'file' });
my $uri_url = RepoMirror::URI->new({ 'path' => $options->{'u'}, 'type' => 'url' });

# lets go grab our repomd.xml first and parse it into a tree
my $pb = RepoMirror::ProgressBar->new({ 'message' => 'Downloading repomd.xml', 'count' => 1, 'silent' => $option_silent });
my $repomd_file = $uri_file->generate('repodata/repomd.xml');
my $repomd_url = $uri_url->generate('repodata/repomd.xml');
my $repomd_list = RepoMirror::XMLParser->new({ 'mdtype' => 'repomd', 'filename' => 'repomd.xml', 'document' => $repomd_url->retrieve() })->parse();
$pb->update();

# if our repomd.xml matches, the repo is fully synced
if(-f $repomd_file->path() && !$option_force)
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
$pb = RepoMirror::ProgressBar->new({ 'message' => 'Downloading repodata', 'count' => scalar(@{$repomd_list}), 'silent' => $option_silent });
RepoMirror::ListDownloader->new({ 'list' => $repomd_list, 'pb' => $pb, 'uri_file' => $uri_file, 'uri_url' => $uri_url })->sync();

# we should have pushed the primary metadata out to disk when we downloaded the repodata
my $primarymd = $uri_file->generate($primarymd_location)->retrieve({ 'decompress' => 1 });
my $primarymd_list = RepoMirror::XMLParser->new({ 'mdtype' => 'primary', 'filename' => $primarymd_location, 'document' => $primarymd })->parse();

# download all of the rpm files listed in the primary.xml variant
$pb = RepoMirror::ProgressBar->new({ 'message' => 'Downloading RPMs', 'count' => scalar(@{$primarymd_list}), 'silent' => $option_silent });
RepoMirror::ListDownloader->new({ 'list' => $primarymd_list, 'pb' => $pb, 'uri_file' => $uri_file, 'uri_url' => $uri_url })->sync();

# write the new repomd.xml at the end, now we've downloaded all the metadata and rpms it references
$pb = RepoMirror::ProgressBar->new({ 'message' => 'Writing repomd.xml', 'count' => 1, 'silent' => $option_silent });
RepoMirror::Helper->file_write($repomd_file->path(), $repomd_url->retrieve());
$pb->update();
