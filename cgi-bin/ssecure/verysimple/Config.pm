# ----------------------------------------------------------------------------
# verysimple::Config
# Copyright (c) 2004 Jason M. Hinkle. All rights reserved. This module is
# free software; you may redistribute it and/or modify it under the same
# terms as Perl itself.
# For more information see: http://www.verysimple.com/scripts/
#
# LEGAL DISCLAIMER:
# This software is provided as-is.  Use it at your own risk.  The
# author takes no responsibility for any damages or losses directly
# or indirectly caused by this software.
# ----------------------------------------------------------------------------
package verysimple::Config;
require 5.000;
use verysimple::DB;
use verysimple::DBGrid;
use verysimple::Util;
use CGI;

$VERSION = "2.00";
$ID = "verysimple::Config.pm";

#_____________________________________________________________________________
sub new {
	my $class = shift;
	my %keyValues = @_;
	my ($vsDB) = new verysimple::DB;

	my $this = {
	    file		=> ($keyValues{'file'} || $keyValues{'File'} || ""),
	    delimiter	=> ($keyValues{'delimiter'} || $keyValues{'Delimiter'} || "\t"),
	    color1		=> ($keyValues{'color1'} || "#DDDDDD"),
	    color2		=> ($keyValues{'color2'} || "#BBBBBB"),
	    color3		=> ($keyValues{'color3'} || "#666666"),
	    color4		=> ($keyValues{'color4'} || "#000000"),
	    db			=> $vsDB,
	    salt		=> "verysimple",
	    errors	=> "",
	};
	
	bless $this, $class;

	# now load the database
    $this->{'db'}->File($this->{'file'});
    $this->{'db'}->Delimiter($this->{'delimiter'});
    $this->{'db'}->Open || die ("Config.pm failed while opening DB (" . $this->{'file'} . "): " . $this->{'db'}->LastError);

	return $this;
}

# read-only properties
sub Version {return $VERSION;}
sub ID {return $ID;}
sub ErrorLog {return shift->{'errors'};}

# read/write properties
sub Color1 {return shift->_GetSetProperty('color1',shift);}
sub Color2 {return shift->_GetSetProperty('color2',shift);}
sub Color3 {return shift->_GetSetProperty('color3',shift);}
sub Color4 {return shift->_GetSetProperty('color4',shift);}
sub Salt {return shift->_GetSetProperty('salt',shift);}

sub GetSetting {
	my ($this) = shift;
	my ($setting) = shift || die("Config.GetSetting: Setting parameter required");
	$this->{'db'}->RemoveFilter;
	$this->{'db'}->MoveFirst;
	$this->{'db'}->Filter("SETTING","eq",$setting);
	my %setting;
	if ($this->{'db'}->EOF) {
		$this->{'errors'} .= "Config.GetValue: Setting '$setting' not found.\n";
	} else {
		foreach my $field ($this->{'db'}->FieldNames) {
			$setting{$field} = $this->{'db'}->FieldValue($field);
		}
	}
	return %setting;
}

sub GetValue {
	my ($this) = shift;
	my ($name) = shift || die("Config.GetValue: Setting parameter required");
	my %setting = $this->GetSetting($name);
	my $val = $setting{'VALUE'};
	$val = $setting{'DEFAULT'} unless (length($val) > 0);
	return $val;
}

sub SetValue {
	my ($this) = shift;
	my ($setting) = shift || die("Config.SetValue: Setting parameter required");
	my ($new_val) = shift;

	$this->{'db'}->RemoveFilter;
	$this->{'db'}->MoveFirst;
	while (!$this->{'db'}->EOF) {
		if ($this->{'db'}->FieldValue("SETTING") eq $setting) {
			# this is a bit clumbsy, but need something to deal with
			# crypted password config settings.  if empty, then the
			# field will not be updated.  if there is a value, it will
			# crypt it and update
			if ($this->{'db'}->FieldValue("CRYPT")) {
				if ($new_val ne "") {
					$new_val = crypt($new_val,$this->Salt);
					$this->{'db'}->FieldValue("VALUE",$new_val);
				}
			} else {
				$this->{'db'}->FieldValue("VALUE",$new_val);
			}
		}
		$this->{'db'}->MoveNext;
	}
}

sub Pages {
	my ($this) = shift;
	my @pages;
	my %exists;
	my $name;
	$this->{'db'}->RemoveFilter;
	$this->{'db'}->Sort("SEQUENCE",2);
	$this->{'db'}->MoveFirst;
	while (!$this->{'db'}->EOF) {
		$name = $this->{'db'}->FieldValue("PAGE");
		if (!$exists{$name}) {
			$pages[@pages] = $name;
			$exists{$name} = "1";
		}
		$this->{'db'}->MoveNext;
	}
	return @pages;
}

sub Settings {
	my ($this) = shift;
	my ($page) = shift || "";
	my @settings;
	$this->{'db'}->RemoveFilter;
	$this->{'db'}->Sort("SEQUENCE",2);
	$this->{'db'}->MoveFirst;
	$this->{'db'}->Filter("PAGE","eq",$page) if $page;
	while (!$this->{'db'}->EOF) {
		$settings[@settings] = $this->{'db'}->FieldValue("SETTING");
		$this->{'db'}->MoveNext;
	}
	return @settings;
}

sub GUI {
	my ($this) = shift;
	my ($style) = shift || "0";
	my ($extraData) = shift || "";
	my ($cgi) = new CGI;
	my ($gui) = "";
	my ($color1) = $this->{'color1'};
	my ($color2) = $this->{'color2'};
	my ($color3) = $this->{'color3'};
	my ($color4) = $this->{'color4'};

	# url and uri vars
	my ($url) = substr($cgi->url,0,rindex($cgi->url,"/")+1);
	my ($uri) = $cgi->path_translated || $ENV{'SCRIPT_FILENAME'} || $ENV{'SCRIPT_NAME'};
	$uri =~ s/\\/\//g;
	$uri = substr($uri,0,rindex($uri,"/")+1);

	my @pages = $this->Pages;
	my $page = $cgi->param("_CONFIG_PAGE") || $pages[0];
	my $command = $cgi->param("_CONFIG_COMMAND") || "DISPLAY";

	if ($command eq "APPLY") {
		# update the settings
		$this->UpdateSettings($cgi);
	} elsif ($command eq "RESET") {
		$this->ResetToDefault();
	} elsif ($command eq "OVERWRITE") {
		$this->OverwriteDefaults();
	}
	
	my $lastPage = @pages;
	$pages[$lastPage] = "Defaults";
	
	$gui .= $cgi->start_form(-name=>'_CONFIG',-id=>'_CONFIG',-method=>'post');
	$gui .= $cgi->hidden(-name=>'_CONFIG_PAGE',value=>$page) . "\n";
	$gui .= "<input type='hidden' name='_CONFIG_COMMAND' value='APPLY'>\n";
	$gui .= "<script>\n";
	$gui .= "	function ChangePage(sPage) {\n";
	$gui .= "		document._CONFIG._CONFIG_PAGE.value=sPage;\n";
	$gui .= "		document._CONFIG._CONFIG_COMMAND.value='DISPLAY';\n";
	$gui .= "		document._CONFIG.submit()\n";
	$gui .= "	}\n";
	$gui .= "</script>\n";
	$gui .= "<table border='0' cellspacing='0' cellpadding='0'>\n";
	$gui .= "<tr><td>\n";
	$gui .= "<table border='0' cellspacing='0' cellpadding='2' style=\"font-family:arial;font-size:10pt\">\n";
	$gui .= "<tr valign='top'>\n";
	foreach my $pageName (@pages) {
		if ($pageName eq $page) {
			$gui .= "<td bgcolor='$color3'><b><font color='$color1'>$pageName</font></b></td>\n";
		} else {
			$gui .= "<td bgcolor='$color2'><a href='' onclick=\"ChangePage('$pageName');return false;\"><font color='$color4'>$pageName<font></a></td>\n";
		}
		$gui .= "<td style=\"font-family:arial;font-size:2pt\">&nbsp;</td>\n";
	}
	$gui .= "</td></tr>\n";
	$gui .= "</table>\n";
	$gui .= "</td></tr><tr bgcolor='$color3' style=\"font-family:arial;font-size:5pt\"><td>&nbsp;</td></tr><tr><td>\n";
	$gui .= "<table border='0' cellspacing='2' cellpadding='2' style=\"font-family:arial;font-size:10pt\">\n";
	
	if ($page eq $pages[$lastPage])
	{
		$gui .= "<tr bgcolor='$color1' valign='top'><td width='100%' align='center'>";
		$gui .= "<p>Click the button below to restore all settings to their ";
		$gui .= "default values.<br>WARNING: All custom settings will be lost!</p>";
		$gui .= "<p><input type='submit' value='Restore Default Settings' onclick=\"if (confirm('Restore Default Settings?')) {this.form._CONFIG_COMMAND.value='RESET';} else {return false;};\"></p>";
		$gui .= "<p>Click the button below to save the current settings as default.<br>";
		$gui .= "One likely use for this is to specify default settings prior to<br>";
		$gui .= "distributing or installing this application on multiple servers.<br>";
		$gui .= "WARNING: Once you overwrite the defaults, you will not be able<br>";
		$gui .= "to restore the original settings without re-installing the application.</p>";
		$gui .= "<p><input type='submit' value='Save Current Settings as Default' onclick=\"if (confirm('Save Current Settings as Default?')) {this.form._CONFIG_COMMAND.value='OVERWRITE';} else {return false;};\"><br>&nbsp;</p>";
		$gui .= "</td></tr>";
	}
	
	my @settingsNames = $this->Settings($page);
	
	# filter the settings for this page & load them into an array
	# (because we have to do further lookups for each val)
	#$this->{'db'}->RemoveFilter;
	#$this->{'db'}->Sort("SEQUENCE",2);
	#$this->{'db'}->MoveFirst;
	#$this->{'db'}->Filter("PAGE","eq",$page) if $page;
	

	#while (!$this->{'db'}->EOF) {
	#	print $this->{'db'}->FieldValue("SETTING") . " " . $this->{'db'}->FieldValue("SEQUENCE") . "<br>";
	#	$settingsNames[@settingsNames] = $this->{'db'}->FieldValue("SETTING");
	#	$this->{'db'}->MoveNext;
	#}
	
	foreach my $settingName (@settingsNames) {
		my %setting = $this->GetSetting($settingName);
		my $input = $setting{"INPUT"};
		my $val = $setting{"VALUE"};
		$val = $setting{"DEFAULT"} unless (length($val) > 0);
		my $description = $setting{"DESCRIPTION"};
		my %selected;
		my %checked;
		foreach my $v ( split(",",$val) ) {
			$selected{$v} = "selected";
			$checked{$v} = "checked";
		}
		# replace the input string with all the approp values
		$input =~ s/{SCRIPT_URI}/$uri/g;
		$input =~ s/{SCRIPT_URL}/$url/g;
		$input =~ s/{SETTING}/_CONFIG_SETTING_$settingName/g;
		$input =~ s/{VALUE}/$val/g;
		$input =~ s/\{SELECTED\((\w+)\)\}/$selected{$1}/g;
		$input =~ s/\{CHECKED\((\w+)\)\}/$checked{$1}/g;
		$gui .= "<tr bgcolor='$color1' valign='top'>";
		$settingName =~ s/_/ /g;
		$gui .= "<td><b>$settingName:</b><br><font size='1'>$description</font></td>" if $style eq "0";
		$gui .= "<td>$settingName:</td>" if $style eq "1";
		$gui .= "<td>$input</td>";
		$gui .= "<td style=\"font-family:arial;font-size:8pt\">$description</td>" if $style eq "1";;
		$gui .= "</tr>\n";
	}
	$gui .= "</table>\n";
	$gui .= "</td></tr><tr><td>\n";
	$gui .= "</td></tr></table>\n";
	$gui .= $cgi->br;
	$gui .= "<input class='BUTTON' type='submit' value='Apply Changes'>\n";
	$gui .= "<input class='BUTTON' type='reset' value='Reset'>\n";
	#$gui .= $cgi->submit('Apply Changes') . "\n";
	#$gui .= $cgi->reset('Reset') . "\n";
	$gui .= $extraData;
	$gui .= $cgi->endform . "\n";
	
	
	
	# do an alert if the update was successful
	if ($command eq "APPLY") {
		my $util = new verysimple::Util;
		$gui .= $util->AlertJS("Settings were updated.");
	}
	return $gui;
}

# public methods
sub UpdateSettings {
	my $this = shift;
	my $cgi = shift || die("Config.UpdateSettings: CGI parameter required");
	foreach my $param ($cgi->param) {
		if (substr($param,0,16) eq "_CONFIG_SETTING_") {
			$this->SetValue(substr($param,16),$cgi->param($param));
		};
	}
	$this->SaveSettings;
}

sub ResetToDefault {
	my $this = shift;
	my $page = shift || "";
	$this->{'db'}->RemoveFilter;
	$this->{'db'}->MoveFirst;
	while (!$this->{'db'}->EOF) {
		if ((!$page) || $this->{'db'}->FieldValue("PAGE") eq $page) {
			$this->{'db'}->FieldValue("VALUE","");
		}
		$this->{'db'}->MoveNext;
	}
	$this->SaveSettings;
}

sub OverwriteDefaults {
	my $this = shift;
	my $page = shift || "";
	my $newVal;
	$this->{'db'}->RemoveFilter;
	$this->{'db'}->MoveFirst;
	while (!$this->{'db'}->EOF) {
		if ((!$page) || $this->{'db'}->FieldValue("PAGE") eq $page) {
			$newVal = $this->{'db'}->FieldValue("VALUE");
			$newVal = $this->{'db'}->FieldValue("DEFAULT") unless (length($newVal) > 0);
			$this->{'db'}->FieldValue("DEFAULT",$newVal);
			$this->{'db'}->FieldValue("VALUE","");
		}
		$this->{'db'}->MoveNext;
	}
	$this->SaveSettings;
}

sub SaveSettings {
	my ($this) = shift;
	$this->{'db'}->Commit || die("Config.SaveSettings: " . $this->{'db'}->LastError);
}

#_____________________________________________________________________________
sub _GetSetProperty {
	# private fuction that is used by properties to get/set values
	# if a parameter is sent in, then the property is set and true is returned.
	# if no parameter is sent, then the current value is returned
	my $this = shift;
	my $fieldName = shift;
	my $newValue = shift;
	if (defined($newValue)) {
		$this->{$fieldName} = $newValue;
	} else {
		return $this->{$fieldName};
	}
	return 1;
}

1; # for require


__END__

=head1 NAME

verysimple::Config - interface for script configuration files

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OBJECT MODEL REFERENCE

=head1 VERSION HISTORY

    2.00: Added Salt property and CRYPT config field
    1.11: Fix bug with incorrect sequence
    1.10: Add RestoreDefaults and SaveDefaults
    1.00: Original Release

=head1 KNOWN ISSUES & LIMITATIONS

=head1 AUTHOR

Jason M. Hinkle

=head1 COPYRIGHT

Copyright (c) 2004 Jason M. Hinkle.  All rights reserved.
This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut