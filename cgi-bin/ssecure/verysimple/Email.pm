# ----------------------------------------------------------------------------
# verysimple::Email
# Copyright (c) 2002 Jason M. Hinkle. All rights reserved. This module is
# free software; you may redistribute it and/or modify it under the same
# terms as Perl itself.  For info see: http://www.verysimple.com/scripts/
#
# LEGAL DISCLAIMER:
# This software is provided as-is.  Use it at your own risk.  The
# author takes no responsibility for any damages or losses directly
# or indirectly caused by this software.
#
# version history
# 2.24 update to use correct message id format according to RFC2822
# 2.23 update to deal with null values in cc, bcc, subject...
# ----------------------------------------------------------------------------

package verysimple::Email;
require 5.000;

use MIME::Lite

$VERSION = "2.24";
$ID = "verysimple::Email.pm";

#_____________________________________________________________________________
sub new {
	my $class = shift;
	my %keyValues = @_;
	my %attachedFiles;
	my %attachedStrings;

	# create instance and set defaults
	my $this = {
		Type => 'TEXT',
		TempDir => './',
		attached_files => \%attachedFiles,
		attached_strings => \%attachedStrings,
	};

	# load all the user parameters
	foreach my $key (keys(%keyValues)) {
		$this->{$key} = $keyValues{$key};
	}
	
	bless $this, $class;
	return $this;
}

# read-only properties
sub Version {return shift->{'version'};}
sub Id {return $ID;}
sub Log {return shift->{'log'}}

# read-write properties
sub To {return shift->_GetSetProperty('To',shift);}
sub From {return shift->_GetSetProperty('From',shift);}
sub Subject {return shift->_GetSetProperty('Subject',shift);}
sub Cc {return shift->_GetSetProperty('Cc',shift);}
sub Bcc {return shift->_GetSetProperty('Bcc',shift);}
sub Body {return shift->_GetSetProperty('Body',shift);}
sub Type {return shift->_GetSetProperty('Type',shift);}
sub Method {return shift->_GetSetProperty('Method',shift);}
sub MethodPath {return shift->_GetSetProperty('MethodPath',shift);}
sub TempDir {return shift->_GetSetProperty('TempDir',shift);}
sub Debug {return shift->_GetSetProperty('Debug',shift);}

sub AttachString {
	my $this = shift;
	my $fileContents = shift;
	my $fileName = shift || "attachment.file";
	$this->{'attachedStrings'}{$fileName} = $fileContents;
	return 1;
}

sub AttachFile {
	my $this = shift;
	my $filePath = shift;
	my $fileName = shift || $this->_GetFileNameFromPath($filePath);;
	
	$this->{'attachedFiles'}{$filePath} = $fileName;
	return 1;
}

sub Send {
	my $this = shift;
	print "Send called\n" if $this->Debug;
	
	# keep the Type property backwards compatible, yet consistent
	$this->{'Type'} = "text/html" if $this->{'Type'} eq "HTML";
	
	# TODO: wait until MIME::Lite fixes the realname bug
	# fix up the from email if it doesn't have a real name
	#if ( index($this->{'From'},"\<") < 0 )
	#{
	#	$this->{'From'} = " \"Email, " . $this->{'From'} . "\"" . " <" . $this->{'From'} . "> ";
	#}
	
	$msg = MIME::Lite->new(
		'Message-ID:'	=> '<'. $$ . '@' . ($ENV{'SERVER_NAME'} || "unknown") . '>',
		'X-Remote-Host'	=> $ENV{'REMOTE_HOST'} || "",
		'X-Module-Id'	=> $ID . " " . $VERSION,
		From			=> $this->{'From'},
		To				=> $this->{'To'},
		Cc				=> $this->{'Cc'} || "",
		Bcc				=> $this->{'Bcc'} || "",
		Subject			=> $this->{'Subject'} || "",
		Type			=> $this->{'Type'} || "",
		Data    		=> $this->{'Body'} || "",
	);

	print "MIME::Lite Created\n" if $this->Debug;

	# attach all strings by first saving them in the TempDir
	my $attachedStrings = $this->{'attachedStrings'};
	foreach my $fileName ( keys(%$attachedStrings) ) {
		my $path = $this->TempDir . $fileName;
		print "Saving attachment ($path)\n" if $this->Debug;
		my $content = $this->{'attachedStrings'}{$fileName};
		open (ATTACHMENT,">$path");
		print ATTACHMENT $content;
		close (ATTACHMENT);
		$this->AttachFile($path);
	}
	
	# attach all files that are saved
	my $attachedFiles = $this->{'attachedFiles'};
	foreach my $filePath ( keys(%$attachedFiles) ) {
	 	# parse the filename from the path
	 	my $fileName = $$attachedFiles{$filePath};
		print "Attaching ($filePath) to message\n" if $this->Debug;
		
	 	$msg->attach(
			#Type     	=> "AUTO",   # <- this causes an error on binary types..??
	 		Type		=> "application/octet-stream",	
	 		Path     	=> $filePath,
	 		Filename 	=> $fileName,
	 		Disposition => 'attachment',
	 		Encoding 	=> 'base64',
	 	);
	}

    # see if we want to use sendmail or smtp
    if ($this->{'Method'} eq "sendmail") {
			my $sendmailPath = $this->{'MethodPath'};
			print "Sending via sendmail ($sendmailPath)\n" if $this->Debug;
			# MIME::Lite->send("sendmail", $sendmailPath); <- doesn't seem to always work
			open (SENDMAIL,"|$sendmailPath -t");
			$msg->print(\*SENDMAIL);
			close (SENDMAIL);
	} elsif ($this->{'Method'} eq "smtp") {
			my $smtpServer = $this->{'MethodPath'};
			print "Sending via SMTP ($smtpServer)\n" if $this->Debug;
			MIME::Lite->send("smtp", $smtpServer);
			$msg->send();
	} else {
		die "Unsupported Email Method: " . $this->{'Method'};
	}
    
	# delete any temporary files that we created
	foreach my $fileName ( keys(%$attachedStrings) ) {
		my $path = $this->TempDir . $fileName;
		print "Removing temp file ($path)\n" if $this->Debug;
		unlink($path);
	}

	print "Send finished.\n" if $this->Debug;
	return 1;	
}

sub _SaveFile {
	my $this = shift;
	my $fileName = shift;
	my $fileContents = shift;
	
	my $filePath = $this->{'TempDir'} . $fileName;
	
	open(ATTACH,">$filePath") or die("Error opening $filePath: " . $!);
	binmode (ATTACH);    # <- force binary mode for windows.  test on unix...
	print ATTACH $fileContents;
	close ATTACH;			
}

sub _GetFileNameFromPath {
	my $this = shift;
	my $filePath = shift;
	my ($fileName) = $filePath;
	$fileName =~ s|\\|\/|g;
	return substr($fileName,rindex($fileName,"/",)+1);
}

sub _GetSetProperty {
	my $this = shift;
	my $prop = shift;
	my $val = shift;
	if ( ! defined($val) ) {
		return $this->{$prop};
	} else {
		$this->{$prop} = $val;
		return 1;
	}
}
