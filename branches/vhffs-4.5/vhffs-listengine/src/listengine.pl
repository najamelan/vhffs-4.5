#!%PERL%
# Copyright (c) vhffs project and its contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
#2. Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in
#   the documentation and/or other materials provided with the
#   distribution.
#3. Neither the name of vhffs nor the names of its contributors
#   may be used to endorse or promote products derived from this
#   software without specific prior written permission.
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
#FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
#COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
#BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
#CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.


use strict;
use utf8;
use Net::SMTP;
use Socket;
use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use File::Path;
use Mail::Internet;
use DateTime;
use DateTime::Format::Mail;
use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::Services::MailingList;
use Vhffs::Listengine;
use Vhffs::Functions;

#Huho, if the program stop heres, you have some problems with your MTA configuration
if( $#ARGV != 2 )
{
	print 'involve as: listengine action localpart domain'."\n";
	exit 1;
}

my $action = shift;
my $lpart  = shift;
my $domain = shift;
my $vhffs = new Vhffs;

my $listengineconfig = $vhffs->get_config->get_listengine;

my $DOMAIN	  = $listengineconfig->{'domain'};
my $LISTMASTER	  = $listengineconfig->{'listmaster'};
my $ADMIN	  = $listengineconfig->{'listmaster'};
my $SMTP_SERVER   = $listengineconfig->{'smtp_server'};
my $SENDMAIL_PATH = $listengineconfig->{'sendmail_path'};

# Be careful, listengine will create /data/listengine/archives for archives
# and /data/listengine/tomoderate for moderation
my $DIRECTORY	= $listengineconfig->{'datadir'};

exit 2 unless( defined $DOMAIN && defined $LISTMASTER && defined $ADMIN && ( defined $SMTP_SERVER ^ defined $SENDMAIL_PATH ) && defined $DIRECTORY );


sub add_list_header
{
    my $header = shift;
    my $list = shift;
    my $mailinglistconfig = $list->get_config;

    $header->replace( 'List-Unsubscribe' ,'<mailto:'.$list->get_listrequestname.'?subject=unsubscribe>' );
    $header->replace( 'List-Subscribe' ,'<mailto:'.$list->get_listrequestname.'?subject=subscribe>' );
    $header->replace( 'List-Help' ,'<mailto:'.$list->get_listrequestname.'?subject=help>' );
    $header->replace( 'List-Software' , 'Listengine, VHFFS '.Vhffs::Constants::VHFFS_VERSION );
    $header->replace( 'List-Id' , $list->get_localpart.'.'.$list->get_domain );
    $header->replace( 'List-Post' , '<mailto:'.$list->get_listname.'>' );
    $header->replace( 'List-Archive' , '<'.$mailinglistconfig->{'url_archives'}.'/'.$list->get_domain.'/'.$list->get_localpart.'>' ) if( $mailinglistconfig->{'url_archives'} );
    $header->replace( 'Precedence' , 'list' );

    #Replace the Reply-To field if selected in the panel
    $header->replace( 'Reply-To' , $list->get_listname ) if( $list->get_replyto == 1 );
}


sub datetime_rfc2822
{
	my $maildate = DateTime::Format::Mail->new();
	my $dt = DateTime->now;
	$dt->set_time_zone( 'local' );
	return $maildate->format_datetime( $dt );
}


sub sendmail
{
	my $mail  = shift;
	my $addrs = shift;
	return 1 unless( defined $mail && defined $addrs );

	# single to
	if( ref($addrs) ne 'ARRAY' ) {
		my @to = ( $addrs );
		$addrs = \@to;
	}

	return 1 unless @{$addrs};

	if( defined $SENDMAIL_PATH )  {

		my $dir = $DIRECTORY.'/errors/';
		File::Path::make_path( $dir, { error => \my $errors }) unless -d $dir;
		my $errorf = '/dev/null';
		$errorf = $dir.time().'_'.$$ if -d $dir;

		open(SENDMAIL, '| '.$SENDMAIL_PATH.' 2> '.$errorf.' 1>&2' ) or die( 'Error - cannot open BSMTP input' );
		print SENDMAIL 'HELO '.$DOMAIN."\n";

		foreach my $adr ( @{$addrs} )
		{
			chomp $adr;

			print SENDMAIL 'RSET'."\n";
			print SENDMAIL 'MAIL FROM:<'.$LISTMASTER.'>'."\n";
			print SENDMAIL 'RCPT TO:<'.$adr.'>'."\n";
			print SENDMAIL 'DATA'."\n";
			print SENDMAIL $mail->as_string;
			print SENDMAIL "\n".'.'."\n";
		}

		print SENDMAIL 'QUIT'."\n";
		close(SENDMAIL);

		# delete the error file if it is empty
		unlink $errorf if ( -f $errorf  &&  ! -s $errorf );
	}
	else {
		foreach my $adr ( @{$addrs} )
		{
			my $smtp = Net::SMTP->new( $SMTP_SERVER,
				Hello => $DOMAIN,
			);

			$smtp->mail( $LISTMASTER );
			$smtp->to( $adr );
			$smtp->data( $mail->as_string );
			$smtp->quit;
		}
	}

	return 0;
}



sub archive_it
{
    my $mail = shift;
    my $list = shift;

    my (undef,undef,undef,$day,$month,$year) = localtime(time);
    $year += 1900;
    $month += 1;
    $month = '0'.$month if( $month <= 9 );
    $day = '0'.$day if( $day <= 9 );

    my ( $message_id  ) =  ($mail->get( 'Message-Id' ) =~ /<(.+)>/);

    #Don't archive if message-id is not found
    return unless( defined $message_id  &&  $message_id ne '' );

    my $directory = $DIRECTORY.'/archives/'.$list->get_domain.'/'.$list->get_localpart.'/'.$year.'/'.$month.'/'.$day;
	File::Path::make_path( $directory, { error => \my $errors }) unless -d $directory;

    my $file = $directory.'/'.$message_id;
    open( FILE , '>'.$file);
    print FILE $mail->as_string;
    close( FILE );
}


sub put_in_moderation
{
    my $mail = shift;
    my $list = shift;
    my @tos;
    my $members = $list->get_members;
    my $header;
    my $email;
    my ( $message_id  ) =  ($mail->get( 'Message-Id' ) =~ /<(.+)>/);
    my ( $from ) = ( $mail->get('From') =~ /([^\s\@<"]+\@[^">\@\s]+)>?[^\@]*$/ );
    $from = lc $from;
    my $directory = get_moderation_dir( $list );
    my $subject = $mail->get('Subject');

	File::Path::make_path( $directory, { error => \my $errors }) unless -d $directory;

    my $filehash = Digest::MD5::md5_hex( $message_id );
    my $file = $directory.'/'.$filehash;

    open( FILE , '>'.$file);
    print FILE $mail->as_string;
    close( FILE );

    foreach ( keys %{$members} )
    {
	#Prepare the destinataire for the mail
	push( @tos , $_ ) if( $members->{$_}{'perm'} == Vhffs::Constants::ML_RIGHT_ADMIN );
    }

    $header = new Mail::Header( );
    $header->replace( 'From' ,  $LISTMASTER );
    $header->replace( 'To' ,  join(', ' , @tos) );
    $header->replace( 'Subject' ,  'moderate '.$filehash );
    $header->replace( 'Reply-To' , $list->get_listrequestname );

    $email = Mail::Internet->new(  [ <> ]  ,
				   Header => $header,
				   Body => Vhffs::Listengine::mail_moderate_message( $list , $filehash , $from , $subject )
				   );

    sendmail( $email , \@tos );
}


sub subscribe_to_list
{
    my $list = shift;
    my $from = shift;
    my $header;
    my $email;
    my $message;
    my @body;

    my $sub_ctrl = $list->get_sub_ctrl;

    if( $sub_ctrl == Vhffs::Constants::ML_SUBSCRIBE_CLOSED )
    {
	$message = 'Subscription are not allowed for this list';
	push @body , $message ;
	push @body , "\n";

	$header = new Mail::Header( );
	$header->replace( 'To' ,  $from );
	$header->replace( 'From' ,  $LISTMASTER );

	my $subject = 'subscription denied';
	$subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
	$header->replace( 'Subject' ,  $subject );

	$email = Mail::Internet->new(  [ <> ] ,
				       Header => $header ,
				       Body => Vhffs::Listengine::mail_sub_deny( $list , $from )
				       );
    }
    else
    {
	if( defined ( my $pass = $list->add_sub_with_reply( $from ) ) )
	{
	    $header = new Mail::Header( );
	    $header->replace( 'To' ,  $from );
	    $header->replace( 'From' ,  $LISTMASTER );
	    my $subject = 'confirm subscribe '.$pass;
	    $subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
	    $header->replace( 'Subject' ,  $subject );
	    $header->replace( 'Reply-To' , $list->get_listrequestname);

	    $email = Mail::Internet->new(  [ <> ]  ,
					   Header => $header,
					   Body => Vhffs::Listengine::mail_new_sub( $list , $from , $pass )
					   );
	}
	else
	{
	    $header = new Mail::Header( );
	    $header->replace( 'To' ,  $from );
	    $header->replace( 'From' ,  $LISTMASTER );
	    my $subject = 'You are already subscribed to this list';
	    $subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
	    $header->replace( 'Subject' ,  $subject );

	    $email = Mail::Internet->new(  [ <> ]  ,
					   Header => $header,
					   Body => Vhffs::Listengine::mail_sub_already_exist( $list , $from )
					   );
	}
    }

    sendmail( $email , $from );
}


sub unsubscribe_to_list
{
    my $list = shift;
    my $from = shift;
    my $hash;
    my $email;

    if( defined ( $hash = $list->del_sub_with_reply( $from ) ) )
    {

	my $header = new Mail::Header( );

	$header->replace( 'To' ,  $from );
	$header->replace( 'From' ,  $LISTMASTER );



	if( ( $hash == -1 ) || ( $hash == -2 ) )
	{
	    $header->replace( 'Subject' ,  'error while unsubscribe' );
	    $email = Mail::Internet->new(  [ <> ] ,
					   Header => $header ,
					   Body => Vhffs::Listengine::mail_sub_not_exist( $list , $from )
					   );
	}
	elsif( $hash == -3 )
	{
	    $header->replace( 'Subject' ,  'Error while unsubscribe' );
	    #If $hash == -3, the subscriber was not a subscriber or admin but has different rights (waiting for confirm ...)
	    $email = Mail::Internet->new(  [ <> ] ,
					      Header => $header ,
					      Body => Vhffs::Listengine::mail_error_unsub( $list , $from , $hash )
					      );
	}
	else
	{
	    $header->replace( 'Subject' ,  'confirm unsubscribe '.$hash );
	    $header->replace( 'Reply-To' , $list->get_listrequestname);

	    $email = Mail::Internet->new(  [ <> ] ,
					   Header => $header ,
					   Body => Vhffs::Listengine::mail_new_unsub( $list , $from , $hash )
					   );
	}
	sendmail( $email , $from );
    }
}


sub confirm_sub
{
    my $list = shift;
    my $from = shift;
    my $hash = shift;

    my $subs = $list->get_members;

    # Check if subscription exists and the subscriber is waiting for reply and taht the hash is valid
    if( ( defined $subs->{$from} ) && ( $subs->{$from}{'perm'} == Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_REPLY ) && ( $hash eq $subs->{$from}{'hash'} ) )
    {
		my $header = new Mail::Header( );
		$header->replace( 'To' ,  $from );
		$header->replace( 'From' ,  $LISTMASTER );
		my $subject = 'Successfully subscribed';
		$subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
		$header->replace( 'Subject' , $subject );
		$header->replace('Date' , datetime_rfc2822() );

		# validation needed or not ?
		if( $list->get_sub_ctrl == Vhffs::Constants::ML_SUBSCRIBE_APPROVAL_REQUIRED )  {

			my $email = Mail::Internet->new(  [ <> ] ,
				Header => $header ,
				Body => Vhffs::Listengine::mail_confirm_sub_approvalneeded( $list , $from )
				);

			$list->change_right_for_sub( $from , Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_VALIDATION );
			my $pass = $list->set_randomhash ( $from );
			sendmail( $email , $from );

			my @tos;
			my $members = $list->get_members;

			# send a mail to all admins
			foreach ( keys %{$members} )
			{
				push( @tos , $_ ) if( $members->{$_}{perm} == Vhffs::Constants::ML_RIGHT_ADMIN );
			}

			my $header = new Mail::Header( );
			$header->replace( 'From' ,  $LISTMASTER );
			$header->replace( 'To' ,  join(', ' , @tos) );
			my $subject = 'approval '.$from;
			$subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
			$header->replace( 'Subject' , $subject );
			$header->replace( 'Reply-To' , $list->get_listrequestname);

			$email = Mail::Internet->new(  [ <> ]  ,
				   Header => $header,
				   Body => Vhffs::Listengine::mail_moderate_subscriber( $list , $from , $pass )
				   );

			sendmail( $email , \@tos );
		}
		else  {

			my $email = Mail::Internet->new(  [ <> ] ,
				Header => $header ,
				Body => Vhffs::Listengine::mail_confirm_sub( $list , $from )
				);

			$list->change_right_for_sub( $from , Vhffs::Constants::ML_RIGHT_SUB );
			$list->clear_hash( $from );
			sendmail( $email , $from );
		}
	}
	else
	{
	    my $header = new Mail::Header( );
	    $header->replace( 'To' ,  $from );
	    $header->replace( 'From' ,  $LISTMASTER );
	    my $subject = 'Subscribe error';
	    $subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
	    $header->replace( 'Subject' , $subject );
    	    $header->replace('Date' , datetime_rfc2822() );

	    my $email = Mail::Internet->new(  [ <> ] ,
					      Header => $header ,
					      Body => Vhffs::Listengine::mail_error_sub( $list , $from )
					      );
	    sendmail( $email , $from );
    }
}

sub confirm_unsub
{
    my $list = shift;
    my $from = shift;
    my $hash = shift;
    my $email;
    my $header;
    my $subs = $list->get_members;

    #Check if subscription exists
    if( ( defined $subs->{$from} ) && ( $subs->{$from}{'perm'} == Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_DEL ) )
    {
	# Ok, hash are the same, treat the mail now and delete the subscriber from the list
	if( $hash eq $subs->{$from}{'hash'} )
	{

	    $header = new Mail::Header( );
	    $header->replace( 'To' ,  $from );
	    $header->replace( 'From' ,  $LISTMASTER );
	    $header->replace( 'Subject' , 'Successfully unsubscribe' );
    	    $header->replace('Date' , datetime_rfc2822() );


	    $email = Mail::Internet->new(  [ <> ] ,
					   Header => $header ,
					   Body => Vhffs::Listengine::mail_unsub_success( $list )
					   );
	    sendmail( $email , $from );

	    $list->del_sub( $from );

	}
	else
	{
	    #Here, hash are not the same, so, we return an error
	    $header = new Mail::Header( );
	    $header->replace( 'To' ,  $from );
	    $header->replace( 'From' ,  $LISTMASTER );
	    $email = Mail::Internet->new(  [ <> ] ,
					   Header => $header ,
					   Body => Vhffs::Listengine::mail_error_unsub_hash( $list )
					   );
	}

    }
}


sub sub_accept
{
    my $list = shift;
    my $from = shift;
    my $subscriber = shift;
    my $hash = shift;

    my $subs = $list->get_members;

    # Check if subscription exists and the subscriber is waiting for approval and that the hash is valid
    if( ( defined $subs->{$from} ) && ( $subs->{$from}{'perm'} == Vhffs::Constants::ML_RIGHT_ADMIN ) && ( defined $subs->{$subscriber} ) && ( $subs->{$subscriber}{'perm'} == Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_VALIDATION ) && ( $subs->{$subscriber}{'hash'} eq $hash ) )
    {
		#send a mail to the subscriber
		my $header = new Mail::Header( );
		$header->replace( 'To' ,  $subscriber );
		$header->replace( 'From' ,  $LISTMASTER );
		my $subject = 'Subscription accepted';
		$subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
		$header->replace( 'Subject' , $subject );
		$header->replace('Date' , datetime_rfc2822() );

		my $email = Mail::Internet->new(  [ <> ] ,
			Header => $header ,
			Body => Vhffs::Listengine::mail_moderate_subscription_accepted( $list , $from )
			);

		$list->change_right_for_sub( $subscriber , Vhffs::Constants::ML_RIGHT_SUB );
		$list->clear_hash( $subscriber );
		sendmail( $email , $subscriber );

		#send a mail to all admins
		my @tos;
		my $members = $list->get_members;

		# send a mail to all admins
		foreach ( keys %{$members} )
		{
			push( @tos , $_ ) if( $members->{$_}{'perm'} == Vhffs::Constants::ML_RIGHT_ADMIN );
		}

		$header = new Mail::Header( );
		$header->replace( 'From' ,  $LISTMASTER );
		$header->replace( 'To' ,  join(', ' , @tos) );
		$subject = 'Subscription approval confirmation '.$from;
		$subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
		$header->replace( 'Subject' , $subject );

		$email = Mail::Internet->new(  [ <> ]  ,
			   Header => $header,
			   Body => Vhffs::Listengine::mail_moderate_subscription_accept_ack( $list , $subscriber )
			   );

		sendmail( $email , \@tos );
    }
    else
    {
	    my $header = new Mail::Header( );
	    $header->replace( 'To' ,  $from );
	    $header->replace( 'From' ,  $LISTMASTER );
	    my $subject = 'Subscription moderation error';
	    $subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
	    $header->replace( 'Subject' , $subject );
    	    $header->replace('Date' , datetime_rfc2822() );

	    my $email = Mail::Internet->new(  [ <> ] ,
					      Header => $header ,
					      Body => Vhffs::Listengine::mail_moderate_subscription_error( $list , $subscriber )
					      );
	    sendmail( $email , $from );
    }
}


sub sub_refuse
{
    my $list = shift;
    my $from = shift;
    my $subscriber = shift;
    my $hash = shift;

    my $subs = $list->get_members;

    # Check if subscription exists and the subscriber is waiting for approval and that the hash is valid
    if( ( defined $subs->{$from} ) && ( $subs->{$from}{'perm'} == Vhffs::Constants::ML_RIGHT_ADMIN ) && ( defined $subs->{$subscriber} ) && ( $subs->{$subscriber}{'perm'} == Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_VALIDATION ) && ( $subs->{$subscriber}{'hash'} eq $hash ) )
    {
		#send a mail to the subscriber
		my $header = new Mail::Header( );
		$header->replace( 'To' ,  $subscriber );
		$header->replace( 'From' ,  $LISTMASTER );
		my $subject = 'Subscription refused';
		$subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
		$header->replace( 'Subject' , $subject );
		$header->replace('Date' , datetime_rfc2822() );

		my $email = Mail::Internet->new(  [ <> ] ,
			Header => $header ,
			Body => Vhffs::Listengine::mail_moderate_subscription_refused( $list , $from )
			);

		$list->del_sub( $subscriber );
		sendmail( $email , $subscriber );

		#send a mail to all admins
		my @tos;
		my $members = $list->get_members;

		# send a mail to all admins
		foreach ( keys %{$members} )
		{
			push( @tos , $_ ) if( $members->{$_}{'perm'} == Vhffs::Constants::ML_RIGHT_ADMIN );
		}

		$header = new Mail::Header( );
		$header->replace( 'From' ,  $LISTMASTER );
		$header->replace( 'To' ,  join(', ' , @tos) );
		$subject = 'Subscription approval confirmation '.$from;
		$subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
		$header->replace( 'Subject' , $subject );

		$email = Mail::Internet->new(  [ <> ]  ,
			   Header => $header,
			   Body => Vhffs::Listengine::mail_moderate_subscription_refuse_ack( $list , $subscriber )
			   );

		sendmail( $email , \@tos );
    }
    else
    {
	    my $header = new Mail::Header( );
	    $header->replace( 'To' ,  $from );
	    $header->replace( 'From' ,  $LISTMASTER );
	    my $subject = 'Subscription moderation error';
	    $subject = '['.$list->get_prefix.'] '.$subject if( length( $list->get_prefix ) > 0 );
	    $header->replace( 'Subject' , $subject );
    	    $header->replace('Date' , datetime_rfc2822() );

	    my $email = Mail::Internet->new(  [ <> ] ,
					      Header => $header ,
					      Body => Vhffs::Listengine::mail_moderate_subscription_error( $list , $subscriber )
					      );
	    sendmail( $email , $from );
    }
}




#Change some mail headers and send it to each subscriber
sub sendmail_to_list
{
	my $mail = shift;
	my $list = shift;
	my $subs = $list->get_members;

	my @tos;

	add_list_header( $mail , $list );

	# Add prefix if not null
	my $prefix = $list->get_prefix;
	if( length( $prefix ) > 0 ) {
		my $subject = $mail->get('Subject');
		my $tsubject = Encode::decode('MIME-Header', $subject);
		$tsubject =~ s/[\n\r]//g;
		my $qprefix = quotemeta $prefix;
		$mail->replace( 'Subject' , '['.$prefix.'] '.$subject ) unless ( $tsubject =~ /\[$qprefix\]/ );
	}

	# Add list's signature at the bottom of mail
	if(defined(my $signature = $list->get_signature)) {
		my $body = $mail->body;
		push @$body, '-- '."\n".$signature."\n";
	}

	foreach ( keys %{$subs} )
	{
		#Send mail to user if he is a confirmed subscriber
		push( @tos , $_ ) if( $subs->{$_}{'perm'} != Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_REPLY  &&  $subs->{$_}{'member'} ne $list->get_listname );
	}

	sendmail( $mail , \@tos );
	archive_it( $mail , $list );
}


sub bounce_mail
{
	my $mail = shift;
	my $list = shift;

	exit -1 if( ! defined $list );

	my ( $from ) = ( $mail->get('From') =~ /([^\s\@<"]+\@[^">\@\s]+)>?[^\@]*$/ );
        $from = lc $from;
	my $subject = $mail->get('Subject');
	my $subs = $list->get_members;

	# we need to know if the sender is a member, an admin, or other
	my $user_class = 'other';  #assume other
	$user_class = 'member' if( defined $subs->{$from}  &&  $subs->{$from}{'perm'} == Vhffs::Constants::ML_RIGHT_SUB );
	$user_class = 'admin' if( defined $subs->{$from}  &&  $subs->{$from}{'perm'} == Vhffs::Constants::ML_RIGHT_ADMIN );

	my $post_ctrl = $list->get_post_ctrl;

	if( $user_class eq 'admin'  ||  $post_ctrl == Vhffs::Constants::ML_POSTING_OPEN_ALL )  {
		sendmail_to_list( $mail , $list );
	}
	elsif ( $user_class eq 'member' )  {
		if( $post_ctrl == Vhffs::Constants::ML_POSTING_MEMBERS_ONLY  ||  $post_ctrl == Vhffs::Constants::ML_POSTING_OPEN_MEMBERS_MODERATED_OTHERS ) {
			sendmail_to_list( $mail , $list )
		} elsif ( $post_ctrl == Vhffs::Constants::ML_POSTING_MODERATED_ALL  ||  $post_ctrl == Vhffs::Constants::ML_POSTING_MEMBERS_ONLY_MODERATED ) {
			put_in_moderation( $mail , $list );
		}
	}
	elsif ( $user_class eq 'other' )  {
		if( $post_ctrl == Vhffs::Constants::ML_POSTING_MODERATED_ALL  ||  $post_ctrl == Vhffs::Constants::ML_POSTING_OPEN_MEMBERS_MODERATED_OTHERS ) {
			put_in_moderation( $mail , $list );	
		}
	}
}


sub get_moderation_dir
{
    my $list = shift;
    return( $DIRECTORY . '/moderation/' . $list->get_domain . '/' . $list->get_localpart  );
}

sub validate_message
{
    my $list = shift;
    my $hash = shift;
    my @tempmail;
    chomp( $hash );
    my $dir  = get_moderation_dir( $list );
    my $file = $dir . '/' . $hash;

    return -1 if( ! -d $dir );
    return -2 if( ! -f $file );

    open( MODERATION , $file ) or return -2;

    while( <MODERATION> )
    {
	push( @tempmail , $_ );
    }
    close( MODERATION );


    return -3 if( unlink( $file ) <= 0 );

    my $m = Mail::Internet->new( \@tempmail );

    sendmail_to_list( $m , $list );

    return 1;
}


sub refuse_message
{
    my $list = shift;
    my $hash = shift;
    chomp( $hash );
    my $dir  = get_moderation_dir( $list );
    my $file = $dir . '/' . $hash;
    return -1 if( ! -d $dir );
    return -2 if( ! -f $file );


    return -1 if( unlink( $file ) == 0 );


    return 1;
}


sub list_msg_to_moderate{
    my $list = shift;
    my $dir = get_moderation_dir( $list );
    my @result;
    my @files;
    my $file;
    my $complete;
    my $mail;

    if( ! -d $dir )
    {
	push( @result , gettext('No message to moderate') );
	push( @result , "\n" );
    }
    else
    {
	opendir( DIR , $dir );
	@files = readdir( DIR );

	foreach $file ( @files )
	{
	    next if( ( $file eq '.' ) || ( $file eq '..' ) );
	    $complete = $dir . '/' . $file ;

	    if( -f $complete )
	    {
		$mail = fetch_mail_from_file( $complete );
		next if( ! defined $mail );
	
		push( @result , 'Sender: ' . $mail->get('From:') );
		push( @result , 'Subject: ' . $mail->get('Subject:') );
		push( @result , 'Id in listengine: ' . $file );
		push( @result , "\n\n");
	    }
	}

	closedir( DIR );
    }

    return( \@result );

}

################
# Get body of a message waiting for moderation in order to check content
#
# This function handle request letmecheck hash sent to list-request@domain.tld
#################################
sub letmecheck_message{
	my $list = shift;
	my $hash = shift;
	my $path = get_moderation_dir( $list ).'/'.$hash;
	my @result;
	unless( -f $path ) {
		push( @result, gettext('No message found or it was already moderated by someone else') );
		push( @result, "\n" );
	} else {
		my $mail = fetch_mail_from_file( $path );
	
		push( @result, 'This is the message you requested to check');
		push( @result, 'From: ' . $mail->get('From:') );
		push( @result, 'Subject: ' . $mail->get('Subject:') );
		push( @result, 'Listengine ID: ' . $hash );
		push( @result, 'Body:'."\n" . $mail->body );
		push( @result, "\n\n".'---------------------------------------------------------------------'."\n\n" );
		push( @result, 'To accept this message send : moderate accept'.$hash.' in subject to '.$list->get_listrequestname );
		push( @result, 'To refuse this message send : moderate refuse'.$hash.' in subject to '.$list->get_listrequestname );
		push( @result, "\n\n");
	}
	return( \@result );
}


#################
# Treat a mail that seems ok
#
# This function treat request, sended to list-request@domain.tld
#################################
sub treat_request
{
    my $mail = shift;
    my $list = shift;

    my ( $from ) = ( $mail->get('From') =~ /([^\s\@<"]+\@[^">\@\s]+)>?[^\@]*$/ );
    $from = lc $from;
    my $subject = $mail->get('Subject');
    my $action;
    my $subscriber;
    my $hash;
    my $email;
    my $header;
    my $lang;
    my $temp;
    my $members = $list->get_members;

	$lang = Vhffs::Services::MailingList::get_language_for_sub( $vhffs , $from );
	#If the user specified a lang, we change it to get internationalized messages
	if( defined $lang )
	{
		bindtextdomain('vhffs', '%localedir%');
		textdomain('vhffs');
	}



    if( $subject =~ /^help$/i )
    {
		$email = Mail::Internet->new( [ <> ],
			     Body => Vhffs::Listengine::mail_generate_help
			     );
		$email->replace('From' ,  $LISTMASTER );
		$email->replace('To' ,  $from );
		$email->replace('Subject' , gettext('listengine help') );
    	$email->replace('Date' , datetime_rfc2822() );
		sendmail( $email , $from );
    }
    elsif( $subject =~ /^subscribe$/i )
    {
		subscribe_to_list( $list , $from );
    }
    elsif( $subject =~ /^unsubscribe$/i )
    {
		unsubscribe_to_list( $list , $from );
    }
    elsif( ( $lang ) = $subject =~ /^lang\s([a-zA-Z\_\-]+)$/i )
    {
	#Try to change the language for this subscriber on whole listengine subsystem
	unless( Vhffs::Services::MailingList::set_language_for_sub( $vhffs , $from , $lang ) )
	{
		$email = Mail::Internet->new( [ <> ],
					 Body => Vhffs::Listengine::mail_lang_change_error( $from , $lang )
					 );
		$email->replace('From' ,  $LISTMASTER );
		$email->replace('To' ,  $from );
		$email->replace('Subject' , gettext('listengine help') );
		$email->replace('Date' , datetime_rfc2822() );
		sendmail( $email , $from );
	}
	else
	{
	    $email = Mail::Internet->new( [ <> ],
					 Body => Vhffs::Listengine::mail_lang_change_success( $from , $lang )
					 );
	    $email->replace('From' ,  $LISTMASTER );
	    $email->replace('To' ,  $from );
	    $email->replace('Subject' , gettext('listengine help') );
    	    $email->replace('Date' , datetime_rfc2822() );
	    sendmail( $email , $from );
	}
    }
    elsif( ( $temp ) = $subject =~ /[.\s]*moderate\s([a-zA-Z0-9\s]+)$/i )
    {
	#To moderate messages, users must be at least ADMIN
	#So, we check this NOW
	if( $members->{$from}{perm} != Vhffs::Constants::ML_RIGHT_ADMIN )
	{
	    $email = Mail::Internet->new( [ <> ],
					 Body => Vhffs::Listengine::mail_not_allowed( $list , $from )

					 );
	    $email->replace('From' ,  $LISTMASTER );
	    $email->replace('To' ,  $from );
	    $email->replace('Subject' , gettext('listengine result command') );
    	    $email->replace('Date' , datetime_rfc2822() );
	    sendmail( $email , $from );

	}
	elsif( ( $hash ) = $temp =~ /accept\s([a-zA-Z0-9]+)$/i )
	{

	    if( validate_message( $list , $hash , $from ) < 0 )
	    {
		$email = Mail::Internet->new( [ <> ],
					     Body => Vhffs::Listengine::mail_moderate_error( $list , $hash )
					     );
		$email->replace('From' ,  $LISTMASTER );
		$email->replace('To' ,  $from );
		$email->replace('Subject' , gettext('listengine moderation') );
    	        $email->replace('Date' , datetime_rfc2822() );
		sendmail( $email , $from );
	    }
	    else
	    {
		$email = Mail::Internet->new( [ <> ],
					     Body => Vhffs::Listengine::mail_moderate_success( $list , $hash )
					     );
		$email->replace('From' ,  $LISTMASTER );
		$email->replace('To' ,  $from );
		$email->replace('Subject' , gettext('listengine moderation') );
    	        $email->replace('Date' , datetime_rfc2822() );
		sendmail( $email , $from );
	    }

	}
	elsif( ( $hash ) = $temp =~ /refuse\s([a-zA-Z0-9]+)$/i )
	{
	    #Here, we refuse the message
	    if( refuse_message( $list , $hash , $from ) < 0 )
	    {
		$email = Mail::Internet->new( [ <> ],
					     Body => Vhffs::Listengine::mail_refuse_error( $list , $hash )
					     );
		$email->replace('From' ,  $LISTMASTER );
		$email->replace('To' ,  $from );
		$email->replace('Subject' , gettext('listengine moderation') );
    	        $email->replace('Date' , datetime_rfc2822() );
		sendmail( $email , $from );
		return;
	    }
	    else
	    {
		$email = Mail::Internet->new( [ <> ],
					     Body => Vhffs::Listengine::mail_refuse_success( $list , $hash )
					     );
		$email->replace('From' ,  $LISTMASTER );
		$email->replace('To' ,  $from );
		$email->replace('Subject' , gettext('listengine moderation') );
    	        $email->replace('Date' , datetime_rfc2822() );
		sendmail( $email , $from );
	    }
	    return;
	}
	elsif( $temp =~ /^list$/i )
	{
	    $email = Mail::Internet->new( [ <> ],
					 Body => list_msg_to_moderate( $list )
					 );
	    $email->replace('From' ,  $LISTMASTER );
	    $email->replace('To' ,  $from );
	    $email->replace('Subject' , sprintf( gettext('listengine - list of messages to moderate for %s') , $list->get_listname  ) );
    	    $email->replace('Date' , datetime_rfc2822() );
	    sendmail( $email , $from );
	    return;
	}
	elsif( $temp =~ /^[a-zA-Z0-9]+$/i )
	{
	    if( validate_message( $list , $temp , $from ) < 0 )
	    {
		$email = Mail::Internet->new( [ <> ],
					     Body => Vhffs::Listengine::mail_moderate_error( $list , $temp )
					     );
		$email->replace('From' ,  $LISTMASTER );
		$email->replace('To' ,  $from );
		$email->replace('Subject' , gettext('listengine moderation') );
    	        $email->replace('Date' , datetime_rfc2822() );
		sendmail( $email , $from );
	    }
	    else
	    {
		$email = Mail::Internet->new( [ <> ],
					     Body => Vhffs::Listengine::mail_moderate_success( $list , $temp )
					     );
		$email->replace('From' ,  $LISTMASTER );
		$email->replace('To' ,  $from );
		$email->replace('Subject' , gettext('listengine moderation') );
    	        $email->replace('Date' , datetime_rfc2822() );
		sendmail( $email , $from );
	    }
	}
    }
    elsif( ( ( $action , $hash ) = $subject =~ /[.\s]*confirm\s([a-zA-Z0-9]+)\s(.+)$/i ) )
    {
		if( $action =~ /^subscribe$/i )
		{
		    #Here, this is a confirmation a subscribing
		    confirm_sub( $list , $from , $hash );
		}
		elsif( $action =~ /^unsubscribe$/i )
		{
		    #It's a confirmation to unsubscribe
		    confirm_unsub( $list , $from , $hash );
		}

    }
    elsif( ( ( $action , $subscriber , $hash ) = $subject =~ /^.*subscription[.\s]([a-z]+)\s([a-z0-9\_\-\.]+@[a-z0-9\-\.]+)\s([a-zA-Z0-9]+)(.*)$/i ) )
    {
		if( $action =~ /^accept$/i )
		{
		    # Here, this is a validation of subscription
		    sub_accept( $list , $from , $subscriber , $hash );
		}
		elsif( $action =~ /^refuse$/i )
		{
		    # And here to deny it
		    sub_refuse( $list , $from , $subscriber , $hash );
		}

    }
	elsif( ( $temp ) = $subject =~ /[.\s]*letmecheck\s([a-zA-Z0-9\s]+)$/i ) {
		#To see message body to moderate, users must be at least ADMIN
		#So, we check this NOW
		if( $members->{$from}{perm} != Vhffs::Constants::ML_RIGHT_ADMIN ) {
			$email = Mail::Internet->new( [ <> ],
				Body => Vhffs::Listengine::mail_not_allowed( $list , $from )
				);
			$email->replace('From' , $LISTMASTER );
			$email->replace('To' , $from );
			$email->replace('Subject' , gettext('listengine result command') );
			$email->replace('Date' , datetime_rfc2822() );
			sendmail( $email , $from );
		} 
		elsif( ( $hash ) = $temp =~ /letmecheck\s([a-zA-Z0-9]+)$/i ) {
			$header = new Mail::Header( );
			$header->replace( 'From' , $LISTMASTER );
			$header->replace( 'To' , $from );
			$header->replace( 'Subject' , 'letmecheck response for message '.$hash );
			$header->replace( 'Reply-To' , $list->get_listrequestname ); 
			$email = Mail::Internet->new( [ <> ],
				Header => $header,
				Body => letmecheck_message( $list , $hash )
				);
			sendmail( $email, $from );
		}
	}    
    else
    {
		$mail = Mail::Internet->new( [ <> ],
			     Body => Vhffs::Listengine::mail_unknown_command( $list )
			     );
		$mail->replace('From' ,  $LISTMASTER );
		$mail->replace('To' ,  $from );
		$mail->replace('Subject' , gettext('listengine: unknown command') );
  	  	$mail->replace('Date' , datetime_rfc2822() );
		sendmail( $mail , $from );
    }

}


####################################
# Fetch the mail from standard input
#
# In fact, exim and others mail-server software give the mail
# through a pipe. So, the mail can be read by the standard input
###############
sub fetch_mail_from_stdin
{
	my @mail;
	my $line;

	# Wait for header
	while( $line = <STDIN> )  {
		last if( $line =~ /^[a-zA-Z0-9\-]+:\s.+$/ );
	}

	do {
		# handle dot on a line by itself if using batched smtp
		$line = '.'.$line if( defined $SENDMAIL_PATH  &&  $line =~ /^\./ );
		push( @mail , $line );
	}  while( $line = <STDIN> );

	return Mail::Internet->new( \@mail );
}

sub fetch_mail_from_file
{
    my @mail;
    my $passed;
    my $line;
    $passed = 0;

    my $file = shift;

    return -1 if( ! -f $file );

    open( FILE , $file ) or return -2;

    while( $line = <FILE> )
    {
	if( $passed == 0 )
	{
	    if( $line =~ /^[a-zA-Z0-9\-]+:\s.+$/ )
	    {
		$passed = 1;
		push( @mail , $line );
	    }
	}
	else
	{
	    push( @mail , $line );
	}
    }
   # my @mail = <STDIN>;
    my $m = Mail::Internet->new( \@mail );

    close( FILE ) or return -3;
    return $m;
}




#######################################
#Get language parameter for poster
#
#Internationalisation inside :-)
######################
sub get_lang
{
    my $mail = shift;
    my ( $from ) = ( $mail->get('From') =~ /([^\s\@<"]+\@[^">\@\s]+)>?[^\@]*$/ );
    $from = lc $from;

    my $lang = Vhffs::Services::MailingList::get_language_for_sub( $vhffs , $from );
    if( defined $lang )
    {
	#Change current locale to user preferences if defined
		bindtextdomain('vhffs', '%localedir%');
		textdomain('vhffs');
		setlocale(LC_ALL, $lang  );
    }
}


#####################################
# Verify if the mail is conform
#
##############################
sub verify_mail_with_list
{
	my $list = shift;
	my $mail = shift;

	my ( $from ) = ( $mail->get('From') =~ /([^\s\@<"]+\@[^">\@\s]+)>?[^\@]*$/ );
	exit( 0 ) unless defined $from;
	exit( 0 ) if( $from eq '' );

	$from = lc $from;
	#there is no reason to accept From set to the request address
	exit( 0 ) if( $from eq $list->get_listrequestname );
}





###############################
# Ok, the program begins here
###############################


#Fetch the mail
my $mail = fetch_mail_from_stdin();

#Get language for subscriber and change locale if settings exists
get_lang( $mail );

#Build the list object from VHFFS
my $list = Vhffs::Services::MailingList::get_by_mladdress( $vhffs , $lpart , $domain );
exit( 0 ) unless defined $list;
$list->fetch_subs;


verify_mail_with_list( $list , $mail );


####
# See what action to do with the list
if( $action eq 'bounce' )
{
    bounce_mail( $mail , $list  );
}
elsif( $action eq 'request' )
{
    treat_request( $mail , $list );
}
exit( 0 );
