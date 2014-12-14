/* 
 * Tuxshell is the shell for vhffs. It was a fork from graplite, 
 * made for vhffs1. It was partially rewritten for vhffs4.
 *
 * graplite - General execution wRAPper LITE
 * Copyright (C) 1999 Lion Templin <lion@leonine.com>
 * Copyright (C) 2002 Igor Genibel <igor@tuxfamily.org>
 * Copyright (C) 2005 Julien Delange <sod@tuxfamily.org>
 * Copyright (C) 2007 Julien Danjou <julien@danjou.info>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * GOTO FOREVER!
 *
 *	Coded on Northwest Airlines Flight 1065, CHI to MSP
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <syslog.h>
#include <pwd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>

/* grap is a wrapper designed to verify commands before passing them to system()
   or just reporting the accepted command.  grap will report an error if the
   input is invalid.  It checks for string lengths (prevent overflows),
   specific sets of options and commands.
   
   grap, in full force, is called as:  <grap> <option> "<command> <arguments
   list ... >" Where <grap> is this program, <option> is an optional trap
   for a single option (like "-e" or "-c" used by programs that call shells,
   subject to the approval list below), <command> is the command wished to
   be run (subject to the approval list below), and <arguments list .. > is
   the list of args passed to <command>.  All are optional, allowing for
   forms such as:
   	graplite -e "foo"   graplite "foo bar"  graplite -e "foo -c foo -f bar"
   	<g     ><o ><cmd>   <g     > <cmd/args> <g     ><o> <cmd/  args       >
   	
	<options> and <command> need to be exact matched to those in the
	acceptance list.  
*/

/* Define the locations of <option> <command> and <arguements list .. >
   on the command line.  0 is this program, begin at 1.  Note that 
   ARGS_ARGC takes everything FROM that position to the end of the
   arguments.

   Undefine any of these to not use them.
*/

#define	OPTION_ARGC 1
#define ARGS_ARGC 2

#define	ARGS_ARE_SINGLE_STRING

/* Define how the <arguements list .. > is checked.
   define ARGS_ALNUMOK for A-Za-z0-9 to be OK
   define any other chars in the string ARGS_CHAROK

   Turn both these off to accept everything.
   WARNING, might be able to bad things with
   shell special chars such as & ; , etc.
*/

#define MAXSTRLEN 256		/* maximum single string length
						   (no max on final command) */
/* Define what strings are acceptable in <option> */
char *options[] = { "-c" , "-e" , NULL };

/* Define what strings are acceptable in <command>
   define an optional execution path CMD_PATH if desired */
char *commands[][9] =	{ 
	{"cvs" , "server" , NULL },
	{"svnserve" , "-t" , NULL },
	{"git-upload-pack" , NULL },
	{"git-fetch-pack" , NULL },
	{"git-receive-pack" , NULL },
	{"git-send-pack" , NULL },
	{"hg" , "-R" , NULL },
	{"bzr" , NULL },
	{NULL}
};

char **line; 
int k;
#define MAXARGS	256


void deny()
{
	printf("\nWelcome to VHFFS plaform\n\n");
	printf("This is a restricted Shell Account\n");
	printf("You cannot execute anything here.\n\n");

	exit(1);
}

#define	GRAP_TRUE 1
#define GRAP_FALSE 0
#define CMD_POS	 0

int main(int argc, char *argv[])
{
	int i, j, flag;
	char *buf;
	char *args[MAXARGS];
	int ok;
	uid_t uid;
	struct passwd *cuser;
	char *username;	

	openlog("tuxshell" , LOG_NOWAIT | LOG_NDELAY , LOG_AUTHPRIV );

	ok = 0;
	uid = getuid();
	cuser = getpwuid(uid);

	if( cuser == NULL )
	{
		closelog();
		exit( -1 );
	}

	/* Get username */
	username = cuser->pw_name;

	if(argc != 3) {
		syslog( LOG_INFO , "user %s tried to open a login shell" , username );
		closelog();
		deny();
	}

	/* process the initial option (see options array) */
	i = -1;
	while((options[++i] != NULL) && strcmp(options[i], argv[OPTION_ARGC]));
	if(options[i] == NULL) {
		/* printf("FATAL: %s bailed because options didn't qualify.\n", argv[0]); */
		syslog( LOG_INFO , "option %s is not allowed for user %s " , argv[OPTION_ARGC] , username );
		closelog();
		deny();
	}

	/* break single command and args string into seperate strings
	   in a char** for execvp() to use */

	i = 0;
	flag = GRAP_TRUE;
	buf = argv[ARGS_ARGC];

	j = CMD_POS;

	while((buf[i] != '\0') && (j < MAXARGS)) {
		if(buf[i] == ' ') {
			buf[i] = '\0';
			flag = GRAP_TRUE;
		} else {
			if(flag) {
				args[j++] = &buf[i];
				flag = GRAP_FALSE;
				args[j] = NULL;
			}
		}
		i++;
	}

	i = 0;
	/* check the command to insure it's in the acceptance list */
	while( commands[i] != NULL )
	{
		line = commands[i];
		k = -1;

		if( line[0] == NULL )
		{
			ok = 0;
			break;
		}
		
		while((line[++k] != NULL) && ( args[CMD_POS+k] != NULL ) && !strcmp(line[k], args[CMD_POS+k]));

		if( line[k] == NULL )
		{
			ok = 1;
			break;
		}
		i++;
	}

	if( ok == 0 ) 
	{
		syslog( LOG_WARNING , "denied command %s for user %s" , args[CMD_POS] , username );
		closelog();
		deny();
	}

	syslog( LOG_INFO , "allowed command %s for user %s" , args[CMD_POS] , username );
	closelog();

	/* remove quotes of pathname (needed for git) */
	if(args[0] && args[1] && args[1][0] == '\'')  {
		args[1]++;
		args[1][ strlen(args[1])-1 ] = '\0';
	}

	/* change the umask to allow shared work */
	umask (02);

	/* ok, the command is clear, exec() it */
	return (execvp(args[CMD_POS], args));
}
