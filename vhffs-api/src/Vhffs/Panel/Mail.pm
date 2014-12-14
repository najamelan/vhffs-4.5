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

package Vhffs::Panel::Mail;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Services::Mail;

sub search_mail {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT m.domain as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_mx m '.
	  'INNER JOIN vhffs_object o ON (o.object_id = m.object_id) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) ';

	if( defined $name ) {
		$sql .= 'WHERE m.domain LIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY label';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

=pod

=head2 getall_per_group

	$dns = Vhffs::Panel::Mail::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all mail domains by
a given group.

=cut
sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT m.object_id AS oid, m.domain AS displayname, o.state FROM vhffs_mx m INNER JOIN vhffs_object o ON m.object_id = o.object_id WHERE o.owner_gid = ? ORDER BY m.domain';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $mails = [];
	while(my $m = $sth->fetchrow_hashref) {
		$m->{active} = ($m->{state} == Vhffs::Constants::ACTIVATED);
		$m->{refused} = ($m->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$m->{state} = Vhffs::Functions::status_string_from_status_id($m->{state});
		push @$mails, $m;
	}
	return $mails;
}

sub create {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group and $user->can_modify( $group ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}
	$panel->set_group( $group );

	my $submitted = defined($cgi->param('mail_submit'));
	my $domain = '';
	my $description = '';
	my $vars = {};

	if( $submitted ) {
		$domain = $cgi->param('domain');
		$description = Encode::decode_utf8( scalar $cgi->param('description') );
		unless( defined $domain and defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
		} else {
			$panel->add_error( gettext('Invalid domain name') ) unless Vhffs::Functions::check_domain_name($domain);
			$panel->add_error( gettext('You must enter a description') ) unless $description !~ /^\s*$/;
		}

		unless( $panel->has_errors() ) {
			my $mail = Vhffs::Services::Mail::create( $vhffs, $domain, $description, $user, $group );
			if( defined $mail ) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('Mail domain successfully created !');
				$panel->redirect($url);
				return;
			}

			$panel->add_error( gettext('An error occured while creating the mail area') );
		}

		$vars->{domain} = $domain;
		$vars->{description} = $description;
	}

	$vars->{group} = $group;
	$panel->set_title( gettext('Create a mail space') );
	$panel->render('mail/create.tt', $vars);
}

sub prefs {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $domain = $cgi->param('name');
	unless( defined $domain ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		return;
	}

	my $mail = Vhffs::Services::Mail::get_by_mxdomain( $vhffs, $domain );
	unless( defined $mail ) {
		$panel->render('misc/message.tt', { message => sprintf( gettext('Unable to get information on mail domain %s'), $domain ) } );
		return;
	}
	$mail->fetch_localparts;
	$panel->set_group( $mail->get_group );

	unless( $user->can_view($mail) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	my $mail_config = $mail->get_config;

	if( defined $cgi->param('add_catchall_submit') ) {
		add_catchall($panel, $mail);
	} elsif( defined $cgi->param('delete_catchall_submit') ) {
		delete_catchall($panel, $mail);
	} elsif( defined $cgi->param('update_localpart_submit') ) {
		update_localpart($panel, $mail);
	} elsif(defined $cgi->param('delete_box_submit')) {
		delete_box($panel, $mail);
	} elsif(defined $cgi->param('add_box_submit')) {
		add_box($panel, $mail);
	} elsif(defined $cgi->param('update_forward_submit')) {
		update_forward($panel, $mail);
	} elsif(defined $cgi->param('delete_forward_submit')) {
		delete_forward($panel, $mail);
	} elsif(defined $cgi->param('add_forward_submit')) {
		add_forward($panel, $mail);
	}

	my $vars = {
		mail => $mail,
		catchall_state => {
			none => Vhffs::Services::Mail::CATCHALL_ALLOW_NONE,
			domain => Vhffs::Services::Mail::CATCHALL_ALLOW_DOMAIN,
			open => Vhffs::Services::Mail::CATCHALL_ALLOW_OPEN,
		},
		novirus => $mail_config->{use_novirus},
		nospam => $mail_config->{use_nospam}
	};

	my @sorted_localparts = sort { $a->{localpart} cmp $b->{localpart} } (values %{$mail->get_localparts});
	$vars->{sorted_localparts} = \@sorted_localparts;

	$panel->set_title( gettext("Mail Administration for domain ") );
	$panel->render('mail/prefs.tt', $vars);
}

sub add_catchall {
	my $panel = shift;
	my $mail = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	# User wants to modify catchall address.
	unless( $user->can_modify($mail) ) {
		$panel->add_error( gettext('You are not allowed to modify this object') );
		return;
	}

	my $catchall = $cgi->param('catchall');
	unless( defined $catchall ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	my ( $localpart, $domain ) = split /\@/, $catchall;

	# Try to fetch the catchall using light mx objects
	my $othermail = Vhffs::Services::Mail::get_by_mxdomain( $vhffs, $domain );
	my $lp = $othermail->fetch_localpart( $localpart ) if defined $othermail;
	unless( defined $othermail and defined $lp and defined $lp->get_box ) {
		$panel->add_error(gettext( 'An error occured while fetching the catchall box' ) );
		return;
	}

	my $box = $lp->get_box;
	unless( $mail->add_catchall( $box ) ) {
		$panel->add_error(gettext( 'An error occured while adding the catchall box' ) );
		return;
	}

	$panel->add_info( gettext('Catchall box successfully added') );
}

sub delete_catchall {
	my $panel = shift;
	my $mail = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	# User wants to delete catchall address.
	unless( $user->can_modify($mail) ) {
		$panel->add_error( gettext('You are not allowed to modify this object') );
		return;
	}

	my $boxname = $cgi->param('boxname');
	unless( defined $boxname ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	my $catchall = $mail->get_catchall( $boxname );
	unless( defined $catchall and $catchall->delete ) {
		$panel->add_error( sprintf(gettext('Unable to delete catchall %s'), $boxname) );
		return;
	}

	$panel->add_info( sprintf(gettext('Catchall %s deleted'), $boxname) );
}

sub add_box {
	my $panel = shift;
	my $mail = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	unless( $user->can_modify($mail) ) {
		$panel->add_error( gettext('You are not allowed to modify this object') );
		return;
	}

	my $box = $cgi->param('localpart');
	my $passwd = $cgi->param('localpart_password');
	unless( defined $box and defined $passwd) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	unless( $mail->add_box( $box, $passwd ) ) {
		$panel->add_error(gettext( "This box already exists for this domain or parameters are not valid. Check your domain." ) );
		return;
	}

	$panel->add_info( gettext('Box successfully added') );
}

sub update_localpart {
	my $panel = shift;
	my $mail = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	unless( $user->can_modify($mail) ) {
		$panel->add_error( gettext('You are not allowed to modify this object') );
		return;
	}

	# User wants to update information about a localpart
	my $lp = $mail->get_localpart( scalar $cgi->param('localpart') );
	my $passwd = $cgi->param('localpart_password');
	my $use_antispam = $cgi->param('use_antispam');
	my $use_antivirus = $cgi->param('use_antivirus');
	my $mail_config = $mail->get_config;
	unless( defined $lp and defined $passwd
	  and (not $mail_config->{'use_novirus'} or defined $use_antivirus)
	  and (not $mail_config->{'use_nospam'} or defined $use_antispam) ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	my @infos;

	if($passwd !~ /^\s*$/) {
		$lp->set_password( $passwd );
		push @infos, gettext('Box password updated');
	}

	if(defined $use_antispam) {
		$lp->set_nospam( ($use_antispam eq 'yes') );
		push @infos, gettext('Spam status updated');
	}

	if(defined $use_antivirus) {
		$lp->set_novirus( ($use_antivirus eq 'yes') );
		push @infos, gettext('Virus status updated');
	}

	unless( $lp->commit ) {
		$panel->add_error( sprintf( gettext('An error occured while updating localpart %s'), $lp->get_localpart ) );
		return;
	}

	$panel->add_info( $_ ) foreach( @infos );
}

sub delete_box {
	my $panel = shift;
	my $mail = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	# User wants to delete a box
	my $local = $cgi->param('localpart');
	unless( defined $local ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	my $box = $mail->get_box( $local );
	unless( $user->can_modify($mail) and defined $box and $box->get_status == Vhffs::Constants::ACTIVATED ) {
		$panel->add_error( gettext('You are not allowed to modify this object') );
		return;
	}

	$box->set_status( Vhffs::Constants::WAITING_FOR_DELETION );
	unless( $box->commit ) {
		$panel->add_error( sprintf(gettext('Unable to delete box %s'), $local) );
		return;
	}

	$panel->add_info( sprintf(gettext('Box %s deleted'), $local) );
}

sub add_forward {
	my $panel = shift;
	my $mail = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	unless( $user->can_modify($mail) ) {
		$panel->add_error( gettext('You are not allowed to modify this object') );
		return;
	}

	my $local = $cgi->param('localpart');
	my $remote = $cgi->param('forward');
	unless( defined $local and defined $remote ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	unless( $mail->add_redirect( $local, $remote ) ) {
		$panel->add_error( sprintf(gettext('Unable to add forward %s'), $local) );
		return;
	}

	$panel->add_info( gettext('Forward added') );
}

sub update_forward {
	my $panel = shift;
	my $mail = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	unless( $user->can_modify($mail) ) {
		$panel->add_error( gettext('You are not allowed to modify this object') );
		return;
	}

	my $local = $cgi->param('localpart');
	my $remote = $cgi->param('remote');
	my $newremote = $cgi->param('newremote');
	my $redirect = $mail->get_redirect( $local, $remote );
	unless( defined $redirect and defined $newremote ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	unless( $redirect->set_redirect( $newremote ) and $redirect->commit ) {
		$panel->add_error( sprintf(gettext('Unable to modify forward %s' ), $local ) );
		return;
	}

	$panel->add_info( sprintf(gettext('Forward %s successfully updated'), $local ) );
}

sub delete_forward {
	my $panel = shift;
	my $mail = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	unless( $user->can_modify($mail) ) {
		$panel->add_error( gettext('You are not allowed to modify this object') );
		return;
	}

	my $local = $cgi->param('localpart');
	my $remote = $cgi->param('remote');
	unless( defined $local and defined $remote ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	my $redirect = $mail->get_redirect( $local, $remote );
	unless( defined $redirect and $redirect->delete ) {
		$panel->add_error( sprintf(gettext('Unable to delete forward %s to %s'), $local, $remote) );
		return;
	}

	$panel->add_info( sprintf(gettext('Forward %s to %s deleted'), $local, $remote) );
}

sub index {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group ) {
		$panel->render('misc/message.tt', { message => gettext('You have to select a group first') } );
		return;
	}

	unless($group->get_status == Vhffs::Constants::ACTIVATED) {
		$panel->render( 'misc/message.tt', { message => gettext('This group is not activated yet') } );
		return;
	}

	unless( $user->can_view( $group ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}

	$panel->set_group( $group );
	$panel->set_title( sprintf(gettext('Mail domains for %s'), $group->get_groupname) );
	my $mails = Vhffs::Panel::Mail::getall_per_group( $vhffs, $group->get_gid );
	if($mails < 0) {
		$panel->render('misc/message.tt', { message => gettext('Unable to get mail domains') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'Mail domains',
	  group => $group,
	  list => $mails,
	  help_url => $vhffs->get_config->get_service('mail')->{url_doc},
	  type => 'mail'
	  });
}

sub search {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $name = $cgi->param('name');
	my $vars = {};

	unless( defined $name ) {

		$panel->render('admin/misc/search.tt', {
		  search_title => gettext('Mail search'),
		  type => 'mail'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all mail domains');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_mail( $vhffs , $name );
	$vars->{type} = 'mail';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Mail domains\' administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_mail_category() ] } );
}

1;
