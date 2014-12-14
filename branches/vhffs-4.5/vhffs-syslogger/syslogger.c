/*
 *     syslogger - A program which redirects its standard input to syslog
 *
 *  Copyright (C) 2012 Sylvain Rochet
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#define DEFAULT_FACILITY LOG_LOCAL4
#define DEFAULT_PRIORITY LOG_NOTICE
#define DEFAULT_OPTION 0

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <getopt.h>
#include <syslog.h>

#define FALSE 0
#define TRUE !FALSE

struct syslogger_name_to_int {
	const char *name;
	int val;
};

enum {
	SYSLOGGER_STATE_NORMALFLOW,	// Flow is normally flowing from standard input to syslog
	SYSLOGGER_STATE_WAITFORNEWLINE	// We received a message which exceeded maxsize,
					// we have to discard any input until we found a newline
};

static void usage_exit(int ret_code, char *progname);
int syslog_facility_from_str(const char *facility);
int syslog_priority_from_str(const char *priority);
int syslog_option_from_str(const char *priority);

int main(int argc, char *argv[])  {
	char *buffer, *ident = "httpd";
	int facility = DEFAULT_FACILITY, priority = DEFAULT_PRIORITY, option = DEFAULT_OPTION;
	size_t bufsize = 32768;
	FILE *tee = NULL;
	int state;
	size_t overflowsize;

	struct option long_options[] = {
		{ "ident", required_argument, NULL, 'i' },
		{ "size", required_argument, NULL,'s' },
		{ "facility", required_argument, NULL, 'f' },
		{ "priority", required_argument, NULL, 'p' },
		{ "option", required_argument, NULL, 'o' },
		{ "tee", required_argument, NULL, 'r' },
		{ "help", no_argument, NULL, 'h' },
		{ "version", no_argument, NULL, 'v' },
		{ 0, 0, 0, 0 }
	};

	while(1) {
		int option_index = 0, c;
		c = getopt_long(argc, argv, "i:s:f:p:o:t:hv", long_options, &option_index);
		if(c == -1)
			break;

		switch(c) {
			case 'i':
				ident = strdup(optarg);
				break;

			case 's':
				bufsize = (size_t)(atoi(optarg));
				break;

			case 'f':
				facility = syslog_facility_from_str(optarg);
				if(facility < 0) {
					fprintf(stderr, "%s is not a valid facility\n\n", optarg);
					usage_exit(1, argv[0]);
				}
				break;

			case 'p':
				priority = syslog_priority_from_str(optarg);
				if(priority < 0) {
					fprintf(stderr, "%s is not a valid priority\n\n", optarg);
					usage_exit(1, argv[0]);
				}
				break;

			case 'o': {
					char *cur = optarg, *ptr;
					while(1) {
						int opt;
						ptr = strchr(cur, ',');
						if(ptr) *ptr = '\0';
						opt = syslog_option_from_str(cur);
						if(opt < 0) {
							fprintf(stderr, "%s is not a valid option\n\n", cur);
							usage_exit(1, argv[0]);
						}
						option |= opt;
						if(!ptr) break;
						cur = ++ptr;
					}
				}
				break;

			case 't':
				tee = fopen(optarg, "a");
				break;

			case 'h':
				usage_exit(0, argv[0]);

			case 'v':
#ifdef VERSION
				fputs("syslogger " VERSION "\n", stdout);
#else
				fputs("syslogger\n", stdout);
#endif
				exit(0);

			case '?':
				/* `getopt_long' already printed an error message. */
				fprintf(stderr, "Try `%s --help' for more information.\n", argv[0]);
				exit(1);

			default:
				abort();
		}
	}

	if(optind != argc)
		usage_exit(1, argv[0]);

	if(bufsize < 1024)
		bufsize = 1024;

	buffer = malloc(bufsize+2); // + '\n' + '\0'
	if(!buffer) {
		fprintf(stderr, "Failed to allocated buffer, exiting.\n");
		return -1;
	}

	state = SYSLOGGER_STATE_NORMALFLOW;
	openlog(ident, option, facility);
	while( fgets(buffer, bufsize+2, stdin) ) {
		size_t len = strlen(buffer);

		if(tee) {
			fwrite(buffer, len, 1, tee);
			fflush(tee);
		}

		switch( *(buffer+len-1) ) {

			case '\n':
				switch(state) {

					// everything's good
					case SYSLOGGER_STATE_NORMALFLOW:
						syslog(priority, "%s", buffer);
						break;

					// overflow recovered
					case SYSLOGGER_STATE_WAITFORNEWLINE:
						overflowsize += len-1;
						fprintf(stderr, "%s: too big message received: %d bytes long, truncated to %d bytes\n", argv[0], overflowsize, bufsize);
						state = SYSLOGGER_STATE_NORMALFLOW;
						break;
				}
				break;

			default:
				switch(state) {

					// new overflow
					case SYSLOGGER_STATE_NORMALFLOW:
						*(buffer+len-1) = '\n';
						overflowsize = len;
						syslog(priority, "%s", buffer);
						state = SYSLOGGER_STATE_WAITFORNEWLINE;
						break;

					// overflow continue
					case SYSLOGGER_STATE_WAITFORNEWLINE:
						overflowsize += len;
						break;
				}
				break;
		}
	}
	closelog();
	if(tee) fclose(tee);

	return 0;
}

int syslog_facility_from_str(const char *facility) {
	int i = 0;
	struct syslogger_name_to_int assoc[] = {
		{ "authpriv", LOG_AUTHPRIV },
		{ "cron", LOG_CRON },
		{ "daemon", LOG_DAEMON },
		{ "ftp", LOG_FTP },
		{ "kern", LOG_KERN },
		{ "local0", LOG_LOCAL0 },
		{ "local1", LOG_LOCAL1 },
		{ "local2", LOG_LOCAL2 },
		{ "local3", LOG_LOCAL3 },
		{ "local4", LOG_LOCAL4 },
		{ "local5", LOG_LOCAL5 },
		{ "local6", LOG_LOCAL6 },
		{ "local7", LOG_LOCAL7 },
		{ "lpr", LOG_LPR },
		{ "mail", LOG_MAIL },
		{ "news", LOG_NEWS },
		{ "user", LOG_USER },
		{ "uucp", LOG_UUCP },
		{ 0, 0 }
	};

	while(assoc[i].name) {
		if(!strcmp(facility, assoc[i].name))
			return assoc[i].val;
		i++;
	}
	return -1;
}

int syslog_priority_from_str(const char *priority) {
	int i = 0;
	struct syslogger_name_to_int assoc[] = {
		{ "emerg", LOG_EMERG },
		{ "alert", LOG_ALERT },
		{ "crit", LOG_CRIT },
		{ "err", LOG_ERR },
		{ "warning", LOG_WARNING },
		{ "notice", LOG_NOTICE },
		{ "info", LOG_INFO },
		{ "debug", LOG_DEBUG },
		{ 0, 0 }
	};

	while(assoc[i].name) {
		if(!strcmp(priority, assoc[i].name))
			return assoc[i].val;
		i++;
	}
	return -1;
}

int syslog_option_from_str(const char *priority) {
	int i = 0;
	struct syslogger_name_to_int assoc[] = {
		{ "cons", LOG_CONS },
		{ "ndelay", LOG_NDELAY },
		{ "nowait", LOG_NOWAIT },
		{ "odelay", LOG_ODELAY },
		{ "perror", LOG_PERROR },
		{ "pid", LOG_PID },
		{ 0, 0 }
	};

	while(assoc[i].name) {
		if(!strcmp(priority, assoc[i].name))
			return assoc[i].val;
		i++;
	}
	return -1;
}

static void usage_exit(int ret_code, char *progname) {
	printf ("Usage: %s [OPTION]...\n"
		"A program which redirects its standard input to syslog\n\n"
		"  -i, --ident=STRING\t\tIdent string to use, defaults to httpd\n"
		"  -s, --size=BYTES\t\tMaximum size of a message, defaults to 32768 bytes, minimum is 1024\n"
		"  -f, --facility=STRING\t\tSyslog facility to use, defaults to local4\n"
		"\t\t\t\tPossible facility are: authpriv, cron, daemon, ftp, kern, local0 through local7, lpr, mail, news, user, uucp\n"
		"  -p, --priority=STRING\t\tSyslog priority to use, defaults to notice\n"
		"\t\t\t\tPossible priority are: emerg, alert, crit, err, warning, notice, info, debug\n"
		"  -o, --option=STRING\t\tA comma separated list of syslog options, defaults to none\n"
		"\t\t\t\tPossible options are: cons, ndelay, nowait, odelay, perror, pid\n"
		"  -t, --tee=PATH\t\tWrite the raw input to file, useful for debugging purposes\n"
		"  -h, --help\t\t\tDisplay this help and exit\n"
		"  -v, --version\t\t\tOutput version information and exit\n"
		"\n"
		"See syslog(3) for details\n",
		progname);
	exit(ret_code);
}
