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

package Vhffs::Panel::User;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Encode;

use Vhffs::Constants;
use Vhffs::User;
use Vhffs;
use Vhffs::Panel;
use Vhffs::Panel::User;
use Vhffs::Panel::Object;
use Vhffs::Services::MailUser;
use Vhffs::Services::Newsletter;

=pod

=head1 NAME

Vhffs::Panel::User - Light weight user method.

Provides methods which can be used when you need informations
about users put don't want to use heavy objects.

=pod
=head1 METHODS
=cut

=head2 get_last_users

Fetches and returns an array of hashrefs {username, firstname, lastname,
groups => {groupname}} containing information about the last ten users of the
platform

=cut

sub get_last_users {
	my ($vhffs) = @_;

	my $sql = 'SELECT u.uid, u.username, u.firstname, u.lastname '.
	  'FROM vhffs_users u '.
	  'INNER JOIN vhffs_object o ON o.object_id=u.object_id '.
	  'WHERE o.state=? ORDER BY o.date_creation DESC LIMIT 10';

	my $dbh = $vhffs->get_db();

	my $users = $dbh->selectall_hashref($sql, 'uid', undef, Vhffs::Constants::ACTIVATED);

	fill_groups($vhffs, $users);

	my @val = values(%$users);

	return \@val;
}

sub search_user {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT u.uid, u.username, u.firstname || \' \' || u.lastname as realname, o.state '.
	  'FROM vhffs_users u '.
	  'INNER JOIN vhffs_object o ON (o.object_id = u.object_id) ';

	if( defined $name ) {
		$sql .= 'WHERE u.username LIKE ? OR u.firstname ILIKE ? OR u.lastname ILIKE ? ';
		push(@params, '%'.lc($name).'%', '%'.$name.'%', '%'.$name.'%');
	}

	$sql .= 'ORDER BY u.username';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

=head2 public_search

	$users = Vhffs::Panel::User::public_search($vhffs, $username, $start);

Returns all users whose username contains C<$username>.

=cut

sub public_search {
	my ($vhffs, $username, $start) = @_;
	my $result = {};

	my $select_clause = 'SELECT u.uid, u.username, u.firstname, u.lastname ';
	my $sql =
	  'FROM vhffs_users u '.
	  'INNER JOIN vhffs_object o ON o.object_id = u.object_id '.
	  'WHERE o.state = ? ';
	my @params;
	push @params, Vhffs::Constants::ACTIVATED;

	if(defined $username) {
		# usernames are enforced in lowercase
		$sql .= ' AND username ILIKE ?';
		push @params, '%'.$username.'%';
	}

	my $limit = ' LIMIT 10';
	$limit .= ' OFFSET '.($start * 10) if(defined $start);

	my $dbh = $vhffs->get_db();

	my $users = $dbh->selectall_hashref($select_clause.$sql.' ORDER BY u.username '.$limit, 'uid', undef, @params);

	my ($count) = $dbh->selectrow_array('SELECT COUNT(*) '.$sql, undef, @params);

	fill_groups($vhffs, $users);

	my @val = values(%$users);

	# We've to sort manualy since we use a hash
	@val = sort { $a->{username} cmp $b->{username}} @val;

	return (\@val, $count);
}

=head2 fill_groups

	Vhffs::Panel::User::fill_groups($vhffs, $users);

C<$users> is a HASHREF indexed by uid containing at least
the C<uid> field. It is modified inplace to add a field
C<groups> containing the names of the groups the user belongs
to.

=cut
sub fill_groups {
	my ($vhffs, $users) =@_;

	my $dbh = $vhffs->get_db();
	my @uids = ();

	foreach my $uid(keys(%$users)) {
		push @uids, $uid;
	}

	# Fetch all groups in one shot
	my $sql = 'SELECT g.groupname, u.uid FROM vhffs_groups g '.
	  'INNER JOIN vhffs_user_group ug ON ug.gid = g.gid '.
	  'INNER JOIN vhffs_users u ON u.uid = ug.uid '.
	  'WHERE g.groupname != u.username AND u.uid IN ( '.join(', ', @uids).') '.
	  'ORDER BY g.groupname';

	my $groups = $dbh->selectall_arrayref($sql, { Slice => {}});
	my $i = 0;

	foreach my $g(@$groups) {
		$users->{$g->{uid}}{groups} = [] unless exists $users->{$g->{uid}}{groups};
		push(@{$users->{$g->{uid}}{groups}}, $g->{groupname});
	}
}

sub fetch_users_and_groups {
	my ($vhffs, $sql, @params) = @_;
	my @users;

	my $dbh = $vhffs->get_db;
	my $sth = $dbh->prepare($sql);
	$sth->execute( @params );
	$sql = 'SELECT g.groupname FROM vhffs_groups g INNER JOIN vhffs_user_group ug ON ug.gid = g.gid WHERE ug.uid = ? AND g.groupname != ?';
	my $ssth = $dbh->prepare($sql);
	while(my $row = $sth->fetchrow_hashref) {
		$ssth->execute($row->{uid}, $row->{username});
		$row->{groups} = $ssth->fetchall_arrayref({});
		push @users, $row;
	}

	return \@users;
}

sub get_available_shells {
	my $vhffs = shift;
	return -1 unless defined $vhffs;
	return split(/\s+/,$vhffs->get_config->get_users->{'available_shells'});
}


sub get_default_shell {
	my $vhffs = shift;
	return -1 unless defined $vhffs;
	return $vhffs->get_config->get_users->{'default_shell'};
}

sub prefs {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $userp;
	my $vars = {};

	my $username = $cgi->param('name');
	if( defined $username ) {
		$userp = Vhffs::User::get_by_username( $vhffs, $username );
	} else {
		$userp = $user;
	}

	unless( defined $userp )  {
		$panel->render( 'misc/message.tt', { message => gettext('Cannot get informations on this object')} );
		return;
	}

	unless( $user->can_view( $userp ) ) {
		$panel->render( 'misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	if( defined $cgi->param('prefs_submit') ) {
		unless( $user->can_modify( $userp ) ) {
			$panel->add_error( gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) );
		} else {
			my $mail = $cgi->param( 'mail' );
			my $firstname = Encode::decode_utf8( scalar $cgi->param( 'firstname' ) );
			my $lastname = Encode::decode_utf8( scalar $cgi->param( 'lastname' ) );
			my $city = Encode::decode_utf8( scalar $cgi->param( 'city' ) );
			my $zipcode = Encode::decode_utf8( scalar $cgi->param( 'zipcode' ) );
			my $country = Encode::decode_utf8( scalar $cgi->param( 'country' ) );
			my $address = Encode::decode_utf8( scalar $cgi->param( 'address' ) );
			my $pass1 = $cgi->param( 'password1' );
			my $pass2 = $cgi->param( 'password2' );
			my $theme = $cgi->param( 'theme' );
			my $lang = $cgi->param( 'lang' );
			my $shell = $cgi->param( 'shell' );
			my $newslettercheckbox = $cgi->param('newsletter');
			$newslettercheckbox = ( defined $newslettercheckbox && $newslettercheckbox eq 'on' );

			my $pwd_change = 0;
			my $mail_change = 0;

			# Commit all the changes for the current user
			unless( defined $firstname and defined $lastname and defined $city and defined $mail and defined $zipcode and defined $country and defined $address and defined $shell and defined $lang and defined $theme )  {
				$panel->add_error( gettext( 'CGI Error !' ) );
			}
			else {
				# We don't really care about what user use as firstname, lastname, ... we just
				# want it not to break everything

				$panel->add_error( gettext( 'Firstname is not correct !') ) unless defined $firstname and $firstname =~ /^[^<">]+$/;
				$panel->add_error( gettext( 'Lastname is not correct !') ) unless defined $lastname and $lastname =~ /^[^<">]+$/;
				$panel->add_error( gettext( 'City is not correct !') ) unless defined $city and $city =~ /^[^<">]+$/;
				$panel->add_error( gettext( 'Email is not correct !') ) unless Vhffs::Functions::valid_mail($mail);
				$panel->add_error( gettext( "Zipcode is not correct !" ) ) unless defined $zipcode and $zipcode =~ /^[\w\d\s\-]+$/;
				$panel->add_error( gettext( 'Country is not correct !') ) unless defined $country and $country =~ /^[^<">]+$/;
				$panel->add_error( gettext( 'Address is not correct !') ) unless defined $address and $address =~ /^[^<">]+$/;
				$panel->add_error( gettext( "Passwords don't match" ) ) unless defined $pass1 and defined $pass2 and $pass1 eq $pass2;

				if( $userp->have_activegroups > 0 ) {
					unless( grep { $_ eq $shell } Vhffs::Panel::User::get_available_shells( $vhffs ) ) {
						$panel->add_error( gettext( 'Wanted shell is not in the shell list' ) );
					}
				}
				else {
					$shell = Vhffs::Panel::User::get_default_shell( $vhffs );
				}

				unless( grep { $_ eq $lang } $vhffs->get_config->get_available_languages ) {
					$panel->add_error( gettext( 'Wanted language is not in the language list' ) );
				}

				unless( grep { $_ eq $theme } $panel->get_available_themes ) {
					$panel->add_error( gettext( 'Wanted theme is not in the theme list' ) );
				}

				unless( $panel->has_errors) {
					$userp->set_firstname( $firstname );
					$userp->set_lastname( $lastname );
					$userp->set_city( $city );
					$userp->set_zipcode( $zipcode );
					$userp->set_country( $country );
					$userp->set_address( $address );
					$userp->set_lang( $lang );
					$userp->set_theme( $theme );
					$userp->set_shell( $shell );

					if( length( $pass1 ) > 1 and $pass1 eq $pass2 ) {
						$pwd_change = 1;
						$userp->set_password( $pass1 );
						$panel->add_info( gettext('Password changed') );
					}

					my $prevmail = $userp->get_mail();
					if( $prevmail ne $mail ) {
						$mail_change = 1;

						my $newsletter = new Vhffs::Services::Newsletter( $vhffs , $userp );
						$newsletter->del if defined $newsletter;

						$userp->set_mail( $mail );
						my $subject = gettext('Mailbox modified');
						my $content = sprintf( gettext("Hello %s %s,\n\nYou changed your email, here are your new personal information :\n\nUser: %s\nMail: %s\n\nVHFFS administrators\n"), $userp->get_firstname, $userp->get_lastname, $userp->get_username, $userp->get_mail);
						$userp->send_mail_user( $subject, $content );
						$panel->add_info( gettext('Email address changed') );
					}

					if( $userp->commit < 0 ) {
						$panel->clear_infos();
						$panel->add_error( gettext('An error occured while updating the user account') );
					}

					# -- Mail User
					my $mu = new Vhffs::Services::MailUser( $vhffs , $userp );
					if( defined $mu )  {

						my $mail_activate = $cgi->param( 'mail_activate' );
						$mail_activate = ( defined $mail_activate and $mail_activate eq 'on' );
						my $nospam = $cgi->param( 'mail_nospam' );
						$nospam = ( defined $nospam and $nospam eq 'on' );
						my $novirus = $cgi->param( 'mail_novirus' );
						$novirus = ( defined $novirus and $novirus eq 'on' );

						if( $mail_activate ) {
							my $usage = $cgi->param( 'mail_usage' );
							unless( defined $usage ) {
								$panel->add_error( gettext('You must choose a method for your mail') );
							}
							elsif( $usage == 1 ) {
								#here, we create the box
								my $box = $mu->get_box;
								unless( $box ) {
									# Box doesn't exists, need a password
									unless( $box = $mu->add_box( $userp->get_password, 1 ) ) {
										$panel->add_error( gettext('An error occured while adding the box') );
									} else {
										$box->get_localpart->set_nospam( $nospam );
										$box->get_localpart->set_novirus( $novirus );
										unless( $box->get_localpart->commit ) {
											$panel->add_error( gettext('An error occured while adding the box (anti-spam or anti-virus adding)') );
										} else {
											$panel->add_info( gettext('Mailbox successfully added') );
										}
									}
								} else {
									#Box already exists
									# The user changed his password, we must update password for mail
									if( $pwd_change ) {
										my $lp = $mu->get_box->get_localpart;
										$lp->set_password( $pass1 );
										unless( $lp->commit ) {
											$panel->add_error( gettext('An error occured while changing the box password') );
										} else {
											$panel->add_info( gettext('Mailbox password changed') );
										}
									}

									# We change the spam status. if the spam status changed
									if( $mu->use_nospam ) {
										if( $nospam != $box->get_localpart->get_nospam ) {
											$box->get_localpart->toggle_nospam;
											if( $box->get_localpart->commit ) {
												$panel->add_info( gettext( 'Changed spam protection status for your account' ) );
											} else {
												$panel->add_error( gettext( 'Error for spam protection' ) );
											}
										}
									}

									# As spam, the virus status changes only if the user changed values
									if( $mu->use_novirus ) {
										if( $novirus != $box->get_localpart->get_novirus ) {
											$box->get_localpart->toggle_novirus;
											if( $box->get_localpart->commit ) {
												$panel->add_info( gettext( 'Changed anti-virus status for your account' ) );
											} else {
												$panel->add_error( gettext( 'Error for virus protection' ) );
											}
										}
									}
								}
							}
							elsif( $usage == 2 ) {
								my $redirect = $mu->get_redirect;
								#Here, we create the forward
								unless( $redirect ) {
									unless( $redirect = $mu->add_redirect( $userp->get_mail ) ) {
										$panel->add_error(  gettext('There is a problem with the address you filled in your profile, unable to add forwarding') );
									} else {
										$panel->add_info( gettext('Forward added') );
									}
								}
								#here, we update the forward
								elsif( $mail_change ) {
									if( $redirect->set_redirect( $mail ) and $redirect->commit ) {
										$panel->add_info( gettext('Redirect updated') );
									} else {
										$panel->add_error( gettext('An error occured while updating the redirect') );
									}
								}
							}
						} elsif( $mu->get_localpart ) {
							$panel->add_info( gettext('Mail deleted') );
							# User doesn't want mail anymore
							$mu->delete;
						}
					}

					# -- Newsletter
					my $newsletter = new Vhffs::Services::Newsletter( $vhffs , $userp );
					if( defined $newsletter )  {
						if( $newslettercheckbox and not $newsletter->exists ) {
							$newsletter->add;
						} elsif( not $newslettercheckbox and $newsletter->exists and $newsletter->get_collectmode != Vhffs::Services::Newsletter::PERMANENT ) {
							$newsletter->del;
						}
					}

				}
			}
		}
	}

	elsif( defined $cgi->param('delete_submit') ) {

		my $delete = $cgi->param('delete');
		my $message;

		# We make sure the current user is allowed to delete the specified user
		unless( $user->can_delete( $userp ) ) {
			$message = gettext('You\'re not allowed to delete this user');
		} else {
			if( $delete == 1 ) {
				if( @{$userp->get_groups} ) {
					$message = gettext('This user is still in a group');
				} else {
					$userp->set_status( Vhffs::Constants::WAITING_FOR_DELETION );
					if( $userp->commit < 0 ) {
						$message = gettext('An error occured while applying changes. This user will NOT be deleted');
					} else {
						$panel->render('misc/message.tt', { message => gettext('This user will BE DELETED'), refresh_url => '?do=login' });
						return;
					}
				}
			} else {
				$message = gettext('This user will NOT be DELETED');
			}
		}

		$panel->render('misc/message.tt', { message => $message });
		return;
	}

	elsif( defined $cgi->param('update_ircnick_submit') ) {
		update_ircnick( $panel, $userp );
	}

	elsif( defined $cgi->param('update_permissions_submit') ) {
		update_permissions( $panel, $userp );
	}

	$panel->set_title( gettext('User Preferences') );
	$vars->{user} = $userp;
	my @themes = $panel->get_available_themes;
	$vars->{themes} = \@themes;
	$vars->{user_help_url} = $vhffs->get_config->get_users()->{url_doc};

	if( $userp->have_activegroups > 0 )  {
	        my @shells = Vhffs::Panel::User::get_available_shells( $vhffs );
	        $vars->{shells} = \@shells;
	} else {
	        $vars->{shells} = [ Vhffs::Panel::User::get_default_shell( $vhffs ) ];
	}

	my $newsletter = new Vhffs::Services::Newsletter( $vhffs , $userp );
	$vars->{newsletter} = { active => 1, subscribed => $newsletter->exists } if defined $newsletter and $newsletter->get_collectmode != Vhffs::Services::Newsletter::PERMANENT;

	$vars->{mail_user} = new Vhffs::Services::MailUser( $vhffs, $userp );
	$vars->{use_avatars} = $panel->use_users_avatars;

	$panel->render('user/prefs.tt', $vars);
}

sub update_ircnick {
	my $panel = shift;
	my $userp = shift;
	my $user = $panel->{user};
	my $cgi = $panel->{cgi};

	unless( $user->is_admin ) {
		$panel->add_error( gettext('Only administrators can do this') );
		return;
	}

	my $ircnick = $cgi->param('ircnick');
	unless(defined $ircnick) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	if( $ircnick !~ /^[^<">\s]*$/ ) {
		$panel->add_error( gettext( 'IRC nick is not correct !') );
		return;
	}

	$userp->set_ircnick($ircnick);
	if($userp->commit < 0) {
		$panel->add_error( gettext('Unable to update user, please try again later') );
	} else {
		$panel->add_info( gettext('User successfully updated') );
	}
}

sub update_permissions {
	my $panel = shift;
	my $userp = shift;
	my $user = $panel->{user};
	my $cgi = $panel->{cgi};

	unless( $user->is_admin ) {
		$panel->add_error( gettext('Only administrators can do this') );
		return;
	}

	my $permissions = $cgi->param('permissions');
	unless(defined $permissions) {
		$panel->add_error( gettext('CGI Error !') );
		return;
	}

	$userp->set_admin($permissions);
	if($userp->commit < 0) {
		$panel->add_error( gettext('Unable to update user, please try again later') );
	} else {
		$panel->add_info( gettext('User successfully updated') );
	}
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
		  search_title => gettext('Users search'),
		  type => 'user'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all users');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{users} = search_user( $vhffs , $name );
	$panel->render('admin/user/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Users\' administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_user_category() ] } );
}

1;
