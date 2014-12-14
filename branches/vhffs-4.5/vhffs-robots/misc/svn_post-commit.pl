#!%PERL%
#
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

my $repopath = $ARGV[0];
my $rev = $ARGV[1];
exit 1 unless ( defined $repopath && defined $rev );

$repopath =~ s#/$##;
( undef , my $reponame ) = ( $repopath =~ /(^.+\/)([a-z0-9]+\/[a-z0-9]+$)/ );

my $mailnotifyfrom = '%MAILNOTIFYFROM%';
my $mailnotifyto = '%MAILNOTIFYTO%';

if( $mailnotifyto ne '' )
{
	use SVN::Notify;

	my %params = (
		repos_path => $repopath,
		revision => $rev,
		from => $mailnotifyfrom,
		to => $mailnotifyto,
		reply_to => $mailnotifyto,
		with_diff => 1,
		attach_diff => 1,
		smtp => '127.0.0.1',
	);

	my $notifier = SVN::Notify->new(%params);
	$notifier->add_headers({
		'X-Repository-Type' => 'svn',
		'X-Repository-Name' => $reponame,
	});
	$notifier->prepare;
	$notifier->execute;
}
