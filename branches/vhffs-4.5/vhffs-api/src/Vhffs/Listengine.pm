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

package Vhffs::Listengine;

use strict;
use utf8;

use locale;
use Locale::gettext;

sub mail_generate_help {
	 my $list = shift;

	 my @result;
	 push( @result , gettext("Hello and welcome on listengine help\n" ));
	 push( @result , "\n" );
	 push( @result , gettext( "All commands can be sent as mail subject.\n" ) );
	 push( @result , gettext( "You can also send a command list in the mail body.\n" )  );
	 push( @result , gettext( "All mails with commands must be sent on YOURLIST-request\@domain.tld list.\n" ) );
	 push( @result , "\n" );
	 push( @result , gettext("Here are the basic listengine commands:\n") );
	 push( @result , gettext("help\t\t - show this help\n") );
	 push( @result , gettext("subscribe\t - subscribe the shipper to the list\n") );
	 push( @result , gettext("unsubscribe\t - unsubscribe from this list\n") );
	 push( @result , gettext("lang [fr|us|es]\t - set listengine language\n") );
	 push( @result , "\n" );
	 push( @result , gettext("Only this list administrators can use the following commands.\n" )  );
	 push( @result , gettext("subscription accept XXXXX\t\t - accept the subscription with key XXXXX\n" ) );
	 push( @result , gettext("subscription refuse XXXXX\t\t - refuse the subscription with key XXXXX\n" ) );
	 push( @result , gettext("moderate XXXXX\t\t\t - accept the message with message-id XXXXX\n" )  );
	 push( @result , gettext("moderate accept XXXXX\t\t\t - accept the message with message-id XXXXX\n" ) );
	 push( @result , gettext("moderate refused XXXXX\t\t\t - refuse the message with message-id XXXXX\n" ) );
	 push( @result , gettext("moderate list\t\t\t - give the message list for moderation\n" ) );
	 push( @result , gettext("user unsubscribe user\@domain.tld\t - delete user user\@domain.tld from list\n") );
	 push( @result , gettext("user subscribe user\@domain.tld\t\t - register the user user\@domain.tld on the list\n") );
	 push( @result , gettext("user right RIGHT user\@domain.tld\t - change right for this user\n") );
	 push( @result , gettext("\t\t\t\t   RIGHT can be subscriber or admin\n") );
	 push( @result , gettext("user info user\@domain.tld\t\t - show user information\n") );

	 push( @result , "\n" );

	 return( \@result );
}

sub mail_new_sub {
	 my $list = shift;
	 my $from = shift;
	 my $pass = shift;
	 my @result;

	 push( @result , sprintf( "You sent a request to be subscribed to the following mailing list:\n  %s\n\nWith the following email:\n  %s\n\n" , $list->get_listname , $from ) );
	 push( @result , gettext( "You must confirm your request by sending a confirmation email\n")  );
	 push( @result , sprintf( gettext( "This mail must have the following subject : \"confirm subscribe %s\"\nOn most clients it should work by just replying this email\n")  , $pass ) );
	 push( @result , "\n" );
	 push( @result , gettext( "If you don't asked to be subscribed to this mailing list,\njust forget this email\n" ) );
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_new_unsub {
	 my $list = shift;
	 my $from = shift;
	 my $hash = shift;
	 my @result;

	 push( @result , sprintf( "You asked to be removed from the following list:\n\n%s\n\n" , $list->get_listname) );
	 push( @result , gettext( "You must confirm your request by sending a confirmation email\n")  );
	 push( @result , sprintf( gettext( "This mail must contains the following subject : \"confirm unsubscribe %s\"\n")  , $hash ) );
	 push( @result , "\n" );
	 push( @result , gettext( "If you haven't asked to be unsubscribed from this list,\nplease don't answer to this mail\n" ) );
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_sub_already_exist {
	 my $list = shift;
	 my $from = shift;
	 my @result;

	 push( @result , sprintf( gettext( "You asked to be subscribed to the following list:\n\n%s\n\n" ) , $list->get_listname) );
	 push( @result , sprintf( gettext( "However you are (%s) already subscribed to this list.\n")  , $from ) );
	 push( @result , "\n" );
	 push( @result , gettext( "The state of you subscription was not changed, you are still subscribed\n") );
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_sub_deny {
	 my $list = shift;
	 my $from = shift;
	 my @result;

	 push( @result , sprintf( gettext( "Subscription to the following list is forbidden:\n  %s\n\nHave a nice day.\n" ) , $list->get_listname) );

	 return( \@result );
}

sub mail_confirm_sub {
	 my $list = shift;
	 my $from = shift;
	 my @result;

	 push( @result , sprintf( gettext( "You have been successfully subscribed to the following mailing list:\n  %s\n" ) , $list->get_listname) );
	 push( @result , "\n" );
	 push( @result , gettext( "You may get some help on listengine by sending an email to\n") );
	 push( @result , sprintf( gettext( "%s-request\@%s with subject \"help\"\n")  , $list->get_localpart , $list->get_domain ) );
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_confirm_sub_approvalneeded {
	 my $list = shift;
	 my $from = shift;
	 my @result;

	 push( @result , sprintf( gettext( "You have been successfully subscribed to the following mailing list:\n  %s\n" ) , $list->get_listname) );
	 push( @result , "\n" );
	 push( @result , gettext( "However this list require approval for new subscribers.\n") );
	 push( @result , gettext( "You will receive an email with the decision of administrators.\n") );
	 push( @result , "\n" );
	 push( @result , gettext( "You may get some help on listengine by sending an email to\n") );
	 push( @result , sprintf( gettext( "%s-request\@%s with subject \"help\"\n")  , $list->get_localpart , $list->get_domain ) );
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_confirm_unsub {
	 my $list = shift;
	 my $from = shift;
	 my @result;

	 push( @result , sprintf( gettext( "You have been successfully removed from the following list:\n  %s\n" ) , $list->get_listname) );

	 return( \@result );
}

sub mail_error_sub {
	 my $list = shift;
	 my $from = shift;
	 my @result;

	 push( @result , sprintf( gettext( "An error occured during your subscription to the following list:\n  %s\n\n" ) , $list->get_listname) );
	 push( @result , gettext("The confirmation code was wrong\n" ));
	 push( @result , gettext("Please try again !\n" ));
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_sub_not_exist {
	 my $list = shift;
	 my $from = shift;

	 my @result;

	 push( @result , sprintf( gettext( "The following address %s is not on the following mailing list:\n  %s\n" ) , $from , $list->get_listname) );
	 push( @result , gettext("You demand was refused\n" ));

	 push( @result , "\n" );

	 return( \@result );
}

sub mail_error_unsub {
	 my $list = shift;
	 my $from = shift;

	 my @result;

	 push( @result , sprintf( gettext( "You cannot unsubscribe from the list %s\n" ) , $list->get_listname) );
	 push( @result , gettext("You are not a subscriber on this list.\n" ));

	 push( @result , "\n" );

	 return( \@result );
}


sub mail_error_unsub_hash {
	 my $list = shift;
	 my @result;

	 push( @result , sprintf( gettext( "Unsubscribe for the list %s was not complete.\n" ) , $list->get_listname) );
	 push( @result , gettext("Confirmation code was wrong.\n" ));
	 push( @result , gettext("Please try again.\n" ));

	 push( @result , "\n" );

	 return( \@result );
}


sub mail_unsub_success {
	 my $list = shift;
	 my @result;

	 push( @result , sprintf( gettext( "You have been successfully removed from the list %s.\n" ) , $list->get_listname) );

	 push( @result , "\n" );

	 return( \@result );
}


sub mail_lang_change_success {
	 my $list = shift;
	 my $from = shift;
	 my $lang = shift;
	 my @result;

	 push( @result , sprintf( gettext( "The listengine language preference was changed for the following address %s.\n" ) , $from) );
	 push( @result , sprintf( gettext( "New language is: %s\n" ) , $lang) );
	 push( @result , "\n" );

	 return( \@result );
}


sub mail_lang_change_error {
	 my $list = shift;
	 my $from = shift;
	 my $lang = shift;
	 my @result;

	 push( @result , sprintf( gettext( "An error occured while updating language for the following address: %s.\n" ) , $from) );
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_unknown_command {
	 my $list = shift;

	 my @result;

	 push( @result , gettext( "Unknow command\n\n" ) );
	 push( @result , gettext( "Please read help of listengine\n" )  );
	 push( @result , gettext( "Send an email with the subject \"help\" to the following address: \n" )  );
	 push( @result , sprintf( "%s-request\@%s" , $list->get_localpart , $list->get_domain) );
	 push( @result , "\n" );
	 push( @result , "---\n" );
	 push( @result , "Listengine 4.0\n" );

	 return( \@result );
}

sub mail_refuse_error {
	 my $list = shift;
	 my $hash = shift;

	 my @result;

	 push( @result , sprintf( gettext( "The message with the following id %s") , $hash ) );
	 push( @result , sprintf( gettext( "present in the moderation queue for the list %s") , $list->get_listname ) );
	 push( @result , gettext( "cannot be removed.\n" ) );
	 push( @result , gettext( "The message does not exists or was moderated before you.\n" ) );
	 push( @result , "\n" );
	 push( @result , "---\n" );
	 push( @result , "Listengine 4.0\n" );

	 return( \@result );
}

sub mail_refuse_success {
	 my $list = shift;
	 my $hash = shift;

	 my @result;

	 push( @result , sprintf( gettext( "Message with id: %s") , $hash ) );
	 push( @result , sprintf( gettext( "was removed from the moderation queue from the list %s") , $list->get_listname ) );
	 push( @result , "\n" );
	 push( @result , "---\n" );
	 push( @result , "Listengine 4.0\n" );

	 return( \@result );
}

sub mail_moderate_error {
	 my $list = shift;
	 my $hash = shift;

	 my @result;

	 push( @result , sprintf( gettext( "Message with id: %s") , $hash ) );
	 push( @result , sprintf( gettext( "present in the moderation queue for the list %s") , $list->get_listname ) );
	 push( @result , gettext( "cannot be removed from the list\n" ) );
	 push( @result , "\n" );
	 push( @result , "---\n" );
	 push( @result , "Listengine 4.0\n" );

	 return( \@result );
}

sub mail_moderate_success {
	 my $list = shift;
	 my $hash = shift;

	 my @result;

	 push( @result , sprintf( gettext( "Mail with id %s") , $hash ) );
	 push( @result , sprintf( gettext( "in the moderation queue of the list %s") , $list->get_listname ) );
	 push( @result , gettext( "was sent on the list.\n" ) );
	 push( @result , "\n" );
	 push( @result , "---\n" );
	 push( @result , "Listengine 4.0\n" );

	 return( \@result );
}

sub mail_not_allowed {
	 my $list = shift;
	 my $from = shift;

	 my @result;

	 push( @result , sprintf( gettext( "The following address %s is not allowed to execute commands on the list %s\n") , $from , $list->get_listname ) );
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_moderate_message {
	 my $list = shift;
	 my $hash = shift;
	 my $from = shift;
	 my $subject = shift;
	 my @result;

	 push( @result , sprintf( gettext( "A mail to moderate is on the following mailing list:\n  %s\n\n" ) , $list->get_listname) );
	 push( @result , sprintf( gettext( "This mail was sent by %s with the following subject:\n  %s\n\n" ) , $from, $subject) );
	 push( @result , sprintf( gettext( "To put this post on the list, send a message to:\n  %s-request\@%s\n" ) , $list->get_localpart , $list->get_domain) );
	 push( @result , sprintf( gettext( "with the following subject :\n  \"moderate %s\" \n" ) , $hash) );
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_moderate_subscriber {
	 my $list = shift;
	 my $from = shift;
	 my $pass = shift;
	 my @result;

	 push( @result , sprintf( gettext( "A new person wants to subscribe to the following mailing list:\n  %s\n\n" ) , $list->get_listname) );
	 push( @result , sprintf( gettext( "His email address is:\n  %s\n" ) , $from) );
	 push( @result , "\n" );
	 push( @result , gettext( "To accept this subscriber, send a message to\n" ) );
	 push( @result , sprintf( gettext( "  %s-request\@%s\nwith the following subject :\n  \"subscription accept %s %s\" \n" ) , $list->get_localpart , $list->get_domain , $from, $pass) );
	 push( @result , "\n" );
	 push( @result , gettext( "To refuse this subscriber, send a message to\n" ) );
	 push( @result , sprintf( gettext( "  %s-request\@%s\nwith the following subject :\n  \"subscription refuse %s %s\" \n" ) , $list->get_localpart , $list->get_domain , $from, $pass) );
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_moderate_subscription_accepted {
	 my $list = shift;
	 my $from = shift;
	 my @result;

	 push( @result , sprintf( gettext( "Your subscription was accepted to the following mailing list:\n  %s\n" ) , $list->get_listname) );
	 push( @result , "\n" );
	 push( @result , gettext( "You may get some help on listengine by sending an email to\n") );
	 push( @result , sprintf( gettext( "%s-request\@%s with subject \"help\"\n")  , $list->get_localpart , $list->get_domain ) );
	 push( @result , "\n" );

	 return( \@result );
}

sub mail_moderate_subscription_accept_ack {
	 my $list = shift;
	 my $subscriber = shift;
	 my @result;

	 push( @result , sprintf( gettext( "We confirm that you accepted the subscription of:\n  %s\n\nto the following mailing list:\n  %s\n\n") , $subscriber, $list->get_listname ) );

	 return( \@result );
}

sub mail_moderate_subscription_refused {
	 my $list = shift;
	 my $from = shift;
	 my @result;

	 push( @result , sprintf( gettext( "Your subscription was refused to the following mailing list:\n  %s\n\nHave a nice day.\n" ) , $list->get_listname) );

	 return( \@result );
}

sub mail_moderate_subscription_refuse_ack {
	 my $list = shift;
	 my $subscriber = shift;
	 my @result;

	 push( @result , sprintf( gettext( "We confirm that you REFUSED the subscription of:\n  %s\n\nto the following mailing list:\n  %s\n\n") , $subscriber, $list->get_listname ) );

	 return( \@result );
}

sub mail_moderate_subscription_error {
	 my $list = shift;
	 my $subscriber = shift;
	 my @result;

	 push( @result , sprintf( gettext( "An error occured during your approval of subscription of:\n  %s\ninto the following mailing list:\n  %s\n\n" ) , $subscriber, $list->get_listname) );

	 return( \@result );
}

1;
