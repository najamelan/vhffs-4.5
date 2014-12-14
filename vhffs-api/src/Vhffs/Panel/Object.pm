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

package Vhffs::Panel::Object;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;

sub search_object {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT o.object_id AS oid, u.username as owner_user, g.groupname as owner_group, o.type, o.state '.
	  'FROM vhffs_object o '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) ';

	if( defined $name ) {
		$sql .= ' WHERE ( o.description ILIKE ? ) OR ( o.object_id = ? ) OR ( o.owner_uid = ? ) OR ( o.owner_gid = ? ) OR ( state = ? ) OR ( u.username LIKE ? ) OR ( g.groupname LIKE ? ) OR ( o.type = ? ) ';
		push(@params, '%'.$name.'%', $name, $name, $name, $name, '%'.lc($name).'%', '%'.lc($name).'%', $name );
	}

	$sql .= 'ORDER BY o.object_id';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

sub history {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	require Vhffs::Object;
	my $object = Vhffs::Object::get_by_oid( $vhffs , scalar $cgi->param('oid') );
	unless( defined $object ) {
		$panel->render('misc/message.tt', { message => gettext( 'Cannot get information on this object') });
		return;
	}
	$panel->set_group( $object->get_group );

	unless( $user->can_view($object) ) {
		$panel->render('misc/message.tt', { message => gettext('You\'re not allowed to view this object\'s ACL') });
		return;
	}

	$panel->set_title( gettext('History') );
	$panel->render('misc/history.tt', { history => $object->get_history });
}

sub resubmit {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $oid = $cgi->param('oid');
	unless( defined $oid ) {
		$panel->render('misc/message.tt', { message => gettext('CGI Error !') } );
		return;
	}

	require Vhffs::ObjectFactory;
	my $object = Vhffs::ObjectFactory::fetch_object( $vhffs , $oid );
	unless(defined $object) {
		$panel->render('misc/message.tt', { message => gettext('This object does not exist') } );
		return;
	}
	$panel->set_group( $object->get_group ) unless $object->get_type == Vhffs::Constants::TYPE_GROUP;

	unless($object->get_status == Vhffs::Constants::VALIDATION_REFUSED )  {
		$panel->render('misc/message.tt', { message => gettext('This object is not in refused state') } );
		return;
	}

	unless($object->get_owner_uid == $user->get_uid )  {
		$panel->render('misc/message.tt', { message => gettext('You are not allowed to do it, you don\'t own this object') } );
		return;
	}

	my $submitted = defined $cgi->param('submitted');
	if( $submitted ) {
		my $description = Encode::decode_utf8( scalar $cgi->param('description') );
		unless( defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
			return;
		}

		unless( $description !~ /^\s*$/ ) {
			$panel->add_error( gettext('You must enter a description') );
			return;
		}

		if ( $object->resubmit_for_moderation( $description ) ) {
			my $url;
			if( $object->get_type == Vhffs::Constants::TYPE_GROUP ) {
				$url = '?do=groupindex;msg='.gettext('The new description has been submitted');
			} else {
				$url = '?do=groupview;group='.$object->get_group->get_groupname.';msg='.gettext('The new description has been submitted');
			}
			$panel->redirect( $url );
			return;
		}

		$panel->add_error( gettext('An error occured while updating this object.') );
	}

	$panel->set_title( gettext('Propose a new description') );

	my $vars = { object => $object };
	$panel->render('object/resubmit.tt', $vars);
}

sub cancel {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $oid = $cgi->param('oid');
	unless(defined $oid) {
		$panel->render('misc/message.tt', { message => gettext('CGI Error !') } );
		return;
	}

	require Vhffs::ObjectFactory;
	my $object = Vhffs::ObjectFactory::fetch_object( $vhffs , $oid );
	unless(defined $object) {
		$panel->render('misc/message.tt', { message => gettext('This object does not exist') } );
		return;
	}
	$panel->set_group( $object->get_group ) unless $object->get_type == Vhffs::Constants::TYPE_GROUP;

	unless($object->get_status == Vhffs::Constants::VALIDATION_REFUSED )  {
		$panel->render('misc/message.tt', { message => gettext('This object is not in refused state') } );
		return;
	}

	unless($object->get_owner_uid == $user->get_uid )  {
		$panel->render('misc/message.tt', { message => gettext('You are not allowed to do it, you don\'t own this object') } );
		return;
	}

	if( $object->delete )  {
		my $url;
		if( $object->get_type == Vhffs::Constants::TYPE_GROUP ) {
			$url = '?do=groupindex;msg='.gettext('This object has been deleted');
		} else {
			$url = '?do=groupview;group='.$object->get_group->get_groupname.';msg='.gettext('This object has been deleted');
		}
		$panel->redirect( $url );
		return;
	}

	$panel->render('misc/message.tt', { message => gettext('An error occured while deleting this object.') } );
}

sub delete {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $oid = $cgi->param('oid');
	my $sure = $cgi->param('delete');
	my $object = Vhffs::Object::get_by_oid( $vhffs, $oid );

	my $message;

	unless( defined $oid and defined $sure ) {
		$message = gettext( 'CGI Error !' );
	} elsif( not defined $object ) {
		$message = gettext( 'Cannot retrieve informations about this object' );
	} elsif( not $user->can_delete( $object ) ) {
		$message = gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' );
	} elsif( $sure == 0 ) {
		$message = gettext( 'This object will NOT be deleted' );
	} else {
		$object->set_status( Vhffs::Constants::WAITING_FOR_DELETION );

		# Commit all the changes for the current user
		if( $object->commit < 0 ) {
			$message = gettext( 'An error occured while deleting this object' );
		} else {
			$message = gettext( 'This object will be deleted' );
		}
	}

	my $vars = { message => $message };

	if( $object->get_type == Vhffs::Constants::TYPE_GROUP ) {
		$vars->{refresh_url} = '?do=groupindex';
	} else {
		$vars->{refresh_url} = '?do=groupview;group='.$object->get_group->get_groupname;
	}

	$panel->render('misc/message.tt', $vars );
}

sub search {
	my $panel = shift;
	return unless $panel->check_admin();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $name = $cgi->param('name');
	my $vars = {};

	unless( defined $name ) {

		$panel->render('admin/misc/search.tt', {
		  search_title => gettext('Object search'),
		  type => 'object'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all objects');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{objects} = search_object( $vhffs , $name );
	$panel->render('admin/object/list.tt', $vars);
}

sub edit {
	my $panel = shift;
	return unless $panel->check_admin();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $oid = $cgi->param('oid');
	my $status = $cgi->param('status');
	my $description = Encode::decode_utf8( scalar $cgi->param('description') );

	unless(defined $oid) {
		$panel->render('misc/message.tt', {
	          message => gettext('CGI Error!')
		  });
		return;
	}

	require Vhffs::ObjectFactory;
	my $object = Vhffs::ObjectFactory::fetch_object( $vhffs, $oid);
	unless( defined $object ) {
		$panel->render('misc/message.tt', {
		  message => gettext('Object not found')
		  });
		return;
	}

	if(defined $status and defined $description) {
		$object->set_status( $status );
		$object->set_description( $description );
		if($object->commit() >= 0) {
			$panel->add_info( gettext('Object updated') );
		} else {
			$panel->add_error( gettext('Error while updating object') );
		}
	}


	$panel->render('admin/object/edit.tt', {
	  object => $object,
	  use_avatars => ($object->get_type == Vhffs::Constants::TYPE_USER and $panel->use_users_avatars) || ($object->get_type == Vhffs::Constants::TYPE_GROUP and $panel->use_groups_avatars)
	  });
}


1;
