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

package Vhffs::Panel::Public;

use base qw(Vhffs::Panel);

use locale;
use Locale::gettext;
use POSIX qw(locale_h);

use Template;
use Encode;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::Tag;
use Vhffs::Functions;
use Vhffs::Constants;
require Vhffs::User;
require Vhffs::Group;
require Vhffs::Tag;
require Vhffs::Panel::Commons;
require Vhffs::Panel::User;
require Vhffs::Panel::Group;
require Vhffs::Panel::Tag;

sub new {
	my $class = shift;
	my $panel = $class->SUPER::new(@_);
	return undef unless defined $panel;
	unless( $panel->check_public() ) {
		$panel->render('misc/closed.tt', undef);
		return undef;
	}
	return $panel;
}

sub render {
	my ($self, $file, $vars) = @_;
	my $vhffs = $self->{vhffs};
	my $conf = $vhffs->get_config;

	$vars = {} unless(defined $vars);

	$vars->{left} = 'parts/left-menu.tt' unless(defined $vars->{left});
	$vars->{right} = 'parts/tags-cloud.tt' unless(defined $vars->{right});
	$vars->{top} = 'parts/top-menu.tt' unless(defined $vars->{top});
	$vars->{help_url} = $conf->get_panel->{url_help};
	$vars->{users_avatar} = $conf->get_panel->{'users_avatars'};
	$vars->{groups_avatar} = $conf->get_panel->{'groups_avatars'};

	# Handling ajax stuff
	if( $vhffs->is_connected ) {
		unless($self->{is_ajax_request}) {
			$vars->{popular_tags} = Vhffs::Tag::get_most_popular_tags($self->{vhffs});
			$vars->{random_tags} = Vhffs::Tag::get_random_tags($self->{vhffs});
		}
	}

	$self->SUPER::render($file, $vars, 'public.tt', 'public');
}

sub lastgroups {
	my $panel = shift;

	my $hostname = $panel->{vhffs}->get_config->get_host_name;

	my $vars = {
		lg_title => sprintf( gettext('Latest projects on %s') , $hostname ),
		groups => Vhffs::Panel::Group::get_last_groups( $panel->{vhffs} )
	};

	$panel->render('content/last-groups.tt', $vars);
}

sub lastusers {
	my $panel = shift;

	my $users = Vhffs::Panel::User::get_last_users($panel->{vhffs});

	$panel->render('content/last-users.tt', {
		users => $users
	});
}

sub groupsearch {
	my $panel = shift;
	my $cgi = $panel->{cgi};

	my @included_tags_ids = map { int($_); } $cgi->param('included_tags');
	my @excluded_tags_ids = map { int($_); } $cgi->param('excluded_tags');

	my $discard_excluded = $cgi->param('discard_ex');
	@excluded_tags_ids = grep { $_ != $discard_excluded } @excluded_tags_ids if(defined $discard_excluded);

	my $discard_included = $cgi->param('discard_inc');
	@included_tags_ids = grep { $_ != $discard_included } @included_tags_ids if(defined $discard_included);

	if( defined $cgi->param('groupname') and defined $cgi->param('description') ) {
		my $groupname = Encode::decode_utf8(scalar $cgi->param('groupname'));
		$groupname = '' unless(defined $groupname);		# Direct tag click brings us here without  without groupname ...
		my $description = Encode::decode_utf8(scalar $cgi->param('description'));
		$description = '' unless(defined $description);	# ... and without description

		# current page
		my $page = defined($cgi->param('page')) ? int($cgi->param('page')) : 1;

		my ($groups, $count) = Vhffs::Panel::Group::public_search($panel->{vhffs}, $groupname, $description, \@included_tags_ids, \@excluded_tags_ids, $page - 1);

		if(scalar(@$groups) == 0) {
			$panel->render('common/error.tt', {
				message => gettext('No group found')
			});
			return;
		}

		my $pager = Vhffs::Panel::Commons::get_pager($page, $count, 10, 5, $panel->{url}, { groupname => $groupname, description => $description, included_tags => \@included_tags_ids, excluded_tags => \@excluded_tags_ids, do => 'groupsearch' });

		my $vars = {
			groups => $groups,
			gs_title => gettext( 'Search results' ),
			gs_pager => $pager
		};

		$panel->render('content/groupsearch-results.tt', $vars);
		return;
	}

	my $query_string = '';

	$query_string .= 'included_tags='.(join(';included_tags=', @included_tags_ids)) if(scalar(@included_tags_ids));
	$query_string .= ';' if(scalar(@included_tags_ids) and scalar(@excluded_tags_ids));
	$query_string .= 'excluded_tags='.(join(';excluded_tags=', @excluded_tags_ids)) if(scalar(@excluded_tags_ids));

	my $vars = {
		included_tags => Vhffs::Panel::Tag::get_by_tag_ids($panel->{vhffs}, @included_tags_ids),
		excluded_tags => Vhffs::Panel::Tag::get_by_tag_ids($panel->{vhffs}, @excluded_tags_ids),
		other_tags => Vhffs::Panel::Tag::get_all_excluding($panel->{vhffs}, @included_tags_ids, @excluded_tags_ids),
		query_string => $query_string
	};

	$panel->render('content/groupsearch-form.tt', $vars);
}

sub group {
	my $panel = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};

	my $config = $vhffs->get_config();

	my $groupname = $cgi->param('name');
	unless(defined $groupname) {
		$panel->render('common/error.tt', {
			message => gettext('CGI Error')
		});
		return;
	}

	my $group = Vhffs::Group::get_by_groupname($panel->{vhffs}, $groupname);

	unless(defined $group) {
		$panel->render('common/error.tt', {
			message => gettext('Group not found')
		});
		return;
	}

	my $tag_categories = $group->get_tags(Vhffs::Constants::TAG_VISIBILITY_PUBLIC);

	my $vars = {
		group => $group,
		tag_categories => $tag_categories
	};

	# Services filling... Really boring
	if( $config->get_service_availability('web') == 1 ) {
		use Vhffs::Panel::Web;
		$vars->{websites} = Vhffs::Panel::Web::get_websites_per_group($vhffs, $group->get_gid);
	}

	if( $vhffs->get_config->get_service_availability('cvs') == 1 ) {
		use Vhffs::Panel::Cvs;
		$vars->{cvs} = {
			cvs_web_url => $config->get_service('cvs')->{'cvsweb_url'},
			repositories => Vhffs::Panel::Cvs::get_repos_per_group($vhffs, $group->get_gid )
		};
	}

	if( $vhffs->get_config->get_service_availability('svn') == 1 ) {
		use Vhffs::Panel::Svn;
		$vars->{svn} = {
			svn_web_url => $config->get_service('svn')->{'svnweb_url'},
			repositories => Vhffs::Panel::Svn::get_repos_per_group($vhffs, $group->get_gid )
		};
	}

	if( $vhffs->get_config->get_service_availability('git') == 1 ) {
		use Vhffs::Panel::Git;
		$vars->{git} = {
			git_web_url => $config->get_service('git')->{'gitweb_url'},
			repositories => Vhffs::Panel::Git::get_repos_per_group($vhffs, $group->get_gid )
		};
	}

	if( $vhffs->get_config->get_service_availability('mercurial') == 1 ) {
		use Vhffs::Panel::Mercurial;
		$vars->{mercurial} = {
			mercurial_web_url => $config->get_service('mercurial')->{'mercurialweb_url'},
			repositories => Vhffs::Panel::Mercurial::get_repos_per_group($vhffs, $group->get_gid )
		};
	}

	if( $vhffs->get_config->get_service_availability('mailinglist') == 1 ) {
		use Vhffs::Panel::MailingList;;
		$vars->{ml} = {
			archives_url => $config->get_service('mailinglist')->{'url_archives'},
			lists => Vhffs::Panel::MailingList::get_lists_per_group($vhffs, $group->get_gid )
		};
	}

	$panel->render('content/group-details.tt', $vars);
}

sub allgroups {
	my $panel = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};

	my $letter = $cgi->param('letter');
	my $used_letters = Vhffs::Panel::Group::get_used_letters($vhffs);
	$letter = $used_letters->[0]{letter} unless(defined $letter || !defined $used_letters->[0]{letter});
	undef $letter if defined $letter and $letter eq 'all';

	my $page = $cgi->param('page');
	$page = 1 unless defined $page and int($page) > 0;
	my $per_page_count = 10;

	my $result = Vhffs::Panel::Group::get_groups_starting_with( $vhffs , $letter, ($page - 1) *  $per_page_count, $per_page_count);
	my $pager = Vhffs::Panel::Commons::get_pager($page, $result->{total_count}, $per_page_count, 5, $panel->{url}, {
		letter => defined($letter) ? $letter : 'all',
		do => 'allgroups'
	});

	my $vars = {
		pager => $pager,
		groups => $result->{data},
		letters => $used_letters
	};

	$panel->render('content/all-groups.tt', $vars);
}

sub usersearch {
	my $panel = shift;
	my $cgi = $panel->{cgi};

	if( defined $cgi->param('username') ) {
		my $username = Encode::decode_utf8(scalar $cgi->param('username'));
		my $page = defined($cgi->param('page')) ? int($cgi->param('page')) : 1;

		if($username =~ /^\s*$/) {
			$panel->render('common/error.tt', {
				message => gettext('You have to enter an username')
			});
			return;
		}

		my ($users, $total) = Vhffs::Panel::User::public_search($panel->{vhffs}, $username, ($page - 1));

		if($total == 0) {
			$panel->render('common/error.tt', {
				message => gettext('No user found')
			});
			return;
		}

		my $pager = Vhffs::Panel::Commons::get_pager($page, $total, 10, 5, $panel->{url}, { username => $username, do => 'usersearch' });

		$panel->render('content/usersearch-results.tt', {
			users => $users,
			u_pager => $pager
		});
		return;
	}

	$panel->render('content/usersearch-form.tt');
}

sub user {
	my $panel = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};

	my $config = $vhffs->get_config();

	my $username = $cgi->param('name');
	unless(defined $username) {
		$panel->render('common/error.tt', {
			message => gettext('CGI Error')
		});
		return;
	}

	my $user = Vhffs::User::get_by_username($panel->{vhffs}, $username);
	unless(defined $user) {
		$panel->render('common/error.tt', {
			message => gettext('User not found')
		});
		return;
	}

	my @groups;
	foreach my $grouphash (@{$user->get_groups}) {
		push @groups, $grouphash->{groupname};
	}
	$user->{groups} = \@groups;

	my $vars = {
		user => $user,
	};

	$panel->render('content/user-details.tt', $vars);
}

sub tags {
	my $panel = shift;
	my $cgi = $panel->{cgi};

	my $search = Encode::decode_utf8(scalar $cgi->param('search'));
	unless( defined $search ) {
		$panel->render('common/error.tt', {
			message => gettext('CGI Error!')
		});
		return;
	}

	# TODO Handle complicated search patterns
	my ($category, $tag) = split /::/, $search;
	unless(defined $tag) {
		$tag = $category;
		$category = undef;
	}

	# current page
	my $page = defined($cgi->param('page')) ? int($cgi->param('page')) : 1;

	my ($groups, $count) = Vhffs::Panel::Tag::get_groups($panel->{vhffs}, $category, $tag, $page - 1);

	if(scalar(@$groups) == 0) {
		$panel->render('common/error.tt', {
			message => gettext('No group found')
		});
		return;
	}

	my $url = $panel->{url};
#	$url =~ s!tags/.*!tagsearch.pl!;

	require URI::Escape;
	my $pager = Vhffs::Panel::Commons::get_pager($page, $count, 10, 5, $url, { search => URI::Escape::uri_escape($search), do => 'tags' });

	my $vars = {
		groups => $groups,
		gs_title => gettext( 'Search results' ),
		gs_pager => $pager
	};

	$panel->render('content/groupsearch-results.tt', $vars);
}

sub externstats {
	my $panel = shift;
	my $vhffs = $panel->{vhffs};

	my $stats = $vhffs->get_stats;
	return unless defined $stats;

	my $output = '';

	$output .= '<?xml version="1.0" encoding="UTF-8"?>'."\n";
	$output .= '<stats>'."\n";

	$output .= '<users>'."\n";
	$output .= '  <total>'.$stats->get_user_total.'</total>'."\n";
	$output .= '</users>'."\n";

	$output .= '<groups>'."\n";
	$output .= '  <total>'.$stats->get_groups_total.'</total>'."\n";
	$output .= '  <activated>'.$stats->get_groups_activated.'</activated>'."\n";
	$output .= '</groups>'."\n";

	$output .= '<service name="web">'."\n";
	$output .= '  <awaitingmoderation>'.$stats->get_web_in_moderation.'</awaitingmoderation>'."\n";
	$output .= '  <activated>'.$stats->get_web_activated.'</activated>'."\n";
	$output .= '</service>'."\n";

	$output .= '<service name="mysql">'."\n";
	$output .= '  <awaitingmoderation>'.$stats->get_mysql_in_moderation.'</awaitingmoderation>'."\n";
	$output .= '  <activated>'.$stats->get_mysql_activated.'</activated>'."\n";
	$output .= '</service>'."\n";

	$output .= '<service name="pgsql">'."\n";
	$output .= '  <awaitingmoderation>'.$stats->get_pgsql_in_moderation.'</awaitingmoderation>'."\n";
	$output .= '  <activated>'.$stats->get_pgsql_activated.'</activated>'."\n";
	$output .= '</service>'."\n";

	$output .= '<service name="cvs">'."\n";
	$output .= '  <awaitingmoderation>'.$stats->get_cvs_in_moderation.'</awaitingmoderation>'."\n";
	$output .= '  <activated>'.$stats->get_cvs_activated.'</activated>'."\n";
	$output .= '</service>'."\n";

	$output .= '<service name="svn">'."\n";
	$output .= '  <awaitingmoderation>'.$stats->get_svn_in_moderation.'</awaitingmoderation>'."\n";
	$output .= '  <activated>'.$stats->get_svn_activated.'</activated>'."\n";
	$output .= '</service>'."\n";

	$output .= '<service name="git">'."\n";
	$output .= '  <awaitingmoderation>'.$stats->get_git_in_moderation.'</awaitingmoderation>'."\n";
	$output .= '  <activated>'.$stats->get_git_activated.'</activated>'."\n";
	$output .= '</service>'."\n";

	$output .= '<service name="mercurial">'."\n";
	$output .= '  <awaitingmoderation>'.$stats->get_mercurial_in_moderation.'</awaitingmoderation>'."\n";
	$output .= '  <activated>'.$stats->get_mercurial_activated.'</activated>'."\n";
	$output .= '</service>'."\n";

	$output .= '<service name="bazaar">'."\n";
	$output .= '  <awaitingmoderation>'.$stats->get_bazaar_in_moderation.'</awaitingmoderation>'."\n";
	$output .= '  <activated>'.$stats->get_bazaar_activated.'</activated>'."\n";
	$output .= '</service>'."\n";

	$output .= '<service name="mail">'."\n";
	$output .= '  <awaitingmoderation>'.$stats->get_mail_in_moderation.'</awaitingmoderation>'."\n";
	$output .= '  <activated>'.$stats->get_mail_activated.'</activated>'."\n";
	$output .= '  <boxes>'.$stats->get_mail_total_boxes.'</boxes>'."\n";
	$output .= '  <forwards>'.$stats->get_mail_total_redirects.'</forwards>'."\n";
	$output .= '</service>'."\n";

	$output .= '<service name="mailinglist">'."\n";
	$output .= '  <total>'.$stats->get_lists_total.'</total>'."\n";
	$output .= '  <activated>'.$stats->get_lists_activated.'</activated>'."\n";
	$output .= '  <subscriptions>'.$stats->get_lists_totalsubs.'</subscriptions>'."\n";
	$output .= '</service>'."\n";

	$output .= '<service name="dns">'."\n";
	$output .= '  <awaitingmoderation>'.$stats->get_dns_in_moderation.'</awaitingmoderation>'."\n";
	$output .= '  <activated>'.$stats->get_dns_activated.'</activated>'."\n";
	$output .= '</service>'."\n";

	$output .= '</stats>'."\n";

	print Encode::encode_utf8( 'Content-Type: text/xml; charset=utf-8'."\n\n".$output );
}

sub externnewusersrss {
	my $panel = shift;
	my $vhffs = $panel->{vhffs};

	my $url = ( $panel->get_config->{'url_public'} or '' );

	unless( $panel->get_config->{'rss_users'} and $panel->get_config->{'use_public'} ) {
		$panel->render('misc/message.tt', {
			message=> gettext( 'RSS infos are not published' )
		});
		return;
	}

	require XML::RSS;
	my $rss = new XML::RSS( version => '1.0' );
	my $title;
	if( defined  $vhffs->get_config->get_host_name ) {
		$title = 'Last users on '.$vhffs->get_config->get_host_name;
	} else {
		$title = 'VHFFS last users';
	}

	$rss->channel(
		title        => $title,
		link         => $url.'?do=lastusers',
		description  => 'Best hosting platform',
		dc => {
			date       => '2000-08-23T07:00+00:00',
			subject    => 'danstoncul',
			creator    => 'vhffs@vhffs.org',
			publisher  => 'vhffs@vhffs.org',
			rights     => 'Copyright 2004, Vhffs Dream Team',
			language   => 'en_US',
		},
		syn => {
			updatePeriod     => 'hourly',
			updateFrequency  => '1',
			updateBase       => '1901-01-01T00:00+00:00',
		},
		taxo => [
			'http://dmoz.org/Computers/Internet',
			'http://dmoz.org/Computers/PC'
		]
	);

	my $users = Vhffs::Panel::User::get_last_users( $vhffs );

	foreach(@{$users}) {
		$rss->add_item(
			title       => $_->{username},
			link        => $url.'?do=user;name='.$_->{username},
			description => 'VHFFS User'
		);
	}
	$rss->{output} = '2.0';
	print Encode::encode_utf8( 'Content-Type: text/xml; charset=utf-8'."\n\n".$rss->as_string );
}

sub externnewgroupsrss {
	my $panel = shift;
	my $vhffs = $panel->{vhffs};

	my $url = ( $panel->get_config->{'url_public'} or '' );

	unless( $panel->get_config->{'rss_groups'} and $panel->get_config->{'use_public'} ) {
		$panel->render('misc/message.tt', {
			message=> gettext( 'RSS infos are not published' )
		});
		return;
	}

	require XML::RSS;
	my $rss = new XML::RSS( version => '1.0' );
	my $title;
	if( defined  $vhffs->get_config->get_host_name ) {
		$title = 'Last groups on '.$vhffs->get_config->get_host_name;
	} else {
		$title = 'VHFFS last groups';
	}

	$rss->channel(
		title        => $title,
		link         => $url.'?do=lastgroups',
		description  => 'Best hosting platform',
		dc => {
			date       => '2000-08-23T07:00+00:00',
			subject    => 'Last groups on '.$vhffs->get_config->get_host_name,
			subject    => 'danstoncul',
			creator    => 'vhffs@vhffs.org',
			publisher  => 'vhffs@vhffs.org',
			rights     => 'Copyright 2004, Vhffs Dream Team',
			language   => 'en_US',
		},
		syn => {
			updatePeriod     => 'hourly',
			updateFrequency  => '1',
			updateBase       => '1901-01-01T00:00+00:00',
		},
		taxo => [
			'http://dmoz.org/Computers/Internet',
			'http://dmoz.org/Computers/PC'
		]
	);

	my $groups = Vhffs::Panel::Group::get_last_groups( $vhffs );

	foreach(@{$groups}) {
		$rss->add_item(
			title       => $_->{realname},
			link        => $url.'?do=group;name='.$_->{groupname},
			description => 'Vhffs Group',
		);
	}

	$rss->{output} = '2.0';
	print Encode::encode_utf8( 'Content-Type: text/xml; charset=utf-8'."\n\n".$rss->as_string );
}

1;
