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

package Vhffs::Panel::Web;

use DBI;
use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Services::Web;
use Vhffs::Constants;
use Vhffs::Functions;

=pod

=head1 NAME

Vhffs::Panel::Web - Light weight objects to handle webareas in VHFFS panel.

=head2 METHODS

=head2 get_all_per_group

	my $areas = Vhffs::Panel::Web::getall_per_group($vhffs, $vhffs);

Returns an array of hashrefs (oid, display, active, state) of all webareas owned by
a given group.

=cut

sub getall_per_group {
	my ($vhffs, $gid) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT w.servername AS displayname, w.object_id AS oid, o.state FROM vhffs_httpd w INNER JOIN vhffs_object o ON o.object_id = w.object_id WHERE o.owner_gid = ? ORDER BY w.servername';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $web = [];
	while(my $w = $sth->fetchrow_hashref) {
		$w->{active} = ($w->{state} == Vhffs::Constants::ACTIVATED);
		$w->{refused} = ($w->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$w->{state} = Vhffs::Functions::status_string_from_status_id($w->{state});
		push @$web, $w;
	}
	return $web;
}

=head2 get_websites_per_group

Returns an array of hashrefs {servername, description} containing all active websites for a
givent group.

=cut

sub get_websites_per_group {
	my ($vhffs, $gid) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT w.servername, o.description FROM vhffs_httpd w INNER JOIN vhffs_object o ON o.object_id = w.object_id WHERE o.owner_gid = ? AND o.state = ?';
	return $dbh->selectall_arrayref($sql, { Slice => {} }, $gid, Vhffs::Constants::ACTIVATED);
}

sub search_web {
	my ($vhffs, $name) = @_;

	my @params;
	my $webs = [];
	my $sql = 'SELECT w.servername as label, o.state, g.groupname as owner_group, u.username as owner_user '.
	  'FROM vhffs_httpd w '.
	  'INNER JOIN vhffs_object o ON o.object_id = w.object_id '.
	  'INNER JOIN vhffs_groups g ON g.gid = o.owner_gid '.
	  'INNER JOIN vhffs_users u ON u.uid = o.owner_uid ';

	if( defined $name ) {
		$sql .= 'WHERE w.servername ILIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY label';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

sub public_search {
	my ($vhffs, $servername, $description, $start, $count) = @_;

	my $select = 'SELECT w.servername, g.groupname, o.description';
	my $from = ' FROM vhffs_httpd w INNER JOIN vhffs_object o ON o.object_id = w.object_id INNER JOIN vhffs_groups g ON g.gid = o.owner_gid WHERE o.state = ?';
	my @params;
	push @params, Vhffs::Constants::ACTIVATED;
	if(defined $servername) {
		$from .= ' AND w.servername LIKE ?';
		push @params, '%'.lc($servername).'%';
	}

	if(defined $description) {
		$from .= ' AND o.description ILIKE ?';
		push @params, '%'.$description.'%';
	}

	return Vhffs::Panel::Commons::fetch_slice_and_count($vhffs, $select, $from, ' ORDER BY w.servername', $start, $count, \@params);
}


sub create_web {
	my( $vhffs, $servername, $description, $user, $group ) = @_;

	return undef unless defined $user;
	return undef unless defined $group;

	my $web = Vhffs::Services::Web::create($vhffs, $servername, $description, $user, $group);
	return undef unless defined $web;


	return $web;
}

sub get_websites_starting_with {
	my ($vhffs, $letter, $start, $count) = @_;

	my @params;
	my $select = 'SELECT w.servername, g.groupname, o.description';
	my $from = ' FROM vhffs_httpd w INNER JOIN vhffs_object o ON o.object_id = w.object_id INNER JOIN vhffs_groups g ON g.gid = o.owner_gid WHERE o.state = ?';
	push @params, Vhffs::Constants::ACTIVATED;
	if(defined $letter) {
		$from .= ' AND substr(w.servername, 1, 1) = ?';
		push @params, $letter;
	}
	my $dbh = $vhffs->get_db;
	return Vhffs::Panel::Commons::fetch_slice_and_count($vhffs, $select, $from, ' ORDER BY w.servername', $start, $count, \@params);
}

=head2 get_used_letters

Returns a reference on an array, each field is a hash with two fields
letter and count (count is the number of websites starting with letter).
0 site letters aren't stored.

=cut

sub get_used_letters {
	my $vhffs = shift;
	my $sql = 'SELECT substr(servername, 1, 1) as letter, COUNT(*) as count FROM vhffs_httpd h INNER JOIN vhffs_object o ON o.object_id = h.object_id WHERE state = ? GROUP BY substr(servername, 1, 1) ORDER BY substr(servername, 1, 1)';
	my $dbh = $vhffs->get_db;
	return $dbh->selectall_arrayref($sql, { Slice => {} }, Vhffs::Constants::ACTIVATED);
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

	my $submitted = defined($cgi->param('web_submit'));
	my $vars = {};
	my $servername = '';
	my $description = '';

	if( $submitted ) {
		$servername = $cgi->param('servername');
		$description = Encode::decode_utf8( scalar $cgi->param('description') );
		unless( defined $servername and defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
		} else {
			$panel->add_error( gettext('Invalid servername (doesn\'t conform to domain names rules)') ) unless Vhffs::Functions::check_domain_name($servername);
			$panel->add_error( gettext('You must enter a description') ) unless defined $description and $description !~ /^\s*$/;
		}

		unless( $panel->has_errors() ) {
			if( defined Vhffs::Panel::Web::create_web( $vhffs, $servername, $description, $user, $group) ) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The webarea was successfully created !');
				$panel->redirect($url);
				return;
			} else {
				$panel->add_error( gettext('Error creating webarea.') );
			}
		}	
		$vars->{servername} = $servername;
		$vars->{description} = $description;
	} else {
		my $webconfig = $vhffs->get_config->get_service('web');
		$vars->{servername} = sprintf( gettext('<new site>.%s'), $webconfig->{default_domain} ) if( defined $webconfig->{default_domain} );
	}

	$panel->set_title( gettext('Create a web space') );
	$vars->{group} = $group;
	$panel->render('web/create.tt', $vars);
}

sub prefs {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $servername = $cgi->param("name");
	unless( defined $servername ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		return;
	}

	my $web = Vhffs::Services::Web::get_by_servername( $vhffs , $servername );
	unless( defined($web) ) {
		$panel->render('misc/message.tt', { message => gettext('Cannot get informations on this object') } );;
		return;
	}
	$panel->set_group( $web->get_group );

	unless( $web->get_status == Vhffs::Constants::ACTIVATED ) {
		$panel->render('misc/message.tt', { message => gettext('This object is not functionnal yet. Please wait creation or moderation.') } );
		return;
	}

	unless( $user->can_view($web) ) {
		$panel->render('misc/message.tt', { message => gettext('You\'re not allowed to do this (ACL rights)') } );
		return;
	}

	if(defined($cgi->param('save_prefs_submit'))) {
		save_prefs($panel, $web);
	}

	my $vars = { web => $web };

	$panel->set_title( gettext("Modify webarea") );
	$panel->render('web/prefs.tt', $vars);
}

sub save_prefs {
	my $panel = shift;
	my $web = shift;
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	my $description = Encode::decode_utf8( scalar $cgi->param('description') );

	unless( $user->can_modify($web) ) {
		$panel->add_error( gettext('You are not allowed to modify this web area') );
		return;
	}

	unless( defined $description ) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	unless( $description !~ /^\s*$/ ) {
		$panel->add_error( gettext('You have to enter a description') );
		return;
	}

	$web->set_description($description);
	if($web->commit < 0) {
		$panel->add_error( gettext('Unable to apply modifications') );
	} else {
		$panel->add_info( gettext('Web area successfully modified') );
	}
}

sub index {
	my $panel = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined($group) ) {
		$panel->render( 'misc/message.tt', { message => gettext('You have to select a group first') });
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
	$panel->set_title( sprintf(gettext('Webareas for %s'), $group->get_groupname) );
	my $web = Vhffs::Panel::Web::getall_per_group( $vhffs, $group->get_gid );
	if($web < 0) {
		$panel->render( 'misc/message.tt', { message => gettext('Unable to get webareas') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'Webareas',
	  group => $group,
	  list => $web,
	  help_url => $vhffs->get_config->get_service('web')->{url_doc},
	  type => 'web'
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
		  search_title => gettext('Webareas search'),
		  type => 'web'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all web areas');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_web( $vhffs , $name );
	$vars->{type} = 'web';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Webareas\' administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_web_category() ] } );
}

1;
