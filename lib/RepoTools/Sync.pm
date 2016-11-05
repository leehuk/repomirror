# RepoTools::Sync
# 	Module to handle the process for syncing a repo
#
# Copyright (C) 2016 Lee H <lee@leeh.co.uk>
# Released under the BSD 2-Clause License
package RepoTools::Sync;

use strict;
use Capture::Tiny qw(capture);
use Carp;

use RepoTools::Helper;
use RepoTools::ListDownloader;
use RepoTools::ListRemover;
use RepoTools::URI;
use RepoTools::XMLParser;

sub new
{
	my ($name, $options) = (shift, shift);

	confess "Missing 'synclist' option"
		unless(defined($options->{'synclist'}));
	confess "Missing 'options' option"
		unless(defined($options->{'options'}));
	confess "Invalid 'synclist' option"
		unless(ref($options->{'synclist'}) eq 'ARRAY');

	my $self = bless({}, $name);
	$self->{'synclist'} = $options->{'synclist'};
	$self->{'options'} = $options->{'options'};
	return $self;
}

sub sync
{
	my $self = shift;

	foreach my $sync (@{$self->{'synclist'}})
	{
		if($sync->{'source'}->{'type'} eq 'url')
		{
			$self->sync_repo_http($sync);
		}
		elsif($sync->{'source'}->{'type'} =~ /^(rsync|file)$/)
		{
			$self->sync_repo_rsync($sync);
		}
	}
}

sub sync_repo_http
{
	my ($self, $sync) = (shift, shift);

	my $uri_source = $sync->{'source'};
	my $uri_dest = $sync->{'dest'};

	# lets go grab our repomd.xml first and parse it into a tree
	RepoTools::Helper->stdout_message((defined($sync->{'name'}) ? "[$sync->{'name'}] " : "") . 'Downloading repomd.xml', $self->{'options'});
	my $repomd_url = $uri_source->generate('repodata/repomd.xml');
	my $repomd_file = $uri_dest->generate('repodata/repomd.xml');
	my $repomd_list = RepoTools::XMLParser->new({ 'mdtype' => 'repomd', 'filename' => 'repomd.xml', 'document' => $repomd_url->retrieve() })->parse();

	# if our repomd.xml matches, the repo is fully synced
	if(-f $repomd_file->path() && !$self->{'options'}->{'force'})
	{
		# retrieve the on-disk file to get its sizing/checksums
		$repomd_file->retrieve();
		return if($repomd_url->size() == $repomd_file->size() && $repomd_url->checksum('sha256') eq $repomd_file->checksum('sha256'));
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

	confess "Unable to locate 'primary' metadata within repomd.xml"
		unless(defined($primarymd_location));

	# download all of the repodata files listed in repomd.xml
	RepoTools::Helper->stdout_message((defined($sync->{'name'}) ? "[$sync->{'name'}] " : "") . 'Downloading repodata', $self->{'options'});
	RepoTools::ListDownloader->new({ 'list' => $repomd_list, 'uri_source' => $uri_source, 'uri_dest' => $uri_dest })->sync();

	# we should have pushed the primary metadata out to disk when we downloaded the repodata
	my $primarymd = $uri_dest->generate($primarymd_location)->retrieve({ 'decompress' => 1 });
	my $primarymd_list = RepoTools::XMLParser->new({ 'mdtype' => 'primary', 'filename' => $primarymd_location, 'document' => $primarymd })->parse();

	# download all of the rpm files listed in the primary.xml variant
	RepoTools::Helper->stdout_message((defined($sync->{'name'}) ? "[$sync->{'name'}] " : "") . 'Downloading RPMs', $self->{'options'});
	RepoTools::ListDownloader->new({ 'list' => $primarymd_list, 'uri_source' => $uri_source, 'uri_dest' => $uri_dest })->sync();

	# write the new repomd.xml at the end, now we've downloaded all the metadata and rpms it references
	RepoTools::Helper->stdout_message((defined($sync->{'name'}) ? "[$sync->{'name'}] " : "") . 'Writing repomd.xml', $self->{'options'});
	RepoTools::Helper->file_write($repomd_file->path(), $repomd_url->retrieve());

	# obtain an up-to-date list of all files in our sync directory and then clear orphan content
	if($self->{'options'}->{'remove'})
	{
		my $filelist = $uri_dest->list();
		RepoTools::Helper->stdout_message((defined($sync->{'name'}) ? "[$sync->{'name'}] " : "") . 'Removing orphan content', $self->{'options'});
		RepoTools::ListRemover->new({ 'list' => [@{$repomd_list},@{$primarymd_list}], 'filelist' => $filelist, 'uri_dest' => $uri_dest })->sync();
	}
}

sub sync_repo_rsync
{
	my ($self, $sync) = (shift, shift);

	RepoTools::Helper->stdout_message((defined($sync->{'name'}) ? "[$sync->{'name'}] " : "") . 'Running rsync', $self->{'options'});

	my $uri_source = $sync->{'source'};
	my $uri_dest = $sync->{'dest'};

	my $param_delete = ($self->{'options'}->{'remove'} ? '--delete-after' : '');
	# the contimeout option is only valid for rsync -> disk, not disk -> disk
	my $param_timeout = ($sync->{'source'}->{'type'} eq 'rsync' ? '--contimeout=60' : '');
	my $param_args = (defined($sync->{'rsync_args'}) ? "$sync->{'rsync_args'} " : '');

	my ($stdout, $stderr, $retval) = capture {
		system("rsync -a --timeout=60 $param_timeout $param_delete $param_args '$uri_source->{'path'}' '$uri_dest->{'path'}'");
	};

	if($retval != 0)
	{
		print STDERR $stderr;
		croak "Error running rsync";
	}
}

1;
