diff --git a/repomirror.pl b/repomirror.pl
old mode 100644
new mode 100755
index c3cca15..06cb423
--- a/repomirror.pl
+++ b/repomirror.pl
@@ -1,6 +1,160 @@
 #!/usr/bin/perl -w
+#
+# repomirror.pl
+# 	Tool for mirroring RPM based repositories in a reasonably intelligent manner.
+#
+# 	Copyright (C) 2016 Lee H <lee -at- leeh -dot- uk>
+#
+#	Released under the MIT License
 
-package RepoMirrorProgressbar;
+package RepoMirror::XMLParser;
+
+use strict;
+use Carp;
+use Data::Dumper;
+use Error qw(:try);
+use IO::String;
+use XML::Tiny qw(parsefile);
+
+sub new
+{
+	my $name = shift;
+	my $options = shift || {};
+
+	confess "Missing option: mdtype:$options->{'mdtype'} filename:$options->{'filename'} or document"
+		unless(defined($options->{'mdtype'}) && defined($options->{'filename'}) && defined($options->{'document'}));
+	confess "Invalid 'mdtype' option"
+		unless($options->{'mdtype'} eq 'repomd' || $options->{'mdtype'} eq 'primary');
+
+	my $self = bless({}, $name);
+	$self->{'document'} = $options->{'document'};
+	$self->{'filename'} = $options->{'filename'};
+	$self->{'mdtype'} = $options->{'mdtype'};
+
+	return $self;
+}
+
+sub parse
+{
+	my $self = shift;
+	my $filename = shift;
+	my $xmlcontent = shift;
+
+	my $xml;
+	try {
+		$xml = parsefile(IO::String->new($self->{'document'}));
+	}
+	catch Error with {
+		my $error = shift;
+		chomp($error->{'-text'});
+
+		confess "XML Parse Error: $filename $error->{'-text'}";
+	};
+
+	confess "XML Error: $filename Root structure is not an array"
+		unless(ref($xml) eq "ARRAY");
+	confess "XML Error: $filename Duplicate root elements"
+		unless(scalar(@{$xml}) == 1);
+
+	# nest down into our first element
+	$xml = @{$xml}[0];
+
+	confess "XML Error: $self->{'filename'} Root element does not have a name"
+		unless(defined($xml->{'name'}));
+	confess "XML Error: $self->{'filename'} Root element is not 'repomd': $xml->{'name'}"
+		if($self->{'mdtype'} eq 'repomd' && $xml->{'name'} ne 'repomd');
+	confess "XML Error: $self->{'filename'} Root element is not 'metadata': $xml->{'name'}"
+		if($self->{'mdtype'} eq 'primary' && $xml->{'name'} ne 'metadata');
+	confess "XML Error: $self->{'filename'} Root element does not have nested data"
+		unless(ref($xml->{'content'}) eq 'ARRAY');
+
+	return $self->parse_content_root($xml->{'content'});
+}
+
+sub parse_content_root
+{
+	my $self = shift;
+	my $xml = shift;
+
+	my $filelist = [];
+
+	foreach my $element (@{$xml})
+	{
+		confess "XML Error: $self->{'filename'} Data block has no name"
+			unless(defined($element->{'name'}));
+
+		# skip elements that arent relevant
+		if($self->{'mdtype'} eq 'repomd')
+		{
+			next unless($element->{'name'} eq 'data');
+		}
+		elsif($self->{'mdtype'} eq 'primary')
+		{
+			next unless($element->{'name'} eq 'package');
+			next unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'type'}) && $element->{'attrib'}->{'type'} eq 'rpm');
+		}
+
+		push(@{$filelist}, $self->parse_content_object($element->{'content'}, $element->{'attrib'}->{'type'}));
+	}
+
+	return $filelist;
+}
+
+sub parse_content_object
+{
+	my $self = shift;
+	my $xml = shift;
+	my $type = shift;
+
+	my $contentobj = {};
+	$contentobj->{'type'}		= $type;
+
+	foreach my $element (@{$xml})
+	{
+		if($element->{'name'} eq 'checksum')
+		{
+			throw Error::Simple("Unable to locate checksum type for data block '$type'")
+				unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'type'}));
+			throw Error::Simple("Unable to locate checksum value for data block '$type'")
+				unless(defined($element->{'content'}) && ref($element->{'content'}) eq 'ARRAY' && scalar(@{$element->{'content'}}) == 1 && defined($element->{'content'}[0]->{'content'}));
+			throw Error::Simple("Unknown checksum type '$element->{'attrib'}->{'type'}' for data block '$type'")
+				unless($element->{'attrib'}->{'type'} eq 'sha1' || $element->{'attrib'}->{'type'} eq 'sha256');
+
+			push(@{$contentobj->{'checksum'}}, {
+				'type'		=> $element->{'attrib'}->{'type'},
+				'value'		=> $element->{'content'}[0]->{'content'},
+			});
+		}
+		elsif($element->{'name'} eq 'location')
+		{
+			throw Error::Simple("Unable to locate location href for data block '$type'")
+				unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'href'}));
+
+			$contentobj->{'location'} = $element->{'attrib'}->{'href'};
+		}
+		elsif($element->{'name'} eq 'size')
+		{
+			if($self->{'mdtype'} eq 'repomd')
+			{
+				throw Error::Simple("Unable to locate size value for data block '$type'")
+					unless(defined($element->{'content'}) && ref($element->{'content'}) eq 'ARRAY' && scalar(@{$element->{'content'}}) == 1 && defined($element->{'content'}[0]->{'content'}));
+
+				$contentobj->{'size'} = $element->{'content'}[0]->{'content'};
+			}
+			elsif($self->{'mdtype'} eq 'primary')
+			{
+				throw Error::Simple("Unable to locate size value for data block '$type'")
+					unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'package'}));
+
+				$contentobj->{'size'} = $element->{'attrib'}->{'package'};
+			}
+		}
+	}
+
+	return $contentobj;
+}
+
+package RepoMirror::ProgressBar;
 
 use strict;
 use Carp;
@@ -10,7 +164,7 @@ sub new
 	my $name = shift;
 	my $options = shift || {};
 
-	my $self = {};
+	my $self = bless({}, $name);
 
 	confess("Missing 'message' option")
 		unless(defined($options->{'message'}));
@@ -24,7 +178,6 @@ sub new
 
 	$|=1;
 
-	bless($self, $name);
 	$self->message();
 	return $self;
 }
@@ -65,18 +218,18 @@ use File::Basename qw(dirname);
 use File::Path qw(make_path);
 use Getopt::Std qw(getopts);
 use HTTP::Tiny;
-use IO::String;
-use XML::Tiny qw(parsefile);
 
 my $mirror_base_path;
 my $mirror_base_url;
 
+my $option_force = 0;
 my $option_silent = 0;
 
 sub mirror_usage
 {
-	print "Usage: $0 [-hrs] -d <directory> -u <url>\n";
+	print "Usage: $0 [-fhrs] -d <directory> -u <url>\n";
 	print "     * -d: Directory to mirror to (required).\n";
+	print "       -f: Force repodata/rpm sync when up to date.\n";
 	print "       -h: Show this help.\n";
 	print "       -r: Remove local files that are no longer on the mirror.\n";
 	print "       -s: Be silent other than for errors.\n";
@@ -211,172 +364,8 @@ sub fileinfo_sha256
 	return sha256_hex(mirror_get_path($path));
 }
 
-sub mirror_parse_repomd
-{
-	my $xmlcontent = shift;
-
-	my $filelist = [];
-	try {
-		my $repomdxml = parsefile(IO::String->new($xmlcontent));
-
-		throw Error::Simple("Invalid XML: Root structure is not an array")
-			unless(ref($repomdxml) eq "ARRAY");
-		throw Error::Simple("Invalid XML: Duplicate root elements")
-			unless(scalar(@{$repomdxml}) == 1);
-
-		my $repomd = @{$repomdxml}[0];
-
-		throw Error::Simple("Invalid XML: Root element is not repomd")
-			unless(defined($repomd->{'name'}) && $repomd->{'name'} eq 'repomd');
-		throw Error::Simple("Invalid XML: repomd element does not have nested data")
-			unless(ref($repomd->{'content'}) eq 'ARRAY');
-
-		my $content = $repomd->{'content'};
-		foreach my $element (@{$content})
-		{
-			# skip non-data elements
-			next unless(defined($element->{'name'}) && $element->{'name'} eq 'data');
-
-			throw Error::Simple("Invalid XML: data block has no type")
-				unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'type'}));
-
-			my $type = $element->{'attrib'}->{'type'};
-
-			my $contentobj = {
-				'type'		=> $type,
-			};
-
-			foreach my $celement (@{$element->{'content'}})
-			{
-				if($celement->{'name'} eq 'checksum')
-				{
-					throw Error::Simple("Unable to locate checksum type for data block '$type'")
-						unless(defined($celement->{'attrib'}) && defined($celement->{'attrib'}->{'type'}));
-					throw Error::Simple("Unable to locate checksum value for data block '$type'")
-						unless(defined($celement->{'content'}) && ref($celement->{'content'}) eq 'ARRAY' && scalar(@{$celement->{'content'}}) == 1 && defined($celement->{'content'}[0]->{'content'}));
-					throw Error::Simple("Unknown checksum type '$celement->{'attrib'}->{'type'}' for data block '$type'")
-						unless($celement->{'attrib'}->{'type'} eq 'sha1' || $celement->{'attrib'}->{'type'} eq 'sha256');
-
-					push(@{$contentobj->{'checksum'}}, {
-						'type'		=> $celement->{'attrib'}->{'type'},
-						'value'		=> $celement->{'content'}[0]->{'content'},
-					});
-				}
-				elsif($celement->{'name'} eq 'location')
-				{
-					throw Error::Simple("Unable to locate location href for data block '$type'")
-						unless(defined($celement->{'attrib'}) && defined($celement->{'attrib'}->{'href'}));
-
-					$contentobj->{'location'} = $celement->{'attrib'}->{'href'};
-				}
-				elsif($celement->{'name'} eq 'size')
-				{
-					throw Error::Simple("Unable to locate size value for data block '$type'")
-						unless(defined($celement->{'content'}) && ref($celement->{'content'}) eq 'ARRAY' && scalar(@{$celement->{'content'}}) == 1 && defined($celement->{'content'}[0]->{'content'}));
-
-					$contentobj->{'size'} = $celement->{'content'}[0]->{'content'};
-				}
-			}
-
-			push(@{$filelist}, $contentobj);
-		}
-	}
-	catch Error with {
-		my $error = shift;
-
-		chomp($error->{'-text'});
-
-		print STDERR "Error: Unable to parse repomd.xml: $error->{'-text'}\n";
-		exit(1);
-	};
-
-	return $filelist;
-}
-
-sub mirror_parse_primarymd
-{
-	my $xmlcontent = shift;
-
-	my $filelist = [];
-	try {
-		my $primarymdxml = parsefile(IO::String->new($xmlcontent));
-
-		throw Error::Simple("Invalid XML: Root structure is not an array")
-			unless(ref($primarymdxml) eq "ARRAY");
-		throw Error::Simple("Invalid XML: Duplicate root elements")
-			unless(scalar(@{$primarymdxml}) == 1);
-
-		my $primarymd = @{$primarymdxml}[0];
-
-		throw Error::Simple("Invalid XML: Root element is not metadata")
-			unless(defined($primarymd->{'name'}) && $primarymd->{'name'} eq 'metadata');
-		throw Error::Simple("Invalid XML: primarymd element does not have nested data")
-			unless(ref($primarymd->{'content'}) eq 'ARRAY');
-
-		my $content = $primarymd->{'content'};
-		foreach my $element (@{$content})
-		{
-			# skip non-data elements
-			next unless(defined($element->{'name'}) && $element->{'name'} eq 'package');
-
-			throw Error::Simple("Invalid XML: data block has no type")
-				unless(defined($element->{'attrib'}) && defined($element->{'attrib'}->{'type'}));
-
-			# skip non-rpm elements
-			next unless($element->{'attrib'}->{'type'} eq 'rpm');
-
-			my $contentobj = {};
-
-			my $type;
-			foreach my $celement (@{$element->{'content'}})
-			{
-				if($celement->{'name'} eq 'checksum')
-				{
-					throw Error::Simple("Unable to locate checksum type for data block '$type'")
-						unless(defined($celement->{'attrib'}) && defined($celement->{'attrib'}->{'type'}));
-					throw Error::Simple("Unable to locate checksum value for data block '$type'")
-						unless(defined($celement->{'content'}) && ref($celement->{'content'}) eq 'ARRAY' && scalar(@{$celement->{'content'}}) == 1 && defined($celement->{'content'}[0]->{'content'}));
-					throw Error::Simple("Unknown checksum type '$celement->{'attrib'}->{'type'}' for data block '$type'")
-						unless($celement->{'attrib'}->{'type'} eq 'sha1' || $celement->{'attrib'}->{'type'} eq 'sha256');
-
-					push(@{$contentobj->{'checksum'}}, {
-						'type'		=> $celement->{'attrib'}->{'type'},
-						'value'		=> $celement->{'content'}[0]->{'content'},
-					});
-				}
-				elsif($celement->{'name'} eq 'location')
-				{
-					throw Error::Simple("Unable to locate location href for data block '$type'")
-						unless(defined($celement->{'attrib'}) && defined($celement->{'attrib'}->{'href'}));
-
-					$contentobj->{'location'} = $celement->{'attrib'}->{'href'};
-				}
-				elsif($celement->{'name'} eq 'size')
-				{
-					throw Error::Simple("Unable to locate size value for data block '$type'")
-						unless(defined($celement->{'attrib'}) && defined($celement->{'attrib'}->{'package'}));
-
-					$contentobj->{'size'} = $celement->{'attrib'}->{'package'};
-				}
-			}
-
-			push(@{$filelist}, $contentobj);
-		}
-	}
-	catch Error with {
-		my $error = shift;
-
-		chomp($error->{'-text'});
-
-		print STDERR "Error: Unable to parse primary.xml: $error->{'-text'}\n";
-		exit(1);
-	};
-
-	return $filelist;
-}
-
 my $options = {};
-getopts('d:hsu:v', $options);
+getopts('d:fhsu:v', $options);
 
 if(defined($options->{'h'}) || !defined($options->{'u'}) || !defined($options->{'d'}))
 {
@@ -390,6 +379,7 @@ if(abs_path($options->{'d'}) eq '/')
 	exit(1);
 }
 
+$option_force = 1 if(defined($options->{'f'}));
 $option_silent = 1 if(defined($options->{'s'}));
 
 # ensure our main folder exists
@@ -402,14 +392,15 @@ $mirror_base_url = $options->{'u'};
 my $repomd_path = mirror_gen_path('repodata/repomd.xml');
 my $repomd_url = mirror_gen_url('repodata/repomd.xml');
 
-my $pb = RepoMirrorProgressbar->new({ 'message' => 'Downloading repomd.xml', 'count' => 1, 'silent' => $option_silent });
+my $pb = RepoMirror::ProgressBar->new({ 'message' => 'Downloading repomd.xml', 'count' => 1, 'silent' => $option_silent });
 my $repomd = mirror_get_url($repomd_url);
 $pb->update();
 
-my $rd_list = mirror_parse_repomd($repomd);
+my $repomd_parser = RepoMirror::XMLParser->new({ 'mdtype' => 'repomd', 'filename' => 'repomd.xml', 'document' => $repomd });
+my $repomd_list = $repomd_parser->parse();
 
 # if our repomd.xml matches, the repo is fully synced
-if(-f $repomd_path && 0)
+if(-f $repomd_path && !$option_force)
 {
 	exit(0) if(mirror_compare($repomd_path, {
 			'location'		=> 'repodata/repomd.xml',
@@ -423,7 +414,7 @@ if(-f $repomd_path && 0)
 
 # before we continue, double check we have a 'primary' metadata object
 my $primarymd_location;
-foreach my $rd_entry (@{$rd_list})
+foreach my $rd_entry (@{$repomd_list})
 {
 	if($rd_entry->{'type'} eq 'primary')
 	{
@@ -435,8 +426,8 @@ foreach my $rd_entry (@{$rd_list})
 throw Error::Simple("Unable to locate 'primary' metadata within repomd.xml")
 	unless(defined($primarymd_location));
 
-$pb = RepoMirrorProgressbar->new({ 'message' => 'Downloading repodata', 'count' => scalar(@{$rd_list}), 'silent' => $option_silent });
-foreach my $rd_entry (@{$rd_list})
+$pb = RepoMirror::ProgressBar->new({ 'message' => 'Downloading repodata', 'count' => scalar(@{$repomd_list}), 'silent' => $option_silent });
+foreach my $rd_entry (@{$repomd_list})
 {
 	$pb->message("Downloading $rd_entry->{'location'}");
 
@@ -463,12 +454,14 @@ foreach my $rd_entry (@{$rd_list})
 my $primarymd_path = mirror_gen_path($primarymd_location);
 my $primarymd = mirror_get_path($primarymd_path, 1);
 
-my $rpm_list = mirror_parse_primarymd($primarymd);
+my $primarymd_parser = RepoMirror::XMLParser->new({ 'mdtype' => 'primary', 'filename' => $primarymd_location, 'document' => $primarymd });
+my $primarymd_list = $primarymd_parser->parse();
 # we're done with the metadata and its fairly expensive to hold in memory, so wipe it out
+$primarymd_parser = undef;
 $primarymd = undef;
 
-$pb = RepoMirrorProgressbar->new({ 'message' => 'Downloading RPMs', 'count' => scalar(@{$rpm_list}), 'silent' => $option_silent });
-foreach my $rpm_entry (@{$rpm_list})
+$pb = RepoMirror::ProgressBar->new({ 'message' => 'Downloading RPMs', 'count' => scalar(@{$primarymd_list}), 'silent' => $option_silent });
+foreach my $rpm_entry (@{$primarymd_list})
 {
 	$pb->message("Downloading $rpm_entry->{'location'}");
 
@@ -494,7 +487,7 @@ foreach my $rpm_entry (@{$rpm_list})
 }
 
 # write the new repomd.xml at the end, now we've downloaded all the metadata and rpms it references
-$pb = RepoMirrorProgressbar->new({ 'message' => 'Writing repomd.xml', 'count' => 1, 'silent' => $option_silent });
+$pb = RepoMirror::ProgressBar->new({ 'message' => 'Writing repomd.xml', 'count' => 1, 'silent' => $option_silent });
 open(my $file, '>', $repomd_path) or throw Error::Simple("Unable to open file for writing: $repomd_path");
 print $file $repomd;
 close($file);
