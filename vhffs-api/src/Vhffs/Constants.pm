package Vhffs::Constants;

use strict;
use utf8;
use Locale::gettext;

=pod

=head1 NAME

Vhffs::Constants - Define VHFFS global constants

=head1 DESCRIPTION

Vhffs::Constants is a class that define all constants values in VHFFS.
So, you can use Vhffs::Constants::ConstantName to get the value of ConstantName.

=cut

use constant {
	VHFFS_VERSION => '4.5.0',
	VHFFS_RELEASE_NAME => 'Mirounga leonina',

	CONF_PATH => '/etc/vhffs/vhffs.conf',

	WAITING_FOR_VALIDATION => 1,
	VALIDATION_REFUSED => 2,
	WAITING_FOR_CREATION => 3,
	CREATION_ERROR => 4,
	WAITING_FOR_ACTIVATION => 5,
	ACTIVATED => 6,
	ACTIVATION_ERROR => 7,
	WAITING_FOR_SUSPENSION => 14,
	SUSPENDED => 15,
	SUSPENSION_ERROR => 16,
	WAITING_FOR_MODIFICATION => 9,
	MODIFICATION_ERROR => 10,
	WAITING_FOR_DELETION => 12,
	DELETION_ERROR => 13,

	ACL_UNDEFINED => -1,
	ACL_DENIED => 0,
	ACL_VIEW => 2,
	ACL_MODIFY => 4,
	ACL_MANAGEACL => 8,
	ACL_DELETE => 10,

	USER_NORMAL => 0,
	USER_ADMIN => 1,
	USER_MODERATOR => 2,

	ML_RIGHT_SUB_WAITING_FOR_REPLY => 2,
	ML_RIGHT_SUB_WAITING_FOR_VALIDATION => 3,
	ML_RIGHT_SUB => 4,
	ML_RIGHT_ADMIN => 10,
	ML_RIGHT_SUB_WAITING_FOR_DEL => 12,

	ML_SUBSCRIBE_NO_APPROVAL_REQUIRED => 0,
	ML_SUBSCRIBE_APPROVAL_REQUIRED => 1,
	ML_SUBSCRIBE_CLOSED => 2,

	ML_POSTING_OPEN_ALL => 0,
	ML_POSTING_MODERATED_ALL => 1,
	ML_POSTING_OPEN_MEMBERS_MODERATED_OTHERS => 2,
	ML_POSTING_MEMBERS_ONLY => 3,
	ML_POSTING_MEMBERS_ONLY_MODERATED => 4,
	ML_POSTING_ADMINS_ONLY => 5,

	MAIL_VALID_LOCAL_PART => qr/^[a-z0-9\_\-\.]+$/,

	BROADCAST_WAITING_TO_BE_SENT => 0,
	BROADCAST_SENT => 1,

	# Objects' types
	TYPE_USER => 10,
	TYPE_GROUP => 11,
	TYPE_WEB => 20,
	TYPE_REPOSITORY => 21,
	TYPE_MYSQL => 30,
	TYPE_PGSQL => 31,
	TYPE_CVS => 40,
	TYPE_SVN => 41,
	TYPE_GIT => 42,
	TYPE_MERCURIAL => 43,
	TYPE_BAZAAR => 44,
	TYPE_DNS => 50,
	TYPE_MAIL => 60,
	TYPE_ML => 61,
	TYPE_CRON => 70,

	# Tags visibility MUST BE ORDERED BY PRIVILEGE LEVEL!
	TAG_VISIBILITY_GROUP_CREATION => 10,
	TAG_VISIBILITY_PUBLIC => 20,
	TAG_VISIBILITY_MODERATORS => 30,
	TAG_VISIBILITY_ADMINS => 40,
};

use constant {
	# Status strings that are going to be read by humans
	STATUS_STRINGS => {
		Vhffs::Constants::WAITING_FOR_VALIDATION => 'Waiting for validation',
		Vhffs::Constants::VALIDATION_REFUSED => 'Validation refused',
		Vhffs::Constants::WAITING_FOR_CREATION => 'Waiting for creation',
		Vhffs::Constants::CREATION_ERROR => 'Creation error',
		Vhffs::Constants::WAITING_FOR_ACTIVATION => 'Waiting for activation',
		Vhffs::Constants::ACTIVATED => 'Activated',
		Vhffs::Constants::ACTIVATION_ERROR => 'Activation error',
		Vhffs::Constants::WAITING_FOR_SUSPENSION => 'Waiting for suspension',
		Vhffs::Constants::SUSPENDED => 'Suspended',
		Vhffs::Constants::SUSPENSION_ERROR => 'Suspension error',
		Vhffs::Constants::WAITING_FOR_MODIFICATION => 'Waiting for modification',
		Vhffs::Constants::MODIFICATION_ERROR => 'Modification error',
		Vhffs::Constants::WAITING_FOR_DELETION => 'Will be deleted',
		Vhffs::Constants::DELETION_ERROR => 'Deletion error',
	},
	# Types strings
	TYPES => {
		Vhffs::Constants::TYPE_USER => {
			name => 'User',
			fs => 'user',
			class => 'Vhffs::User',
		},
		Vhffs::Constants::TYPE_GROUP => {
			name => 'Group',
			fs => 'group',
			class => 'Vhffs::Group',
		},
		Vhffs::Constants::TYPE_WEB => {
			name => 'Webarea',
			fs => 'web',
			class => 'Vhffs::Services::Web',
		},
		Vhffs::Constants::TYPE_REPOSITORY => {
			name => 'Download Repository',
			fs => 'repository',
			class => 'Vhffs::Services::Repository',
		},
		Vhffs::Constants::TYPE_MYSQL => {
			name => 'MySQL DB',
			fs => 'mysql',
			class => 'Vhffs::Services::Mysql',
		},
		Vhffs::Constants::TYPE_PGSQL => {
			name => 'PgSQL DB',
			fs => 'postgresql',
			class => 'Vhffs::Services::Pgsql',
		},
		Vhffs::Constants::TYPE_CVS => {
			name => 'CVS Repository',
			fs => 'cvs',
			class => 'Vhffs::Services::Cvs',
		},
		Vhffs::Constants::TYPE_SVN => {
			name => 'SVN Repository',
			fs => 'svn',
			class => 'Vhffs::Services::Svn',
		},
		Vhffs::Constants::TYPE_GIT => {
			name => 'GIT Repository',
			fs => 'git',
			class => 'Vhffs::Services::Git',
		},
		Vhffs::Constants::TYPE_MERCURIAL => {
			name => 'Mercurial Repository',
			fs => 'mercurial',
			class => 'Vhffs::Services::Mercurial',
		},
		Vhffs::Constants::TYPE_BAZAAR => {
			name => 'Bazaar Repository',
			fs => 'bazaar',
			class => 'Vhffs::Services::Bazaar',
		},
		Vhffs::Constants::TYPE_DNS => {
			name => 'Domain Name',
			fs => 'dns',
			class => 'Vhffs::Services::DNS',
		},
		Vhffs::Constants::TYPE_MAIL => {
			name => 'Mail Domain',
			fs => 'mail',
			class => 'Vhffs::Services::Mail',
		},
		Vhffs::Constants::TYPE_ML => {
			name => 'Mailing List',
			fs => 'mailinglist',
			class => 'Vhffs::Services::MailingList',
		},
		Vhffs::Constants::TYPE_CRON => {
			name => 'Cron job',
			fs => 'cron',
			class => 'Vhffs::Services::Cron',
		},
	},
};

1;

__END__

=head1 MAIN CONSTANTS
=head2 VHFFS_VERSION
=head2 VHFFS_RELEASE_NAME
=head2 CONF_PATH

=head1 OBJECT STATUS CONSTANTS
=head2 WAITING_FOR_VALIDATION
=head2 VALIDATION_REFUSED
=head2 WAITING_FOR_CREATION
=head2 CREATION_ERROR
=head2 WAITING_FOR_ACTIVATION
=head2 ACTIVATED
=head2 ACTIVATION_ERROR
=head2 WAITING_FOR_SUSPENSION
=head2 SUSPENDED
=head2 SUSPENSION_ERROR
=head2 WAITING_FOR_MODIFICATION
=head2 MODIFICATION_ERROR
=head2 WAITING_FOR_DELETION
=head2 DELETION_ERROR

=head1 ACL CONSTANTS
=head2 ACL_UNDEFINED
=head2 ACL_DENIED
=head2 ACL_VIEW
=head2 ACL_MODIFY
=head2 ACL_MANAGEACL
=head2 ACL_DELETE

=head1 USER CONSTANTS
=head2 USER_NORMAL
=head2 USER_ADMIN
=head2 USER_MODERATOR

=head1 MAILING LISTS CONSTANTS
=head2 ML_RIGHT_SUB_WAITING_FOR_REPLY
=head2 ML_RIGHT_SUB_WAITING_FOR_VALIDATION
=head2 ML_RIGHT_SUB
=head2 ML_RIGHT_ADMIN
=head2 ML_RIGHT_SUB_WAITING_FOR_DEL
=head2 ML_SUBSCRIBE_NO_APPROVAL_REQUIRED
=head2 ML_SUBSCRIBE_APPROVAL_REQUIRED
=head2 ML_SUBSCRIBE_CLOSED
=head2 ML_POSTING_OPEN_ALL
=head2 ML_POSTING_MODERATED_ALL
=head2 ML_POSTING_OPEN_MEMBERS_MODERATED_OTHERS
=head2 ML_POSTING_MEMBERS_ONLY
=head2 ML_POSTING_MEMBERS_ONLY_MODERATED
=head2 ML_POSTING_ADMINS_ONLY

=head1 MAIL CONSTANTS
=head2 MAIL_VALID_LOCAL_PART

=head1 OBJECT TYPE CONSTANTS
=head2 TYPE_USER
=head2 TYPE_GROUP
=head2 TYPE_WEB
=head2 TYPE_REPOSITORY
=head2 TYPE_MYSQL
=head2 TYPE_PGSQL
=head2 TYPE_CVS
=head2 TYPE_SVN
=head2 TYPE_GIT
=head2 TYPE_MERCURIAL
=head2 TYPE_BAZAAR
=head2 TYPE_DNS
=head2 TYPE_MAIL
=head2 TYPE_ML
=head2 TYPE_CRON

=head1 TAG CONSTANTS
=head2 TAG_VISIBILITY_GROUP_CREATION
=head2 TAG_VISIBILITY_PUBLIC
=head2 TAG_VISIBILITY_MODERATORS
=head2 TAG_VISIBILITY_ADMINS

=head1 STATUS STRINGS

my $statusstr = Vhffs::Constants::STATUS_STRINGS->{ OBJECT STATUS CONSTANTS };

=head1 TYPES STRINGS

Constants for objects: human name, name for filesystem (lowercase, without spaces), and name of VHFFS API Class

my $typesstr = Vhffs::Constants::TYPES->{ OBJECT TYPE }->{name};
my $typesstrfs = Vhffs::Constants::TYPES->{ OBJECT TYPE }->{fs};
my $class = Vhffs::Constants::TYPES->{ OBJECT TYPE }->{class};
