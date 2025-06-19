#!/usr/bin/perl
# ----------------------------------------------------------------------------
# PRODUCT INFORMATION:
my $PRODUCT_VERSION = "3.33";
my $PRODUCT_NAME = "SimpleSecure Pro";
my $PRODUCT_DESCRIPTION = "Professional secure form processor.";
my $PRODUCT_COPYRIGHT = "Copyright &copy; 1997-2004 <a href='http://www.verysimple.com/'>verysimple.com</a>";
#
# COPYRIGHT NOTICE:
# The product and copyright information above may not be changed unless
# you have purchased a user license for this software.  Please support
# the continued development of this product by either registering, or
# leaving the small copyright notice as-is.
#
# LEGAL DISCLAIMER:
# This software is provided as-is.  Use it at your own risk.  The
# author takes no responsibility for any damages or losses directly
# or indirectly caused by this software.
#
# CHANGE HISTORY:
# TODO: (3.34) implement "cfgOrder" parameter
# 3.33 fixed incorrect login bug & added PGP files to keys dir
# 3.32 changed keypaths to relative
# 3.31 added cfgSupress
# 3.30 crypt the admin password for added security
# 3.22 added support for multi-value fields
# 3.21 updated form url for nix servers 404 errors, added cfgRequired
# 3.20 add PGP keyview and key import
# 3.10 add auto-response feature
# 3.00 code re-write
# ----------------------------------------------------------------------------


BEGIN {
# #############################################################################	
# CONFIGURATION SETTINGS	
# #############################################################################	
	
	# these settings should only be changed if the script does not install
	# correctly, or you need to move the configuration file to an alternate
	# location.  all user settings should be changed using the setup utility
	# through your web browser.
	
    # if the script can't find the current directory, then you
    # can manually specify it here.  for example:
    #$ENV{"CWD"} = "C:/InetPub/wwwroot/cgi-bin";
    $ENV{"CWD"} = GetCwd();
    
    # this is the file path to the config file.  not recommended
    # to change this 
    $ENV{"CONFIG_FILE"} = $ENV{"CWD"} . "/data/ssecure.cfg.txt";

    # multi-value field value delimiter 
    $ENV{"MVF_DELIM"} = ", ";
	
	# you can change the crypt salt here if desired.  however, you
	# will have to manually generate your admin password and edit
	# ssecure.cfg.txt manually before you will be able to login
	$ENV{'SALT'} = "verysimple";
	
	# uncomment to disable output buffering.  different servers react
	# differently to this setting
	# $|++
    
# #############################################################################	

    push(@INC,$ENV{"CWD"});
    
    sub GetCwd {
		# v 1.2 - returns cwd _with_ trailing slash
		my $sPath = $ENV{"SCRIPT_FILENAME"} || $ENV{"PATH_TRANSLATED"} || $0 || "./";
		my $pos = rindex($sPath,"\\");
		if ($pos < 0) {$pos = rindex($sPath,"\/")}
		if ($pos < 0) {$pos = "./"} # servers that report no name
		return (( substr($sPath,0,$pos) || ($ENV{"PWD"} || ".") ) . "/");
    }

}
# ----------------------------------------------------------------------------

use strict;
use CGI::Carp 'fatalsToBrowser';
use CGI;
use verysimple::Config;
use verysimple::DB;
use verysimple::DBGrid;
use verysimple::Email;
use verysimple::Session;
use verysimple::Util;

# $CGI::DISABLE_UPLOADS = 1;

# set some application scope variables:
my ($CGI) = new CGI;
my ($CONFIG) = new verysimple::Config(file => $ENV{"CONFIG_FILE"});
$CONFIG->Salt($ENV{'SALT'});
my ($TEMP_DIR) = $ENV{"CWD"} . $CONFIG->GetValue("Temp_Directory");
my ($SESSION) = new verysimple::Session(TempDir=>$TEMP_DIR, CookieName=>'SimpleSecure');
my ($UTIL) = new verysimple::Util();
my ($SCRIPT_PATH) = $ENV{'SCRIPT_NAME'} || $CGI->url || "ssecure.pl";

&main();

#_____________________________________________________________________________
sub main {
	
	my ($command) = $CGI->param("c") || "";
	my ($id) = $CGI->param("cfgId") || "";
	
	if ($command eq "x") 	{ PrintSetup() }
	elsif ($command eq "l") { ProcessLogin() }
	elsif ($command eq "o") { ProcessLogout() }
	elsif ($id) 			{ ProcessForm($id) }
	else                    { PrintLogin() }
	
}

#_____________________________________________________________________________
sub ProcessForm {
	my $formId = shift;
	my %attachedFiles;
	
	# get the form record from the forms DB
	my $recipientsDB = new verysimple::DB(file => $ENV{'CWD'} . $CONFIG->GetValue('Recipients_Path'));
	$recipientsDB->Open || die("SimpleSecure.ProcessForm: " . $recipientsDB->LastError);
	$recipientsDB->Filter("ID","eq",$formId);
	
	# check that specified form id exists
	if ($recipientsDB->EOF) {
		PrintFriendlyError("SimpleSecure.ProcessForm: Form Id '$formId' not found.")
	}

	# check that we are in secure mode if specified
	if ($recipientsDB->FieldValue("RequireSSL") && !IsConnectionSecure()) {
		PrintFriendlyError("SimpleSecure.ProcessForm: This form must be submitted in secure (SSL) mode. Visitors: Please contact the site administrator for assistance. Administrators: Either update your form tag 'action' parameter to begin with 'https://' or update Recipient #$formId so that RequireSSL = 'No'.")
	}

	# set all the vars that will be available to the encryption code
	my $redirect = $CGI->param('cfgRedirectUrl') || $recipientsDB->FieldValue("DefaultRedirectUrl");
	my $format = $CGI->param('cfgEmailFormat') || $recipientsDB->FieldValue("DefaultEmailFormat");
	my $from = $CGI->param('cfgFrom') || $recipientsDB->FieldValue("DefaultFrom");
	my $subject = $CGI->param('cfgSubject') || $recipientsDB->FieldValue("DefaultSubject");
	my $required = $CGI->param('cfgRequired') || "";
	my $order = $CGI->param('cfgOrder') || "";
	my $supress = $CGI->param('cfgSupress') || "";

	# create the email message object
	my $email = new verysimple::Email;

	my $plainText = "";
	my $useHtml = 0;
	my %cgiFields;
	
	# if cgfRequired was specified, check that all required fields are there
	if ( $CGI->param('cfgRequired') ) {
		my $buff = $CGI->param('cfgRequired');
		my @required_fields = split(/,/,$buff);
		foreach my $rf (@required_fields) {
			if (!$CGI->param($rf)) {
				PrintFriendlyError("The field '" . $rf . "' is required.");
			}
		}
	}
	
	# if cgfFrom was used, add it to the regular form too
	if ($CGI->param('cfgFrom')) {
		$CGI->param(-name=>'Email',-value=>$CGI->param('cfgFrom'));
	}

	if ($recipientsDB->FieldValue("DefaultEmailFormat") eq "HTML"
	|| ($CGI->param('cfgEmailFormat') || "") eq "HTML") {
		$useHtml = 1;
	}

	foreach my $param ( $CGI->param ) {
		
		if (substr($param,0,3) ne "cfg") {
			if ($CGI->uploadInfo($CGI->param($param)))
			{
				# this is a file upload
				my $filename = $CGI->param($param);
				$cgiFields{$param} = $filename;  # (used in auto-reply)

				$filename =~ s/\\/\//g;
				$filename = substr($filename,rindex($filename,"/")+1);
				my $filepath = $TEMP_DIR . $$ . "_" . $filename; # temporarily save file here
				if ($useHtml) {
					$plainText .= "<tr valign='top'><th>$param</th><td>($filename attached)</td></tr>\n";
				} else {
					$plainText .= "$param: ($filename attached)\n";
				}
				
				# save the file to disk for email attaching.  use binmode
				# so windows will deal with binary files properly
				my $fh = $CGI->upload($param);
				my $buffer, 
				my $bytesread;
				open (OUTFILE,">>$filepath");
				binmode(OUTFILE);
				while ($bytesread=read($fh,$buffer,1024)) {
				   print OUTFILE $buffer;
				}
				close OUTFILE;
				$email->AttachFile($filepath,$filename);
				$attachedFiles{$filepath} = 1;
			}
			else
			{
				# this is a regular field
				my @buff = $CGI->param($param);  # in case of multi-value field
				$cgiFields{$param} = join($ENV{"MVF_DELIM"}, @buff);

				if (($cgiFields{$param} ne "") || (!$supress) ) {
					if ($useHtml) {
						$plainText .= "<tr valign='top'><th>" . $param . "</th><td>" . $cgiFields{$param} . "</td></tr>\n";
					} else {
						$plainText .= $param . ": " . $cgiFields{$param} . "\n";
					}
				}

			}
		}
	}

	# little formating if html
	if ($useHtml) {
		$plainText = "<table>$plainText</table>\n";
		$plainText = "<style>\n" . $recipientsDB->FieldValue("HtmlTableStyle") . "\n</style>\n" . $plainText;
	}

	#print "<pre>$plainText</pre>";
	#die("This is the End, my only friend, the end...");
	
	# get the encryption code from the crypt codes DB
	my ($cryptDB) = new verysimple::DB(file => ($ENV{"CWD"} . $CONFIG->GetValue("Crypt_FilePath")) );
	$cryptDB->Open || die ("ProcessForm: " . $cryptDB->LastError);
	$cryptDB->Filter("Id","eq",$recipientsDB->FieldValue("EncryptMethod"));
	!$cryptDB->EOF || die ("ProcessForm: Unsupported Crypt_Method setting (".$recipientsDB->FieldValue("EncryptMethod").")");
	my $code = $cryptDB->FieldValue("EncryptCode");
	my $attachmentExtention = $cryptDB->FieldValue("AttachmentExtention");
	
	# -- debug crypt perl code
	#print $CGI->header;
	#print "<pre>$code</pre>";
	#return 1;
	# --
	
	# execute the crypt code.  it will set $encrpytedText
	my $encryptedText;
	eval $code;
	if ($@) {
		PrintFriendlyError("SimpleSecure.ProcessForm: Encryption Failed: $@")
	}
	
	# get the recipient(s)
	my ($recipients) = $recipientsDB->FieldValue("Recipients");
	$recipients =~ s/\r/,/g;
	$recipients =~ s/\n//g;
	
	# set all the email properties
	$email->To($recipients);
	$email->From($from);
	$email->Subject($subject);
	$email->Type($format);
	$email->TempDir($TEMP_DIR);
	$email->Method($CONFIG->GetValue("Email_Method"));
	$email->MethodPath($CONFIG->GetValue("Email_Method_Path"));
	if ($attachmentExtention) {
		# figure out the file attachment name
		my $att_name = "att_" . $$; # default to process id to give some uniqueness
		# if a lookup fieldname is specified, then use that for the filename
		my $name_lookup = $recipientsDB->FieldValue("AttNameLookup") || "";
		if ( $name_lookup & $CGI->param($name_lookup) ) {
			$att_name = $CGI->param($name_lookup);
		}
		$email->AttachString($encryptedText,$att_name . "." . $attachmentExtention);
		$email->Body("(Form Submission Attached)");
	} else {
		$email->Body($encryptedText);
	}
	
	#print $CGI->header;
	#$email->Debug(1);
	
	$email->Send;
	
	# delete any attached temporary files
	foreach my $fn (keys(%attachedFiles))
	{
		unlink($fn);
	}
	
	# now send the auto-reply if one was specified
	if ($recipientsDB->FieldValue("AutoReplyId"))
	{

		my $repliesDB = new verysimple::DB(file => $ENV{'CWD'} . $CONFIG->GetValue('AutoReplies_Path'));
		$repliesDB->Open || die("SimpleSecure: " . $repliesDB->LastError);
		$repliesDB->Filter("ID","eq",$recipientsDB->FieldValue("AutoReplyId"));
		
		my $message = $repliesDB->FieldValue("Message");
		$message =~ s/{(\w+)}/$cgiFields{$1}/g;

		my $reply_email = new verysimple::Email;
		$reply_email->To($from);
		$reply_email->From($repliesDB->FieldValue("FromEmail"));
		$reply_email->Subject($repliesDB->FieldValue("Subject"));
		$reply_email->Body($message);
		$reply_email->Type($repliesDB->FieldValue("EmailFormat"));
		$reply_email->TempDir($TEMP_DIR);
		$reply_email->Method($CONFIG->GetValue("Email_Method"));
		$reply_email->MethodPath($CONFIG->GetValue("Email_Method_Path"));
		
		$reply_email->Send;
	}
	
	if ($redirect)
	{
		print $CGI->header;
		print $UTIL->RedirectJS($redirect);
	}
	else
	{
		PrintHeader();
		print "<b>Thank You.  Your information has been submitted.</b>";
		PrintFooter();
	}
}

#_____________________________________________________________________________
sub PrintFriendlyError {
	# print a user error to the browser
	my $message = shift || "Unknown Error";
	PrintHeader();
	print "<p><b><font color='red'>$message</font></b></p>";
	print "<p>Please use the 'Back' button on your browser to
	return to the previous page and correct this issue.
	If you continue to experience problems, please contact
	the site administrator.</p>";
	PrintFooter();
	exit 1;
}

#_____________________________________________________________________________
sub PrintLogin {
	my $message = shift || $CGI->param('m') || "";
	PrintHeader(1);
	print "<p><font color='red'>$message</font>\n" if ($message);
	print "<p>\n";
	print $UTIL->LoginGUI("<input type='hidden' name='c' value='l'>");
	PrintFooter();
	print $CGI->end_html;
}

#_____________________________________________________________________________
sub ProcessLogin {
	
	$SESSION->Load;
	
	if ($CGI->param('Username') eq $CONFIG->GetValue('Admin_Username')
		&& crypt($CGI->param('Userpass'),$ENV{'SALT'}) eq $CONFIG->GetValue('Admin_Password')) {
		$SESSION->Authorize;
		print $CGI->header;
		print $UTIL->RedirectJS($SCRIPT_PATH . "?c=x");
	} else {
		print $CGI->header;
		# print crypt($CGI->param('Userpass'),"verysimple");
		print $UTIL->RedirectJS($SCRIPT_PATH . "?m=Login+failed.+Please+try+again.");
	}
}

#_____________________________________________________________________________
sub ProcessLogout {
	# TODO: check authentication
	$SESSION->Load;
	$SESSION->Abandon;
	print $UTIL->RedirectJS($SCRIPT_PATH);
}

#_____________________________________________________________________________
sub PrintSetupNav {
	my $active = shift || 1;
	my @tag;
	$tag[$active] = "NAVON";
	print "<p><table cellspacing='0' cellpadding='1' border='0'>";
	print "<tr>";
	print "<td class='NAVBLANK'>&nbsp;</td>";
	print "<td class='" . ($tag[1] || "NAVOFF") . "'><a href='" . $SCRIPT_PATH . "?c=x&x=f'>Recipients</a></td>";
	print "<td class='NAVBLANK'>&nbsp;</td>";
	print "<td class='" . ($tag[2] || "NAVOFF") . "'><a href='" . $SCRIPT_PATH . "?c=x&x=a'>Auto&nbsp;Replies</a></td>";
	print "<td class='NAVBLANK'>&nbsp;</td>";
	print "<td class='" . ($tag[3] || "NAVOFF") . "'><a href='" . $SCRIPT_PATH . "?c=x&x=k'>Keys&nbsp;Manager</a></td>";
	print "<td class='NAVBLANK'>&nbsp;</td>";
	print "<td class='" . ($tag[4] || "NAVOFF") . "'><a href='" . $SCRIPT_PATH . "?c=x&x=s'>System&nbsp;Settings</a></td>";
	print "<td class='NAVBLANK'>&nbsp;</td>";
	print "<td class='" . ($tag[5] || "NAVOFF") . "'><a href='" . $SCRIPT_PATH . "?c=x&x=m'>System&nbsp;Information</a></td>";
	print "<td class='NAVBLANK'>&nbsp;</td>";
	print "<td class='" . ($tag[6] || "NAVOFF") . "'><a href='" . $SCRIPT_PATH . "?c=o'>Logout</a></td>";
	print "<td class='NAVBLANK'>&nbsp;</td>";
	print "</tr></table></p>\n<p>\n";
}

#_____________________________________________________________________________
sub PrintSetup {
	
	$SESSION->Load;
	
	# PrintSetup shows the setup information for the script.
	if ($SESSION->IsAuthorized) {
		my $setupScreen = $CGI->param('x') || "f";
		PrintHeader(1);
		
		if ($setupScreen eq "s") {
			# show the system setup screen
			PrintSetupNav(4);
			print "System settings control the behavior of the application.\n";
			print "Edit these setting with caution.\n";
			print "<p>\n";
			my $controlCode .= "<input type='hidden' name='c' value='x'>\n";
			$controlCode .= "<input type='hidden' name='x' value='s'>\n";
			print $CONFIG->GUI(0,$controlCode);
		} elsif ($setupScreen eq "k") {
			# show the key manager
			my $formAction = $CGI->param('f') || "";
			my $app_var = $CGI->param('app') || "gpg";
			PrintSetupNav(3);
			print "<p>Keys Manager allows you to manager your public encryption keys.\n";
			print "If you have GPG or PGP installed, you can view the keys that are\n";
			print "currently in your keyring.  You may also upload a public key which\n";
			print "can then be used for sending encrypted form mail messages.\n";
			print "The key import features supports only .asc files, which is the\n";
			print "default export format for GPG and PGP public keys.\n";
			print "</p>\n";
			
			print "<a href='" . $SCRIPT_PATH . "?c=x&x=k&f=sg&app=gpg'>Show GPG Keys</a> ";
			print " | <a href='" . $SCRIPT_PATH . "?c=x&x=k&f=sg&app=pgp'>Show PGP Keys</a> ";

			eval 'use Crypt::PGPSimple';
			my $objPGP = new Crypt::PGPSimple;
			$objPGP->PgpTempDir($ENV{'CWD'} . $CONFIG->GetValue("Temp_Directory"));
			if ($formAction eq "sg") {
				# show pgp/gpg keys
				my $result = "";
				if ($app_var eq "pgp")
				{
					$objPGP->PgpExePath($CONFIG->GetValue("PGP_Executable_Path"));
					$objPGP->PgpKeyPath("" . $ENV{"CWD"} . $CONFIG->GetValue("PGP_Keyring_Path") . "");
					$result = $objPGP->DoPgpCommand($objPGP->PgpExePath . " -kv");
				}
				else
				{
					$objPGP->PgpExePath($CONFIG->GetValue("GPG_Executable_Path"));
					$objPGP->PgpKeyPath("\"" . $ENV{"CWD"} . $CONFIG->GetValue("GPG_Keyring_Path"). "\"");
					$result = $objPGP->DoPgpCommand($objPGP->PgpExePath . " --verbose --homedir " . $objPGP->PgpKeyPath . " --list-keys");
				}
				print "<pre>\n";
				print $result || ("Keyring is empty\n");
				print "</pre>\n";
			} elsif ($formAction eq "ig") {
				# insert a new pgp/gpg key
				if ($CGI->uploadInfo($CGI->param("keyfile")))
				{
					# save the file temporarily
					my $filepath = $TEMP_DIR . $$ . "_key.asc"; # temporarily save file here
					my $fh = $CGI->upload("keyfile");
					my $buffer, 
					my $bytesread;
					open (OUTFILE,">>$filepath");
					binmode(OUTFILE);
					while ($bytesread=read($fh,$buffer,1024)) {
					   print OUTFILE $buffer;
					}
					close OUTFILE;
					
					# see if it's pgp or gpg
					my $result = "";
					if ($app_var eq "pgp")
					{
						$objPGP->PgpExePath($CONFIG->GetValue("PGP_Executable_Path"));
						$objPGP->PgpKeyPath("" . $ENV{"CWD"} . $CONFIG->GetValue("PGP_Keyring_Path"). "");
						$result = $objPGP->DoPgpCommand($objPGP->PgpExePath . " -ka +batchmode +force \"" . $filepath . "\" \"" . $objPGP->PgpKeyPath . "/pubring.pgp\"");
					}
					else
					{
						$objPGP->PgpExePath($CONFIG->GetValue("GPG_Executable_Path"));
						$objPGP->PgpKeyPath("\"" . $ENV{"CWD"} . $CONFIG->GetValue("GPG_Keyring_Path") . "\"");
						$result = $objPGP->DoPgpCommand($objPGP->PgpExePath . " --verbose --homedir " . $objPGP->PgpKeyPath . " --import \"" . $filepath . "\"");
					}
					print "<pre>\n";
					print $result || ($objPGP->Result);
					print "</pre>\n";
					
					unlink $filepath;
				}
			} elsif ($formAction eq "dg") {
				# delete a gpg key
			}
			# show import forms
			print "<p><table><tr><td><form action='' method='post' enctype='multipart/form-data'>\n";
			print "<table><tr><td class='MEDIUM' align='center'>\n";
			print "<b>Import GPG Key</b><p />\n";
			print "<input type='hidden' name='c' value='x'>\n";
			print "<input type='hidden' name='x' value='k'>\n";
			print "<input type='hidden' name='f' value='ig'>\n";
			print "<input type='hidden' name='app' value='gpg'>\n";
			print "ASC File: <input type='file' name='keyfile'><p />\n";
			print "<input class='button' type='submit' value='Import'>\n";
			print "</td></tr></table>\n";
			print "</form></td>\n";

			# show import forms
			print "<td><form action='' method='post' enctype='multipart/form-data'>\n";
			print "<table><tr><td class='MEDIUM' align='center'>\n";
			print "<b>Import PGP Key</b><p />\n";
			print "<input type='hidden' name='c' value='x'>\n";
			print "<input type='hidden' name='x' value='k'>\n";
			print "<input type='hidden' name='f' value='ig'>\n";
			print "<input type='hidden' name='app' value='pgp'>\n";
			print "ASC File: <input type='file' name='keyfile'><p />\n";
			print "<input class='button' type='submit' value='Import'>\n";
			print "</td></tr></table>\n";
			print "</form></td></tr></table></p>\n";

		} elsif ($setupScreen eq "f") {
			# show the form database
			my $formAction = $CGI->param('f') || "";
			my $formId = $CGI->param('fi') || "";
			PrintSetupNav(1);
			print "<p>Recipients are used to specify settings & recipients for one or more HTML forms.\n";
			print "Typical form processors allow you to specify a recipient using\n";
			print "hidden form fields, however this can present major security problems.\n";
			print "$PRODUCT_NAME stores the recipients and other settings as a 'Recipient.'\n";
			print "You include a hidden 'cfgId' field on your HTML form to specify ";
			print "which Recipient record should be used.\n";
			print "</p>\n";
			my $recipientsDB = new verysimple::DB(file => $ENV{'CWD'} . $CONFIG->GetValue('Recipients_Path'));
			$recipientsDB->Open || die("SimpleSecure.PrintSetup: " . $recipientsDB->LastError);
			my $dbGrid = new verysimple::DBGrid(DB => $recipientsDB);
			
			print $CGI->start_form(-method=>'post') . "\n";
			print $CGI->hidden(-name=>'c',value=>'x') . "\n";
			print $CGI->hidden(-name=>'x',value=>'f') . "\n";

			if ($formAction eq "e") {
				# show the edit screen
				$recipientsDB->Filter("ID","eq",$formId);
				PrintSetupForm($dbGrid);
				print "<input type='hidden' name='f' value='u'>\n";
				#print $CGI->submit('Update') . "\n";
				print "<input class='BUTTON' type='submit' value='Update'>\n";
				print "<input class='BUTTON' type='submit' value='Delete'onclick=\"if (confirm('Delete Form Setting?')) {self.location='". $SCRIPT_PATH ."?c=x&x=f&f=d&fi=$formId';} return false;\">\n";
				print "<input class='BUTTON' type='submit' value='Back...' onclick=\"self.location='". $SCRIPT_PATH ."?c=x&x=f';return false;\">\n";
			} elsif ($formAction eq "n") {
				# TODO show the new screen (re-use display)
				$recipientsDB->AddNew;
				PrintSetupForm($dbGrid);
				print "<input type='hidden' name='f' value='i'>\n";
				print "<input class='BUTTON' type='submit' value='Insert'>\n";
				print "<input class='BUTTON' type='submit' value='Cancel' onclick=\"self.location='". $SCRIPT_PATH ."?c=x&x=f';return false;\">\n";
			} elsif ($formAction eq "i") {
				# insert new record
				$recipientsDB->AddNew;
				$recipientsDB->FieldValue("ID",$recipientsDB->NextId("ID"));
				ProcessUpdateForm($recipientsDB);
			} elsif ($formAction eq "u") {
				# update existing
				$recipientsDB->Filter("ID","eq",$formId);
				ProcessUpdateForm($recipientsDB);
			} elsif ($formAction eq "d") {
				# delete existing
				$recipientsDB->Filter("ID","eq",$formId);
				$recipientsDB->Delete;
				$recipientsDB->Commit || die("PrintSetup-DeleteForm " . $recipientsDB->LastError);
				print $UTIL->RedirectJS($SCRIPT_PATH . "?c=x&x=f");
			} else {
				# show all the forms
				$dbGrid->RowFormat("<tr bgcolor='{color1}'><td><a href='" . $SCRIPT_PATH . "?c=x&x=f&f=e&fi={ID}'>EDIT</a></td><td>{ID}</td><td>{FormName}</td><td>{Recipients}</td></tr>\n");
				$dbGrid->HeaderFormat("<tr bgcolor='{color2}'><td>&nbsp;</td><td>Id</td><td>Form Name</td><td>Recipients</td></tr>\n");
				print $dbGrid->HTMLTable;
				print "<p></p>\n";
				print "<input class='BUTTON' type='submit' value='Add New Recipient' onclick=\"self.location='". $SCRIPT_PATH ."?c=x&x=f&f=n';return false;\">\n";
			}
			print $CGI->end_form;
		} elsif ($setupScreen eq "a") {
			PrintSetupNav(2);
			print "<p>Auto-Replies allow you to have an automatic reply sent to a user after\n";
			print "they have filled out the form.  NOTE: If you use an auto-reply, you must\n";
			print "use cfgFrom as the fieldname for the visitors email address.\n";
			print "</p>\n";

			print $CGI->start_form(-method=>'post') . "\n";
			print $CGI->hidden(-name=>'c',value=>'x') . "\n";
			print $CGI->hidden(-name=>'x',value=>'a') . "\n";

			my $formAction = $CGI->param('f') || "";
			my $formId = $CGI->param('fi') || "";

			my $repliesDB = new verysimple::DB(file => $ENV{'CWD'} . $CONFIG->GetValue('AutoReplies_Path'));
			$repliesDB->Open || die("SimpleSecure.PrintSetup: " . $repliesDB->LastError);
			my $dbGrid = new verysimple::DBGrid(DB => $repliesDB);

			if ($formAction eq "e") {
				# show the edit screen
				$repliesDB->Filter("ID","eq",$formId);

				$dbGrid->FormRow("ID","<tr bgcolor='{color3}'><td>Setting</td><td>Value</td></tr>" .
						"<tr><td bgcolor='{color2}'><b>Id</b></td>" .
						"<td bgcolor='{color1}'>{VALUE}<input type='hidden' name='fi' value='{VALUE}'></td></tr>\n\n");
				$dbGrid->FormRow("Message","<tr><td bgcolor='{color2}'><b>Message</b><br><font size='1'>You can include fields from your message<br>in the auto reply like so: {cfgFrom}</font></td><td bgcolor='{color1}'>" .
						"<textarea rows='4' cols='50' name='Message' wrap='off'>{VALUE}</textarea></td></tr>\n");
				$dbGrid->FormRow("EmailFormat","<tr><td bgcolor='{color2}'><b>EmailFormat</b></td><td bgcolor='{color1}'>" .
						"<select name='EmailFormat'><option value='TEXT' {SELECTED(TEXT)}>Text</option>" .
						"<option value='HTML' {SELECTED(HTML)}>HTML</option></select></td></tr>\n");

				print $dbGrid->HTMLForm;
				print "<p></p>\n";
				print "<input type='hidden' name='f' value='u'>\n";
				#print $CGI->submit('Update') . "\n";
				print "<input class='BUTTON' type='submit' value='Update'>\n";
				print "<input class='BUTTON' type='submit' value='Delete'onclick=\"if (confirm('Delete Form Setting?')) {self.location='". $SCRIPT_PATH ."?c=x&x=f&f=d&fi=$formId';} return false;\">\n";
				print "<input class='BUTTON' type='submit' value='Back...' onclick=\"self.location='". $SCRIPT_PATH ."?c=x&x=f';return false;\">\n";
			} elsif ($formAction eq "n") {
				# TODO show the new screen (re-use display)
				$repliesDB->AddNew;

				$dbGrid->FormRow("ID","<tr bgcolor='{color3}'><td>Setting</td><td>Value</td></tr>" .
						"<tr><td bgcolor='{color2}'><b>Id</b></td>" .
						"<td bgcolor='{color1}'>{VALUE}<input type='hidden' name='fi' value='{VALUE}'></td></tr>\n\n");
				$dbGrid->FormRow("Message","<tr><td bgcolor='{color2}'><b>Message</b><br><font size='1'>You can include fields from your message<br>in the auto reply like so: {cfgFrom}</font></td><td bgcolor='{color1}'>" .
						"<textarea rows='4' cols='50' name='Message' wrap='off'>{VALUE}</textarea></td></tr>\n");
				$dbGrid->FormRow("EmailFormat","<tr><td bgcolor='{color2}'><b>EmailFormat</b></td><td bgcolor='{color1}'>" .
						"<select name='EmailFormat'><option value='TEXT' {SELECTED(TEXT)}>Text</option>" .
						"<option value='HTML' {SELECTED(HTML)}>HTML</option></select></td></tr>\n");

				print $dbGrid->HTMLForm;
				print "<p></p>\n";
				print "<input type='hidden' name='f' value='i'>\n";
				print "<input class='BUTTON' type='submit' value='Insert'>\n";
				print "<input class='BUTTON' type='submit' value='Cancel' onclick=\"self.location='". $SCRIPT_PATH ."?c=x&x=f';return false;\">\n";
			} elsif ($formAction eq "i") {
				# insert new record
				$repliesDB->AddNew;
				$repliesDB->FieldValue("ID",$repliesDB->NextId("ID"));
				ProcessUpdateAutoReply($repliesDB);
			} elsif ($formAction eq "u") {
				# update existing
				$repliesDB->Filter("ID","eq",$formId);
				ProcessUpdateAutoReply($repliesDB);
			} elsif ($formAction eq "d") {
				# delete existing
				$repliesDB->Filter("ID","eq",$formId);
				$repliesDB->Delete;
				$$repliesDB->Commit || die("PrintSetup-DeleteForm " . $repliesDB->LastError);
				print $UTIL->RedirectJS($SCRIPT_PATH . "?c=x&x=f");
			} else {
				# show all the forms
				$dbGrid->RowFormat("<tr bgcolor='{color1}'><td><a href='" . $SCRIPT_PATH . "?c=x&x=a&f=e&fi={ID}'>EDIT</a></td><td>{ID}</td><td>{Title}</td><td>{Subject}</td></tr>\n");
				$dbGrid->HeaderFormat("<tr bgcolor='{color2}'><td>&nbsp;</td><td>Id</td><td>Title</td><td>Subject</td></tr>\n");
				print $dbGrid->HTMLTable;
				print "<p></p>\n";
				print "<input class='BUTTON' type='submit' value='Add New Auto-Reply' onclick=\"self.location='". $SCRIPT_PATH ."?c=x&x=a&f=n';return false;\">\n";
			}
			print $CGI->end_form;
			
			#print $dbGrid->HTMLTable;
			#print "<input class='BUTTON' type='submit' value='Add New Recipient' onclick=\"self.location='". $SCRIPT_PATH ."?c=x&x=f&f=n';return false;\">\n";
		} else {
			PrintSetupNav(5);
			print $UTIL->SysInfo;
		}

		PrintFooter();
	} else {
		# if the user is not authorized, redirect to the login page
		PrintLogin("Login Required:");
	}
}

#_____________________________________________________________________________
sub PrintSetupForm {
	
	# PrintSetupForm prints the configuration screen for a form template
	my $dbGrid = shift;
	my $id = $dbGrid->{'DB'}->FieldValue("ID");
	
	# open the crypt database to present all the available options
	my ($cryptDB) = new verysimple::DB(file => ($ENV{"CWD"} . $CONFIG->GetValue("Crypt_FilePath")) );
	my ($cryptOptions) =
		"<select name='EncryptMethod'>\n";
	$cryptDB->Open || die ("ProcessForm: " . $cryptDB->LastError);
	while (!$cryptDB->EOF) {
		$cryptOptions .= "<option value='" . $cryptDB->FieldValue("Id") . "' {SELECTED(" . $cryptDB->FieldValue("Id") . ")}>" . $cryptDB->FieldValue("Description") . "</option>\n";
		$cryptDB->MoveNext;
	}
	$cryptOptions .= "</select>\n";
	$cryptDB->Close;

	# open the auto-reply database to present all the available options
	my ($autoDB) = new verysimple::DB(file => ($ENV{"CWD"} . $CONFIG->GetValue("AutoReplies_Path")) );
	my ($autoReplyOptions) =
		"<select name='AutoReplyId'><option value=''>None</option>\n";
	$autoDB->Open || die ("PrintSetupForm: " . $autoDB->LastError);
	while (!$autoDB->EOF) {
		$autoReplyOptions .= "<option value='" . $autoDB->FieldValue("ID") . "' {SELECTED(" . $autoDB->FieldValue("ID") . ")}>" . $autoDB->FieldValue("Title") . "</option>\n";
		$autoDB->MoveNext;
	}
	$autoReplyOptions .= "</select>\n";
	$autoDB->Close;
	
	# customize the dbgrid output
	$dbGrid->FormRow("ID","<tr bgcolor='{color3}'><td>Setting</td><td>Value</td></tr>" .
						"<tr><td bgcolor='{color2}'><b>Id</b><br><font size='1'>To use this form, include a hidden variable 'cfgId' on your form with this Id as it's value.</font></td>" .
						"<td bgcolor='{color1}'>{VALUE}<input type='hidden' name='fi' value='{VALUE}'></td></tr>\n\n");
	$dbGrid->FormRow("EncryptMethod","<tr><td bgcolor='{color2}'><b>EncryptMethod</b><br><font size='1'>Specify if this form data should be encrypted.</font></td><td bgcolor='{color1}'>" .
						"$cryptOptions</td></tr>\n");
	$dbGrid->FormRow("RequireSSL","<tr><td bgcolor='{color2}'><b>RequireSSL</b><br><font size='1'>If Yes is selected, SimpleSecure will not process the form unless it is submitted though an SSL connection.  Recommended to select Yes as a precaution if this is a secure form with encryption.</font></td><td bgcolor='{color1}'>" .
						"<select name='RequireSSL'><option value='0' {SELECTED(0)}>No</option>" .
						"<option value='1' {SELECTED(1)}>Yes</option></select></td></tr>\n");
	$dbGrid->FormRow("DefaultEmailFormat","<tr><td bgcolor='{color2}'><b>DefaultEmailFormat</b><br><font size='1'>If the message is encrypted, it is recommended to use TEXT format.  Can be overridden with the hidden form variable 'cfgEmailFormat'</font></td><td bgcolor='{color1}'>" .
						"<select name='DefaultEmailFormat'><option value='TEXT' {SELECTED(TEXT)}>Text</option>" .
						"<option value='HTML' {SELECTED(HTML)}>HTML</option></select></td></tr>\n");
	$dbGrid->FormRow("Recipients","<tr><td bgcolor='{color2}'><b>Recipients</b><br><font size='1'>(One email address per line)</font></td><td bgcolor='{color1}'>" .
						"<textarea rows='3' cols='40' name='Recipients'>{VALUE}</textarea></td></tr>\n");
	$dbGrid->FormRow("HtmlTableStyle","<tr><td bgcolor='{color2}'><b>HtmlTableStyle</b><br><font size='1'>If email is HTML format, Enter CSS code here to control the style of the table.  (Use TABLE, TH and TD tags)</font></td><td bgcolor='{color1}'>" .
						"<textarea rows='4' cols='50' name='HtmlTableStyle' wrap='off'>{VALUE}</textarea></td></tr>\n");
	
	$dbGrid->FormRow("AutoReplyId","<tr><td bgcolor='{color2}'><b>Auto-Reply</b><br><font size='1'>Specify if an auto-reply is sent</font></td><td bgcolor='{color1}'>" .
						"$autoReplyOptions</td></tr>\n");
	
	$dbGrid->FormRowLabel("FormName","<b>FormName</b><br><font size='1'>Enter a friendly name to identify this form.</font>");
	$dbGrid->FormRowLabel("EncryptKey","<b>EncryptKey</b><br><font size='1'>If you specified an encryption type that uses public key cryptography, this is the public key to use when encrypting.</font>");
	$dbGrid->FormRowLabel("AttNameLookup","<b>AttNameLookup</b><br><font size='1'>If you specified an encrytion type that is sent as an attachment, a hidden or visible form field can be used to control the filename of the attachment.  If none specifed, the file will be given a semi-random numeric name.  Suggestion: cfgFrom</font>");
	$dbGrid->FormRowLabel("DefaultRedirectUrl","<b>DefaultRedirectUrl</b><br><font size='1'>Upon successful submission, the visitor will be redirected to this page.  If not specified, a generic thank-you message will be displayed.  Can be overridden with the hidden form variable 'cfgRedirectUrl'</font>");
	$dbGrid->FormRowLabel("DefaultFrom","<b>DefaultFrom</b><br><font size='1'>Email address from which the form submission will be emailed.  Can be overridden with the hidden form variable 'cfgFrom'</font>");
	$dbGrid->FormRowLabel("DefaultSubject","<b>DefaultSubject</b><br><font size='1'>Subject of the form submission email message.  Can be overridden with the hidden form variable 'cfgSubject'</font>");
					 
	print "<table>";
	print "<tr valign='top'>";
	
	print "<td>";
	print $dbGrid->HTMLForm;
	print "</td>";
	
	if ($id)
	{
		print "<td>";
		print "<p><b>Example Form Code:</b></p>";
		print "<p>Below is example HTML code that could be used with ";
		print "this Form Setting.  All variables that do not begin with 'cfg' will be included in ";
		print "the email message.  File uploads will be included as an attachment.</p>";
		print "<p style=\"font-family:courier new,courier; font-size: 8pt;\">";
		print "&lt;form action=\"$ENV{SCRIPT_NAME}\" method=\"post\" enctype=\"multipart/form-data\"&gt;<br>\n";
		print "&lt;input type=\"hidden\" name=\"cfgId\" value=\"$id\"&gt;<br>\n";
		print "Name: &lt;input type=\"text\" name=\"Name\"&gt;&lt;br&gt;<br>\n";
		print "Email: &lt;input type=\"text\" name=\"cfgFrom\"&gt;&lt;br&gt;<br>\n";
		print "Resume: &lt;input type=\"file\" name=\"Resume\"&gt;&lt;br&gt;<br>\n";
		print "&lt;input type=\"submit\" value=\"Submit Form\"&gt;";
		print "&lt;/form&gt;<br>\n";
		print "</p>\n";
		print "<p>Hidden field cfgId is required.  The following optional\n";
		print "fields can be used to override the defaults: cfgRedirectUrl, \n";
		print "cfgEmailFormat, cfgFrom and cfgSubject.  If cfgFrom is used,\n";
		print "the message will be sent from this address and also appear on\n";
		print "the form itself with the name 'Email'\n";
		print "</p>";
		print "</td>\n";
	}
	
	print "</tr>\n";
	print "</table>\n";
	print "<p></p>\n";
}

#_____________________________________________________________________________
sub PrintHeader {
	my $warn_ssl = shift || 0;
	print $CGI->header;
	print $CGI->start_html(-title=>$CONFIG->GetValue('Page_Title')) . "\n";
	print "<style>\n".$CONFIG->GetValue('CSS_Style')."\n</style>\n";
	print "<h1>".$CONFIG->GetValue('Page_Title')."</h1>\n";
	# print "<p><i>$PRODUCT_DESCRIPTION</i></p>\n";

	if ($warn_ssl && !IsConnectionSecure() ) {
		print "<p><b><font color='red'>Warning: SSL is not enabled.  This session is insecure.</font></b></p>\n";
	}
}

#_____________________________________________________________________________
sub PrintFooter {
	print "<h5><hr>$PRODUCT_NAME $PRODUCT_VERSION<br>$PRODUCT_COPYRIGHT</h5>\n";
	if ($CGI->param("M")) {
		print $UTIL->AlertJS($CGI->param("M"))
	}
	print $CGI->end_html;
}

#_____________________________________________________________________________
sub IsConnectionSecure {
	if ($ENV{'HTTPS'} eq "on") {
		return 1;
	}
}


#_____________________________________________________________________________
sub ProcessUpdateForm {
	my $recipientsDB = shift;
	foreach my $field (('FormName','EncryptMethod','EncryptKey','Recipients','DefaultRedirectUrl','DefaultEmailFormat','DefaultFrom','DefaultSubject','AttNameLookup','RequireSSL','HtmlTableStyle','AutoReplyId')) {
		$recipientsDB->FieldValue($field,$CGI->param($field));
	}
	$recipientsDB->Commit || die("PrintSetup-DeleteForm " . $recipientsDB->LastError);
	print $UTIL->RedirectJS($SCRIPT_PATH . "?c=x&x=f&f=e&fi=" . $recipientsDB->FieldValue("ID") . "&M=Recipient+Updated");
}

#_____________________________________________________________________________
sub ProcessUpdateAutoReply {
	my $DB = shift;
	foreach my $field (('FromEmail','EmailFormat','Title','Subject','Message')) {
		$DB->FieldValue($field,$CGI->param($field));
	}
	$DB->Commit || die("ProcessUpdateAutoReply: " . $DB->LastError);
	print $UTIL->RedirectJS($SCRIPT_PATH . "?c=x&x=a&f=e&fi=" . $DB->FieldValue("ID") . "&M=Auto-Reply+Updated");
}

