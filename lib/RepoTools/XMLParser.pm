# RepoTools::XMLParser
# 	Module to parse repomd.xml and primary.xml repodata files
#
# Copyright (C) 2016 Lee H <lee@leeh.co.uk>
# Released under the BSD 2-Clause License
package RepoTools::XMLParser;

use strict;
use Carp;
use Error qw(:try);
use XML::Parser;

sub new
{
	my $name = shift;
	my $options = shift || {};

	confess "Missing option: mdtype:$options->{'mdtype'} filename:$options->{'filename'} or document"
		unless(defined($options->{'mdtype'}) && defined($options->{'filename'}) && defined($options->{'document'}));
	confess "Invalid 'mdtype' option"
		unless($options->{'mdtype'} eq 'repomd' || $options->{'mdtype'} eq 'primary');

	my $self = bless({}, $name);
	$self->{'filename'} = $options->{'filename'};
	$self->{'mdtype'} = $options->{'mdtype'};
	$self->{'document'} = $self->sensiblexml($options->{'document'});

	return $self;
}

sub sensiblexml
{
	my ($self, $document) = (shift, shift);
	my $xml = XML::Parser->new(Style => 'Tree')->parse($document);
	return $self->sensiblexml_iter(shift(@{$xml}), shift(@{$xml}), {});
}

sub sensiblexml_iter
{
	my ($self, $element, $data, $structure) = (shift, shift, shift, shift);

	$structure->{'name'} = $element;

	my $args = shift(@{$data});
	while(my($key, $value) = each(%{$args}))
	{
		$structure->{'attrib'}->{$key} = $value;
	}

	while(scalar(@{$data}) > 0)
	{
		my ($subelem, $subdata) = (shift(@{$data}), shift(@{$data}));

		if($subelem eq '0')
		{
			next if($subdata =~ /^\s+$/m);
			$structure->{'value'} = $subdata;
		}
		else
		{
			$structure->{'content'} ||= [];
			push(@{$structure->{'content'}}, $self->sensiblexml_iter($subelem, $subdata, {}));

		}
	}

	return $structure;
}

sub parse
{
	my ($self, $filename) = (shift, shift);

	my $xml = $self->{'document'};

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
				unless(defined($element->{'value'}));
			throw Error::Simple("Unknown checksum type '$element->{'attrib'}->{'type'}' for data block '$type'")
				unless($element->{'attrib'}->{'type'} eq 'sha1' || $element->{'attrib'}->{'type'} eq 'sha256');

			push(@{$contentobj->{'checksum'}}, {
				'type'		=> $element->{'attrib'}->{'type'},
				'value'		=> $element->{'value'},
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
					unless(defined($element->{'value'}));

				$contentobj->{'size'} = $element->{'value'};
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

1;
