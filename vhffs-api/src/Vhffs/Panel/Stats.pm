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

package Vhffs::Panel::Stats;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Encode;

use Vhffs::Constants;
use Vhffs::Functions;


sub stats {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $stats = $vhffs->get_stats( 0 );
	unless( defined $stats ) {
		$panel->render('misc/message.tt', { message => gettext('Cannot get statistics') } );
		return;
	}

	my $vars = {
		users_count => $stats->get_user_total,
		administrators_count => $stats->get_user_total_admin,
		moderators_count => $stats->get_user_total_moderator,

		groups_count => $stats->get_groups_total,
		activated_groups_count => $stats->get_groups_activated,

		waiting_web_count => $stats->get_web_in_moderation,
		activated_web_count => $stats->get_web_activated,

		waiting_dns_count => $stats->get_dns_in_moderation,
		activated_dns_count => $stats->get_dns_activated,

		waiting_cvs_count => $stats->get_cvs_in_moderation,
		activated_cvs_count => $stats->get_cvs_activated,

		waiting_svn_count => $stats->get_svn_in_moderation,
		activated_svn_count => $stats->get_svn_activated,

		waiting_git_count => $stats->get_git_in_moderation,
		activated_git_count => $stats->get_git_activated,

		waiting_mercurial_count => $stats->get_mercurial_in_moderation,
		activated_mercurial_count => $stats->get_mercurial_activated,

		waiting_bazaar_count => $stats->get_bazaar_in_moderation,
		activated_bazaar_count => $stats->get_bazaar_activated,

		waiting_mail_domains_count => $stats->get_mail_in_moderation,
		activated_mail_domains_count => $stats->get_mail_activated,
		mail_boxes_count => $stats->get_mail_total_boxes,
		mail_forwards_count => $stats->get_mail_total_redirects,

		waiting_mysql_count => $stats->get_mysql_in_moderation,
		activated_mysql_count => $stats->get_mysql_activated,

		waiting_pgsql_count => $stats->get_pgsql_in_moderation,
		activated_pgsql_count => $stats->get_pgsql_activated,

		waiting_ml_count => $stats->get_lists_in_moderation,
		activated_ml_count => $stats->get_lists_activated,
		ml_subscribers_count => $stats->get_lists_totalsubs,

		tag_categories_count => $stats->get_tags_categories_total,
		used_tags_count => $stats->get_tags_used_total,
		total_tags_count => $stats->get_tags_total,
		tagged_groups_count => $stats->get_tags_groups_total,
		max_tags_count => $stats->get_tags_groups_max,
		top10_tags => $stats->get_most_popular_tags,
		all_tags => $stats->get_all_tags,
		all_sorted_tags => $stats->get_all_sorted_tags
	};

	$panel->render('admin/misc/stats.tt', $vars);
}

1;
