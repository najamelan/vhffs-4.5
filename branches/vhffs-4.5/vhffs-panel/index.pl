#!%PERL% -w
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


require 5.004;
use utf8;
use POSIX;
use strict;
use locale;
use Locale::gettext;
#use CGI::Fast qw(:standard);
use CGI();
use CGI::Fast();
use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::Panel;

# -- prefork
CGI->compile();

my $vhffs = new Vhffs( { backend => 0 } );
exit 1 unless defined $vhffs;

$vhffs->connect;

# -- requests loop
while (my $cgi = new CGI::Fast) {

	$vhffs->reload_config;

	my $panel = new Vhffs::Panel( $vhffs, $cgi );
	next unless defined $panel;

	my $do = ( $cgi->url_param('do') or 'login' );

	# -- anonymous
	if( $do eq 'login' or $do eq 'lost' or $do eq 'subscribe' or $do eq 'logout' ) {
		if( $do eq 'login' ) {
			require Vhffs::Panel::Auth;
			Vhffs::Panel::Auth::login( $panel );
		} elsif( $do eq 'lost' ) {
			require Vhffs::Panel::Auth;
			Vhffs::Panel::Auth::lost( $panel );
		} elsif( $do eq 'subscribe' ) {
			require Vhffs::Panel::Subscribe;
			Vhffs::Panel::Subscribe::subscribe( $panel );
		} elsif( $do eq 'logout' ) {
			require Vhffs::Panel::Auth;
			Vhffs::Panel::Auth::logout( $panel );
		}

		next;
	}

	# -- session required
	my $session = ( $panel->get_session or next );

	if( $do eq 'contact' ) {
		require Vhffs::Panel::Contact;
		Vhffs::Panel::Contact::contact( $panel );
	} elsif( $do eq 'acl' ) {
		require Vhffs::Panel::Acl;
		Vhffs::Panel::Acl::acl( $panel );
	} elsif( $do eq 'objecthistory' ) {
		require Vhffs::Panel::Object;
		Vhffs::Panel::Object::history( $panel );
	} elsif( $do eq 'objectresubmit' ) {
		require Vhffs::Panel::Object;
		Vhffs::Panel::Object::resubmit( $panel );
	} elsif( $do eq 'objectcancel' ) {
		require Vhffs::Panel::Object;
		Vhffs::Panel::Object::cancel( $panel );
	} elsif( $do eq 'objectdelete' ) {
		require Vhffs::Panel::Object;
		Vhffs::Panel::Object::delete( $panel );
	} elsif( $do eq 'avatarget' ) {
		require Vhffs::Panel::Avatar;
		Vhffs::Panel::Avatar::get( $panel );
	} elsif( $do eq 'avatarput' ) {
		require Vhffs::Panel::Avatar;
		Vhffs::Panel::Avatar::put( $panel );
	} elsif( $do eq 'avatardelete' ) {
		require Vhffs::Panel::Avatar;
		Vhffs::Panel::Avatar::delete( $panel );
	} elsif( $do eq 'userprefs' ) {
		require Vhffs::Panel::User;
		Vhffs::Panel::User::prefs( $panel );
	} elsif( $do eq 'groupindex' ) {
		require Vhffs::Panel::Group;
		Vhffs::Panel::Group::index( $panel );
	} elsif( $do eq 'groupcreate' ) {
		require Vhffs::Panel::Group;
		Vhffs::Panel::Group::create( $panel );
	} elsif( $do eq 'groupview' ) {
		require Vhffs::Panel::Group;
		Vhffs::Panel::Group::view( $panel );
	} elsif( $do eq 'groupprefs' ) {
		require Vhffs::Panel::Group;
		Vhffs::Panel::Group::prefs( $panel );
	} elsif( $do eq 'grouphistory' ) {
		require Vhffs::Panel::Group;
		Vhffs::Panel::Group::history( $panel );
	} elsif( $do eq 'webcreate' ) {
		require Vhffs::Panel::Web;
		Vhffs::Panel::Web::create( $panel );
	} elsif( $do eq 'webprefs' ) {
		require Vhffs::Panel::Web;
		Vhffs::Panel::Web::prefs( $panel );
	} elsif( $do eq 'webindex' ) {
		require Vhffs::Panel::Web;
		Vhffs::Panel::Web::index( $panel );
	} elsif( $do eq 'mysqlcreate' ) {
		require Vhffs::Panel::Mysql;
		Vhffs::Panel::Mysql::create( $panel );
	} elsif( $do eq 'mysqlprefs' ) {
		require Vhffs::Panel::Mysql;
		Vhffs::Panel::Mysql::prefs( $panel );
	} elsif( $do eq 'mysqlindex' ) {
		require Vhffs::Panel::Mysql;
		Vhffs::Panel::Mysql::index( $panel );
	} elsif( $do eq 'pgsqlcreate' ) {
		require Vhffs::Panel::Pgsql;
		Vhffs::Panel::Pgsql::create( $panel );
	} elsif( $do eq 'pgsqlprefs' ) {
		require Vhffs::Panel::Pgsql;
		Vhffs::Panel::Pgsql::prefs( $panel );
	} elsif( $do eq 'pgsqlindex' ) {
		require Vhffs::Panel::Pgsql;
		Vhffs::Panel::Pgsql::index( $panel );
	} elsif( $do eq 'cvscreate' ) {
		require Vhffs::Panel::Cvs;
		Vhffs::Panel::Cvs::create( $panel );
	} elsif( $do eq 'cvsprefs' ) {
		require Vhffs::Panel::Cvs;
		Vhffs::Panel::Cvs::prefs( $panel );
	} elsif( $do eq 'cvsindex' ) {
		require Vhffs::Panel::Cvs;
		Vhffs::Panel::Cvs::index( $panel );
	} elsif( $do eq 'svncreate' ) {
		require Vhffs::Panel::Svn;
		Vhffs::Panel::Svn::create( $panel );
	} elsif( $do eq 'svnprefs' ) {
		require Vhffs::Panel::Svn;
		Vhffs::Panel::Svn::prefs( $panel );
	} elsif( $do eq 'svnindex' ) {
		require Vhffs::Panel::Svn;
		Vhffs::Panel::Svn::index( $panel );
	} elsif( $do eq 'gitcreate' ) {
		require Vhffs::Panel::Git;
		Vhffs::Panel::Git::create( $panel );
	} elsif( $do eq 'gitprefs' ) {
		require Vhffs::Panel::Git;
		Vhffs::Panel::Git::prefs( $panel );
	} elsif( $do eq 'gitindex' ) {
		require Vhffs::Panel::Git;
		Vhffs::Panel::Git::index( $panel );
	} elsif( $do eq 'mercurialcreate' ) {
		require Vhffs::Panel::Mercurial;
		Vhffs::Panel::Mercurial::create( $panel );
	} elsif( $do eq 'mercurialprefs' ) {
		require Vhffs::Panel::Mercurial;
		Vhffs::Panel::Mercurial::prefs( $panel );
	} elsif( $do eq 'mercurialindex' ) {
		require Vhffs::Panel::Mercurial;
		Vhffs::Panel::Mercurial::index( $panel );
	} elsif( $do eq 'bazaarcreate' ) {
		require Vhffs::Panel::Bazaar;
		Vhffs::Panel::Bazaar::create( $panel );
	} elsif( $do eq 'bazaarprefs' ) {
		require Vhffs::Panel::Bazaar;
		Vhffs::Panel::Bazaar::prefs( $panel );
	} elsif( $do eq 'bazaarindex' ) {
		require Vhffs::Panel::Bazaar;
		Vhffs::Panel::Bazaar::index( $panel );
	} elsif( $do eq 'dnscreate' ) {
		require Vhffs::Panel::DNS;
		Vhffs::Panel::DNS::create( $panel );
	} elsif( $do eq 'dnsprefs' ) {
		require Vhffs::Panel::DNS;
		Vhffs::Panel::DNS::prefs( $panel );
	} elsif( $do eq 'dnsindex' ) {
		require Vhffs::Panel::DNS;
		Vhffs::Panel::DNS::index( $panel );
	} elsif( $do eq 'repositorycreate' ) {
		require Vhffs::Panel::Repository;
		Vhffs::Panel::Repository::create( $panel );
	} elsif( $do eq 'repositoryprefs' ) {
		require Vhffs::Panel::Repository;
		Vhffs::Panel::Repository::prefs( $panel );
	} elsif( $do eq 'repositoryindex' ) {
		require Vhffs::Panel::Repository;
		Vhffs::Panel::Repository::index( $panel );
	} elsif( $do eq 'mailcreate' ) {
		require Vhffs::Panel::Mail;
		Vhffs::Panel::Mail::create( $panel );
	} elsif( $do eq 'mailprefs' ) {
		require Vhffs::Panel::Mail;
		Vhffs::Panel::Mail::prefs( $panel );
	} elsif( $do eq 'mailindex' ) {
		require Vhffs::Panel::Mail;
		Vhffs::Panel::Mail::index( $panel );
	} elsif( $do eq 'mailinglistcreate' ) {
		require Vhffs::Panel::MailingList;
		Vhffs::Panel::MailingList::create( $panel );
	} elsif( $do eq 'mailinglistprefs' ) {
		require Vhffs::Panel::MailingList;
		Vhffs::Panel::MailingList::prefs( $panel );
	} elsif( $do eq 'mailinglistindex' ) {
		require Vhffs::Panel::MailingList;
		Vhffs::Panel::MailingList::index( $panel );
	} elsif( $do eq 'croncreate' ) {
		require Vhffs::Panel::Cron;
		Vhffs::Panel::Cron::create( $panel );
	} elsif( $do eq 'cronprefs' ) {
		require Vhffs::Panel::Cron;
		Vhffs::Panel::Cron::prefs( $panel );
	} elsif( $do eq 'cronindex' ) {
		require Vhffs::Panel::Cron;
		Vhffs::Panel::Cron::index( $panel );

	# -- admins and moderators stuff
	} elsif( $do eq 'admin' ) {
		require Vhffs::Panel::Admin;
		Vhffs::Panel::Admin::main( $panel );
	} elsif( $do eq 'stats' ) {
		require Vhffs::Panel::Stats;
		Vhffs::Panel::Stats::stats( $panel );
	} elsif( $do eq 'moderation' ) {
		require Vhffs::Panel::Moderation;
		Vhffs::Panel::Moderation::moderation( $panel );
	} elsif( $do eq 'su' ) {
		require Vhffs::Panel::Admin;
		Vhffs::Panel::Admin::su( $panel );
	} elsif( $do eq 'broadcastcreate' ) {
		require Vhffs::Panel::Broadcast;
		Vhffs::Panel::Broadcast::create( $panel );
	} elsif( $do eq 'broadcastlist' ) {
		require Vhffs::Panel::Broadcast;
		Vhffs::Panel::Broadcast::list( $panel );
	} elsif( $do eq 'broadcastview' ) {
		require Vhffs::Panel::Broadcast;
		Vhffs::Panel::Broadcast::view( $panel );
	} elsif( $do eq 'broadcastdelete' ) {
		require Vhffs::Panel::Broadcast;
		Vhffs::Panel::Broadcast::delete( $panel );
	} elsif( $do eq 'objectsearch' ) {
		require Vhffs::Panel::Object;
		Vhffs::Panel::Object::search( $panel );
	} elsif( $do eq 'objectedit' ) {
		require Vhffs::Panel::Object;
		Vhffs::Panel::Object::edit( $panel );
	} elsif( $do eq 'usersearch' ) {
		require Vhffs::Panel::User;
		Vhffs::Panel::User::search( $panel );
	} elsif( $do eq 'adminuserindex' ) {
		require Vhffs::Panel::User;
		Vhffs::Panel::User::adminindex( $panel );
	} elsif( $do eq 'groupsearch' ) {
		require Vhffs::Panel::Group;
		Vhffs::Panel::Group::search( $panel );
	} elsif( $do eq 'admingroupindex' ) {
		require Vhffs::Panel::Group;
		Vhffs::Panel::Group::adminindex( $panel );
	} elsif( $do eq 'websearch' ) {
		require Vhffs::Panel::Web;
		Vhffs::Panel::Web::search( $panel );
	} elsif( $do eq 'adminwebindex' ) {
		require Vhffs::Panel::Web;
		Vhffs::Panel::Web::adminindex( $panel );
	} elsif( $do eq 'mysqlsearch' ) {
		require Vhffs::Panel::Mysql;
		Vhffs::Panel::Mysql::search( $panel );
	} elsif( $do eq 'adminmysqlindex' ) {
		require Vhffs::Panel::Mysql;
		Vhffs::Panel::Mysql::adminindex( $panel );
	} elsif( $do eq 'pgsqlsearch' ) {
		require Vhffs::Panel::Pgsql;
		Vhffs::Panel::Pgsql::search( $panel );
	} elsif( $do eq 'adminpgsqlindex' ) {
		require Vhffs::Panel::Pgsql;
		Vhffs::Panel::Pgsql::adminindex( $panel );
	} elsif( $do eq 'cvssearch' ) {
		require Vhffs::Panel::Cvs;
		Vhffs::Panel::Cvs::search( $panel );
	} elsif( $do eq 'admincvsindex' ) {
		require Vhffs::Panel::Cvs;
		Vhffs::Panel::Cvs::adminindex( $panel );
	} elsif( $do eq 'svnsearch' ) {
		require Vhffs::Panel::Svn;
		Vhffs::Panel::Svn::search( $panel );
	} elsif( $do eq 'adminsvnindex' ) {
		require Vhffs::Panel::Svn;
		Vhffs::Panel::Svn::adminindex( $panel );
	} elsif( $do eq 'gitsearch' ) {
		require Vhffs::Panel::Git;
		Vhffs::Panel::Git::search( $panel );
	} elsif( $do eq 'admingitindex' ) {
		require Vhffs::Panel::Git;
		Vhffs::Panel::Git::adminindex( $panel );
	} elsif( $do eq 'mercurialsearch' ) {
		require Vhffs::Panel::Mercurial;
		Vhffs::Panel::Mercurial::search( $panel );
	} elsif( $do eq 'adminmercurialindex' ) {
		require Vhffs::Panel::Mercurial;
		Vhffs::Panel::Mercurial::adminindex( $panel );
	} elsif( $do eq 'bazaarsearch' ) {
		require Vhffs::Panel::Bazaar;
		Vhffs::Panel::Bazaar::search( $panel );
	} elsif( $do eq 'adminbazaarindex' ) {
		require Vhffs::Panel::Bazaar;
		Vhffs::Panel::Bazaar::adminindex( $panel );
	} elsif( $do eq 'dnssearch' ) {
		require Vhffs::Panel::DNS;
		Vhffs::Panel::DNS::search( $panel );
	} elsif( $do eq 'admindnsindex' ) {
		require Vhffs::Panel::DNS;
		Vhffs::Panel::DNS::adminindex( $panel );
	} elsif( $do eq 'mailsearch' ) {
		require Vhffs::Panel::Mail;
		Vhffs::Panel::Mail::search( $panel );
	} elsif( $do eq 'adminmailindex' ) {
		require Vhffs::Panel::Mail;
		Vhffs::Panel::Mail::adminindex( $panel );
	} elsif( $do eq 'mailinglistsearch' ) {
		require Vhffs::Panel::MailingList;
		Vhffs::Panel::MailingList::search( $panel );
	} elsif( $do eq 'adminmailinglistindex' ) {
		require Vhffs::Panel::MailingList;
		Vhffs::Panel::MailingList::adminindex( $panel );
	} elsif( $do eq 'repositorysearch' ) {
		require Vhffs::Panel::Repository;
		Vhffs::Panel::Repository::search( $panel );
	} elsif( $do eq 'adminrepositoryindex' ) {
		require Vhffs::Panel::Repository;
		Vhffs::Panel::Repository::adminindex( $panel );
	} elsif( $do eq 'cronsearch' ) {
		require Vhffs::Panel::Cron;
		Vhffs::Panel::Cron::search( $panel );
	} elsif( $do eq 'admincronindex' ) {
		require Vhffs::Panel::Cron;
		Vhffs::Panel::Cron::adminindex( $panel );
	} elsif( $do eq 'tagcreate' ) {
		require Vhffs::Panel::Tag;
		Vhffs::Panel::Tag::create_tag( $panel );
	} elsif( $do eq 'taglist' ) {
		require Vhffs::Panel::Tag;
		Vhffs::Panel::Tag::list_tag( $panel );
	} elsif( $do eq 'tagedit' ) {
		require Vhffs::Panel::Tag;
		Vhffs::Panel::Tag::edit_tag( $panel );
	} elsif( $do eq 'tagcategorycreate' ) {
		require Vhffs::Panel::Tag;
		Vhffs::Panel::Tag::create_category( $panel );
	} elsif( $do eq 'tagcategorylist' ) {
		require Vhffs::Panel::Tag;
		Vhffs::Panel::Tag::list_category( $panel );
	} elsif( $do eq 'tagcategoryedit' ) {
		require Vhffs::Panel::Tag;
		Vhffs::Panel::Tag::edit_category( $panel );
	} elsif( $do eq 'tagrequestlist' ) {
		require Vhffs::Panel::Tag;
		Vhffs::Panel::Tag::list_request( $panel );
	} elsif( $do eq 'tagrequestdetails' ) {
		require Vhffs::Panel::Tag;
		Vhffs::Panel::Tag::details_request( $panel );
	} elsif( $do eq 'admintagindex' ) {
		require Vhffs::Panel::Tag;
		Vhffs::Panel::Tag::adminindex( $panel );
	} else {
		$panel->render('misc/message.tt',  { message => gettext('CGI Error !') });
	}
}

exit 0;
