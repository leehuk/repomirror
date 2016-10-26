package RepoTools::ProgressBar;

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
	my $message = shift || $self->{'message'};

	$self->{'current'}++;
	$self->message($message);
}

1;
