package RepoTools::TermUpdater;

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
	$self->{'silent'}		= $options->{'options'}->{'silent'};

	# if output is to a terminal, default to a prettier prompt with status updates,
	# otherwise we just output the first message we're given and go silent
	$self->{'pretty'} = 1 if(-t STDOUT);

	$|=1;

	$self->message();
	return $self;
}

sub message
{
	my $self = shift;
	my $message = shift;

	return if($self->{'silent'});

	if($self->{'pretty'})
	{
		my $percent = int(($self->{'current'}/$self->{'count'})*100);
		my $actmessage = ($percent == 100 ? $self->{'message'} : (defined($message) ? $message : $self->{'message'}));

		printf("\r\e[K[%3d%%] %s%s", $percent, $actmessage, ($percent == 100 ? "\n" : ""));
	}
	else
	{
		print "$self->{'message'}\n";
		$self->{'silent'} = 1;
	}
}

sub update
{
	my $self = shift;
	my $message = shift || $self->{'message'};

	$self->{'current'}++;
	$self->message($message);
}

1;
