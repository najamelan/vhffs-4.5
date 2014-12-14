#!%PERL% -w

use strict;
use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::User;
use MIME::Base64;

# Flush output immediately.
$| = 1;

my $vhffs = new Vhffs( { backend => 0 } );
exit 1 unless defined $vhffs;

$vhffs->connect;

# On startup, we have to inform c2s of the functions we can deal with. USER-EXISTS is not optional.
#print "OK USER-EXISTS GET-PASSWORD CHECK-PASSWORD SET-PASSWORD GET-ZEROK SET-ZEROK CREATE-USER DESTROY-USER FREE\n";
print "OK USER-EXISTS CHECK-PASSWORD CREATE-USER FREE\n";

# Our main loop
my $buf;
while(sysread (STDIN, $buf, 1024) > 0)
{
	my ($cmd, @args) = split ' ', $buf;
	$cmd =~ tr/[A-Z]/[a-z]/;
	$cmd =~ tr/-/_/;

	eval "print _cmd_$cmd(\@args), '\n'";
}

return 0;


sub fetch_user
{
	my $username = shift;

	# Reconnect to backend if necessary
	return undef unless $vhffs->reconnect();

	my $user = Vhffs::User::get_by_username( $vhffs , $username );
	return undef unless( defined $user );

	undef $user if( $user->have_activegroups <= 0 );

	return $user;
}


# Determine if the requested user exists.
sub _cmd_user_exists
{
	my ($username, $realm) = @_;
	my $user = fetch_user( $username );

	if ( defined $user )  {
		undef $user;
		return 'OK';
	}
	return 'NO';
}


# Compare the given password with the stored password.
sub _cmd_check_password
{
	my ($username, $passb64, $realm) = @_;

	return 'NO' unless defined $passb64;

	my $user = fetch_user( $username );
	undef $user if( defined $user  &&  $user->check_password( decode_base64($passb64) ) == 0 );

	if( defined $user )  {
		undef $user;
		return 'OK';
	}
	return 'NO';
}


# Create a user in the database (with no auth credentials).
sub _cmd_create_user
{
	my ($username, $realm) = @_;

	return _cmd_user_exists($username, $realm);
}


# c2s shutting down, do the same.
sub _cmd_free
{
	exit(0);
}
