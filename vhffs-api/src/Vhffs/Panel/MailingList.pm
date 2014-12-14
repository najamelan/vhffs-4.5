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

package Vhffs::Panel::MailingList;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Services::MailingList;
use Vhffs::Constants;
require Vhffs::Panel::Mail;

sub search_mailinglist {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT mlp.localpart || \'@\' || mx.domain as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_mx_ml ml '.
	  'INNER JOIN vhffs_object o ON o.object_id = ml.object_id '.
	  'INNER JOIN vhffs_groups g ON g.gid = o.owner_gid '.
	  'INNER JOIN vhffs_users u ON u.uid = o.owner_uid '.
	  'INNER JOIN vhffs_mx_localpart mlp ON mlp.localpart_id=ml.localpart_id '.
	  'INNER JOIN vhffs_mx mx ON mx.mx_id=mlp.mx_id ';

	if( defined $name ) {
		$sql .= 'WHERE mlp.localpart LIKE ? OR mx.domain LIKE ? ';
		push(@params, '%'.lc($name).'%' , '%'.lc($name).'%' );
	}

	$sql .= 'ORDER BY mx.domain, mlp.localpart';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

=pod

=head2 getall_per_group

	$ml = Vhffs::Panel::MailingList::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all mailing lists owned by
a given group.

=cut
sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT ml.object_id AS oid, mlp.localpart || \'@\' || mx.domain AS displayname, o.state FROM vhffs_mx_ml ml INNER JOIN vhffs_object o ON ml.object_id = o.object_id '.
		'INNER JOIN vhffs_mx_localpart mlp ON mlp.localpart_id=ml.localpart_id INNER JOIN vhffs_mx mx ON mx.mx_id=mlp.mx_id WHERE o.owner_gid = ? ORDER BY mlp.localpart, mx.domain';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $mls = [];
	while(my $l = $sth->fetchrow_hashref) {
		$l->{active} = ($l->{state} == Vhffs::Constants::ACTIVATED);
		$l->{refused} = ($l->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$l->{state} = Vhffs::Functions::status_string_from_status_id($l->{state});
	push @$mls, $l;
	}
	return $mls;
}

sub get_lists_per_group {
	my ($vhffs, $gid) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT mlp.localpart || \'@\' || mx.domain AS listname, mlp.localpart, mx.domain, ml.open_archive, o.description FROM vhffs_mx_ml ml INNER JOIN vhffs_object o ON ml.object_id = o.object_id '.
		'INNER JOIN vhffs_mx_localpart mlp ON mlp.localpart_id=ml.localpart_id INNER JOIN vhffs_mx mx ON mx.mx_id=mlp.mx_id WHERE o.owner_gid = ? AND o.state = ?';
	return $dbh->selectall_arrayref($sql, { Slice => {} }, $gid, Vhffs::Constants::ACTIVATED);
}

=pod

=head2 getall_mdomains_per_group

	$domains = Vhffs::Panel::MailingList::getall_mdomains_per_group($vhffs, $gid);

Returns an array of hashref (domain) of all active mail domains for
a given group.

=cut

sub getall_mdomains_per_group($$) {
	my ($vhffs, $gid) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = q{ SELECT m.domain FROM vhffs_mx m INNER JOIN vhffs_object o ON o.object_id = m.object_id WHERE o.owner_gid = ? AND o.state = ? ORDER BY m.domain };
	return ($dbh->selectall_arrayref($sql, { Slice => {} }, $gid, Vhffs::Constants::ACTIVATED) );
}

sub create {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group and $user->can_modify($group) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}
	$panel->set_group( $group );

	my $default_domain = $vhffs->get_config->get_service('mailinglist')->{'default_domain'};
	my $domains = Vhffs::Panel::MailingList::getall_mdomains_per_group( $vhffs, $group->get_gid );
	unless( @$domains or defined $default_domain ) {
		$panel->render('misc/message.tt', { message => gettext('There is no default mail domain on this platform, you have to create a mail domain before creating a mailing list') } );
		return;
	}

	my $submitted = $cgi->param('mailing_submit');
	my $vars = {};

	if( $submitted ) {
		my $localpart = $cgi->param( 'localpart' );
		my $domain = $cgi->param( 'domain' );
		my $description = Encode::decode_utf8( scalar $cgi->param( 'description' ) );
		my $mail;

		unless( defined $localpart and defined $domain and defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
		} else {
			$panel->add_error( gettext('You must enter a description') ) unless $description !~ /^\s*$/;
			$panel->add_error( gettext('Invalid local part') ) unless $localpart =~ Vhffs::Constants::MAIL_VALID_LOCAL_PART;
			$mail = Vhffs::Services::Mail::get_by_mxdomain( $vhffs, $domain );
			$panel->add_error( gettext('You do not own this domain !') ) unless( ($domain eq $default_domain) or $mail->get_group->get_gid == $group->get_gid );
		}

		unless( $panel->has_errors() ) {
			my $mailinglist =  Vhffs::Services::MailingList::create( $vhffs, $mail, $localpart, $description, $user, $group ); 
			if( defined $mailinglist ) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The mailing list object was successfully created !');
				$panel->redirect( $url );
				return;
			}

			$panel->add_error( gettext('An error occured while creating the object.It probably already exists') );
		}

		$vars->{localpart} = $localpart;
		$vars->{domain} = $domain;
		$vars->{description} = $description;
	}

	push(@$domains, { domain => $default_domain }) if defined $default_domain;
	$vars->{domains} = $domains;
	$vars->{group} = $group;

	$panel->render('mailinglist/create.tt', $vars);
}

sub prefs {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $lpart = $cgi->param('local');
	my $domain = $cgi->param('domain');

	# Generic service management use name param
	unless( defined $lpart and defined $domain ) {
		my $name = $cgi->param('name');
		( $lpart , $domain ) = ( $name =~ /(.+)\@(.+)/ ) if defined $name;
	}

	unless( defined $lpart and defined $domain ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		return;
	}

	my $list = Vhffs::Services::MailingList::get_by_mladdress( $vhffs , $lpart , $domain );
	unless( defined $list ) {
		$panel->render('misc/message.tt', { message => sprintf( gettext('Mailing list %s@%s not found'), $lpart, $domain) } );
		return;
	}

	my $group = $list->get_group;
	$panel->set_group( $group );

	unless( $user->can_view( $list ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	$list->fetch_subs;

	if(defined $cgi->param('options_submit')) {
		update_ml_options($panel, $list);
	} elsif(defined $cgi->param('delete_submit')) {
		delete_member($panel, $list);
	} elsif(defined $cgi->param('change_rights_submit')) {
		change_rights($panel, $list);
	} elsif(defined $cgi->param('add_members_submit')) {
		add_members($panel, $list);
	}

	my $vars = { list => $list };

	$vars->{group_emails} = join("\n", map { $_->{mail} } @{$group->get_users});

	$panel->set_title( sprintf(gettext('Administration for list %s'), $list->get_localpart.'@'.$list->get_domain) );
	$panel->render('mailinglist/prefs.tt', $vars);
}

sub update_ml_options {
	my $panel = shift;
	my $list = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	my $prefix = Encode::decode_utf8( scalar $cgi->param('prefix') );
	my $sub_ctrl = $cgi->param('subscribe_control');
	my $post_ctrl = $cgi->param('posting_control');
	my $sig = Encode::decode_utf8( scalar $cgi->param('signature') );

	unless( $user->can_modify($list) ) {
		$panel->add_error( gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) );
		return;
	}

	unless( defined $prefix and defined $sub_ctrl and defined $post_ctrl and defined $sig) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	$list->set_prefix($prefix);
	$list->set_sub_ctrl($sub_ctrl);
	$list->set_post_ctrl($post_ctrl);
	$list->set_open_archive(defined $cgi->param('public_archive') ? 1 : 0);
	$list->set_replyto(defined $cgi->param('reply_to') ? 1 : 0);
	$list->set_signature($sig);

	if($list->commit() < 0) {
		$panel->add_error( gettext('Unable to save object') );
		return;
	}

	$panel->add_info( gettext('List updated') );
}

sub delete_member {
	my $panel = shift;
	my $list = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	my $member = $cgi->param('member');

	unless( $user->can_modify($list) ) {
		$panel->add_error( gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) );
		return;
	}

	unless(defined $member) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	if( $list->del_sub($member) < 0 ) {
		$panel->add_error('An error occured while deleting this subscriber');
		return;
	}

	$panel->add_info( sprintf( gettext('Subscriber %s deleted'), $member ) );
}

sub change_rights {
	my $panel = shift;
	my $list = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	my $member = $cgi->param('member');
	my $right = $cgi->param('right');

	unless( $user->can_modify($list) ) {
		$panel->add_error( gettext('You are not allowed to manager subscribers\' rights (ACL rights)') );
		return;
	}

	unless( defined $member and defined $right ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	if( $list->change_right_for_sub( $member, $right ) < 0) {
		$panel->add_error( sprintf( gettext('Unable to change rights for subscriber %s'), $member ) );
		return;
	}

	$panel->add_info( sprintf( gettext('Rights for subscriber %s updated'), $member ) );
}

sub add_members {
	my $panel = shift;
	my $list = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	my $memberlist = $cgi->param('members');

	unless( $user->can_modify($list) ) {
		$panel->add_error( gettext('You are not allowed to add members (ACL rights)') );
		return;
	}

	unless( defined $memberlist ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	unless($memberlist !~ /^\s*$/) {
		$panel->add_error( gettext('You need to enter at least one new member') );
		return;
	}

	my @members = split /\r\n/, $memberlist;
	my $listengineconfig = $vhffs->get_config->get_listengine;

	foreach my $member ( @members )  {
		chomp $member;
		( $member ) = ( $member =~ /^\s*([^\s]+)\s*$/ );
		$member = lc $member;
		unless( Vhffs::Functions::valid_mail( $member ) )  {
			 $panel->add_error( sprintf( gettext('%s is not a valid mail'), $member ) )
		} elsif( $list->add_sub( $member , Vhffs::Constants::ML_RIGHT_SUB ) < 0 ) {
			$panel->add_error( sprintf( gettext( '%s is already a member of this list' ), $member ) );
		} else {
			$panel->add_info( sprintf( gettext( '%s has been added' ), $member ) );
			Vhffs::Functions::send_mail(
			  $vhffs,
			  $listengineconfig->{'listmaster'},
			  $member,
			  undef,
			  sprintf(gettext('[%s] You\'ve been added to the list %s'), $list->get_prefix, $list->get_localpart.'@'.$list->get_domain),
			  sprintf(gettext("Greetings,\n\nYou've been added to the list %s on platform %s.\n\nYou may get some help on listengine by sending an email to %s-request\@%s with subject help.\n\nCheers.\n"), $list->get_localpart.'@'.$list->get_domain, $vhffs->get_config->get_host_name, $list->get_localpart, $list->get_domain),
			  );
		}
	}
}

sub index {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group ) {
		$panel->render( 'misc/message.tt', { message => gettext('You have to select a group first') } );
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
	$panel->set_title( sprintf(gettext('Mailing lists for %s'), $group->get_groupname) );

	my $mls = Vhffs::Panel::MailingList::getall_per_group( $vhffs, $group->get_gid );
	if($mls < 0) {
		$panel->render( 'misc/message.tt', { message => gettext('Unable to get SVN repositories') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'Mailing lists',
	  group => $group,
	  list => $mls,
	  type => 'mailinglist'
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
		  search_title => gettext('Mailing lists search'),
		  type => 'mailinglist'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all mailing lists');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_mailinglist( $vhffs , $name );
	$vars->{type} = 'mailinglist';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Mailing lists administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_mailing_category() ] } );
}

1;
