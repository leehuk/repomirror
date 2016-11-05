# RepoTools::Helper
# 	Module containing various helper functions
#
# Copyright (C) 2016 Lee H <lee@leeh.co.uk>
# Released under the BSD 2-Clause License
package RepoTools::Helper;

use strict;
use Carp;

sub file_write
{
	my ($name, $path, $contents) = (shift, shift, shift);

	open(my $file, '>', $path) or confess "Unable to open file for writing: $path";
	print $file $contents;
	close($file);
}

sub stdout_message
{
	my ($name, $message, $options) = (shift, shift, shift);

	return if($options->{'quiet'});
	print "$message\n";
}

1;
