<?php 

/*
	VHFFS Auth plugin for MediaWiki


LocalSettings.php :

$wgWhitelistEdit = true;
$wgVHFFSAuthPluginDB = 'host=127.0.0.1 port=5432 dbname=vhffs user=vhffs_forum password=mysecret';
require_once( 'includes/VHFFSAuthPlugin.php' );
$wgAuth = new VHFFSAuthPlugin;
$wgGroupPermissions['*']['createaccount'] = false;
	
*/


require_once("AuthPlugin.php"); 

class VHFFSAuthPlugin extends AuthPlugin
{
	var $pglink;

	function VHFFSAuthPlugin() {
		$this->pglink = null;
	}

	function mydie( $msg )  {
		header('HTTP/1.0 503 Service Unavailable');
		die( $msg );
	}

	function pgcon() {
		if( !$this->pglink ) {
			global $wgVHFFSAuthPluginDB;
			$llink = pg_connect( $wgVHFFSAuthPluginDB );
			if(!$llink) $this->mydie('Could not connect: '.pg_ErrorMessage());
			$this->pglink = $llink;
		}
		return $this->pglink;
	}

	function pgquery( $query )  {
		$result = pg_exec( $this->pgcon() , $query);
		if(!$result) $this->mydie("Could not successfully run query ($query) from DB: " . pg_ErrorMessage() );
		return $result;
	}

	function userExists( $username )  {
		$result = $this->pgquery( 'SELECT username FROM vhffs_forum WHERE state=6 AND username=\''.pg_escape_string( strtolower( $username ) ).'\'' );
		$userexist = (pg_num_rows($result) == 1);
		pg_free_result( $result );
		return $userexist;
	}

	function authenticate( $username, $password )
	{
		$authok = false;
		$result = $this->pgquery( 'SELECT passwd FROM vhffs_forum WHERE state=6 AND username=\''.pg_escape_string( strtolower( $username ) ).'\'' );
		if( pg_num_rows($result) == 1 ) {
			$row = pg_fetch_assoc($result);
			if(!$row) $this->mydie('What the fuck ?!');
			$CRYPT_MD5 = 1;
			if( crypt( $password, $row['passwd'] ) == $row['passwd'] )
				$authok = true;
		}
		pg_free_result( $result );
		return $authok;
	}

	function autoCreate()
	{
		return true;
	}

	function strict()
	{
		return true;
	}

	function initUser( $user )
	{
		$result = $this->pgquery( 'SELECT firstname,lastname,mail FROM vhffs_forum WHERE state=6 AND username=\''.pg_escape_string( strtolower( $user->getName() ) ).'\'' );
		if( pg_num_rows($result) != 1 ) $this->mydie('Hummmmmm......');
		$row = pg_fetch_assoc($result);
		if(!$row) $this->mydie('What the fuck ?!');
		$user->setRealName( $row['firstname'].' '.$row['lastname'] );
		$user->setEmail( $row['mail'] );
		pg_free_result( $result );
		return true;
	}

	function updateUser( $user ) {
		$this->initUser( $user );
	}

	function allowPasswordChange() {
		return false;
	}

	function canCreateAccounts() {
		return false;
	}
}   

?>
