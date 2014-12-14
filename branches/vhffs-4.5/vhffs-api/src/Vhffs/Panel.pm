#!%PERL% -w

package Vhffs::Panel;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( display );

use strict;
use utf8;
use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use CGI::Session;
use File::Spec;
use Encode;
use Template;

use Vhffs;
use Vhffs::User;
use Vhffs::Group;
use Vhffs::Functions;
use Vhffs::Constants;

=pod

=head1 NAME

Vhffs::Panel - Provides acces to common VHFFS
functionnalities from Vhffs Panel.

=head1 SYNOPSIS

TODO

=head1 METHODS

=cut

=pod

=head2 get_config

	$panel->get_config;

Returns panel configuration.

=cut
sub get_config {
	my $panel = shift;
	return $panel->{vhffs}->get_config->get_panel;
}

=head2 check_public

	$panel->check_public;

Checks that public area is available, if it's not the case show a message and returns.

=cut
sub check_public {
	my $panel = shift;
	return $panel->get_config->{'use_public'};
}

=pod

=head2 is_open

	$panel->is_open;

Return 1 if panel is open, else return 0

=cut
sub is_open {
	my $panel = shift;
	return $panel->get_config->{'open'};
}

=pod

=head2 is_public

	$panel->is_public;

Return 1 if public part is enabled, else return 0

=cut
sub is_public {
	my $panel = shift;
	return $panel->get_config->{'use_public'};
}

=pod

=head2 use_avatars

	$panel->use_avatars;

Return 1 if either or both users or groups avatars are enabled, else return 0

=cut
sub use_avatars {
	my $panel = shift;
	return ( $panel->get_config->{'users_avatars'} or $panel->get_config->{'groups_avatars'} );
}

=pod

=head2 use_users_avatars

	$panel->use_users_avatars;

Return 1 if users avatars are enabled, else return 0

=cut
sub use_users_avatars {
	my $panel = shift;
	return $panel->get_config->{'users_avatars'};
}

=pod

=head2 use_groups_avatars

	$panel->use_groups_avatars;

Return 1 if groups avatars are enabled, else return 0

=cut
sub use_groups_avatars {
	my $panel = shift;
	return $panel->get_config->{'groups_avatars'};
}

=pod


=head2 check_modo

	$panel->check_modo

Checks that logged in user is admin or moderator. If it is
not the case, show a message and returns.

=cut

sub check_modo {
	my $panel = shift;
	my $user = $panel->{user};
	unless($user->is_moderator or $user->is_admin) {
		$panel->set_title( gettext('Access denied') );
		$panel->render('misc/message.tt',  { message => gettext('You are not allowed to access this page') });
		return 0;
	}
	$panel->{display_admin_menu} = 1;
	return 1;
}

=head2

	$panel->check_admin

Check that logged in user is an admin. If it is not
the case, show a message and returns.

=cut

sub check_admin {
	my $panel = shift;
	my $user = $panel->{user};
	unless($user->is_admin) {
		$panel->set_title( gettext('Access denied') );
		$panel->render('misc/message.tt', { message => gettext('You are not allowed to access this page') });
		return 0;
	}
	$panel->{display_admin_menu} = 1;
	return 1;
}

sub get_available_themes {
	my $panel = shift;
	my @themes;

	my $path = $panel->get_config->{'themesdir'};
	opendir( my $dir, $path ) or return;
	my @files = readdir( $dir );
	foreach( @files ) {
		next if /^\./;
		next unless -d $path.'/'.$_;
		push @themes, $_;
	}
	closedir( $dir );
	return @themes;
}

sub new {
	my $class = ref($_[0]) || $_[0];
	my $vhffs = $_[1];
	my $cgi = $_[2];

	return undef unless( defined $vhffs and defined $cgi );

	$vhffs->clear_current_user;
	$cgi->charset('UTF-8');

	my $self = {};
	bless( $self, $class );
	$self->{errors} = [];
	$self->{infos} = [];
	$self->{cookies} = [];
	$self->{vhffs} = $vhffs;
	$self->{cgi} = $cgi;
	$self->{url} = $cgi->url();
	$self->{display_admin_menu} = 0;

	# FIXME: maybe we should move templatedir to <panel/> configuration ?
	my $templatedir = $vhffs->get_config->get_templatedir;
	$self->{templatedir} = $templatedir;

	# lang cookie
	my $lang = $cgi->param('lang');
	$self->add_cookie( $cgi->cookie( -name=>'language', -value=>$lang, -expires=>'+10y' ) ) if defined $lang;
	$lang = $cgi->cookie('language') unless defined $lang;
	$lang = $vhffs->get_config->get_default_language unless( defined $lang and grep { $_ eq $lang } $vhffs->get_config->get_available_languages );
	$lang = 'en_US' unless defined $lang;
	$self->{lang} = $lang;

	setlocale(LC_ALL, $lang );
	bindtextdomain('vhffs', '%localedir%');
	textdomain('vhffs');

	# theme cookie
	my $theme = $cgi->param('theme');
	$self->add_cookie( $cgi->cookie( -name=>'theme', -value=>$theme, -expires=>'+10y' ) ) if defined $theme;
	$theme = $cgi->cookie('theme') unless defined $theme;
	$theme = $self->get_config->{'default_theme'} unless defined $theme;
	$theme = 'vhffs' unless( defined $theme and -f $self->get_config->{'themesdir'}.'/'.$theme.'/main.css' );

	# theme feature is more or less deprecated since we never had more than one theme working, let me force to the current theme
	$self->{theme} = 'light-grey';

	unless( $vhffs->reconnect() and $self->get_config->{'open'} )  {
		$self->render('misc/closed.tt', undef, 'anonymous.tt');
		undef $self;
		return undef;
	}

	$self->{is_ajax_request} = (defined $self->{cgi}->http('X-Requested-With')
		and $self->{cgi}->http('X-Requested-With') eq 'XMLHttpRequest');

	return $self;
}

sub get_session {
	my $panel = shift;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};

	require Vhffs::Panel::Auth;

	my $sid = $cgi->cookie( CGI::Session::name() );
	unless( defined $sid )  {
		$panel->add_error( gettext('No cookie found, please accept the cookie and then please login again !') );
		Vhffs::Panel::Auth::display_login( $panel );
		return;
	}

	my $session = new CGI::Session('driver:File', $sid, { Directory => '/tmp' } );
	unless( defined $session )  {
		$panel->add_error( gettext('Cannot fetch session file, please check that /tmp is readable and writeable') );
		Vhffs::Panel::Auth::display_login( $panel );
		return;
	}

	my $uid = $session->param('uid');
	unless( defined $uid ) {
		$panel->add_error( gettext('Expired session ! Please login again') );
		$session->delete();
		$session->flush(); # Recommended practice says use flush() after delete().
		Vhffs::Panel::Auth::display_login( $panel );
		return;
	}

	my $user = Vhffs::User::get_by_uid($vhffs, $uid);
	unless ( defined $user )  {
		$panel->add_error( gettext('User does not exist') );
		$session->delete();
		$session->flush(); # Recommended practice says use flush() after delete().
		Vhffs::Panel::Auth::display_login( $panel );
		return;
	}

	unless( $user->get_status == Vhffs::Constants::ACTIVATED )  {
		$panel->add_error( gettext('You\'re are not allowed to browse panel') );
		$session->delete();
		$session->flush(); # Recommended practice says use flush() after delete().
		Vhffs::Panel::Auth::display_login( $panel );
		return;
	}

	$panel->{session} = $session;
	$panel->{user} = $user;
	$vhffs->set_current_user( $user );

	return $session;
}

sub set_group {
	my $panel = shift;
	$panel->{group} = shift;
}

sub has_errors {
	my $panel = shift;
	return (@{$panel->{errors}} > 0);
}

sub set_title {
	my ($panel, $title) = @_;
	$panel->{title} = $title;
}

sub add_error {
	my ($panel, $error) = @_;
	# TODO Do not use anonymous hash when Template::Toolkit transition is over.
	push(@{$panel->{errors}}, {msg => $error});
}

sub add_info {
	my ($panel, $info) = @_;
	# TODO Do not use anonymous hash when Template::Toolkit transition is over.
	push(@{$panel->{infos}}, {msg => $info});
}

sub add_cookie {
	my ($panel, $cookie) = @_;
	push(@{$panel->{cookies}}, $cookie);
}

sub clear_infos {
	my $panel = shift;
	$panel->{infos} = [];
}

sub get_lang {
	my $panel = shift;
	return $panel->{lang};
}

sub get_theme {
	my $panel = shift;
	return $panel->{theme};
}

=head2 $panel->render($file, $vars, $layout)

Renders given template with substitution variables C<$vars>.

If no C<$layout> is provided, C<layouts/panel.tt> will be used
otherwise C<$layout> should be the name of the layout relative
to the C<layouts> folder.

If request was made through Ajax, no layout will be processed.

B<This function never return>.

=cut


sub render {
	my ($self, $file, $vars, $layout, $include_path) = @_;
	my $vhffs = $self->{vhffs};
	my $cgi = $self->{cgi};
	$vhffs->clear_current_user;

	# TODO Should be in parent class when Template::Toolkit switch is over
	my $create_vars = {
		INCLUDE_PATH => $self->{templatedir}.(defined $include_path ? '/'.$include_path.'/' : '/panel/'),
		CONSTANTS => {
			vhffs => {
				VERSION                     => Vhffs::Constants::VHFFS_VERSION,
				RELEASE_NAME                => Vhffs::Constants::VHFFS_RELEASE_NAME,
			},
			object_statuses => {
				WAITING_FOR_VALIDATION      => Vhffs::Constants::WAITING_FOR_VALIDATION,
				VALIDATION_REFUSED          => Vhffs::Constants::VALIDATION_REFUSED,
				WAITING_FOR_CREATION        => Vhffs::Constants::WAITING_FOR_CREATION,
				CREATION_ERROR              => Vhffs::Constants::CREATION_ERROR,
				WAITING_FOR_ACTIVATION      => Vhffs::Constants::WAITING_FOR_ACTIVATION,
				ACTIVATED                   => Vhffs::Constants::ACTIVATED,
				ACTIVATION_ERROR            => Vhffs::Constants::ACTIVATION_ERROR,
				WAITING_FOR_SUSPENSION      => Vhffs::Constants::WAITING_FOR_SUSPENSION,
				SUSPENDED                   => Vhffs::Constants::SUSPENDED,
				SUSPENSION_ERROR            => Vhffs::Constants::SUSPENSION_ERROR,
				WAITING_FOR_MODIFICATION    => Vhffs::Constants::WAITING_FOR_MODIFICATION,
				MODIFICATION_ERROR          => Vhffs::Constants::MODIFICATION_ERROR,
				WAITING_FOR_DELETION        => Vhffs::Constants::WAITING_FOR_DELETION,
				DELETION_ERROR              => Vhffs::Constants::DELETION_ERROR
			},
			user_permissions => {
				NORMAL                      => Vhffs::Constants::USER_NORMAL,
				MODERATOR                   => Vhffs::Constants::USER_MODERATOR,
				ADMIN                       => Vhffs::Constants::USER_ADMIN
			},
			acl => {
				UNDEFINED                   => Vhffs::Constants::ACL_UNDEFINED,
				DENIED                      => Vhffs::Constants::ACL_DENIED,
				VIEW                        => Vhffs::Constants::ACL_VIEW,
				MODIFY                      => Vhffs::Constants::ACL_MODIFY,
				MANAGEACL                   => Vhffs::Constants::ACL_MANAGEACL,
				DELETE                      => Vhffs::Constants::ACL_DELETE
			},
			mailinglist => {
				SUBSCRIBE_NO_APPROVAL_REQUIRED          => Vhffs::Constants::ML_SUBSCRIBE_NO_APPROVAL_REQUIRED,
				SUBSCRIBE_APPROVAL_REQUIRED             => Vhffs::Constants::ML_SUBSCRIBE_APPROVAL_REQUIRED,
				SUBSCRIBE_CLOSED                        => Vhffs::Constants::ML_SUBSCRIBE_CLOSED,
				POSTING_OPEN_ALL                        => Vhffs::Constants::ML_POSTING_OPEN_ALL,
				POSTING_MODERATED_ALL                   => Vhffs::Constants::ML_POSTING_MODERATED_ALL,
				POSTING_OPEN_MEMBERS_MODERATED_OTHERS   => Vhffs::Constants::ML_POSTING_OPEN_MEMBERS_MODERATED_OTHERS,
				POSTING_MEMBERS_ONLY                    => Vhffs::Constants::ML_POSTING_MEMBERS_ONLY,
				POSTING_MEMBERS_ONLY_MODERATED          => Vhffs::Constants::ML_POSTING_MEMBERS_ONLY_MODERATED,
				POSTING_ADMINS_ONLY                     => Vhffs::Constants::ML_POSTING_ADMINS_ONLY,
				RIGHT_SUB_WAITING_FOR_REPLY             => Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_REPLY,
				RIGHT_SUB_WAITING_FOR_VALIDATION        => Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_VALIDATION,
				RIGHT_SUB                               => Vhffs::Constants::ML_RIGHT_SUB,
				RIGHT_SUB_WAITING_FOR_DEL               => Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_DEL,
				RIGHT_ADMIN                             => Vhffs::Constants::ML_RIGHT_ADMIN
			}
		},
		FILTERS => {
			i18n => \&gettext,
			mail => sub {
				return Vhffs::Functions::obfuscate_email($vhffs, $_[0]);
			},
			# Format filter accept only one argument
			# pretty_print can 'sprintf' anything, use it as
			# [% '%s is $%d' | pretty_print(article, price)]
			pretty_print => [sub {
				my $context = shift;
				my @args = @_;
				return sub {
					my $format = shift;
					return sprintf($format, @args);
				}
			}, 1],
			stringify_status => sub {
				return Vhffs::Functions::status_string_from_status_id( $_[0] );
			},
			stringify_type => sub {
				Vhffs::Functions::type_string_from_type_id( $_[0] );
			},
			idn_to_unicode => sub {
				require Net::LibIDN;
				Encode::decode_utf8( Net::LibIDN::idn_to_unicode( $_[0] , 'utf-8') );
			},
		},
		PRE_CHOMP => 2
	};

	$vars = {} unless(defined $vars);

	my $query_string = '';
	foreach( my @params = $cgi->url_param ) {
		my $p = $cgi->url_param($_);
		$query_string .= $_.'='.$p.';' if defined $p and $_ ne 'lang' and $_ ne 'theme';
	}
	chop $query_string;
	undef $query_string unless $query_string;

	$vars->{do} = $cgi->url_param('do');
	$vars->{query_string} = $query_string;
	$vars->{theme} = $self->{theme};
	$vars->{panel_url} = $self->get_config->{url};
	$vars->{title} = sprintf( gettext( '%s\'s Panel' ), $vhffs->get_config->get_host_name );
	$vars->{page_title} = $self->{title};
	$vars->{public_url} = $self->get_config->{'url_public'} if $self->is_public;
	$vars->{msg} = Encode::decode_utf8($self->{cgi}->param('msg')) if defined $self->{cgi}->param('msg');
	my @langs = $vhffs->get_config->get_available_languages;
	$vars->{languages} = \@langs;
	$vars->{language} = $self->{lang};
	$vars->{errors} = $self->{errors};
	$vars->{infos} = $self->{infos};
	$vars->{current_user} = $self->{user};
	$vars->{current_group} = $self->{group};

	# Handling ajax stuff
	if($self->{is_ajax_request}) {
		delete $create_vars->{PROCESS};
	} else {
		if(defined $layout) {
			$create_vars->{PROCESS} = 'layouts/'.$layout;
		} else {
			$create_vars->{PROCESS} = 'layouts/panel.tt';
			$vars->{panel_header} = {
				help_url => $self->get_config->{'url_help'} || 'http://www.vhffs.org/',
				admin_menu => $self->{display_admin_menu},
				available_services => $vhffs->get_config->get_available_services
			};
		}
	}

	my $template = new Template($create_vars);

	my $http_accept = ( $cgi->http('HTTP_ACCEPT') or '' );
	print $cgi->header( -cookie=>[ @{$self->{cookies}} ], -type=>( $http_accept =~ /application\/xhtml\+xml/ ? 'application/xhtml+xml' : 'text/html' ), -charset=>'utf-8' );

	my $data;
	unless( $template->process($file, $vars, \$data) ) {
		warn 'Error while processing template: '.$template->error();
		return;
	}
	# FCGI does not handle UTF8
	print Encode::encode_utf8( $data );
}

=pod

=head2 redirect

	$panel->redirect($dest);

Issues a redirection header sending to $dest.

=cut
sub redirect {
	my ($panel, $dest) = @_;
	my $vhffs = $panel->{vhffs};
	my $cgi = $panel->{cgi};
	$vhffs->clear_current_user;

	print $cgi->redirect( -uri=>Encode::encode_utf8($dest), -cookie=>[ @{$panel->{cookies}} ] );
}

1;
