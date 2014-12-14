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

package Vhffs::Panel::Cron;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Services::Cron;
use Vhffs::Constants;

=pod

=head2 getall_per_group

	$cron = Vhffs::Panel::Cron::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all download
repositories owned by a given group.

=cut

sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT c.object_id AS oid, c.cronpath AS displayname, o.state FROM vhffs_cron c INNER JOIN vhffs_object o ON c.object_id = o.object_id WHERE o.owner_gid = ? ORDER BY c.cronpath';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $crons = [];
	while(my $m = $sth->fetchrow_hashref) {
		$m->{active} = ($m->{state} == Vhffs::Constants::ACTIVATED);
		$m->{refused} = ($m->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$m->{state} = Vhffs::Functions::status_string_from_status_id($m->{state});
		push @$crons, $m;
	}
	return $crons;
}

sub search_cron {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT cron.cronpath as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_cron cron '.
	  'INNER JOIN vhffs_object o ON (o.object_id = cron.object_id) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) ';

	if( defined $name ) {
		$sql .= 'WHERE cron.cronpath LIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY cron.cronpath';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

sub create_cron {
	my( $vhffs , $cronpath , $interval , $reportmail , $description , $user , $group ) = @_;

	my $cron = Vhffs::Services::Cron::create( $vhffs , $cronpath , $interval , $reportmail , $description, $user , $group );
	return undef unless defined $cron;


	return $cron;
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

	my $submitted = defined $cgi->param('cron_submit');
	my $cronpath = '';
	my $interval = '';
	my $reportmail = '';
	my $description = '';
	my $vars = {};

	if( $submitted ) {
		my $fullcronpath;
		$cronpath = $cgi->param('cronpath');
		$interval = $cgi->param('interval');
		$reportmail = $cgi->param('reportmail');
		$description = Encode::decode_utf8( scalar $cgi->param('description') );

		unless( defined $cronpath and defined $interval and defined $reportmail and defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
			return;
		} else {
			$fullcronpath = '/home/'.$group->get_groupname.'/'.$cronpath;
			$panel->add_error( gettext('You must enter a description') ) unless $description !~ /^\s*$/;
			$panel->add_error( gettext('Invalid cronpath, it must contain only letters, numbers, underscore, dash, dot or slash. A valid cronpath will be something like /home/group/script.sh)') ) unless Vhffs::Services::Cron::check_cronpath($fullcronpath);
			$panel->add_error( gettext('Invalid interval, it must be a positive integer') ) unless $interval =~ /^\d+$/ and $interval > 0;
			$panel->add_error( gettext('The email you entered fails syntax check') ) unless( ($reportmail eq '') or Vhffs::Functions::valid_mail( $reportmail ) );
		}

		unless( $panel->has_errors() ) {
			my $mail = Vhffs::Panel::Cron::create_cron($vhffs, $fullcronpath, $interval*60, $reportmail , $description, $user, $group);
			if( defined $mail ) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The Cron job was successfully created !');
				$panel->redirect($url);
				return;
			}

			$panel->add_error( 'An error occured while creating the object.' );
		}

		$vars->{cronpath} = $cronpath;
		$vars->{interval} = $interval;
		$vars->{reportmail} = $reportmail;
		$vars->{description} = $description;
	}

	$vars->{group} = $group;
	$vars->{default_interval} = $vhffs->get_config->get_service('cron')->{minimum_interval};
	$panel->set_title( gettext('Create a Cron job') );
	$panel->render('cron/create.tt', $vars);
}

sub prefs {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $cronpath = $cgi->param('name');
	unless( defined $cronpath ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		return;
	}

	my $cron = Vhffs::Services::Cron::get_by_cronpath( $vhffs , $cronpath );
	unless( defined $cron ) {
		$panel->render('misc/message.tt', { message => gettext('Cannot get informations on this object') } );
		return;
	}
	$panel->set_group( $cron->get_group );

	unless( $user->can_view($cron) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	save_prefs($panel, $cron) if defined $cgi->param('save_prefs_submit');

	my $vars = { cron => $cron };

	$panel->set_title( gettext("Cron job Administration") );
	$panel->render('cron/prefs.tt', $vars);
}

sub save_prefs {
	my $panel = shift;
	my $cron = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	unless( $user->can_modify($cron) ) {
		$panel->add_error( gettext('You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights') );
		return;
	}

	my $interval = $cgi->param('interval');
	my $reportmail = $cgi->param('reportmail');
	unless( defined $interval and defined $reportmail ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	$cron->set_interval( $interval*60 );
	$cron->set_nextrundate( time() );

	if( $cron->set_reportmail( $reportmail ) ) {
		$panel->add_error( gettext('The email you entered fails syntax check') );
		return;
	}

	if( $cron->commit < 0)  {
		$panel->add_error( gettext('Unable to apply changes') );
		return;
	}

	$panel->add_info( gettext('Cron job successfully updated') );
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

	unless( $user->can_view($group) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}

	$panel->set_group( $group );
	$panel->set_title( sprintf(gettext('Cron jobs for %s'), $group->get_groupname) );
	my $crons = Vhffs::Panel::Cron::getall_per_group( $vhffs, $group->get_gid );
	if($crons < 0) {
		$panel->render('misc/message.tt', { message => gettext('Unable to get cron jobs') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'Cron jobs',
	  group => $group,
	  list => $crons,
	  help_url => $vhffs->get_config->get_service('cron')->{url_doc},
	  type => 'cron'
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
		  search_title => gettext('Cron search'),
		  type => 'cron'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all cron jobs');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_cron( $vhffs , $name );
	$vars->{type} = 'cron';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Cron jobs administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_cron_category() ] } );
}

1;
