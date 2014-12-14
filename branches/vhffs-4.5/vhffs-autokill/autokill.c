/*
 *     autokill - A program to kill all process running during a certain
 *                period of time or using too much cpu
 *
 *  Copyright (C) 2006 Sylvain Rochet
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

#ifndef __linux__
#error This software is only running on Linux-based OS, bye!
#endif

#define _BSD_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <dirent.h>
#include <sys/types.h>
#include <signal.h>
#include <time.h>
#include <sys/time.h>
#include <pwd.h>
#include <getopt.h>
#include <sys/stat.h>

#define FALSE 0
#define TRUE !FALSE


void addlogline(char *line, char *logfile);
static void usage_exit(int ret_code, char *progname);

int main(int argc, char *argv[])  {
	long tickspersec;
	int foreground = FALSE;
	int demomode = FALSE;
	char *logfile = NULL;
	long minuid = 10000, maxuid = -1; // default is 10000 for minuid, unlimited for maxuid
	long waittime = 100; // default is to wait 1s between probes
	long runtimeterm, runtimekill;
	long cputimeterm, cputimekill;

	struct option long_options[] = {
		{ "foreground", no_argument, NULL, 'f' },
		{ "logfile", required_argument, NULL, 'l' },
		{ "demo", no_argument, NULL, 'd' },
		{ "minuid", required_argument, NULL, 1000 },
		{ "maxuid", required_argument, NULL, 1001 },
		{ "runtimeterm", required_argument, NULL, 1002 },
		{ "runtimekill", required_argument, NULL, 1003 },
		{ "cputimeterm", required_argument, NULL, 1004 },
		{ "cputimekill", required_argument, NULL, 1005 },
		{ "interval", required_argument, NULL, 'i' },
		{ "help", no_argument, NULL, 'h' },
		{ "version", no_argument, NULL, 'v' },
		{ 0, 0, 0, 0 }
	};


	tickspersec = sysconf(_SC_CLK_TCK);
	if(tickspersec <= 0) tickspersec = 100;  // assume 100

	runtimeterm = 300 * tickspersec; // default is ~300s for running time
	runtimekill = 302 * tickspersec;
	cputimeterm = 32 * tickspersec;  // default is ~32s for cputime
	cputimekill = 34 * tickspersec;

	while(1) {
		int option_index = 0, c;
		c = getopt_long(argc, argv, "fl:di:hv", long_options, &option_index);
		if(c == -1)
			break;

		switch(c) {
			case 'f':
				foreground = TRUE;
				break;

			case 'd':
				demomode = TRUE;
				break;

			case 'l':
				logfile = strdup(optarg);
				break;

			case 1000:
				minuid = atoll(optarg);
				break;

			case 1001:
				maxuid = atoll(optarg);
				break;

			case 1002:
				runtimeterm = (long)(atof(optarg)*(double)tickspersec);
				break;

			case 1003:
				runtimekill = (long)(atof(optarg)*(double)tickspersec);
				break;

			case 1004:
				cputimeterm = (long)(atof(optarg)*(double)tickspersec);
				break;

			case 1005:
				cputimekill = (long)(atof(optarg)*(double)tickspersec);
				break;

			case 'i':
				waittime = (long)(atof(optarg)*100.0);
				break;

			case 'h':
				usage_exit(0, argv[0]);

			case 'v':
#ifdef VERSION
				fputs("autokill " VERSION "\n", stdout);
#else
				fputs("autokill\n", stdout);
#endif
				exit(0);

			case '?':
				/* `getopt_long' already printed an error message. */
				fprintf(stderr,"Try `%s --help' for more information.\n", argv[0]);
				exit(1);

			default:
				abort();
		}
	}

	if(optind != argc)
		usage_exit(1, argv[0]);

	if(runtimeterm > runtimekill) runtimeterm = runtimekill;
	if(cputimeterm > cputimekill) cputimeterm = cputimekill;

	if(logfile || foreground) {
		if(demomode) addlogline("Starting autokill in DEMOMODE", logfile);
		else addlogline("Starting autokill", logfile);
	}

	if(!foreground) {
		close(STDIN_FILENO);
		close(STDOUT_FILENO);
		close(STDERR_FILENO);
		if(fork()) exit(0);
	}

	while(1)  {
		char path[256], data[8192];
		FILE *f;
		int br;
		unsigned long long uptime;
		DIR *d;
		struct dirent *dir;

		// read uptime
		f = fopen("/proc/uptime", "r");
		if(!f) continue;
		br = fread(data, 1, 8192, f);
		fclose(f);
		if(!br) continue;

		uptime = (unsigned long long)(atof(data)*100.0);
		if(!uptime) continue;

		// search running process
		d = opendir("/proc");
		if(!d) continue;

		while( (dir = readdir(d) ) )  {
			int i, c, s, zombie;
			uid_t uid;
			pid_t pid;
			long long starttime, rtime, cputime;
			int signal;
			char *signame;

			// discard non directory and non numerical name
			if(dir->d_type == DT_UNKNOWN) {
				struct stat st;
				if( !lstat(dir->d_name, &st) && S_ISDIR(st.st_mode) ) dir->d_type = DT_DIR;
			}
			if(dir->d_type != DT_DIR || dir->d_name[0] < '0' || dir->d_name[0] > '9')  continue;

			pid = atoi(dir->d_name);
			if(!pid) continue;

			// read /proc/pid/status
			snprintf(path, 256, "/proc/%d/status", pid);
			f = fopen(path, "r");
			if(!f) continue;
			br = fread(data, 1, 8192, f);
			fclose(f);
			if(!br) continue;

			uid = 0;
			for(i = 0 ; i < br-4 ; i++)  {
				if( (i == 0 || data[i-1] == '\n') && data[i] == 'U' && data[i+1] == 'i' && data[i+2] == 'd')  {
					for(; i < br ; i++)  {
						if(data[i] >= '0' && data[i] <= '9')  {
							uid = atol(data+i);
							break;
						}
					}
					break;
				}
			}

			if(uid <= 0) continue;
			if(minuid >= 0 && uid < minuid) continue;
			if(maxuid >= 0 && uid > maxuid) continue;

			// read /proc/pid/stats
			snprintf(path, 256, "/proc/%d/stat", pid);
			f = fopen(path, "r");
			if(!f) continue;
			br = fread(data, 1, 8192, f);
			fclose(f);
			if(!br) continue;

			starttime = -1;
			zombie = FALSE;
			cputime = 0;
			for(i = c = s = 0 ; i < br ; i++)  {
				if(data[i] == ' ' || data[i] == '\t')  {
					s = 0;
				} else {
					if(!s) {
						// triggered
						s = 1;
						c++;

						if(c == 3)  {
							if(data[i] == 'Z')  {
								zombie = TRUE;
								break;
							}
						}

						if(c >= 14 && c <= 17)  {
							long long cpu;
							cpu = atoll(data+i);
							if(cpu > 0) cputime += cpu;
						}

						if(c == 22)  {
							starttime = atoll(data+i);
							break;
						}
					}
				}
			}

			if(zombie) continue;
			if(starttime < 0) continue;
			if(cputime <= 0) continue;

			signal = -1;
			// check cputime
			if(cputimeterm > 0 && cputimekill > 0 && cputime > cputimeterm)  {

				if(cputime > cputimekill)  {
					signal = SIGKILL;
					signame = "SIGKILL";
				}
				else  {
					signal = SIGTERM;
					signame = "SIGTERM";
				}
			}

			// check running time
			rtime = uptime - starttime;
			if(runtimeterm > 0 && runtimekill > 0 && rtime > runtimeterm)  {

				if(rtime > runtimekill)  {
					signal = SIGKILL;
					signame = "SIGKILL";
				}
				else  {
					signal = SIGTERM;
					signame = "SIGTERM";
				}
			}

			if(signal >= 0)  {
				char line[128];
				struct passwd *pw;
				char *name, *demo;

				pw = getpwuid(uid);
				if(pw) name = pw->pw_name;
				else name = "unknown";

				if(demomode) demo = "[DEMO MODE] ";
				else demo = "";

				snprintf(line, 128, "%sSend %s to process %ld, owned by %s(%ld), cpu time %.2f sec, running time %.2f sec", demo, signame, (long)pid, name, (long)uid, (float)cputime/(float)tickspersec, (float)rtime/(float)tickspersec);
				if(logfile || foreground) addlogline(line, logfile);

				if(!demomode) kill(pid, signal);
			}

		}
		closedir(d);

		// just wait, nothing more, really, I am not kidding, you can trust me
		// be serious, if I tell you that it is only a stupid wait inside an
		// infinite loop it is probably true, it is not an uncommon thing
		// as far as I know !
		// ok... give up... and let me do my job right now, want you ?
		if(waittime/100) sleep(waittime/100);
		if(waittime%100) usleep((waittime%100)*10000);
	}

	return 0;
}


void addlogline(char *line, char *logfile)  {

	FILE *lf = NULL;

	struct timeval tv;
	char date[64];

	gettimeofday(&tv, NULL);
	ctime_r(&tv.tv_sec, date);
	date[strlen(date)-1] = '\0';

	if(logfile)  {
		lf = fopen(logfile, "a");
	}

	if(lf)  {
		fprintf(lf, "%s: %s\n", date, line);
		fclose(lf);
	}
	else  {
		// use stdout if logfile is not available
		fprintf(stdout, "%s: %s\n", date, line);
	}
}


static void usage_exit(int ret_code, char *progname)  {
	printf ("Usage: %s [OPTION]...\n"
		"A program to kill all process running during a certain period of time or using too much cpu\n\n"
		"  -f, --foreground\t\tDo not daemonise, default is to daemonise\n"
		"  -l, --logfile=LOGFILE\t\tPath to logfile, default is to log on stdout\n"
		"      --minuid=UID\t\tDo not kill process owned by UID below MINUID, default is 10000\n"
		"      --maxuid=UID\t\tDo not kill process owner by UID above MAXUID, default is -1 (unlimited)\n"
		"      --runtimeterm=SECONDS\tMaximum allowed running time before sending SIGTERM signals, default to 300s\n"
		"      --runtimekill=SECONDS\tMaximum allowed running time before sending SIGKILL signals, default to 302s\n"
		"\t\t\t\tSetting -1 to either runtime* options disable running time check\n"
		"      --cputimeterm=SECONDS\tMaximum allowed cpu time before sending SIGTERM signals, default to 30s\n"
		"      --cputimekill=SECONDS\tMaximum allowed cpu time before sending SIGKILL signals, default to 32s\n"
		"\t\t\t\tSetting -1 to either cputime* options disable cpu time check\n"
		"  -i, --interval=SECONDS\tDelay between each probe, default to 1s\n"
		"  -d, --demo\t\t\tDo not kill any process, default is to kill them\n"
		"  -h, --help\t\t\tDisplay this help and exit\n"
		"  -v, --version\t\t\tOutput version information and exit\n",
		progname);
	exit(ret_code);
}
