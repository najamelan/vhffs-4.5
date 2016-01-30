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

use lib '%VHFFS_LIB_DIR%';
use Vhffs::Robots::Group;

my $vhffs = new Vhffs;
exit 1 unless defined $vhffs;

Vhffs::Robots::lock( $vhffs, 'quotagroup' );
my $reminders  = 5;
my $adminUser  = Vhffs::User::get_by_username( $vhffs, 'admin' );
my @needsAdmin = ();


my $groups = Vhffs::Group::getall( $vhffs, Vhffs::Constants::ACTIVATED );
foreach my $group ( @$groups ) {

	# Check the user home and update it's usage in the database
	#
	Vhffs::Robots::Group::quotaDuUpdate( $group );

	# Compare the usage to the allowed quota
	# If exceeded, send mail and up reminder count
	#
	if ( $group->quota_exceeded )
	{
		my $reminded = $group->get_quota_reminded;

		foreach my $user ( @{$group->get_users} )
		{
			my $subject = sprintf( 'Quota of group %s exceeded on %s', $group->get_groupname, $vhffs->get_config->get_host_name );
			my $content = sprintf( "Hello %s %s.\n\n The filesystem usage for your group (%s) directory (%s MB) is exceeding the allowed quota (%s MB). Please use ftp to verify what's taking up space and remove some files. If you think you need more space, please contact us at...", $user->get_firstname, $user->get_lastname, $group->get_groupname, $group->get_quota_used, $group->get_quota );

			$user->send_mail_user( $subject, $content );
		}


		$group->set_quota_reminded( ++$reminded );
		$group->commit;


		# If reminded x times, contact an admin
		#
		if( $group->get_quota_reminded > $reminders )
		{
			my @exceeded = ( $group->get_groupname, $group->get_quota_used, $group->get_quota, $group->get_quota_reminded, $group->get_dir );
			push @needsAdmin, [ @exceeded ];
		}

	}

	# The quota is not exceeded, maybe it was before, set the reminder counter back to 0
	#
	else
	{
		$group->set_quota_reminded( 0 );
		$group->commit;
	}


}

Vhffs::Robots::unlock( $vhffs, 'quotagroup' );

# if the array isn't empty, we need to send a mail to administrators
#
if( $#needsAdmin > -1 )
{
	my $table = "The following groups exceed their disk quota (numbers are in MB):\n\n";
	$table .= "------------------------------------------------------------------------------------------------\n";
	$table .= "| name                 | used | quota | # reminders | path                                     |\n";
	$table .= "------------------------------------------------------------------------------------------------\n";

	foreach my $group (@needsAdmin)
	{
		$table .= sprintf( "| %-20s | %4d | %5d | %11d | %-40s |\n", @$group[0], @$group[1], @$group[2], @$group[3], @$group[4] );
	}

	$table .= "------------------------------------------------------------------------------------------------\n";


	my $subject = sprintf( 'Certain groups on %s exceed their disk quota.', $vhffs->get_config->get_host_name );

	$adminUser->send_mail_user( $subject, $table );
}

exit 0;
