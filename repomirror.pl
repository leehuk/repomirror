#!/usr/bin/perl -w

package RepoMirrorProgressbar;

use strict;
use Carp;

sub new
{
	my $name = shift;
	my $options = shift || {};

	my $self = {};

	confess("Missing 'message' option")
		unless(defined($options->{'message'}));
	confess("Missing 'count' option")
		unless(defined($options->{'count'}));

	$self->{'message'}		= $options->{'message'};
	$self->{'current'}		= 0;
	$self->{'count'} 		= $options->{'count'};
	$self->{'silent'}		= $options->{'silent'};

	$|=1;

	bless($self, $name);
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


package main;

use strict;
use v5.10;

use Cwd qw(abs_path);
use Data::Dumper;
use Digest::SHA qw(sha1_hex sha256_hex);
use Error qw(:try);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use Getopt::Std qw(getopts);
use HTTP::Tiny;
use IO::String;
use XML::Tiny qw(parsefile);

my $mirror_base_path;
my $mirror_base_url;

my $option_force = 0;
my $option_silent = 0;

sub mirror_usage
{
	print "Usage: $0 [-fhrs] -d <directory> -u <url>\n";
	print "     * -d: Directory to mirror to (required).\n";
	print "       -f: Force repodata/rpm sync when up to date.\n";
	print "       -h: Show this help.\n";
	print "       -r: Remove local files that are no longer on the mirror.\n";
	print "       -s: Be silent other than for errors.\n";
	print "     * -u: Sets the base URL for the repository (required).\n";
	print "           This should be the same path used in a yum.repos.d file,\n";
	print "           but without any variables like \$releasever etc.\n";
}

sub mirror_get_url
{
	my $url = shift;

	my $response = HTTP::Tiny->new->get($url);
	throw Error::Simple("Unable to retrieve $url: $response->{'status'}: $response->{'reason'}")
		unless($response->{'success'} && $response->{'status'} == 200);

	return $response->{'content'};
}

sub mirror_get_path
{
	my $path = shift;
	my $decompress = shift || 0;
	my $contents;

	# update for decompression if required
	$path = "gunzip -c $path |"
		if($decompress && $path =~ /\.gz$/);
	$path = "bunzip2 -c $path |"
		if($decompress && $path =~ /\.bz2$/);

	open(my $file, $path) or throw Error::Simple("Unable to open $path");
	{ local $/; $contents = <$file>; }
	close($file);

	return $contents;
}

sub mirror_gen_path
{
	my $path = shift;

	throw Error::Simple("Error: Path contains strange characters: $path")
		unless($path =~ /^[a-zA-Z0-9\.\-\_\/]+$/);
	throw Error::Simple("Error: Path traverses upwards: $path")
		if($path =~ /\.\.\//);

	my $dirname = dirname($mirror_base_path . $path);
	make_path($dirname);

	my $genpath = abs_path($mirror_base_path . $path);
	throw Error::Simple("Error: Generated path is unsafe: $mirror_base_path$path -> $genpath")
		if(substr(abs_path($genpath), 0, length($mirror_base_path)) ne $mirror_base_path);

	return $genpath;
}

sub mirror_gen_url
{
	my $url = shift;

	return "$mirror_base_url$url";
}

sub mirror_compare
{
	my $path = shift;
	my $entry = shift;
	my $size_only = shift || 0;

	return 0 unless(mirror_compare_size($path, $entry->{'size'}));
	return 1 if($size_only);

	foreach my $checksum (@{$entry->{'checksum'}})
	{
		return 0 unless(mirror_compare_hash($path, $checksum->{'type'}, $checksum->{'value'}));
	}

	return 1;
}

sub mirror_compare_size
{
	my $path = shift;
	my $size = shift;

	return 1 if(fileinfo_size($path) == $size);
	return 0;
}

sub mirror_compare_hash
{
	my $path = shift;
	my $type = shift;
	my $hash = shift;

	my $filehash;
	if($type eq 'sha1')
	{
		$filehash = fileinfo_sha1($path);
	}
	elsif($type eq 'sha256')
	{
		$filehash = fileinfo_sha256($path);
	}
	else
	{
		throw Error::Simple("Invalid hash method: $type for '$path'");
	}

	return 1 if($hash eq $filehash);
	return 0;
}

sub fileinfo_size
{
	my $path = shift;

	my @stat = stat($path);
	return $stat[7];
}

sub fileinfo_sha1
{
	my $path = shift;
	return sha1_hex(mirror_get_path($path));
}

sub fileinfo_sha256
{
	my $path = shift;
	return sha256_hex(mirror_get_path($path));
}

sub mirror_parse_repomd
{
	my $xmlcontent = shift;

	my $filelist = [];
	try {
		my $repomdxml = parsefile(IO::String->new($xmlcontent));

		throw Error::Simple("Invalid XML: Root structure is not an array")
			unless(ref($repomdxml) eq "ARRAY");
		throw Error::Simple("Invalid XML: Duplicate root elements")
			unless(scalar(@{$repomdxml}) == 1);

		my $repomd = @{$repomdxml}[0];

		throw Error::Simple("Invalid XML: Root element is not repomd")
			unless(defined($repomd->{'name'}) && $repomd->{'name'} eq 'repomd');
		throw Error::Simple("Invalid XML: repomd element does not have nested data")
			unless(ref($repomd->{'content'}) eq 'ARRAY');

		my $content = $repomd->{'content'};
		foreach my $element (@{$content})
		{
			# skip non-data elements
			next unless(defined($element->{'name'}) && $element->{'name'} eq 'data');

			throw Error::Simple("Invalid XML: data block has no type")
				unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'type'}));

			my $type = $element->{'attrib'}->{'type'};

			my $contentobj = {
				'type'		=> $type,
			};

			foreach my $celement (@{$element->{'content'}})
			{
				if($celement->{'name'} eq 'checksum')
				{
					throw Error::Simple("Unable to locate checksum type for data block '$type'")
						unless(defined($celement->{'attrib'}) && defined($celement->{'attrib'}->{'type'}));
					throw Error::Simple("Unable to locate checksum value for data block '$type'")
						unless(defined($celement->{'content'}) && ref($celement->{'content'}) eq 'ARRAY' && scalar(@{$celement->{'content'}}) == 1 && defined($celement->{'content'}[0]->{'content'}));
					throw Error::Simple("Unknown checksum type '$celement->{'attrib'}->{'type'}' for data block '$type'")
						unless($celement->{'attrib'}->{'type'} eq 'sha1' || $celement->{'attrib'}->{'type'} eq 'sha256');

					push(@{$contentobj->{'checksum'}}, {
						'type'		=> $celement->{'attrib'}->{'type'},
						'value'		=> $celement->{'content'}[0]->{'content'},
					});
				}
				elsif($celement->{'name'} eq 'location')
				{
					throw Error::Simple("Unable to locate location href for data block '$type'")
						unless(defined($celement->{'attrib'}) && defined($celement->{'attrib'}->{'href'}));

					$contentobj->{'location'} = $celement->{'attrib'}->{'href'};
				}
				elsif($celement->{'name'} eq 'size')
				{
					throw Error::Simple("Unable to locate size value for data block '$type'")
						unless(defined($celement->{'content'}) && ref($celement->{'content'}) eq 'ARRAY' && scalar(@{$celement->{'content'}}) == 1 && defined($celement->{'content'}[0]->{'content'}));

					$contentobj->{'size'} = $celement->{'content'}[0]->{'content'};
				}
			}

			push(@{$filelist}, $contentobj);
		}
	}
	catch Error with {
		my $error = shift;

		chomp($error->{'-text'});

		print STDERR "Error: Unable to parse repomd.xml: $error->{'-text'}\n";
		exit(1);
	};

	return $filelist;
}

sub mirror_parse_primarymd
{
	my $xmlcontent = shift;

	my $filelist = [];
	try {
		my $primarymdxml = parsefile(IO::String->new($xmlcontent));

		throw Error::Simple("Invalid XML: Root structure is not an array")
			unless(ref($primarymdxml) eq "ARRAY");
		throw Error::Simple("Invalid XML: Duplicate root elements")
			unless(scalar(@{$primarymdxml}) == 1);

		my $primarymd = @{$primarymdxml}[0];

		throw Error::Simple("Invalid XML: Root element is not metadata")
			unless(defined($primarymd->{'name'}) && $primarymd->{'name'} eq 'metadata');
		throw Error::Simple("Invalid XML: primarymd element does not have nested data")
			unless(ref($primarymd->{'content'}) eq 'ARRAY');

		my $content = $primarymd->{'content'};
		foreach my $element (@{$content})
		{
			# skip non-data elements
			next unless(defined($element->{'name'}) && $element->{'name'} eq 'package');

			throw Error::Simple("Invalid XML: data block has no type")
				unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'type'}));

			# skip non-rpm elements
			next unless($element->{'attrib'}->{'type'} eq 'rpm');

			my $contentobj = {};

			my $type;
			foreach my $celement (@{$element->{'content'}})
			{
				if($celement->{'name'} eq 'checksum')
				{
					throw Error::Simple("Unable to locate checksum type for data block '$type'")
						unless(defined($celement->{'attrib'}) && defined($celement->{'attrib'}->{'type'}));
					throw Error::Simple("Unable to locate checksum value for data block '$type'")
						unless(defined($celement->{'content'}) && ref($celement->{'content'}) eq 'ARRAY' && scalar(@{$celement->{'content'}}) == 1 && defined($celement->{'content'}[0]->{'content'}));
					throw Error::Simple("Unknown checksum type '$celement->{'attrib'}->{'type'}' for data block '$type'")
						unless($celement->{'attrib'}->{'type'} eq 'sha1' || $celement->{'attrib'}->{'type'} eq 'sha256');

					push(@{$contentobj->{'checksum'}}, {
						'type'		=> $celement->{'attrib'}->{'type'},
						'value'		=> $celement->{'content'}[0]->{'content'},
					});
				}
				elsif($celement->{'name'} eq 'location')
				{
					throw Error::Simple("Unable to locate location href for data block '$type'")
						unless(defined($celement->{'attrib'}) && defined($celement->{'attrib'}->{'href'}));

					$contentobj->{'location'} = $celement->{'attrib'}->{'href'};
				}
				elsif($celement->{'name'} eq 'size')
				{
					throw Error::Simple("Unable to locate size value for data block '$type'")
						unless(defined($celement->{'attrib'}) && defined($celement->{'attrib'}->{'package'}));

					$contentobj->{'size'} = $celement->{'attrib'}->{'package'};
				}
			}

			push(@{$filelist}, $contentobj);
		}
	}
	catch Error with {
		my $error = shift;

		chomp($error->{'-text'});

		print STDERR "Error: Unable to parse primary.xml: $error->{'-text'}\n";
		exit(1);
	};

	return $filelist;
}

my $options = {};
getopts('d:fhsu:v', $options);

if(defined($options->{'h'}) || !defined($options->{'u'}) || !defined($options->{'d'}))
{
	mirror_usage();
	exit(1);
}

if(abs_path($options->{'d'}) eq '/')
{
	print "Error: You *really* dont want to sync to the root filesystem.\n";
	exit(1);
}

$option_force = 1 if(defined($options->{'f'}));
$option_silent = 1 if(defined($options->{'s'}));

# ensure our main folder exists
make_path($options->{'d'});

# initialise the base path and urls
$mirror_base_path = abs_path($options->{'d'}) . '/';
$mirror_base_url = $options->{'u'};

my $repomd_path = mirror_gen_path('repodata/repomd.xml');
my $repomd_url = mirror_gen_url('repodata/repomd.xml');

my $pb = RepoMirrorProgressbar->new({ 'message' => 'Downloading repomd.xml', 'count' => 1, 'silent' => $option_silent });
my $repomd = mirror_get_url($repomd_url);
$pb->update();

my $rd_list = mirror_parse_repomd($repomd);

# if our repomd.xml matches, the repo is fully synced
if(-f $repomd_path && !$option_force)
{
	exit(0) if(mirror_compare($repomd_path, {
			'location'		=> 'repodata/repomd.xml',
			'size'			=> length($repomd),
			'checksum'		=> [{
				'type'			=> 'sha256',
				'value'			=> sha256_hex($repomd),
			}],
		}));
}

# before we continue, double check we have a 'primary' metadata object
my $primarymd_location;
foreach my $rd_entry (@{$rd_list})
{
	if($rd_entry->{'type'} eq 'primary')
	{
		$primarymd_location = $rd_entry->{'location'};
		last;
	}
}

throw Error::Simple("Unable to locate 'primary' metadata within repomd.xml")
	unless(defined($primarymd_location));

$pb = RepoMirrorProgressbar->new({ 'message' => 'Downloading repodata', 'count' => scalar(@{$rd_list}), 'silent' => $option_silent });
foreach my $rd_entry (@{$rd_list})
{
	$pb->message("Downloading $rd_entry->{'location'}");

	my $path = mirror_gen_path($rd_entry->{'location'});
	my $url = mirror_gen_url($rd_entry->{'location'});

	unless(-f $path && mirror_compare($path, $rd_entry))
	{
		my $repodata = mirror_get_url($url);
		open(my $file, '>', $path) or throw Error::Simple("Unable to open file for writing: $path");
		print $file $repodata;
		close($file);

		unless(mirror_compare($path, $rd_entry))
		{
			unlink($path);
			throw Error::Simple("Size/hash mismatch downloading: $url");
		}
	}

	$pb->update("Downloaded $rd_entry->{'location'}");
}

my $primarymd_path = mirror_gen_path($primarymd_location);
my $primarymd = mirror_get_path($primarymd_path, 1);

my $rpm_list = mirror_parse_primarymd($primarymd);
# we're done with the metadata and its fairly expensive to hold in memory, so wipe it out
$primarymd = undef;

$pb = RepoMirrorProgressbar->new({ 'message' => 'Downloading RPMs', 'count' => scalar(@{$rpm_list}), 'silent' => $option_silent });
foreach my $rpm_entry (@{$rpm_list})
{
	$pb->message("Downloading $rpm_entry->{'location'}");

	my $path = mirror_gen_path($rpm_entry->{'location'});
	my $url = mirror_gen_url($rpm_entry->{'location'});

	unless(-f $path && mirror_compare($path, $rpm_entry, 1))
	{
		my $rpm = mirror_get_url($url);
		open(my $file, '>', $path) or throw Error::Simple("Unable to open file for writing: $path");
		print $file $rpm;
		close($file);

		# validate what we downloaded matches the xml
		unless(mirror_compare($path, $rpm_entry))
		{
			unlink($path);
			throw Error::Simple("Size/hash mismatch downloading: $url");
		}
	}

	$pb->update("Downloaded $rpm_entry->{'location'}");
}

# write the new repomd.xml at the end, now we've downloaded all the metadata and rpms it references
$pb = RepoMirrorProgressbar->new({ 'message' => 'Writing repomd.xml', 'count' => 1, 'silent' => $option_silent });
open(my $file, '>', $repomd_path) or throw Error::Simple("Unable to open file for writing: $repomd_path");
print $file $repomd;
close($file);
$pb->update();
