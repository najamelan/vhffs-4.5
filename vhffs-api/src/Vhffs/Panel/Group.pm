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

package Vhffs::Panel::Group;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;

use Vhffs::Constants;
use Vhffs::Functions;

require Vhffs::Tag;
require Vhffs::Tag::Category;
require Vhffs::Tag::Request;
require Vhffs::Services::MailGroup;


=head1 NAME

Vhffs::Panel::Group - Handle group information in the panel.

=head1 METHODS

=head2 getall_users

	$users = Vhffs::Panel::Group::getall_users( $vhffs, $gid );

Returns an array of hashes {uid, username, state} containing all users of
the given group (C<state> is a descriptive string).

=cut
sub getall_users {
	my ($vhffs, $gid) = @_;
	my $sql = 'SELECT u.uid, u.username, u.firstname, u.lastname, u.mail, ug.state FROM vhffs_users u INNER JOIN vhffs_user_group ug ON ug.uid = u.uid WHERE ug.gid = ?';
	my $dbh = $vhffs->get_db;
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $users = [];
	while(my $u = $sth->fetchrow_hashref) {
		$u->{active} = ($u->{state} == Vhffs::Constants::ACTIVATED);
		$u->{state} = Vhffs::Functions::status_string_from_status_id($u->{state});
		push @$users, $u;
	}
	return $users;
}

sub get_last_groups {
	my $vhffs = shift;
	my @groups;

	my $sql = 'SELECT g.gid, g.groupname, g.realname, o.description, owner.username AS owner_name, o.object_id FROM vhffs_groups g LEFT OUTER JOIN vhffs_users u ON u.username=g.groupname INNER JOIN vhffs_object o ON o.object_id=g.object_id INNER JOIN vhffs_users owner ON owner.uid = o.owner_uid WHERE o.state=? AND u.username IS NULL ORDER BY o.date_creation DESC LIMIT 10';

	 return fetch_groups_and_users($vhffs, $sql, Vhffs::Constants::ACTIVATED);
}

sub search_group {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT g.groupname, o.state, u.username as owner_user '.
	  'FROM vhffs_groups g '.
	  'INNER JOIN vhffs_object o ON (g.object_id = o.object_id) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) '.
	  'LEFT JOIN vhffs_users uu ON (uu.username = g.groupname) '.
	  'WHERE uu.username IS NULL ';

	if( defined $name ) {
		$sql .= ' AND g.groupname LIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY g.groupname';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}


sub public_search {
	my ($vhffs, $groupname, $description, $included_tags, $excluded_tags, $start) = @_;

	my $sql = ' FROM vhffs_groups g
	  LEFT OUTER JOIN vhffs_users u ON u.username=g.groupname
	  INNER JOIN vhffs_object o ON o.object_id=g.object_id
	  INNER JOIN vhffs_users owner ON owner.uid = o.owner_uid
	  WHERE o.state=? AND u.username IS NULL';

	my @params;
	push @params, Vhffs::Constants::ACTIVATED;

	if($groupname =~ /\S/) {
		$sql .= ' AND g.groupname ILIKE ?';
		push @params, '%'.$groupname.'%';
	}

	if($description =~ /\S/) {
		$sql .= ' AND o.description ILIKE ? ';
		push @params, '%'.$description.'%';
	}

	if(scalar(@$included_tags)) {
		$sql .= ' AND o.object_id IN (SELECT ot.object_id from vhffs_object_tag ot WHERE ot.tag_id IN(?';
		$sql .= ', ?' x (scalar(@$included_tags) - 1);
		$sql .= '))';
		push @params, @$included_tags;
	}

	if(scalar(@$excluded_tags)) {
		$sql .= ' AND o.object_id NOT IN (SELECT ot.object_id from vhffs_object_tag ot WHERE ot.tag_id IN(?';
		$sql .= ', ?' x (scalar(@$excluded_tags) - 1);
		$sql .= '))';
		push @params, @$excluded_tags;
	}

	my $limit = ' LIMIT 10';
	$limit .= ' OFFSET '.($start * 10) if(defined $start);

	my $select = 'SELECT g.gid, g.groupname, g.realname, o.description, owner.username AS owner_name, o.object_id'.$sql.' ORDER BY groupname '.$limit;
	my $groups = fetch_groups_and_users($vhffs, $select, @params);

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare('SELECT COUNT(*)'.$sql);
	return undef unless ( $sth->execute(@params) );

	my ($count) = $sth->fetchrow_array();

	return ($groups, $count);
}

sub getall_groups_per_user {
	my ( $user , $vhffs ) = @_;

	return undef if ( ! defined $user );

	my $query = "SELECT g.groupname , g.object_id, o.state  FROM vhffs_groups g, vhffs_user_group ug , vhffs_object o WHERE o.object_id=g.object_id AND ug.gid=g.gid AND ug.uid='".$user->{'uid'}."'";

	my $request = $vhffs->get_db->prepare( $query ) or return -1;
	my @retour;

	return undef if ( $request->execute() <= 0);
	return ( $request->fetchall_hashref( 'groupname' ) );
}

=head2 create_group($groupname, $user, $vhffs)

Create a new group with specified name and the
specified user as owner. Owner if affected to
the group and an ACL is created in order to
allow him to delete group.

All arguments are mandatory

=over

=item $groupname: Name of the group

=item $user: Vhffs::User owner of the group (must be registered
in DB).

=item $vhffs: Vhffs instance

=cut

sub create_group {
	my( $groupname , $realname, $user, $vhffs, $description ) = @_;
	return Vhffs::Group::create($vhffs, $groupname, $realname, $user->get_uid, undef, $description);
}

sub get_groups_starting_with {
	my ($vhffs, $letter, $starting, $count) = @_;
	my @params;

	my $select_clause = 'SELECT g.gid, g.groupname, g.realname, o.description, owner.username as owner_name, o.object_id';
	my $sql = ' FROM vhffs_groups g '.
	  'LEFT OUTER JOIN vhffs_users u ON u.username=g.groupname '.
	  'INNER JOIN vhffs_object o ON o.object_id=g.object_id '.
	  'INNER JOIN vhffs_users owner ON owner.uid = o.owner_uid '.
	  'WHERE o.state=? AND u.username IS NULL';
	push @params, Vhffs::Constants::ACTIVATED;
	if(defined $letter) {
		$sql .=  ' AND SUBSTR(g.groupname, 1, 1) = ?';
		push @params, $letter;
	}

	my $order_clause = ' ORDER BY g.groupname LIMIT '.$count.' OFFSET '.$starting;
	return Vhffs::Panel::Commons::fetch_slice_and_count($vhffs, $select_clause, $sql, ' ORDER BY groupname', $starting, $count, \@params, \&Vhffs::Panel::Group::fetch_groups_and_users);
}

sub fetch_groups_and_users {
	my ($vhffs, $sql, @params) = @_;
	my @groups;


	my $dbh = $vhffs->get_db;
	my $sth = $dbh->prepare($sql);
	$sql = 'SELECT u.username FROM vhffs_users u INNER JOIN vhffs_user_group ug ON ug.uid = u.uid WHERE ug.gid = ?';
	my $usth = $dbh->prepare($sql);
	# FIXME fetch object_id along with gid in every caller and suppress vhffs_groups from the query
	$sql = 'SELECT c.tag_category_id as category_id, c.label as category_label, t.tag_id, t.label as tag_label '.
	  'FROM vhffs_tag t INNER JOIN vhffs_tag_category c ON c.tag_category_id = t.category_id '.
	  'INNER JOIN vhffs_object_tag ot ON ot.tag_id = t.tag_id '.
	  'INNER JOIN vhffs_groups g ON g.object_id = ot.object_id '.
	  'WHERE g.gid = ? AND c.visibility = ?';
	my $tsth = $dbh->prepare($sql);
	$sth->execute(@params);
	while(my $row = $sth->fetchrow_hashref) {
		$usth->execute($row->{gid});
		$row->{users} = $usth->fetchall_arrayref({});
		$tsth->execute($row->{gid}, Vhffs::Constants::TAG_VISIBILITY_PUBLIC);
		$row->{tags} = $tsth->fetchall_arrayref({});
		push @groups, $row;
	}

	return \@groups;
}

sub get_used_letters {
	my $vhffs = shift;
	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT substr(g.groupname, 1, 1) AS letter, COUNT(*) AS count FROM vhffs_groups g LEFT OUTER JOIN vhffs_users u ON u.username = g.groupname INNER JOIN vhffs_object o ON o.object_id = g.object_id WHERE u.username IS NULL AND o.state = ? GROUP BY substr(g.groupname, 1, 1) ORDER BY substr(g.groupname, 1, 1)';
	return $dbh->selectall_arrayref($sql, { Slice => {} }, Vhffs::Constants::ACTIVATED);
}

sub index {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title( gettext('My Projects') );

	my $owned_projects = [];
	my $contributed_projects = [];
	foreach my $group ( @{$user->get_groups} ) {
		if($group->get_owner_uid == $user->get_uid) {
			push @{$owned_projects}, $group;
		} else {
			push @{$contributed_projects}, $group;
		}
	}

	my $vars = {};
	$vars->{user} = $user;
	$vars->{owned_projects} = $owned_projects;
	$vars->{contributed_projects} = $contributed_projects;
	$vars->{url_help} = ( $panel->get_config->{'url_help'} or '' );

	require Vhffs::Panel::User;
	$panel->render('group/index.tt', $vars);
}

sub create {
	my $panel = shift;

	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $submitted = defined($cgi->param('project_submit'));
	my $groupname = $cgi->param('project_name');
	my $realname = Encode::decode_utf8( scalar $cgi->param('realname') );
	my $description = Encode::decode_utf8( scalar $cgi->param('description') );

	if($submitted) {
		# User posted the form, let's check it
		$panel->add_error( gettext('The groupname must not be the same as your username') ) if $groupname eq $user->get_username;
		$panel->add_error( gettext('Groupname must contain between 3 and 12 characters, only letters or numbers in lower case') ) unless $groupname =~ /^[a-z0-9]{3,12}$/;
		$panel->add_error( gettext('You must enter a description') ) unless defined $description and $description !~ /^\s*$/;
		$panel->add_error( gettext('You must enter a full name') ) unless defined $realname and $realname !~ /^\s*$/;
		$panel->add_error( gettext('The first letter of groupname and full name must be the same') ) unless defined $realname and substr($groupname,0,1) eq lc substr($realname,0,1);

		unless( $panel->has_errors() ) {
			my $group = Vhffs::Panel::Group::create_group( $groupname , $realname, $user , $vhffs, $description );
			unless( defined $group ) {
				$panel->add_error( gettext('Error creating group (maybe a group with the same name already exists)') );
			} else {
				# Creation succeeded. Since we don't care about the correctness
				# of the tags we were passed, we don't do display any error messages
				my @tags = $cgi->param('tags');
				foreach my $tag_id (@tags) {
					my $tag = Vhffs::Tag::get_by_tag_id($vhffs, $tag_id);
					$group->add_tag($tag, $user) if defined $tag and $tag->get_category()->{visibility} == Vhffs::Constants::TAG_VISIBILITY_GROUP_CREATION;
				}
				my $url = '?do=groupindex;msg='.gettext('Project Successfully created !');
				$panel->redirect($url);
				return;
			}
		}
	}

	if( not $submitted or $panel->has_errors() ) {
		my $vars = {};
		$vars->{public_part_available} = $panel->is_public;

		$panel->set_title( gettext('Create a Project') );
		$vars->{owner} = $user->get_username;
		$vars->{groupname} = $groupname;
		$vars->{realname} = $realname;
		$vars->{description} = $description;

		require Vhffs::Tag::Category;
		my $categories = Vhffs::Tag::Category::get_all($vhffs, Vhffs::Constants::TAG_VISIBILITY_GROUP_CREATION);
		foreach my $c (@{$categories}) {
			$c->{tags} = Vhffs::Tag::get_by_category_id($vhffs, $c->{category_id});
		}

		$vars->{tag_categories} = $categories;

		$panel->render('group/create.tt', $vars);
	}
}

sub view {
	my $panel = shift;

	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group ) {
		$panel->render('misc/message.tt', { message => gettext( 'You must specify a project name' ) });
		return;
	}

	unless( $user->can_view( $group ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	$panel->set_group( $group );

	my $vars = { group => $group };
	my $config = $vhffs->get_config;
	my $groups_config = $config->get_groups;
	my @services;
	my $services_labels = {
		cvs => 'CVS repositories',
		dns => 'Domain names',
		mail => 'Mail domains',
		mailinglist => 'Mailing lists',
		mysql => 'MySQL DBs',
		pgsql => 'PostgreSQL DBs',
		repository => 'Download repositories',
		svn => 'SVN repositories',
		git => 'Git repositories',
		mercurial => 'Mercurial repositories',
		bazaar => 'Bazaar repositories',
		web => 'Webareas',
		cron => 'Cron jobs',
	};

	$panel->set_title( sprintf( gettext("Group %s") , $group->get_groupname ) );
	$vars->{help_url} = $groups_config->{url_doc} if defined $groups_config and defined $groups_config->{url_doc};

	foreach my $s(qw/web mysql pgsql cvs svn git mercurial bazaar mailinglist mail repository dns cron/) {
		next unless $config->get_service_availability($s);
		my $module = 'Vhffs::Panel::'.($s eq 'dns' ? 'DNS' : ($s eq 'mailinglist' ? 'MailingList' : ucfirst($s)));
		eval("require $module;");
		{
			no strict 'refs';
			my $ss = {};
			$ss->{name} = $s;
			$ss->{help} = $config->get_service($s)->{url_doc};
			$ss->{items} = &{"$module\::getall_per_group"}($vhffs, $group->get_gid);
			push @services, $ss;
		}
	}
	$vars->{services} = \@services;
	$vars->{services_labels} = $services_labels;

	$panel->render('group/info.tt', $vars);
}

sub prefs {
	my $panel = shift;

	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	my $vars = {};

	unless( defined $group ) {
		$panel->render('misc/message.tt', { message => gettext( "Error. This group doesn't exists") });
		return;
	}

	unless( $user->can_view( $group ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	$panel->set_group( $group );

	if( defined( $cgi->param( 'update_desc_submit' ) ) ) {
		# Description modification
		unless( $user->can_modify( $group ) ) {
			$panel->add_error( gettext( 'You\'re not allowed to do this (ACL rights)' ) );
		} else {
			my $description = Encode::decode_utf8( scalar $cgi->param( 'description' ) );
			my $realname = Encode::decode_utf8( scalar $cgi->param( 'realname' ) );

			$panel->add_error( gettext('You must enter a description') ) unless defined $description and $description !~ /^\s*$/;
			$panel->add_error( gettext('You must enter a full name') ) unless defined $realname and $realname !~ /^\s*$/;
			$panel->add_error( gettext('The first letter of groupname and full name must be the same') ) unless defined $realname and substr($group->get_groupname,0,1) eq lc substr($realname,0,1);

			unless( $panel->has_errors() ) {
				$group->set_description($description);
				$group->set_realname($realname);
				if($group->commit < 0) {
					$panel->add_error( gettext('An error occured while updating the project') );
				} else {
					$panel->add_info( gettext('Group updated') );
				}
			}
		}

	} elsif( defined( $cgi->param( 'remove_user_submit' ) ) ) {
		unless( $user->can_modify( $group ) ) {
			$panel->add_error( gettext( 'You\'re not allowed to do this (ACL rights)' ) );
		} elsif( not $user->is_admin ) {
			$panel->add_error( gettext('Only an administrator can remove someone from a group, please contact the administration team') );
		} else {
			my $username = $cgi->param( 'username' );
			unless( defined $username ) {
				$panel->add_error( gettext('CGI Error !') );
			} elsif( $username =~ /^\s*$/ ) {
				$vars->{add_user_error} = gettext('You must enter an username');
			} else {
				my $del_user = Vhffs::User::get_by_username( $vhffs, $username);
				unless( defined $del_user) {
					$vars->{add_user_error} = gettext('User not found');
				} elsif( $del_user->get_uid == $group->get_owner_uid ) {
					$vars->{add_user_error} = gettext('You cannot remove the owner of the group');
				} elsif( $group->remove_user($del_user) ) {
					$vars->{add_user_info} = gettext('This user will be removed from this group as soon as possible');
				} else {
					$vars->{add_user_error} = gettext('Unable to remove user from group');
				}
			}
		}

	} elsif( defined( $cgi->param( 'add_user_submit' ) ) ) {
		unless( $user->can_modify( $group ) ) {
			$panel->add_error( gettext( 'You\'re not allowed to do this (ACL rights)' ) );
		} else {
			my $username = $cgi->param( 'username' );
			unless( defined $username ) {
				$panel->add_error( gettext('CGI Error !') );
			} elsif( $username =~ /^\s*$/ ) {
				$vars->{add_user_error} = gettext('You must enter an username');
			} else {
				# First, we try to get an user with the *exact* name
				my $new_user = Vhffs::User::get_by_username( $vhffs, $username);
				if(defined $new_user) {
					# Fine, user exists, let's add it
					if( $group->add_user( $new_user ) ) {
						$vars->{add_user_info} = gettext('User will be added as soon as possible');
					} else {
						$vars->{add_user_error} = gettext('Unable to add user, he might already be in the group (waiting for addition or deletion)');
					}
				} else {
					# User not found with exact match,let's search
					require Vhffs::Panel::User;
					my $users = Vhffs::Panel::User::search_user( $vhffs , $username );
					unless( @{$users} ) {
						$vars->{add_user_error} = gettext('User not found');
					} else {
						$vars->{add_user_info} = gettext('Several users matched your query. Please choose between them.');
						$vars->{add_user_list} = $users;
					}
				}
			}
		}

	} elsif( defined( $cgi->param('contact_email_submit') ) ) {
		unless( $user->can_modify( $group ) ) {
			$panel->add_error( gettext( 'You\'re not allowed to do this (ACL rights)' ) );
		} else {
			my $forward = $cgi->param('contact_email');
			my $mg = new Vhffs::Services::MailGroup( $vhffs, $group );
			if( defined $mg ) {
				unless( defined $forward and $forward !~ /^\s*$/ ) {
					$mg->delete_redirect;
					$panel->add_info( gettext('Redirect deleted') );
				} else {
					if( $mg->add_redirect( $forward ) ) {
						$panel->add_info( gettext('Forward added') );
					} else {
						$panel->add_error( gettext('The email you entered fails syntax check') );
					}
				}
			}
		}

	} elsif( defined( $cgi->param('update_quota_submit')) ) {
		update_quota( $panel, $group );

	} elsif( defined( $cgi->param('add_tag_submit') ) ) {
		add_tag( $panel, $group );

	} elsif( defined( $cgi->param('delete_tag_submit') ) ) {
		delete_tag( $panel, $group );

	} elsif( defined( $cgi->param('request_tag_submit') ) ) {
		request_tag( $panel, $group );

	} elsif( defined( $cgi->param('cancel_tag_request_submit') ) ) {
		cancel_request( $panel, $group );
	}

	$panel->set_title( gettext('Project Preferences') );

	$vars->{group} = $group;
	$vars->{mailgroup} = new Vhffs::Services::MailGroup( $vhffs , $group );
	$vars->{use_avatars} = $panel->use_groups_avatars;
	$vars->{group_users} = Vhffs::Panel::Group::getall_users( $vhffs , $group->get_gid );

	fill_tags( $panel, $group, $vars );
	$panel->render('group/prefs.tt', $vars);
}


sub update_quota {
	my $panel = shift;
	my $group = shift;
	my $cgi = $panel->{cgi};
	my $user = $panel->{user};

	my $quota = $cgi->param('new_quota');
	unless(defined $quota and $quota =~ /^\d+$/) {
		$panel->add_error( gettext('Invalid quota') );
		return;
	}

	unless($user->is_admin()) {
		$panel->add_error( gettext('Only administrators are allowed to do this') );
		return;
	}

	$group->set_quota($quota);

	if($group->commit < 0) {
		$panel->add_error( gettext('Unable to apply modifications, please try again later') );
	} else {
		$panel->add_info( gettext('Group updated, please wait while quota is updated on filesystem') );
	}
}

sub fill_tags {
	my $panel = shift;
	my $group = shift;
	my $vars = shift;
	my $vhffs = $panel->{vhffs};
	my $user = $panel->{user};

	my $visibility = ($user->is_admin() ? Vhffs::Constants::TAG_VISIBILITY_ADMINS :
	  ($user->is_moderator() ? Vhffs::Constants::TAG_VISIBILITY_MODERATORS :
	  Vhffs::Constants::TAG_VISIBILITY_PUBLIC) );

	my $categories = Vhffs::Tag::Category::get_all($vhffs, $visibility);
	foreach my $c (@{$categories}) {
		$c->{tags} = Vhffs::Tag::get_by_category_id($vhffs, $c->{category_id});
	}
	$vars->{tag_categories} = $categories;
	$vars->{current_tag_categories} = $group->get_tags($visibility);
	$vars->{tag_requests} = $group->get_tag_requests();
}

sub add_tag {
	my $panel = shift;
	my $group = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};
	my $user = $panel->{user};

	unless( $user->can_modify( $group ) or $user->is_moderator) {
		$panel->add_error( gettext( 'You\'re not allowed to do this (ACL rights)' ) );
		return 0;
	}

	my $tag_id = $cgi->param('tag_id');

	unless(defined $tag_id) {
		$panel->add_error( gettext('CGI error') );
		return 0;
	}

	my $tag = Vhffs::Tag::get_by_tag_id($vhffs, $tag_id);

	unless(defined $tag) {
		$panel->add_error( gettext('Tag not found') );
		return 0;
	}

	if( ($tag->{visibility} >= Vhffs::Constants::TAG_VISIBILITY_ADMINS && !$user->is_admin()) ||
		($tag->{visibility} >= Vhffs::Constants::TAG_VISIBILITY_MODERATORS && !$user->is_moderator())) {
		$panel->add_error( gettext('You don\'t have enough privileges to add this tag') );
		return 0;
	}

	if($group->add_tag($tag, $user)) {
		$panel->add_info( gettext('Tag added') );
	} else {
		$panel->add_error( gettext('Unable to add tag, check it was not already added to your project') );
	}
}

sub delete_tag {
	my $panel = shift;
	my $group = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};
	my $user = $panel->{user};

	unless( $user->can_modify( $group ) or $user->is_moderator) {
		$panel->add_error( gettext( 'You\'re not allowed to do this (ACL rights)' ) );
		return 0;
	}

	my $tag_id = $cgi->param('tag_id');

	unless(defined $tag_id) {
		$panel->add_error( gettext('CGI error') );
		return 0;
	}

	my $tag = Vhffs::Tag::get_by_tag_id($vhffs, $tag_id);

	unless(defined $tag) {
		$panel->add_error( gettext('Tag not found') );
		return 0;
	}

	if( ($tag->{visibility} >= Vhffs::Constants::TAG_VISIBILITY_ADMINS && !$user->is_admin()) ||
		($tag->{visibility} >= Vhffs::Constants::TAG_VISIBILITY_MODERATORS && !$user->is_moderator())) {
		$panel->add_error( gettext('You don\'t have enough privileges to delete this tag') );
		return 0;
	}

	if($group->delete_tag($tag, $user)) {
		$panel->add_info( gettext('Tag deleted') );
	} else {
		$panel->add_error( gettext('Unable to delete tag') );
	}
}

sub request_tag {
	my $panel = shift;
	my $group = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};
	my $user = $panel->{user};

	unless( $user->can_modify( $group ) ) {
		$panel->add_error( gettext( 'You\'re not allowed to do this (ACL rights)' ) );
		return 0;
	}

	my $category_label = $cgi->param('category');
	my $tag_label = $cgi->param('tag');

	unless(defined $category_label && defined $tag_label) {
		$panel->add_error( gettext('CGI error') );
		return 0;
	}

	if($category_label =~ /^\s*$/) {
		$panel->add_error( gettext('Category can\'t be empty') );
		return 0;
	}

	if($tag_label =~ /^\s*$/) {
		$panel->add_error( gettext('Tag name can\'t be empty') );
		return 0;
	}

	unless( defined(Vhffs::Tag::Request::create($vhffs, $category_label, $tag_label, $user, $group) ) ) {
		$panel->add_error( gettext('An error occured while saving your request') );
		return;
	}

	$panel->add_info( gettext('Tag request saved, please wait while a moderator approve it') );
}

sub cancel_request {
	my $panel = shift;
	my $group = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};
	my $user = $panel->{user};

	unless( $user->can_modify( $group ) ) {
		$panel->add_error( gettext( 'You\'re not allowed to do this (ACL rights)' ) );
		return 0;
	}

	my $request_id = $cgi->param('request_id');

	my $request = Vhffs::Tag::Request::get_by_request_id($vhffs, $request_id);

	unless(defined $request) {
		$panel->add_error( gettext('Request not found') );
		return 0;
	}

	if($request->{tagged_id} != $group->get_oid()) {
		$panel->add_error( gettext('You can only delete requests attached to your group') );
		return 0;
	}

	$request->delete();

	$panel->add_info( gettext('Request canceled') );
	return 1;
}

sub history {
	my $panel = shift;

	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );

	unless( defined $group ) {
		$panel->render('misc/message.tt', { message => gettext( 'Error. This group doesn\'t exists') });
		return;
	}

	unless( $group->get_status == Vhffs::Constants::ACTIVATED ) {
		$panel->render('misc/message.tt', { message => gettext( 'This object is not functional yet. Please wait creation or moderation.') });
		return;
	}

	unless( $user->can_view( $group ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}

	$panel->set_group( $group );
	$panel->set_title( gettext('Project History') );

	require DateTime;
	require DateTime::Locale;
	my $loc = DateTime::Locale->load($user->get_lang);

	my $history = $group->get_full_history;
	foreach (@{$history}) {
		my $dt = DateTime->from_epoch( epoch => $_->{date}, locale => $user->get_lang);
		$_->{object} = Vhffs::ObjectFactory::fetch_object( $vhffs , $_->{object_id} );
		$_->{object_type} = Vhffs::Functions::type_string_from_type_id( $_->{type} );
	}
	$panel->render('misc/history.tt', { history => $history });
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
		  search_title => gettext('Groups search'),
		  type => 'group'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all groups');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{groups} = search_group( $vhffs , $name );
	$panel->render('admin/group/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Groups\' administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_group_category() ] } );
}

1;
