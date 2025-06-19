# ----------------------------------------------------------------------------
# verysimple::Session
# Copyright (c) 2001 Jason M. Hinkle. All rights reserved. This module is
# free software; you may redistribute it and/or modify it under the same
# terms as Perl itself.
# For more information see: http://www.verysimple.com/scripts/
#
# LEGAL DISCLAIMER:
# This software is provided as-is.  Use it at your own risk.  The
# author takes no responsibility for any damages or losses directly
# or indirectly caused by this software.
# ----------------------------------------------------------------------------
package verysimple::Session;
require 5.000;
use CGI;
use Data::Dumper;
use MIME::Base64;
use DBI;

$VERSION = "2.00";
$ID = "verysimple::Session.pm";
$SESSION_MAX_KB = 512;
$SESSION_RAISE_ERR = 1;

#_____________________________________________________________________________
sub new {
	my $class = shift;
	my %keyValues = @_;
	my $cgi = new CGI;
	my %params; # holds the parameter objects

	my $this = {
	    cookie_name		=> $keyValues{'CookieName'} || "SessionId",
	    db_table_name	=> "sessions",
	    session_id		=> "",
	    last_modified	=> "",
	    conn_string		=> "",
	    conn_username	=> "",
	    conn_password	=> "",
	    temp_dir		=> $keyValues{'TempDir'} || "./",
	    params			=> \%params,
	    cgi				=> $cgi,
	    timeout			=> 1800, # in seconds
	    expired			=> 0,
	    check_ip		=> 1,
	    isLoaded		=> 0,
	    errors			=> "",
	};
	
	# override any of the defaults if they were specified
	foreach my $keyName (%keyValues) {
		$this->{$keyName} = $keyValues{$keyName};
	}

	bless $this, $class;

	return $this;
}

# read-only properties
#_____________________________________________________________________________
sub Version {return $VERSION;}
sub ID {return $ID;}
sub ErrorLog {return shift->{'errors'};}
sub SessionId {return shift->{'session_id'};}
sub IsLoaded {return shift->{'isLoaded'};}
sub IsExpired {return shift->{'expired'};}

# read/write properties
#_____________________________________________________________________________
sub Timout {return shift->_GetSetProperty('timeout',shift);}
sub CheckIP {return shift->_GetSetProperty('check_ip',shift);}
sub CookieName {return shift->_GetSetProperty('cookie_name',shift);}

#_____________________________________________________________________________
sub Param {
	my $this = shift || die("verysimple::Session->Param is not a static method");
	my $paramName = shift || die("verysimple::Session->Param: parameter name argument required");
	my $newVal = shift;
	if (defined($newVal)) {
		$this->{'params'}{$paramName} = $newVal;
		return 1;
	} else {
		if (defined($this->{'params'}{$paramName})) {
			return $this->{'params'}{$paramName}
		} else {
			return "";
		}
	}
}

#_____________________________________________________________________________
sub GetSessionFile {
	my $this = shift || die("verysimple::Session->GetSessionFile is not a static method");
	return $this->{"temp_dir"} . ".session-" . $this->{"session_id"};
}

#_____________________________________________________________________________
sub GetDateTime {
	my @dateArray = localtime(time);
	$dateArray[5] += 1900; # year
	$dateArray[4] += 1;  # month
	$dateArray[4] = "0" . $dateArray[4] unless (length($dateArray[4]) > 1); # month
	$dateArray[3] = "0" . $dateArray[3] unless (length($dateArray[3]) > 1); # day
	$dateArray[1] = "0" . $dateArray[1] unless (length($dateArray[1]) > 1); # min
	$dateArray[0] = "0" . $dateArray[0] unless (length($dateArray[0]) > 1); # sec
	return ($dateArray[5] . $dateArray[4] . $dateArray[3] . $dateArray[1] . $dateArray[0]);
}

#_____________________________________________________________________________
sub GetNewSessionId {
	# generates an id that is unique for this visitor:
	my $this = shift || die("verysimple::Session->GetNewSessionId is not a static method");
	# return $ENV{'REMOTE_HOST'} . "-" . $this->GetDateTime . "-" . $$;
	return $this->GetDateTime . "-" . $$;
}

#_____________________________________________________________________________
sub Load {
	my $this = shift || die("verysimple::Session->Load is not a static method");

	# set the isLoaded bit so we can check if load has already been called
	$this->{"isLoaded"} = 1;
	
	# grab the session id, which should be stored as a cookie
	$this->{'session_id'} = $this->{'cgi'}->cookie($this->CookieName) || "";
	
	# if the session cookie is not there, then we need to generate an
	# id and create the session cookie
	if (!$this->{'session_id'}) {
		# this is a new session, create a new session
		$newId = $this->GetNewSessionId;
		$cookieName = $this->CookieName;
		$this->{'session_id'} = $newId;
		# my $cookie = $this->{'cgi'}->cookie($COOKIE_NAME,$this->{'session_id'});
		my $cookie = $this->{'cgi'}->cookie(
			-name=>$cookieName,
			-value=>$newId,
			-expires=>'+1y',
		);
		print "Set-Cookie: " . $cookie . "\n";
	}

	if ($this->{'conn_string'}) {
		# load session info from the database
		my $dbh = $this->_GetDbh;
		$dbh->{LongReadLen} = $SESSION_MAX_KB * 1024;
		# select the existing session record
		my $sth = $dbh->prepare("select Session from " . $this->{'db_table_name'} . " where Id=?");
		$sth->bind_param(1,$this->SessionId);

		$sth->execute() || die $DBI::errstr;
		if (my $encoded = $sth->fetchrow_array) {
			# sessions exits, eval the saved session to reload all the dumped vars
			eval( decode_base64($encoded) );
		} else {
			# calling save will create a new record
			$this->Save;
		}

		$sth->finish;
		$dbh->disconnect;
	} else {
		# load session infro from a file
		my $fileName = $this->GetSessionFile;
		if (open (INPUTFILE, "$fileName")) {
			# the session file exists
			my @tempFileArray = <INPUTFILE>;
			close INPUTFILE;
			# decrypt and repopulate the params hash from the session file
			eval( decode_base64(join('',@tempFileArray)) );
		} else {
			# the session is here, but the file is gone.  this could mean that
			# the file was deleted (session was abandoned) or this is a new
			# session altogether.  either way we don't have any info about them,
			# so we'll create a new session file
			$this->Save;
		}
	}
	
	# now we've loaded the session, we need to see if
	# it has expired or the IP has changed.  Timout of 0 means never expire
	if (
	($this->Timout && ($this->GetDateTime - $this->Param("LastModified") > $this->Timout))
	|| ($this->CheckIP && $this->Param("RemoteHost") ne $ENV{'REMOTE_HOST'})
	) {
		# if the session is expired, then automatically abandon it.  we don't
		# need to save the session in this case.  it will get if they change a
		# setting or call Load again.
		$this->Abandon;
		$this->{'expired'} = 1;
	} else {
		# save the session again - so the LastModified date will be updated
		$this->Save;
	}

}

#_____________________________________________________________________________
sub Save {
	my $this = shift || die("verysimple::Session->Save is not a static method");
	
	$this->{"isLoaded"} || die("verysimple::Session->Save: you must call Load method before session can be saved.");
	
	# set a few properties if necessary
	$this->Param("SessionCreated",$this->GetDateTime) unless ($this->Param("SessionCreated")); # set created time if doesn't exist
	$this->Param("LastModified",$this->GetDateTime); # update modified time
	$this->Param("RemoteHost",$ENV{'REMOTE_HOST'}); # update modified time

	if ($this->{'conn_string'}) {
		# encrypt and save the dump to the database
		my $dbh = $this->_GetDbh;
		# do the update and see if any records were effected
		if ($dbh->do("update " . $this->{'db_table_name'} . " set Session=?, Modified = sysdate() where Id=?",undef, (encode_base64($this->GetDump),$this->SessionId) ) < 1) {
			# 0 records updated means session didn't exist, so do an insert
			$dbh->do("insert into " . $this->{'db_table_name'} . " (Id,Session,Modified) values (?,?,sysdate())",undef, ($this->SessionId,encode_base64($this->GetDump) )) || die $DBI::errstr;
		}
		$dbh->disconnect;
	} else {
		# encrypt and print the dump to the file
		my $fileName = $this->GetSessionFile;
		open (OUTPUTFILE, ">$fileName") || die("verysimple::Session->Save: couldn't open datafile '$fileName' for writing");
		print OUTPUTFILE encode_base64($this->GetDump);
		close OUTPUTFILE;
	}
	return 1;
}

#_____________________________________________________________________________
sub GetDump {
	my $this = shift || die("verysimple::Session->GetDump is not a static method");
	my $parameters = $this->{"params"};
	# DEBUGGING FOR SESSION
	# $ENV{"SESSION_DUMP"} = "<pre>" . Data::Dumper->Dump([$parameters],[qw(this->{'params'})]) . "</pre>";
	return Data::Dumper->Dump([$parameters],[qw(this->{'params'})]);
}

#_____________________________________________________________________________
sub Abandon {
	my $this = shift || die("verysimple::Session->Abandon is not a static method");

	$this->{"isLoaded"} || die("verysimple::Session->Abandon: you must call Load method before session can be removed.");

	# clear all saved settings
	$this->{'params'} = {};

	if ($this->{'conn_string'}) {
		# delete from the database
		my $dbh = $this->_GetDbh;
		$dbh->do("delete from " . $this->{'db_table_name'} . " where Id=?",undef,$this->SessionId) || die $DBI::errstr;
		$dbh->disconnect;
	} else {
		# delete the session file
		my $fileName = $this->GetSessionFile;
		unlink($fileName);
	}
	return 1;
}

#_____________________________________________________________________________
sub Authorize {
	my $this = shift || die("verysimple::Session->Authorize is not a static method");
	$this->Param("IsAuthorized","1");
	$this->Save;
	return 1;
}

#_____________________________________________________________________________
sub IsAuthorized {
	my $this = shift || die("verysimple::Session->IsAuthorized is not a static method");
	return $this->Param("IsAuthorized");
}

#_____________________________________________________________________________
sub Unauthorize {
	my $this = shift || die("verysimple::Session->UnAuthorize is not a static method");
	$this->Param("IsAuthorized","0");
	$this->Save;
	return 1;
}

#_____________________________________________________________________________
sub _GetDbh {
	my $this = shift || die("verysimple::Session->_GetDbh: Not a Static Method");
	my $dbh = DBI->connect(
		$this->{'conn_string'},
		$this->{'conn_username'},
		$this->{'conn_password'},
		{RaiseError=>,PrintError=>$SESSION_RAISE_ERR}
	) or die "verysimple::Session->_GetDbh: couldn't connect to datasource: " . $DBI::errstr;
	return $dbh;
}

#_____________________________________________________________________________
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
1; # for require


__END__

=head1 NAME

verysimple::Session - interface for preserving web session state
to file or database

=head1 SYNOPSIS

	use verysimple::Session;
	
	# create the session, saving to a file
	my $session = new verysimple::Session(TempDir=>'c:/temp/');

	# -or- create the session saving to a database connection 
	# mhaving a table called "sessions" with three fields:
	# Id : varchar(25)
	# Modified : datetime
	# Session : clob (or large text field)
	my $session = new verysimple::Session(
		conn_string =>'DBI:mysql:vs_session:localhost',
		conn_username=>'db_username',
		conn_password=>'db_password'
	);
	
	# set the timeout in seconds (default is 1800)  0 = no timeout
	my $session->Timout(1200);

	# load the session file (will die if encounters error
	$session->Load;
	
	# read a value
	my $userId = $session->Param("UserId");
	
	# save a value
	$session->Param("UserId", 1234);

	# save an object
	$session->Param("cgi", \$cgi);

	# save a hash
	$session->Param("myhash", \%myhash);

	# retrieve a hash
	my $temp = $session->Param("myhash");
	my %myhash = %$temp;

	# must call save after updating session values to update the physical file
	$session->Save
	
	# sets an authorization bit (assumes you provide $login_successful variable)
	if ($login_successful) {
		$session->Authorize;
	}
	
	# check if the user is authorized
	if ($session->IsAuthorized) {# do some stuff}
	
	# reset the authorization bit	
	$session->UnAuthorize;
	
	# don't forget to save the session
	$session->Save
	
	# kill the session and remove the physical file
	$session->Abandon


=head1 DESCRIPTION

A simple object-oriented interface for preserving state in a cgi application.
This module sets an ID cookie on the visitors browser which links back to a
physical file on the server.  By saving information in this file, you can
preserve the users session state.

This module allows you to save simple scalar values, arrays, hashes
and even objects.  Session information is preserved to disk using the
Data::Dumper module.

The session data will remain until you call the Abandon method, the
session times out, or the visitor's IP address changes.  The Id cookie
will remain on the visitors machine for a duration of 1 year.

=head1 SECURITY CONSIDERATIONS

Because you may be inclined to store sensitive information in the session,
it is important that you protect the directory or database
containing the session information.  The module uses a basic encoding
when storing the session data so that it is not easily readable, however
this is not adequate for high-security requirements.  You should take
the appropriate measures to ensure that the directory or database is
secure from unathorized access.

This module also provides considerations to prevent a hacker from hijacking
an authenticated SessionId, however by using SSL on your application will
give you the greatest level of protection.

=head1 OBJECT MODEL REFERENCE

=head2 Properties

	CheckIP([NewVal]) # sets or returns whether IP security check is enabled. default = 1
	CookieName([NewVal]) # sets or returns name for cookie. default = "SessionId"
	ID() # returns module id
	IsExpired() # returns 1 or 0 if session is expired
	Param(Name,[NewVal]) # sets or returns a session parameter value
	SessionId() # returns session id
	Timout([NewVal]) # sets or returns session timeout in seconds.  default = 1800
	Version() # returns module version

=head2 Methods

	Abandon()  # clears session & removes file
	Authorize() # sets authorization bit = true
	GetSessionFile() # returns filepath of current session file
	GetDateTime() # returns date/time in YYYYMMDDmmss format
	GetDump() # returns data dump of session
	GetNewSessionId() # generates new session id
	IsAuthorized() # returns authorization bit
	Load() # loads session from disk
	Save() # saves session to disk
	UnAuthorize() # sets authorization bit = false

=head1 VERSION HISTORY

    2.00: Added support for database in addition to file persistance
    1.01: Param returns empty string instead of undefined if value doesn't exist
    1.00: Original Release

=head1 KNOWN ISSUES & LIMITATIONS

sessions that are not explicitly abandoned will remain on the disk.  It is
necessary to remove files that have not been updated within a certain time period
on occasion.

When first creating a new session, this module needs to write a cookie to the
user's browser.  For this reason, you should call the Load method before
writing any HTTP content headers to the browser.  If you notice a Set-Cookie
content header being written to the browser, this is the problem.

=head1 AUTHOR

Jason M. Hinkle

=head1 COPYRIGHT

Copyright (c) 2003 Jason M. Hinkle.  All rights reserved.
This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut