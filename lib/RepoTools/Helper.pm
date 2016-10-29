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

	return if($options->{'silent'});
	print "$message\n" unless($options->{'silent'});
}

1;
