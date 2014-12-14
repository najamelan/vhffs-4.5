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

package Vhffs::Panel::Tag;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Constants;
use Vhffs::Panel::Group;
require Vhffs::Tag;
require Vhffs::Tag::Category;
require Vhffs::Tag::Request;

=head1 NAME

Vhffs::Panel::Tag - Handle tags information in the panel.

=head1 METHODS

=cut

=head2 get_groups

	Vhffs::Panel::Tag::get_groups($vhffs, $category_name, $tag_name, $start)

Fetches 10 groups associated to tag C<$tag_name> in (optional) category
C<$category_name> starting at index C<$start>

=cut

sub get_groups {
	my ($vhffs, $category_name, $tag_name, $start) = @_;

	my $select =  'SELECT g.gid, g.groupname, g.realname, o.description, owner.username AS owner_name ';
	my $restriction = ' FROM vhffs_groups g INNER JOIN vhffs_object o ON o.object_id=g.object_id '.
		'INNER JOIN vhffs_object_tag ot ON ot.object_id = o.object_id '.
		'INNER JOIN vhffs_tag t ON t.tag_id = ot.tag_id '.
		'INNER JOIN vhffs_tag_category c ON t.category_id = c.tag_category_id '.
		'INNER JOIN vhffs_users owner ON owner.uid = o.owner_uid '.
		'WHERE o.state = ? AND t.label = ? ';
	my @params;
	push @params, Vhffs::Constants::ACTIVATED;
	push @params, $tag_name;
	if(defined $category_name) {
		$restriction .= ' AND c.label = ?';
		push @params, $category_name;
	}

	my $limit = ' LIMIT 10';
	$limit .= ' OFFSET '.($start * 10) if(defined $start);

	my $groups = Vhffs::Panel::Group::fetch_groups_and_users($vhffs, $select.$restriction.' ORDER BY g.groupname '.$limit, @params);

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare('SELECT COUNT(*) '.$restriction);
	return undef unless ( $sth->execute(@params) );

	my ($count) = $sth->fetchrow_array();

	return ($groups, $count);
}

=head2 get_by_tag_ids

	my $tags = Vhffs::Panel::get_by_tag_ids($vhffs, id1, id2);

Return information about specific public tags.

=cut

sub get_by_tag_ids {
	my $vhffs = shift;
	my @ids = @_;
	return _get_by_tag_ids($vhffs, 0, @ids);
}

sub get_all_excluding {
	my $vhffs = shift;
	my @ids = @_;
	return _get_by_tag_ids($vhffs, 1, @ids);
}

sub _get_by_tag_ids {
	my $vhffs = shift;
	my $exclude = shift;
	my @ids = @_;

	# There can be no ID if we are in exclude mode (meaning
	# that we want all tags)

	return undef unless($exclude ||  scalar(@ids) > 0);

	my $sql = 'SELECT c.tag_category_id AS category_id, c.label AS category_label, t.tag_id, t.label AS tag_label '.
		'FROM vhffs_tag t INNER JOIN vhffs_tag_category c ON c.tag_category_id = t.category_id '.
		'WHERE c.visibility = '.Vhffs::Constants::TAG_VISIBILITY_PUBLIC;

	if(scalar(@ids)) {
		$sql .= ' AND tag_id '.($exclude ? 'NOT ' : '').'IN(?';
		$sql .= ', ?' x (scalar(@ids) - 1);
		$sql .= ')';
	}
	$sql .= ' ORDER BY c.label, t.label';
	my $dbh = $vhffs->get_db;
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @ids);
}

sub create_tag {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $vars = {};

	if(defined $cgi->param('create_tag_submit')) {
		if(_create_tag( $panel , $vars )) {
			$panel->redirect('?do=taglist;msg='.gettext('Tag successfully created'));
		}
	}

	$vars->{categories} = Vhffs::Tag::Category::get_all($panel->{vhffs});
	$panel->render('admin/tag/create.tt', $vars);
}

sub _create_tag {
	my $panel = shift;
	my $vars = shift;
	my $cgi = $panel->{'cgi'};

	my $category_id = $cgi->param('category_id');
	my $label = $cgi->param('label');
	my $description = $cgi->param('description');
	my $vhffs = $panel->{vhffs};

	$vars->{label} = $label;
	$vars->{description} = $description;
	$vars->{category_id} = $category_id;

	unless(defined $category_id && defined $label && defined $description) {
		$panel->add_error( gettext('CGI Error!') );
		return 0;
	}

	if($category_id !~ /^\d+$/) {
		$panel->add_error( gettext('Invalid category') );
		return 0;
	}

	if($label =~ /^\s*$/) {
		$panel->add_error( gettext('You have to enter a label') );
		return 0;
	}

	if($description =~ /^\s*$/) {
		$panel->add_error( gettext('You have to enter a description') );
		return 0;
	}

	my $category = Vhffs::Tag::Category::get_by_category_id($vhffs, $category_id);

	unless(defined $category) {
		$panel->add_error( gettext('Category does not exists') );
		return 0;
	}

	unless(defined Vhffs::Tag::create($vhffs, $label, $description, $panel->{user}, $category)) {
		$panel->add_error( gettext('Unable to create tag') );
		return 0;
	}

	return 1;
}

sub create_category {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $vars = {};

	if(defined $cgi->param('create_tag_category_submit')) {
		if(_create_category( $panel, $vars )) {
			$panel->redirect('?do=tagcategorylist;msg='.gettext('Tag category successfully created'));
		}
	}

	$panel->set_title(gettext('Create Tag Category'));
	$vars->{visibilities} = [
		{ code => Vhffs::Constants::TAG_VISIBILITY_GROUP_CREATION, label => gettext('Public (available on group creation)') },
		{ code => Vhffs::Constants::TAG_VISIBILITY_PUBLIC, label => gettext('Public') },
		{ code => Vhffs::Constants::TAG_VISIBILITY_MODERATORS, label => gettext('Moderators') },
		{ code => Vhffs::Constants::TAG_VISIBILITY_ADMINS, label => gettext('Administrators') }
	];

	$panel->render('admin/tag/category/create.tt', $vars);
}

sub _create_category {
	my $panel = shift;
	my $vars = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};

	my $label = $cgi->param('label');
	my $description = $cgi->param('description');
	my $visibility = $cgi->param('visibility');

	$vars->{label} = $label;
	$vars->{description} = $description;
	$vars->{visibility} = $visibility;

	unless( defined $label and defined $description and defined $visibility ) {
		$panel->add_error( gettext('CGI error') );
		return 0;
	}

	if($label =~ /^\s*$/ || $description =~ /^\s*$/) {
		$panel->add_error( gettext('You have to enter a label and a description for the category') );
		return 0;
	}

	if(!defined Vhffs::Tag::Category::create($vhffs, $label, $description, $visibility, $panel->{user})) {
		$panel->add_error( gettext('Unable to create category') );
		return 0;
	}
	return 1;
}

sub list_tag {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	if(defined $cgi->param('delete_tag_submit')) {
		if(_delete_tag( $panel )) {
			$panel->add_info( gettext('Tag deleted') );
		} else {
			$panel->add_error( gettext('Unable to delete tag') );
		}
	}

	$panel->set_title(gettext('Tags'));
	my $vars = {
		tags => Vhffs::Tag::get_all($panel->{vhffs})
	};
	$panel->render('admin/tag/list.tt', $vars);
}

sub _delete_tag {
	my $panel = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};

	my $tag_id = $cgi->param('tag_id');
	my $tag = Vhffs::Tag::get_by_tag_id($vhffs, $tag_id);
	return 0 unless defined $tag;

	return $tag->delete();
}

sub list_category {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	if(defined $cgi->param('delete_category_submit')) {
		if(_delete_category( $panel )) {
			$panel->add_info( gettext('Category deleted') );
		} else {
			$panel->add_error( gettext('Unable to delete category') );
		}
	}

	$panel->set_title(gettext('Tag categories'));

	my $vars = {};
	$vars->{categories} = Vhffs::Tag::Category::get_all($panel->{vhffs});
	$panel->render('admin/tag/category/list.tt', $vars);
}

sub _delete_category {
	my $panel = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};

	my $category_id = $cgi->param('category_id');
	my $category = Vhffs::Tag::Category::get_by_category_id($panel->{vhffs}, $category_id);
	return 0 unless defined $category;

	return $category->delete();
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Tags\' administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_tag_category() ] } );
}

sub list_request {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $requests = Vhffs::Tag::Request::get_all($panel->{vhffs});
	$panel->render('admin/tag/request/list.tt', {
		requests => $requests
	});
}

sub edit_tag {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};
	my $tag;

	unless( defined $cgi->param('tag_id') ) {
		$panel->render('misc/message.tt', { message => gettext('CGI Error!') } );
		return;
	}

	unless( defined ( $tag = Vhffs::Tag::get_by_tag_id($panel->{vhffs}, scalar $cgi->param('tag_id')) ) ) {
		$panel->render('misc/message.tt', { message => gettext('Tag not found!') } );
		return;
	}

	if( defined $cgi->param('update_tag_submit') ) {
		if( _update_tag( $panel, $tag )) {
			$panel->add_info( gettext('Tag successfully updated') );
		} else {
			$panel->add_error( gettext('Unable to update tag') )
		}
	}

	my $vars = {
		tag => $tag,
		categories => Vhffs::Tag::Category::get_all($vhffs)
	};
	$panel->render('admin/tag/edit.tt', $vars);
}

sub _update_tag {
	my $panel = shift;
	my $tag = shift;
	my $cgi = $panel->{cgi};
	my $user = $panel->{'user'};

	my $tag_id = $cgi->param('tag_id');
	my $label = $cgi->param('label');
	my $description = $cgi->param('description');
	my $category_id = $cgi->param('category_id');

	unless( defined $tag_id and defined $label and defined $description and defined $category_id ) {
		$panel->add_error( gettext('CGI error') );
		return 0;
	}

	if($label =~ /^\s*$/) {
		$panel->add_error( gettext('You have to enter a label') );
	}

	if($description =~ /^\s*$/) {
		$panel->add_error( gettext('You have to enter a description') );
	}

	if($category_id !~ /^\d+$/) {
		$panel->add_error( gettext('Invalid category') );
	}

	if($panel->has_errors()) {
		return 0;
	}

	$tag->{label} = $label;
	$tag->{description} = $description;
	$tag->{category_id} = $category_id;
	$tag->{updated} = time();
	$tag->{updater_id} = $user->get_uid;
	return $tag->save();
}

sub edit_category {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};
	my $category;
	my $vars = {};

	unless( defined $cgi->param('category_id') ) {
		$panel->render('misc/message.tt', { message => gettext('CGI Error!') } );
		return;
	}

	unless( defined( $category = Vhffs::Tag::Category::get_by_category_id($panel->{vhffs}, scalar $cgi->param('category_id')) ) ) {
		$panel->render('misc/message.tt', { message => gettext('Category not found!') } );
		return;
	}

	if(defined $cgi->param('update_tag_category_submit')) {
		if( _update_category( $panel, $category )) {
			$panel->add_info( gettext('Tag category successfully updated') );
		} else {
			$panel->add_error( gettext('Unable to update category') )
		}
	}

	$panel->set_title(gettext('Update Tag Category'));
	$vars->{visibilities} = [
		{ code => Vhffs::Constants::TAG_VISIBILITY_GROUP_CREATION, label => gettext('Public (available on group creation)') },
		{ code => Vhffs::Constants::TAG_VISIBILITY_PUBLIC, label => gettext('Public') },
		{ code => Vhffs::Constants::TAG_VISIBILITY_MODERATORS, label => gettext('Moderators') },
		{ code => Vhffs::Constants::TAG_VISIBILITY_ADMINS, label => gettext('Administrators') }
	];
	$vars->{category} = $category;
	$panel->render('admin/tag/category/edit.tt', $vars);
}

sub _update_category {
	my $panel = shift;
	my $category = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};
	my $user = $panel->{user};

	my $label = $cgi->param('label');
	my $description = $cgi->param('description');
	my $visibility = $cgi->param('visibility');

	unless( defined $label and defined $description and defined $visibility ) {
		$panel->add_error( gettext('CGI error') );
		return 0;
	}

	if($label =~ /^\s*$/) {
		$panel->add_error( gettext('You have to enter a label') );
	}

	if($description =~ /^\s*$/) {
		$panel->add_error( gettext('You have to enter a description') );
	}

	if($visibility !~ /^\d+$/) {
		$panel->add_error( gettext('Invalid visibility') );
	}

	if($panel->has_errors()) {
		return 0;
	}

	$category->{label} = $label;
	$category->{description} = $description;
	$category->{visibility} = $visibility;
	$category->{updated} = time();
	$category->{updater_id} = $user->get_uid;
	return $category->save();
}

sub details_request {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $request_id;
	my $vars = {};

	unless(defined ($request_id = $cgi->param('request_id'))) {
		$panel->render('misc/message.tt', {
			message => gettext('CGI Error'),
			refresh_url => '?do=tagrequestlist'
		});
		return;
	}

	my $request;

	unless(defined ($request = Vhffs::Tag::Request::get_by_request_id($vhffs, $request_id))) {
		$panel->render('misc/message.tt', {
			message => gettext('Tag request not found'),
			refresh_url => '?do=tagrequestlist'
			});
		return;
	}

	if(defined $cgi->param('accept_request_submit')) {
		if(_accept_request( $panel, $request )) {
			$panel->render('misc/message.tt', {
				message => gettext('Tag request accepted'),
				refresh_url => '?do=tagrequestlist'
			});
			return;
		}

		$vars->{category_label} = scalar $cgi->param('category_label');
		$vars->{category_description} = scalar $cgi->param('category_description');
		$vars->{tag_label} = scalar $cgi->param('tag_label');
		$vars->{tag_description} = scalar $cgi->param('tag_description');
	}

	if(defined $cgi->param('discard_request_submit')) {
		$request->delete();
		$panel->render('misc/message.tt', {
			message => gettext('Tag request deleted'),
			refresh_url => '?do=tagrequestlist'
		});
		return;
	}

	$panel->set_title( gettext('Tag request details') );

	my $category_id = $cgi->param('category');

	if(defined $category_id) {
		$vars->{category_tags} = Vhffs::Tag::get_by_category_id($vhffs, $category_id);
		$vars->{selected_category} = $category_id;
	}
	$vars->{categories} = Vhffs::Tag::Category::get_all($vhffs);
	$vars->{request} = $request;

	$panel->render('admin/tag/request/details.tt', $vars);
}

sub _accept_request {
	my $panel = shift;
	my $request = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};

	my $category_id = $cgi->param('category');
	my $category_label = $cgi->param('category_label');
	my $tag_id = $cgi->param('tag');
	my $tag_label = $cgi->param('tag_label');
	my $category_description = $cgi->param('category_description');
	my $tag_description = $cgi->param('tag_description');

	unless(defined $category_id and defined $category_label and defined $category_description
			and defined $tag_id and defined $tag_label and defined $tag_description) {
		$panel->add_error(gettext('CGI Error'));
		return 0;
	}

	my $category;
	my $tag;

	if($category_id < 0) {
		if($tag_id > 0) {
			$panel->add_error( gettext('If you want to create a new category, you have to create a new tag too') );
			return 0;
		}

		if($category_label =~ /^\s*$/ || $category_description =~ /^\s*$/) {
			$panel->add_error( gettext('You have to enter a label and a description for the category') );
			return 0;
		}

		if($tag_label =~ /^\s*$/ || $tag_description =~ /^\s*$/) {
			$panel->add_error( gettext('You have to enter a label and a description for the tag') );
			return 0;
		}

		unless(defined ($category = Vhffs::Tag::Category::create($vhffs, $category_label, $category_description, Vhffs::Constants::TAG_VISIBILITY_PUBLIC, $panel->{user}) ) ) {
			$panel->add_error( gettext('Unable to create category') );
			return 0;
		}

		unless(defined ($tag = Vhffs::Tag::create($vhffs, $tag_label, $tag_description, $panel->{user}, $category) ) ) {
			$panel->add_error( gettext('Unable to create tag') );
			$category->delete();
			return 0;
		}
	} else {
		$category = Vhffs::Tag::Category::get_by_category_id($vhffs, $category_id);
		unless(defined $category) {
			$panel->add_error( gettext('Category not found') );
			return 0;
		}

		if($tag_id > 0) {
			$tag = Vhffs::Tag::get_by_tag_id($vhffs, $tag_id);
			unless( defined($tag) ) {
				$panel->add_error( gettext('Tag not found') );
				return 0;
			}
		} else {
			if($tag_label =~ /^\s*$/ || $tag_description =~ /^\s*$/) {
				$panel->add_error( gettext('You have to enter a label and a description for the tag') );
				return 0;
			}

			$tag = Vhffs::Tag::create($vhffs, $tag_label, $tag_description, $panel->{user}, $category);

			unless(defined $tag) {
				$panel->add_error( gettext('Unable to create tag') );
				return 0;
			}
		}
	}

	# Adds the tag to the object for which it has
	# been requested.

	my $object = $request->get_tagged();
	if(defined $object) {
		my $user = $request->get_requester();
		$user = $panel->{user} unless(defined $user);
		$object->add_tag($tag, $user);
	}

	$request->delete();

	return 1;
}

1;
