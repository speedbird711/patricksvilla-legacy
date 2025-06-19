# ----------------------------------------------------------------------------
# verysimple::Util
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
package verysimple::Util;
require 5.000;
use CGI;

$VERSION = "1.003";
$ID = "verysimple::Util.pm";

#_____________________________________________________________________________
sub new {
	my $class = shift;
	my %keyValues = @_;
	my $cgi = new CGI;

	my $this = {
	    cgi			=> $cgi,
	    url			=> $ENV{'SCRIPT_NAME'},
	    TemplateFile=> $keyValues{'TemplateFile'} || '',
	    color1		=> ($keyValues{'color1'} || "#DDDDDD"),
	    color2		=> ($keyValues{'color2'} || "#BBBBBB"),
	    color3		=> ($keyValues{'color3'} || "#666666"),
	    color4		=> ($keyValues{'color4'} || "#000000"),
	};
	
	bless $this, $class;
	return $this;
}

# read-only properties
sub Version {return $VERSION;}
sub ID {return $ID;}
sub ErrorLog {return shift->{'errors'};}
sub SessionId {return shift->{'session_id'};}

# read/write properties
sub TemplateFile {return shift->_GetSetProperty('TemplateFile',shift);}
sub Color1 {return shift->_GetSetProperty('color1',shift);}
sub Color2 {return shift->_GetSetProperty('color2',shift);}
sub Color3 {return shift->_GetSetProperty('color3',shift);}
sub Color4 {return shift->_GetSetProperty('color4',shift);}

# public methods:

sub LoginGUI {
	my $this = shift;
	my $extraCode = shift || "";
	my $gui = "<!-- verysimple.Util.LoginGUI -->\n";
	$gui .= "<form action='" . $this->{'url'} . "' name='_CONFIG' id='_CONFIG' method='post'>\n";
	$gui .= "<table class='LoginGuiTable'>\n";
	$gui .= "<tr class='LoginGuiRow'><td class='LoginGuiLabelCell'>Username</td><td class='LoginGuiFieldCell'>" . $this->{'cgi'}->textfield(-name=>'Username') . "</td></tr>\n";
	$gui .= "<tr class='LoginGuiRow'><td class='LoginGuiLabelCell'>Password</td><td class='LoginGuiFieldCell'>" . $this->{'cgi'}->password_field(-name=>'Userpass') . "</td></tr>\n";
	$gui .= "</table>\n";
	$gui .= "<br>\n";
	$gui .= "<input class='BUTTON' type='submit' value='Login'>\n";
	$gui .= "<input class='BUTTON' type='reset' value='Reset'>\n";
	$gui .= $extraCode;
	$gui .= $this->{'cgi'}->endform . "\n";
}

sub RedirectJS {
	my $this = shift;
	my $url = shift || $this->{'url'};
	my $gui .= "\n\n<script>\n";
	$gui .= "self.location='$url';\n";
	$gui .= "</script>\n";
	$gui .= "<a href='$url'>One moment please...</a>\n";
	return $gui;
}
sub AlertJS {
	my $this = shift;
	my $message = shift || "";
	my $gui .= "\n\n<script>\n";
	$gui .= "alert('$message');\n";
	$gui .= "</script>\n";
	return $gui;
}

sub BackButtonJS {
	my $this = shift;
	my $message = shift || "Back...";
	my $numPages = shift || 1;
	my $gui .= "\n<form>\n";
	$gui .= "<a href='' onclick=\"self.history.go(-$numPages);return false;\">$message</a>\n";
	$gui .= "</form>\n";
	return $gui;
}

sub SysInfo {
	my $this = shift;
	my $color1 = $this->Color1;
	my $color3 = $this->Color3;
	my $info = "<!-- verysimple.Util.SysInfo -->\n";
	$info .= "<table>\n";
	$info .= "<tr bgcolor='$color3'><td>Setting</td><td>Value</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>ENV{'OS'}</td><td>" . $ENV{'OS'} . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>ENV{'SERVER_SOFTWARE'}</td><td>" . $ENV{'SERVER_SOFTWARE'} . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>ENV{'SERVER_ADMIN'}</td><td>" . $ENV{'SERVER_ADMIN'} . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>ENV{'CWD'}</td><td>" . $ENV{'CWD'} . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>ENV{'CONFIG_FILE'}</td><td>" . $ENV{'CONFIG_FILE'} . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>CGI->url</td><td>" . $this->{'cgi'}->url . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>verysimple::Config version</td><td>" . $verysimple::Config::VERSION . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>verysimple::DB version</td><td>" . $verysimple::DB::VERSION . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>verysimple::DBGrid version</td><td>" . $verysimple::DBGrid::VERSION . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>verysimple::Email version</td><td>" . $verysimple::Email::VERSION . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>verysimple::Session version</td><td>" . $verysimple::Session::VERSION . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>verysimple::Util version</td><td>" . $verysimple::Util::VERSION . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>CGI version</td><td>" . $CGI::VERSION . "</td></tr>\n";
	$info .= "<tr bgcolor='$color1'><td>MIME::Lite version</td><td>" . $MIME::Lite::VERSION . "</td></tr>\n";
	$info .= "</table>\n";
	return $info;
}

sub PrintTemplateFile {
	my $this = shift;
	my $templateFile = $this->TemplateFile;
	my $err;
	my $template;
	open(OUT,$templateFile) || ($template = "Error opening template file '$templateFile'.<p>\$ENV{\"PAGE_CONTENT\"}");
	if (!$template) {
		$template = join('',<OUT>);
		close OUT;
	}
	$this->PrintTemplate($template);
}

sub PrintTemplate {
	my $this = shift;
	my $template = shift || "\$ENV{\"PAGE_CONTENT\"}";
	$template =~ s/\$ENV\{\"(\w+)\"\}/$ENV{$1}/g;
	print $this->{'cgi'}->header;
	print $template;
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
1; # for require


__END__

=head1 NAME

verysimple::Util - interface for generic HTML utilities

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OBJECT MODEL REFERENCE

=head1 VERSION HISTORY

    1.003: Use ENV{'SCRIPT_NAME'} instead of $cgi->url to obtain URL
    1.002: Changed LoginGUI Userpass to Password, added classnames to buttons
    1.001: PrintTemplateFile outputs message if file not found instead of crashing
    1.000: Original Release

=head1 KNOWN ISSUES & LIMITATIONS

=head1 AUTHOR

Jason M. Hinkle

=head1 COPYRIGHT

Copyright (c) 2003 Jason M. Hinkle.  All rights reserved.
This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut