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


=pod

=head1 NAME

Vhffs:Stats - Provide statistics on Vhffs Platform

=head1 SYNOPSIS

	my $vhffs = new Vhffs(...);

	my $stats = new Vhffs::Stats($vhffs);
	my $lstcount = $stats->get_lists_in_moderation;
	my $count = $stats->get_...

	$stats->flush();  # Flush cache
	my $newlstcount = $stats->get_lists_in_moderation;


=head1 METHODS

=cut


package Vhffs::Stats;

use strict;
use utf8;

use Vhffs::Constants;

=pod

=head2 new

	my $stats = new Vhffs::Stats($vhffs);

Creates a new Vhffs::Stats instance. C<$vhffs> is the C<Vhffs> instance used to get database connection.

=cut
sub new {
	my ( $class, $vhffs ) = @_;

	my $this = {};
	$this->{vhffs} = $vhffs;
	$this->{flushed} = time();
	bless( $this, $class );
}

=pod

=head2 flush

	$stats->flush( $time );

When you call a C<get_xxxx> method, data are fetched from database and cached. If you want to flush the cache, call C<flush>.

$time is an optional parameter, if set the cache is not going to be flushed if data were not flushed $time seconds ago.

=cut
sub flush {
	my $self = shift;
	my $time = shift;

	my $curtime = time();
	return if defined $time and ($curtime - $self->{flushed} < $time or $self->{flushed} > $curtime);
	delete $self->{stats};
	$self->{flushed} = $curtime;
}

=pod

=head2 get_lists_totalsubs

	my $count = $stats->get_lists_totalsubs();

Returns the count of mailing list subscribers on
the platform.

=cut
sub get_lists_totalsubs {
	my $self = shift;
	unless(defined $self->{stats}->{lists}->{totalsubs}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mx_ml_subscribers';
		($self->{stats}->{lists}->{totalsubs}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{lists}->{totalsubs};
}

=pod

=head2 get_lists_in_moderation

	my $count = $stats->get_lists_in_moderation();

Returns the count of mailing lists waiting for moderation.

=cut
sub get_lists_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{lists}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mx_ml ml, vhffs_object o WHERE o.object_id=ml.object_id AND o.state='.Vhffs::Constants::WAITING_FOR_VALIDATION;
		($self->{stats}->{lists}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{lists}->{awaiting_validation};
}

=pod

=head2 get_lists_activated

	my $count = $stats->get_lists_activated();

Returns the count of mailing lists currently activated.

=cut
sub get_lists_activated {
	my $self = shift;
	unless(defined $self->{stats}->{lists}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mx_ml ml, vhffs_object o WHERE o.object_id=ml.object_id AND o.state = ?';
		($self->{stats}->{lists}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::ACTIVATED )};
	}
	return $self->{stats}->{lists}->{activated};
}

=pod

=head2 get_lists_total

	my $count = $stats->get_lists_total();

Returns the total count of mailing lists (activated or not).

=cut
sub get_lists_total {
	my $self = shift;
	unless(defined $self->{stats}->{lists}->{total}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mx_ml';
		($self->{stats}->{lists}->{total}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{lists}->{total};
}

=pod

=head2 get_web_in_moderation

	my $count = $stats->get_web_in_moderation();

Returns the count of web areas waiting for moderation.

=cut
sub get_web_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{web}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_httpd w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{web}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};
	}
	return $self->{stats}->{web}->{awaiting_validation};
}

=pod

=head2 get_web_activated

	my $count = $stats->get_web_activated();

Returns the count of web areas currently activated.

=cut
sub get_web_activated {
	my $self = shift;
	unless(defined $self->{stats}->{web}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_httpd w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{web}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::ACTIVATED )};
	}
	return $self->{stats}->{web}->{activated};
}

=pod

=head2 get_user_total

	my $count = $stats->get_user_total();

Returns the total count of users (activated or not).

=cut
sub get_user_total {
	my $self = shift;
	unless(defined $self->{stats}->{users}->{total}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_users';
		($self->{stats}->{users}->{total}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{users}->{total};
}

=pod

=head2 get_user_total_admin

	my $count = $stats->get_user_total_admin();

Returns the total count of administrators.

=cut
sub get_user_total_admin {
	my $self = shift;
	unless(defined $self->{stats}->{users}->{total_admin}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_users WHERE admin=?';
		($self->{stats}->{users}->{total_admin}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::USER_ADMIN )};
	}
	return $self->{stats}->{users}->{total_admin};
}

=pod

=head2 get_user_total_moderator

	my $count = $stats->get_user_total_moderator();

Returns the total count of moderators.

=cut
sub get_user_total_moderator {
	my $self = shift;
	unless(defined $self->{stats}->{users}->{total_moderator}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_users WHERE admin=?';
		($self->{stats}->{users}->{total_moderator}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::USER_MODERATOR )};
	}
	return $self->{stats}->{users}->{total_moderator};
}


=pod

=head2 get_dns_in_moderation

	my $count = $stats->get_dns_in_moderation();

Returns the count of domain name (DNS) waiting for moderation.

=cut
sub get_dns_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{dns}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_dns w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state=?';
		($self->{stats}->{dns}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};
	}
	return $self->{stats}->{dns}->{awaiting_validation};
}

=pod

=head2 get_dns_activated

	my $count = $stats->get_dns_activated();

Returns the count of domaine name (DNS) currently activated.

=cut
sub get_dns_activated {
	my $self = shift;
	unless(defined $self->{stats}->{dns}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_dns w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state=?';
		($self->{stats}->{dns}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::ACTIVATED )};
	}
	return $self->{stats}->{dns}->{activated};
}

=pod

=head2 get_mail_in_moderation

	my $count = $stats->get_mail_in_moderation();

Returns the count of mail domains waiting for moderation.

=cut
sub get_mail_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{mail}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mx w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{mail}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};
	}
	return $self->{stats}->{mail}->{awaiting_validation};
}

=pod

=head2 get_mail_activated

	my $count = $stats->get_mail_activated();

Returns the count of mail domains currently activated.

=cut
sub get_mail_activated {
	my $self = shift;
	unless(defined $self->{stats}->{mail}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mx w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{mail}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::ACTIVATED )};
	}
	return $self->{stats}->{mail}->{activated};
}

=pod

=head2 get_mail_total_boxes

	my $count = $stats->get_mail_total_boxes();

Returns the total count of mail boxes.

=cut
sub get_mail_total_boxes {
	my $self = shift;
	unless(defined $self->{stats}->{mail}->{total_boxes}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mx_box';
		($self->{stats}->{mail}->{total_boxes}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{mail}->{total_boxes};
}

=pod

=head2 get_mail_total_redirects

	my $count = $stats->get_mail_total_redirects();

Returns the total count of mail forwards.

=cut
sub get_mail_total_redirects {
	my $self = shift;
	unless(defined $self->{stats}->{mail}->{total_redirects}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mx_redirect';
		($self->{stats}->{mail}->{total_redirects}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{mail}->{total_redirects};
}

=pod

=head2 get_cvs_in_moderation

	my $count = $stats->get_cvs_in_moderation();

Returns the count of CVS repositories waiting for moderation.

=cut
sub get_cvs_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{cvs}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_cvs w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state=?';
		($self->{stats}->{cvs}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};
	}
	return $self->{stats}->{cvs}->{awaiting_validation};
}

=pod

=head2 get_cvs_activated

	my $count = $stats->get_cvs_activated();

Returns the count of CVS repositories currently activated.

=cut
sub get_cvs_activated {
	my $self = shift;
	unless(defined $self->{stats}->{cvs}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_cvs w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state=?';
		($self->{stats}->{cvs}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::ACTIVATED )};
	}
	return $self->{stats}->{cvs}->{activated};
}

=pod

=head2 get_svn_in_moderation

	my $count = $stats->get_svn_in_moderation();

Returns the count of SVN repositories waiting for moderation.

=cut
sub get_svn_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{svn}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_svn w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{svn}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};

	}
	return $self->{stats}->{svn}->{awaiting_validation};
}

=pod

=head2 get_svn_activated

	my $count = $stats->get_svn_activated();

Returns the count of SVN repositories currently activated.

=cut
sub get_svn_activated {
	my $self = shift;
	unless(defined $self->{stats}->{svn}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_svn w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state='.Vhffs::Constants::ACTIVATED;
		($self->{stats}->{svn}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{svn}->{activated};
}

=pod

=head2 get_git_in_moderation

	my $count = $stats->get_git_in_moderation();

Returns the count of Git repositories waiting for moderation.

=cut
sub get_git_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{git}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_git w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{git}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};

	}
	return $self->{stats}->{git}->{awaiting_validation};
}

=pod

=head2 get_git_activated

	my $count = $stats->get_git_activated();

Returns the count of Git repositories currently activated.

=cut
sub get_git_activated {
	my $self = shift;
	unless(defined $self->{stats}->{git}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_git w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state='.Vhffs::Constants::ACTIVATED;
		($self->{stats}->{git}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{git}->{activated};
}

=pod

=head2 get_mercurial_in_moderation

	my $count = $stats->get_mercurial_in_moderation();

Returns the count of Mercurial repositories waiting for moderation.

=cut
sub get_mercurial_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{mercurial}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mercurial w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{mercurial}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};

	}
	return $self->{stats}->{mercurial}->{awaiting_validation};
}

=pod

=head2 get_mercurial_activated

	my $count = $stats->get_mercurial_activated();

Returns the count of Mercurial repositories currently activated.

=cut
sub get_mercurial_activated {
	my $self = shift;
	unless(defined $self->{stats}->{mercurial}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mercurial w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state='.Vhffs::Constants::ACTIVATED;
		($self->{stats}->{mercurial}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{mercurial}->{activated};
}

=pod

=head2 get_bazaar_in_moderation

	my $count = $stats->get_bazaar_in_moderation();

Returns the count of Bazaar repositories waiting for moderation.

=cut
sub get_bazaar_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{bazaar}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_bazaar w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{bazaar}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};

	}
	return $self->{stats}->{bazaar}->{awaiting_validation};
}

=pod

=head2 get_bazaar_activated

	my $count = $stats->get_bazaar_activated();

Returns the count of Bazaar repositories currently activated.

=cut
sub get_bazaar_activated {
	my $self = shift;
	unless(defined $self->{stats}->{bazaar}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_bazaar w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state='.Vhffs::Constants::ACTIVATED;
		($self->{stats}->{bazaar}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{bazaar}->{activated};
}

=pod

=head2 get_mysql_in_moderation

	my $count = $stats->get_mysql_in_moderation();

Returns the count of Mysql databases waiting for moderation.

=cut
sub get_mysql_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{mysql}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mysql w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{mysql}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};
	}
	return $self->{stats}->{mysql}->{awaiting_validation};
}

=pod

=head2 get_mysql_activated

	my $count = $stats->get_mysql_activated();

Returns the count of Mysql databaes currently activated.

=cut
sub get_mysql_activated {
	my $self = shift;
	unless(defined $self->{stats}->{mysql}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_mysql w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{mysql}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::ACTIVATED )};
	}
	return $self->{stats}->{mysql}->{activated};
}

=pod

=head2 get_pgsql_in_moderation

	my $count = $stats->get_pgsql_in_moderation();

Returns the count of Pgsql databases waiting for moderation.

=cut
sub get_pgsql_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{pgsql}->{awaiting_validation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_pgsql w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{pgsql}->{awaiting_validation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};

	}
	return $self->{stats}->{pgsql}->{awaiting_validation};
}

=pod

=head2 get_pgsql_activated

	my $count = $stats->get_pgsql_activated();

Returns the count of Pgsql databaes currently activated.

=cut
sub get_pgsql_activated {
	my $self = shift;
	unless(defined $self->{stats}->{pgsql}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_pgsql w INNER JOIN vhffs_object o ON o.object_id=w.object_id WHERE o.state = ?';
		($self->{stats}->{pgsql}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::ACTIVATED )};
	}
	return $self->{stats}->{pgsql}->{activated};
}

=pod

=head2 get_groups_in_moderation

	my $count = $stats->get_groups_in_moderation();

Returns the count of groups waiting for moderation.

=cut
sub get_groups_in_moderation {
	my $self = shift;
	unless(defined $self->{stats}->{groups}->{awaiting_moderation}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_groups g INNER JOIN vhffs_object o ON o.object_id=g.object_id LEFT JOIN vhffs_users u ON u.username = g.groupname WHERE o.state = ? AND u.username IS NULL';
		($self->{stats}->{groups}->{awaiting_moderation}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql, undef, Vhffs::Constants::WAITING_FOR_VALIDATION )};
	}
	return $self->{stats}->{groups}->{awaiting_moderation};
}

=pod

=head2 get_groups_activated

	my $count = $stats->get_groups_activated();

Returns the count of groups currently activated.

=cut
sub get_groups_activated {
	my $self = shift;
	unless(defined $self->{stats}->{groups}->{activated}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_groups g INNER JOIN vhffs_object o ON o.object_id=g.object_id LEFT JOIN vhffs_users u ON u.username = g.groupname WHERE o.state='.Vhffs::Constants::ACTIVATED.' AND u.username IS NULL';
		($self->{stats}->{groups}->{activated}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{groups}->{activated};
}

=pod

=head2 get_groups_total

	my $count = $stats->get_groups_total();

Returns the total count of groups.

=cut
sub get_groups_total {
	my $self = shift;
	unless(defined $self->{stats}->{groups}->{total}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_groups g LEFT JOIN vhffs_users u ON u.username = g.groupname WHERE u.username IS NULL';
		($self->{stats}->{groups}->{total}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{groups}->{total};
}

=pod

=head2 get_tags_categories_total

	my $count = $stats->get_tags_categories_total();

Returns the total count of tags categories.

=cut
sub get_tags_categories_total {
	my $self = shift;
	unless(defined $self->{stats}->{tags_categories}->{total}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_tag_category';
		($self->{stats}->{tags_categories}->{total}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{tags_categories}->{total};
}

=pod

=head2 get_tags_total

	my $count = $stats->get_tags_total();

Returns the total count of tags.

=cut
sub get_tags_total {
	my $self = shift;
	unless(defined $self->{stats}->{tags}->{total}) {
		my $sql = 'SELECT COUNT(*) FROM vhffs_tag';
		($self->{stats}->{tags}->{total}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{tags}->{total};
}

=pod

=head2 get_tags_used_total

	my $count = $stats->get_tags_used_total();

Returns the total count of tags used.

=cut
sub get_tags_used_total {
	my $self = shift;
	unless(defined $self->{stats}->{tags_used}->{total}) {
		my $sql = 'SELECT COUNT(distinct tag_id) FROM vhffs_object_tag';
		($self->{stats}->{tags_used}->{total}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{tags_used}->{total};
}

=pod

=head2 get_tags_groups_total

	my $count = $stats->get_tags_groups_total();

Returns the total count of tags groups.

=cut
sub get_tags_groups_total {
	my $self = shift;
	unless(defined $self->{stats}->{tags_groups}->{total}) {
		my $sql = 'SELECT COUNT(distinct object_id) FROM vhffs_object_tag';
		($self->{stats}->{tags_groups}->{total}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{tags_groups}->{total};
}

=pod

=head2 get_most_popular_tags

	my $tags = $stats->get_most_popular_tags();

Returns the ten most popular tags.

=cut
sub get_most_popular_tags {
	my $self = shift;
	# well, I did not succeed to use $self->{stats}->{tags}->{most_popular}
	my $tags = [];
	my $sql = 'SELECT vhffs_tag_category.label as category, vhffs_tag.label as tag_label, COUNT(object_id) as nb_groups
	        FROM vhffs_object_tag, vhffs_tag_category, vhffs_tag
	        WHERE vhffs_tag.category_id=vhffs_tag_category.tag_category_id
	          AND vhffs_object_tag.tag_id=vhffs_tag.tag_id
	        GROUP BY category,tag_label ORDER BY nb_groups DESC LIMIT 10';
	my $sth = $self->{vhffs}->get_db->prepare($sql);
	$sth->execute() or return undef;
	while( (my $t = $sth->fetchrow_hashref() )  ) {
		push @$tags, $t;
	}
	return $tags;
}

=pod

=head2 get_all_tags

	my $tags = $stats->get_all_tags();

Returns all the tags by category.

=cut
sub get_all_tags {
	my $self = shift;
	# well, I did not succeed to use $self->{stats}->{tags}->{most_popular}
	my $tags = [];
	my $sql = 'SELECT vhffs_tag_category.label as category, vhffs_tag.label as tag_label, COUNT(object_id) as nb_groups
	        FROM vhffs_object_tag, vhffs_tag_category, vhffs_tag
	        WHERE vhffs_tag.category_id=vhffs_tag_category.tag_category_id
	          AND vhffs_object_tag.tag_id=vhffs_tag.tag_id
	        GROUP BY category,tag_label ORDER BY category, tag_label';
	my $sth = $self->{vhffs}->get_db->prepare($sql);
	$sth->execute() or return undef;
	while( (my $t = $sth->fetchrow_hashref() )  ) {
		push @$tags, $t;
	}
	return $tags;
}

=pod

=head2 get_all_sorted_tags

	my $tags = $stats->get_all_sorted_tags();

Returns all the tags by alphabetical order, without category.

=cut
sub get_all_sorted_tags {
	my $self = shift;
	# well, I did not succeed to use $self->{stats}->{tags}->{most_popular}
	my $tags = [];
	my $sql = 'SELECT vhffs_tag_category.label as category, vhffs_tag.label as tag_label, COUNT(object_id) as nb_groups
	        FROM vhffs_object_tag, vhffs_tag_category, vhffs_tag
	        WHERE vhffs_tag.category_id=vhffs_tag_category.tag_category_id
	          AND vhffs_object_tag.tag_id=vhffs_tag.tag_id
	        GROUP BY category,tag_label ORDER BY tag_label';
	my $sth = $self->{vhffs}->get_db->prepare($sql);
	$sth->execute() or return undef;
	while( (my $t = $sth->fetchrow_hashref() )  ) {
		push @$tags, $t;
	}
	return $tags;
}

=pod

=head2 get_most_popular_tags

	my $tags = $stats->get_most_popular_tags();

Returns the ten most popular tags.

=cut
sub get_tags_groups_max {
	my $self = shift;

	unless(defined $self->{stats}->{tags_groups}->{max}) {
		my $sql = 'SELECT MAX(count_tag_id) FROM (select COUNT(tag_id) as count_tag_id, object_id FROM vhffs_object_tag GROUP BY object_id) AS count_tags_groups';
		($self->{stats}->{tags_groups}->{max}) = @{$self->{vhffs}->get_db->selectrow_arrayref( $sql )};
	}
	return $self->{stats}->{tags_groups}->{max};
}

1;
