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

package Vhffs::Panel::Commons;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;

use Vhffs::Constants;

=head2 paginate

	Vhffs::Panel::Commons::paginate($template, $current_page, $total_count, $items_per_page, $url_params);

C<$url_param> is a reference to a hash containing parameters to append to the URL and their values. Empty
parameters won't be appended.

=cut
sub paginate($$$$$) {
	my ($template, $current_page, $total_count, $items_per_page, $url_params) = @_;
	return undef unless $template->query(name => 'PAGINATION');
	my $max_pages = int( ($total_count + ($items_per_page - 1)) / $items_per_page );
	if($max_pages > 1) {
		my @params;
		$template->param(PAGINATION => 1);
		foreach my $key (keys %$url_params) {
			my $value = $url_params->{$key};
			push @params, $key.'='.$value unless($value =~ /^\s*$/);
		}
		$template->param( SEARCH_CRITERIA => join(';', @params) );
		$template->param( CURRENT_PAGE => $current_page );
		my $pages = [];
		if($current_page > 1) {
			for(($current_page - $items_per_page < 1 ? 1 : $current_page - $items_per_page)..($current_page - 1)) {
				push @$pages, { PAGE => $_ };
			}
		}
		$template->param( PREVIOUS_PAGES => \@$pages );
		$pages = [];

		if($current_page < $max_pages) {
			for(($current_page + 1)..($current_page + $items_per_page > $max_pages ? $max_pages : $current_page + $items_per_page)) {
				push @$pages, { PAGE => $_ };
			}
		}
		$template->param( NEXT_PAGES => $pages );

		$template->param( PREVIOUS_PAGE => ($current_page - 1 < 1 ? 0 : $current_page - 1 ) );
		$template->param( NEXT_PAGE => ($current_page + 1 > $max_pages ? 0 : $current_page + 1 ) );
	}
}

=head2 get_pager
	get_pager($current_page, $total, $item_per_page, $url, $url_params)
=cut
sub get_pager {
	my ($current_page, $total, $ipp, $slider_size, $url, $url_params) = @_;
	my $last_page = int( ($total + $ipp - 1 ) / $ipp);
	my $pager = {};

	if($last_page > 1) {
		$pager->{last_page} = $last_page;
		$pager->{current_page} = $current_page;
		$pager->{url} = $url;

		my @params = ();
		foreach my $key (keys %$url_params) {
			my $value = $url_params->{$key};
			if(ref($value) eq 'ARRAY') {
				push @params, $key.'='.$_ foreach(@$value);
			} else {
				push @params, $key.'='.$value;
			}
		}
		$pager->{query_string} = join(';', @params);
		my $pages = [];
		for( ( ($current_page - $slider_size > 0) ? $current_page - $slider_size : 1 )..($current_page - 1) ) {
			push @$pages, $_;
		}
		$pager->{previous_pages} = $pages;

		$pages = [];
		for( ($current_page + 1)..(($current_page + $slider_size <= $last_page) ? $current_page + $slider_size : $last_page ) ) {
			push @$pages, $_;
		}
		$pager->{next_pages} = $pages;
	}

	return $pager;
}

=head2

	fetch_slice_and_count($vhffs, $select, $conditions, $order, $start, $count, $params, $select_callback);

Helper function for pagination. Fetches a slice of result (using C<"LIMIT"> and C<"OFFSET"> clauses)
and the total count of items (if there was no slice).

=over 4

=item C<$vhffs>: Vhffs instance;

=item C<$select>: C<"SELECT"> clause of the query, will be replaced with C<"SELECT COUNT(*)"> to
		get the total count;

=item C<$conditions>: conditions applied to the SELECT clausse. Includes all the query
		begining at C<"FROM"> and ending right befor C<"ORDER BY">;

=item C<$order>: C<"ORDER BY"> clause of the query;

=item C<$start>: first item of the result set to fetch;

=item C<$count>: number of items to fetch;

=item C<$params>: array ref containing parameters of the query when using placeholders;

=item C<$select_callback>: optional sub reference which will be used to fetch results instead
		of C<DBI::selectall_arrayref>. Its protorype must be ($vhffs, $sql, @params).
=back

=cut
sub fetch_slice_and_count($$$$$$$;$) {
	my ($vhffs, $select, $conditions, $order, $start, $count, $params, $select_callback) = @_;

	my $dbh = $vhffs->get_db;
	my $result = {};
	my $sql = $select.$conditions.$order.' LIMIT '.$count.' OFFSET '.$start;
	if(defined $select_callback) {
		$result->{data} = $select_callback->($vhffs, $sql, @{$params});
	} else {
		$result->{data} = $dbh->selectall_arrayref($sql, { Slice => {} }, @{$params});
	}
	($result->{total_count}) = @{$dbh->selectrow_arrayref('SELECT COUNT(*) '.$conditions, undef, @$params)};
	return $result;
}

1;
