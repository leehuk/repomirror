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

1;
