#!%PERL%


# modobot is an IRC bot which allow you to validate
# VHFFS objects through IRC
# Written by Florent Bayle and Sylvain Rochet (this is very important to add my name here, to become famous very soon)

use strict;
use utf8;
use POSIX qw(locale_h);
use locale;
use warnings;
use Locale::gettext;
use Encode;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Constants;
use Vhffs::Object;
use Vhffs::ObjectFactory;
use Vhffs::Tag;
use Vhffs::Tag::Request;
use Vhffs::Tag::Category;

use Net::IRC;
use Net::DNS;
use Text::Wrapper;

binmode STDOUT, ':utf8';

my $bot;
my $cmpt = 0;

my %oldobjects = ();
my %oldrequests = ();

my $irc=new Net::IRC;

# Connections to servers

my $vhffs = new Vhffs( { backend => 0 } );
exit 1 unless defined $vhffs;

$vhffs->connect;

my $configirc = $vhffs->get_config->get_irc;
my $chan = $configirc->{modobot_channel};

my $conn=$irc->newconn(Nick     =>  $configirc->{modobot_name},
                       Server   =>  $configirc->{modobot_server},
                       Port     =>  $configirc->{modobot_port},
                       Username =>  'modobot',
                       Ircname  =>  'VHFFS Moderation bot' );
exit 2 unless $conn;


sub deletenl
{
    ($_) = @_;
    $_ =~ s/\n/ /g;
    $_ =~ s/\r//g;
    return $_;
}


sub list_moderation
{
	my $seq = shift;  # set that to 1 in order to display only new entries

	# Do nothing if backend is lost
	return unless $vhffs->reconnect();

	my $objects = Vhffs::Object::getall( $vhffs, undef, Vhffs::Constants::WAITING_FOR_VALIDATION );
	if( defined $objects )  {
		foreach my $obj ( @{$objects} ) {
			next if( $seq && exists( $oldobjects{$obj->get_oid} ) );

			my $user = $obj->get_owner;
			my $group = $obj->get_group;
			my $object = Vhffs::ObjectFactory::fetch_object( $vhffs , $obj->{object_id} );
			my $duration = delay_modo($obj->get_date);

			my $msg = '['.$duration.'] '.Vhffs::Functions::type_string_from_type_id( $obj->{type} ).':   '.$obj->get_oid.'   '.$user->get_username;
			$msg .= ' ('.$user->get_note.')' if $user->get_config->{'use_notation'};
			$msg .= ' ['.$user->get_lang.']   '.$group->get_groupname.'   '.$object->get_label.'   '.$obj->get_description;
			$msg .= "\n[".format_tags_list($group).']';
			irc_msg( $msg );

			$oldobjects{$obj->get_oid} = '';
		}
	}

	my $requests = Vhffs::Tag::Request::get_all($vhffs);
	foreach my $r (@$requests) {
		next if ( $seq && exists( $oldrequests{$r->{request_id}} ) );

		my $duration = delay_modo($r->{created});

                my $msg = '[' . $duration.'] tag request: ' . $r->{request_id} . ' ' . $r->{category_label} . '::' . $r->{tag_label};
		irc_msg( $msg );

		$oldrequests{$r->{request_id}} = '';
	}
}

sub delay_modo
{
        my $last = shift;
        my $diff = int( time() - $last );
        my $duration = '';
        if ( $diff >= 31536000 ) {
                $duration .= int( $diff / 31536000 ).'y ';
                $diff %= 31536000;
        }
        if ( $diff >= 2678400 ) {
                $duration .= int( $diff / 2678400 ).'M ';
                $diff %= 2678400;
        }
        if ( $diff >= 86400 ) {
                $duration .= int( $diff / 86400 ).'d ';
                $diff %= 86400;
        }
        if ( $diff >= 3600 ) {
                $duration .= int( $diff / 3600 ).'h ';
                $diff %= 3600;
        }

        $duration .= int( $diff / 60 ).'m';

        return $duration;
}


sub moderate
{
	my $oid = shift;
	my $user = shift;
	my $status = shift; # 0 = refuse , 1 = accept
	my $reason = shift;

	my $object = Vhffs::ObjectFactory::fetch_object( $vhffs , $oid );

	my $wfreason;
	my $charset;
	eval { $wfreason = Encode::decode_utf8( $reason , Encode::FB_CROAK ); };
	if( $@ )  {
		#decoding from utf8 failed, falling back to iso
		$wfreason = Encode::decode('iso-8859-1', $reason);
		$charset = 'ISO';
	}
	else  {
		$charset = 'UTF-8';
	}

	unless( defined $object )
	{
		irc_msg ('Error : Cannot fetch object');
		return ( -1 );
	}
	elsif( $object->get_status != Vhffs::Constants::WAITING_FOR_VALIDATION )
	{
		irc_msg ('Error : Object is not waiting for validation');
		return ( -2 );
	}
	else
	{
		if( $status == 1 )  {
			if( $object->moderate_accept( $wfreason ) < 0 )  {
				irc_msg('Error while committing changes');
			}
			else {
				irc_msg( 'Object '.$oid.' accepted ('.$charset.' detected)' );
			}
		}
		else  {

			if( $object->moderate_refuse( $wfreason ) < 0 )  {
				irc_msg('Error while committing changes');
			}
			else {
				irc_msg( 'Object '.$oid.' refused ('.$charset.' detected)' );
			}
		}
		delete $oldobjects{$oid};
	}
	return 0;
}

sub moderatetag
{
	my $rid = shift;
	my $user = shift;
	my $status = shift; # 0 = refuse , 1 = accept
	my $reason = shift;

	my $request = Vhffs::Tag::Request::get_by_request_id( $vhffs, $rid );

	my $wfreason;
	my $charset;
	eval { $wfreason = Encode::decode_utf8( $reason , Encode::FB_CROAK ); };
	if( $@ )  {
		#decoding from utf8 failed, falling back to iso
		$wfreason = Encode::decode('iso-8859-1', $reason);
		$charset = 'ISO';
	}
	else  {
		$charset = 'UTF-8';
	}

	unless( defined $request )
	{
		irc_msg ('Error : Cannot fetch request');
		return ( -1 );
	}
	else
	{
		if( $status == 1 )
		{
			my $category = Vhffs::Tag::Category::get_by_label($vhffs, $request->{category_label});
			unless( defined $category )
			{
				irc_msg('Error : Cannot fetch category');
				return -1;
			}

			my $tag = Vhffs::Tag::create($vhffs, $request->{tag_label}, $wfreason, $user, $category);
		
			unless(defined $tag) {
				irc_msg('Error : Unable to create tag');
				return -1;
			}

			# Adds the tag to the object for which it has
			# been requested.
		
			my $object = $request->get_tagged();
			if(defined $object) {
				my $ruser = $request->get_requester();
				$ruser = $user unless(defined $ruser);
				$object->add_tag($tag, $user);
			}
		
			$request->delete();
			irc_msg( 'Request '.$rid.' accepted ('.$charset.' detected)' );
		}
		else
		{

			if( $request->delete < 0 )  {
				irc_msg('Error while committing changes');
			}
			else {
				irc_msg( 'Request '.$rid.' deleted' );
			}
		}
		delete $oldrequests{$rid};
	}
	return 0;
}



sub on_ping {
    my ($self, $event) = @_;
    my $nick = $event->nick;
    my $timestamp = $event->{'args'}[0];

    $self->ctcp_reply($nick, 'PING ' . $timestamp);
    print "[ping-from]  : {$nick}\n"
} # on_ping

sub on_ping_reply {
    my ($self, $event) = @_;
    my ($args) = ($event->args)[1];
    my ($nick) = $event->nick;

    $args = time - $args;
    print "[ping-rsp]  : from $nick: $args sec.\n";
} # on_ping_reply

sub on_cversion {
    my ($self, $event) = @_;
    my ($nick, $mynick) = ($event->nick, $self->nick);
    my $reply = "Vhffs Bot";
    print "[ctcp-version] : <$nick>\n";
    $self->ctcp_reply($nick, join(' ', ($event->args), $reply));
} # on_cversion

sub on_connect {
    my $self=shift;
    $bot=$self;
    $self->join($chan);
    irc_msg ("--> $configirc->{modobot_name} started");
    &CatchAlrm();
} # on_connect

sub is_modo
{
	return (defined $_[0] && ($_[0]->is_moderator || $_[0]->is_admin ) )
} # is_modo

sub get_desc
{
    my $name = shift;
    my $group;
    if (! defined ($group= Vhffs::Group::get_by_groupname( $vhffs , $name ) ) )
    {
        irc_msg ("$name : No such group");
    }
    else
    {
        irc_msg ("$name : " . $group->get_description.'['.format_tags_list($group).']' );
    }
}

sub format_tags_list {
	my ($object) = @_;
	my $tag_categories = $object->get_tags(Vhffs::Constants::TAG_VISIBILITY_MODERATORS);

	return 'No tag' unless(@$tag_categories);

	my $result = '';
	foreach(@$tag_categories) {
		$result .= $_->{label}.': ';
		foreach(@{$_->{tags}}) {
			$result .= $_->{label}.', ';
		}
	}
	$result = substr($result, 0, -2);
}

sub find_group_from_web
{
	my $name = shift;
	my $web = Vhffs::Services::Web::get_by_servername( $vhffs, $name );
	unless( defined $web) {
		irc_msg( $name.' : No such website' );
	}
	else {
		irc_msg( $name.' => group  '.$web->get_group->get_groupname );
	}
}

sub owner_info
{
  my $groupname = shift;
  my $group;
  if (! defined ($group = Vhffs::Group::get_by_groupname( $vhffs , $groupname)))
  {
    irc_msg ("$groupname : No such groupname");
  }
  else
  {
    my $user = Vhffs::User::get_by_uid($vhffs, $group->get_owner_uid);
    if ( defined $user )
    {
      irc_msg ($groupname.' is owned by '.$user->get_username.' - '.$user->get_firstname.' '.$user->get_lastname.' <'.$user->get_mail.'>' );
    }
    else
    {
      irc_msg ($groupname." : error fetching user");}
    }
}

sub fetch_usergroup {
	my $groupname = shift;
	my $group = Vhffs::Group::get_by_groupname( $vhffs , $groupname );
	unless( defined $group ) {
		irc_msg ($groupname.' : No such group');
		return;
	}

	my $users = Vhffs::Group::get_users( $group );
	my $owner = $group->get_owner->get_uid;
	my $list = '';
	foreach ( @{$users} ) {
		$list .= '@' if $_->get_uid == $owner;
		$list .= $_->get_username.' ';
	}

	irc_msg( $list );
}

sub fetch
{
        my $name = shift;
        my $user = Vhffs::User::get_by_username( $vhffs , $name );
        unless( defined $user )
        {
               my $group = Vhffs::Group::get_by_groupname( $vhffs , $name );
               unless( defined $group )
               {
               		irc_msg ($name.' : No such user or group');
                        return;
		}

	        my $objects = Vhffs::Group::getall_objects( $group );
	        my $list = '';

	        foreach my $obj ( @{$objects} )
        	{
               		my $object = Vhffs::ObjectFactory::fetch_object( $vhffs , $obj->{object_id} );
               		$list .= '[ '.Vhffs::Functions::type_string_from_type_id( $object->{type} ).' ] '.$object->get_label.' ';
        	}
	        irc_msg( $list );
		return;
        }
        my $groups = Vhffs::User::get_groups( $user );
        my $list = '';

        foreach ( @{$groups} )
        {
                $list .= $_->get_groupname.' ';
        }

        irc_msg( $list );
}

sub quotacheck
{
 my $limit = shift;
 my $list = Vhffs::Group::getall_quotalimit($vhffs,$limit);
 my $temp;
 foreach $temp ( @{$list} )
  {
  irc_msg("Group ".$temp->get_groupname.": ".$temp->get_quota_used." / ".$temp->get_quota);
  }
}

sub get_quota
{
        my $groupname = shift;
        my $group = Vhffs::Group::get_by_groupname( $vhffs , $groupname );
        unless( defined $group )
        {
                irc_msg ($groupname.' : No such group');
                return;
        }
  irc_msg("Group ".$groupname.": ".$group->get_quota_used." / ".$group->get_quota);

}

sub set_quota
{
        my $groupname = shift;
        my $quotavalue = shift;
        my $group = Vhffs::Group::get_by_groupname( $vhffs , $groupname );
        unless( defined $group )
        {
                irc_msg ($groupname.' : No such group');
                return;
        }
my $old_quota = $group->get_quota;
$group->set_quota($quotavalue);
irc_msg("Group ".$groupname.": Setting quota from ".$old_quota." to ".$group->get_quota) if ($group->commit >= 0);

}

sub irc_msg
{
    my $text = shift;
    $text = deletenl ($text);
    my $wrapper = Text::Wrapper->new(columns => 300);
    my @text = split (/\n/, $wrapper->wrap($text));
    while ($text = shift @text)
    {
        $bot->privmsg($chan, Encode::encode_utf8($text) );
        sleep 2;
        sleep 8 if (($cmpt%10) == 9);
        $cmpt++;
        $cmpt = 0 if ($cmpt == 30);
    }
}

sub on_public {
    my ($self, $event)=@_;
    my ($nick, $mynick)=($event->nick, $self->nick);
    my $texte=$event->{args}[0];

	# Do nothing if backend is lost
	return unless $vhffs->reconnect();

    my $user = ( Vhffs::User::get_by_ircnick($vhffs, $nick) or Vhffs::User::get_by_username($vhffs, $nick) );
	$vhffs->set_current_user( $user );

    $texte =~ s/\s*$//;

    if ($texte =~ m/^${mynick}:\s+accept\s+[0-9]+.*$/)
    {
		if (is_modo ($user) == 1)
		{
			my ( $oid , $reason ) = ( $texte =~ /^${mynick}:\s+accept\s+([0-9]+)(?:\s+)?(.+)?$/ );
			moderate( $oid , $user, 1 , $reason );
		}
    }
    elsif ($texte =~ m/^${mynick}:\s+refuse\s+[0-9]+\s+.+$/)
    {
		if (is_modo ($user) == 1) {
			my ( $oid , $reason ) = ( $texte =~ /^${mynick}:\s+refuse\s+([0-9]+)(?:\s+)(.+)$/ );
			moderate( $oid , $user, 0 , $reason );
		}
    }
    elsif ($texte =~ m/^${mynick}:\s+help$/)
    {
        irc_msg("Commands :");
        irc_msg("help - show this help");
        irc_msg("accept <oid> [reason] - accept object with id <oid> for reason [reason]");
        irc_msg("refuse <oid> <reason> - refuse object with id <oid> for reason <reason>");
	irc_msg("list - force listing of all objects waiting for moderation");
	irc_msg("desc <group> - give the description of <group>");
        irc_msg("web2group <website> - give the groupe name of <website>");
        irc_msg("owner <group> - give owner information of <group>");
        irc_msg("lsgroup <group> - give the list of users of <group>");
        irc_msg("quotacheck <limit> - give the list of <limit> users where quota limit nearly reach ");
        irc_msg("getquota <group> - give quota for <group>");
        irc_msg("setquota <group> <newquota> - change quota for <group> to <newquota>");
	irc_msg("whois <domain> - give NS for <domain>");
        irc_msg("accepttag <rid> <description> - accept tag request with id <rid> with description <description>");
        irc_msg("refusetag <rid> - refuse tag request with id <rid>");
        irc_msg("fetch <user|group> - fetch user | group with  <user|group>");

   }
    elsif ($texte =~ m/^${mynick}:\s+list$/)
    {
	list_moderation( 0 );
    }
    elsif ($texte =~ m/^${mynick}:\s+desc\s+[a-z0-9]+$/)
    {
        my $groupid = $texte;
	$groupid =~ s/^${mynick}:\s+desc\s+//;
        get_desc ($groupid);
    }

    elsif ($texte =~ m/^${mynick}:\s+web2group\s+[a-z0-9\.\-]+$/)
    {
        my $webtogroup = $texte;
        $webtogroup =~ s/^${mynick}:\s+web2group\s+//;
        find_group_from_web($webtogroup);
    }

    elsif ($texte =~ m/^${mynick}:\s+owner\s+[a-z0-9]+$/)
    {
        my $groupid = $texte;
        $groupid =~ s/^${mynick}:\s+owner\s+//;
        owner_info ($groupid);
    }

    elsif ($texte =~ m/^${mynick}:\s+lsgroup\s+[a-z0-9]+$/)
    {
        my $groupid = $texte;
        $groupid =~ s/^${mynick}: lsgroup //;
        fetch_usergroup ($groupid);
    }
    elsif ($texte =~ m/^${mynick}:\s+quotacheck\s+[0-9]+$/)
    {
        my $limit = $texte;
        $limit =~ s/^${mynick}:\s+quotacheck\s+//;
        quotacheck($limit);
    }

    elsif ($texte =~ m/^${mynick}:\s+getquota\s+[a-z0-9]+$/)
    {
        my $groupquota = $texte;
        $groupquota =~ s/^${mynick}:\s+getquota\s+//;
        get_quota($groupquota);
    }

    elsif ($texte =~ m/^${mynick}:\s+setquota\s+[a-z0-9]+\s+.*$/)
    {
        if (is_modo ($user) == 1)
        {
            my $groupname = $texte;
            my $quotavalue = $texte;
            $quotavalue =~ s/^${mynick}:\s+setquota\s+[a-z0-9]+\s+//;
            $groupname =~ s/^${mynick}:\s+setquota\s+([a-z0-9]+)\s+.*$/$1/;
            set_quota($groupname,$quotavalue);
        }

    }

    elsif ($texte =~ m/^${mynick}:\s+whois\s+[a-z0-9\.\-]+$/)
    {
	my $whois = $texte;
	$whois =~ s/^${mynick}:\s+whois\s+//;
	my $resolv = Net::DNS::Resolver->new;

	if (my $query = $resolv->query($whois, "NS"))
	{
	    irc_msg ("Domain $whois registered");
	    foreach my $rr (grep { $_->type eq 'NS' } $query->answer)
		{ irc_msg("NS : ".$rr->nsdname); }
 	}
  	else { irc_msg("query failed for $whois : ".$resolv->errorstring); }
    }

    elsif ($texte =~ m/^${mynick}:\s+accepttag\s+[0-9]+.*$/)
    {
		if (is_modo ($user) == 1)
		{
			my ( $rid , $reason ) = ( $texte =~ /^${mynick}:\s+accepttag\s+([0-9]+)(?:\s+)?(.+)?$/ );
			moderatetag( $rid , $user, 1 , $reason );
		}
    }
    elsif ($texte =~ m/^${mynick}:\s+refusetag\s+[0-9]+\s*$/)
    {
		if (is_modo ($user) == 1) {
			my $rid = $texte;
			$rid =~ s/^${mynick}:\s+refusetag\s+([0-9]+)\s*$/$1/;
			moderatetag( $rid , $user, 0 , '' );
		}
    }
    elsif ($texte =~ m/^${mynick}:\s+fetch\s+[a-z0-9]+$/)
    {
        my $name = $texte;
        $name =~ s/^${mynick}: fetch //;
        fetch($name);
    }


	$vhffs->clear_current_user;
} # on_public

sub on_kick {
    my $self=shift;
    $self->join($chan);
} # on_kick

$conn->add_handler        ('cping',    \&on_ping);
$conn->add_handler        ('crping',   \&on_ping_reply);
$conn->add_global_handler ('376',      \&on_connect);
$conn->add_global_handler ('422',      \&on_connect); # if MOTD is missing
$conn->add_handler        ('cversion', \&on_cversion);
$conn->add_handler        ('public',   \&on_public);
$conn->add_handler        ('kick',     \&on_kick);

sub CatchAlrm
{
    list_moderation( 1 );
    alarm 60;
}


local $SIG{ALRM} = \&CatchAlrm;
$irc->start;

