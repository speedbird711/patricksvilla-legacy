# ----------------------------------------------------------------------------
# verysimple::DBGrid
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
package verysimple::DBGrid;
require 5.000;
use verysimple::DB;

$VERSION = "1.10";
$ID = "verysimple::DBGrid.pm";

#_____________________________________________________________________________
sub new {
	my $class = shift;
	my %keyValues = @_;
	my $DB = $keyValues{'DB'} || new verysimple::DB();
	my %formRow;

	my $this = {
	    DB			=> $DB,
	    RowFormat	=> ($keyValues{'RowFormat'} || ""),
	    AltRowFormat=> ($keyValues{'AltRowFormat'} || ""),
	    HeaderFormat=> ($keyValues{'HeaderFormat'} || ""),
	    FormRow		=> \%formRow,
	    color1		=> ($keyValues{'color1'} || "#DDDDDD"),
	    color2		=> ($keyValues{'color2'} || "#BBBBBB"),
	    color3		=> ($keyValues{'color3'} || "#666666"),
	    color4		=> ($keyValues{'color4'} || "#000000"),
	    errors		=> "",
	};
	
	bless $this, $class;
	return $this;
}

# read-only properties
sub Version {return $VERSION;}
sub ID {return $ID;}
sub ErrorLog {return shift->{'errors'};}

# read/write properties
sub RowFormat {return shift->_GetSetProperty('RowFormat',shift);}
sub AltRowFormat {return shift->_GetSetProperty('AltRowFormat',shift);}
sub HeaderFormat {return shift->_GetSetProperty('HeaderFormat',shift);}
sub Color1 {return shift->_GetSetProperty('color1',shift);}
sub Color2 {return shift->_GetSetProperty('color2',shift);}
sub Color3 {return shift->_GetSetProperty('color3',shift);}
sub Color4 {return shift->_GetSetProperty('color4',shift);}

sub FormRow {
	my $this = shift;
	my $fieldName = shift;
	my $format = shift;
	$this->{'FormRow'}{$fieldName} = $format;
}

sub FormRowLabel {
	my $this = shift;
	my $fieldName = shift;
	my $replace = ">" . (shift) . "<";
	my $find = ">{$fieldName}<";
	my $rowFormat = $this->{'FormRow'}{$fieldName};
	# get a generic format if none is set

	
	if (!$rowFormat) {
		$rowFormat = $this->GenericFormRow($fieldName);
	}

	#print "<pre>$rowFormat</pre>";

	$rowFormat =~ s/$find/$replace/g;
	
	$this->{'FormRow'}{$fieldName} = $rowFormat;
}

sub GenericRowFormat {
	my $this = shift;
	my @fields = $this->{'DB'}->FieldNames;
	my $row = "<tr bgcolor='{color1}'>\n";
	foreach my $field (@fields) {
		$row .= "<td>{$field}</td>\n";
	}
	$row .= "</tr>\n";
	return $row
}

sub GenericFormRow {
	my $this = shift;
	my $fieldName = shift;
	my $format = "<tr><td bgcolor='{color2}'><b>{$fieldName}</b></td><td bgcolor='{color1}'><input name='{$fieldName}' value='{VALUE}' size='35'></td></tr>\n";
	$this->{'FormRowFormat'}{$fieldName} = $format;
}

sub Bind {
	my $this = shift;
	my $db = shift || die("verysimple::DBGrid: DB parameter required.");
	$this->{'DB'} = $db;
}

sub HTMLTable {
	my $this = shift;
	my $extraCode = shift || "";
	my $supressTableTag = shift || 0;
	my $rowFormat = $this->{'RowFormat'} || $this->GenericRowFormat();
	my $altRowFormat = $this->{'AltRowFormat'} || $rowFormat;
	my $headerFormat = $this->{'HeaderFormat'} || $rowFormat;
	my ($color1) = $this->{'color1'};
	my ($color2) = $this->{'color2'};
	my ($color3) = $this->{'color3'};
	my ($color4) = $this->{'color4'};
	my $html = "";
	$html = "<table cellspacing='2' cellpadding='2' border='0' style='font-family:Arial,Helvetica;font-size:10pt;'>\n" unless $supressTableTag;
	my @fields = $this->{'DB'}->FieldNames;
	my $temp = $headerFormat;
	foreach my $field (@fields) {
		$temp =~ s/\{$field\}/$field/g;
	}
	$html .= $temp;
	my $rowCount = 0;
	while (!$this->{'DB'}->EOF) {
		$rowCount++;
		$temp = $rowFormat;
		$temp = $altRowFormat if ($rowCount % 2 == 0);
		foreach my $field (@fields) {
			my $fieldVal = $this->{'DB'}->FieldValue($field);
			$temp =~ s/\{$field\}/$fieldVal/g;
		}
		$html .= $temp . "\n";
		$this->{'DB'}->MoveNext
	}
	$html .= "</table>\n" unless $supressTableTag;
	$html =~ s/\{color1\}/$color1/g;
	$html =~ s/\{color2\}/$color2/g;
	$html =~ s/\{color3\}/$color3/g;
	$html =~ s/\{color4\}/$color4/g;
	return $html;
}

sub HTMLForm {
	my $this = shift;
	my $readonly = shift || 0;
	my $extraCode = shift || "";
	my ($color1) = $this->{'color1'};
	my ($color2) = $this->{'color2'};
	my ($color3) = $this->{'color3'};
	my ($color4) = $this->{'color4'};
	my $html = "";
	my @fields = $this->{'DB'}->FieldNames;
	if (!$this->{'DB'}->EOF) {
		$html = "<table cellspacing='2' cellpadding='2' border='0' style='font-family:Arial,Helvetica;font-size:10pt;'>\n";
		foreach my $field (@fields) {
			my $formRow = $this->{"FormRow"}{$field} || $this->GenericFormRow($field);
			my $fieldVal = $this->{'DB'}->FieldValue($field);
			my %selected;
			my %checked;
			$selected{$fieldVal} = "selected";
			$checked{$fieldVal} = "checked";
			# if the values are delimited, deal with those too...
			foreach my $delimited (split(/,/,$fieldVal)) {
				$selected{$delimited} = "selected";
				$checked{$delimited} = "checked";
			}
			$formRow =~ s/\{$field\}/$field/g;
			$formRow =~ s/\{VALUE\}/$fieldVal/g;
			$formRow =~ s/\{SELECTED\((\w+)\)\}/$selected{$1}/g;
			$formRow =~ s/\{CHECKED\((\w+)\)\}/$checked{$1}/g;
			$html .= $formRow;
		}
		$html .= "</table>\n";
	}
	$html =~ s/\{color1\}/$color1/g;
	$html =~ s/\{color2\}/$color2/g;
	$html =~ s/\{color3\}/$color3/g;
	$html =~ s/\{color4\}/$color4/g;
	$html .= $extraCode;
	return $html;

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

verysimple::DBGrid - interface for displaying verysimple::DB objects as HTML

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OBJECT MODEL REFERENCE

=head1 VERSION HISTORY

    1.10: Added FormRowLabel method
    1.01: Added optional SuppressTableTag argument to HTMLTable
    1.00: Original Release

=head1 KNOWN ISSUES & LIMITATIONS

=head1 AUTHOR

Jason M. Hinkle

=head1 COPYRIGHT

Copyright (c) 2003 Jason M. Hinkle.  All rights reserved.
This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut