/*
 *  STSMON: Quick and dirty tool to monitor dry contacts connected
 *          on serial port
 *
 *  Copyright 2008-2009  Sylvain Rochet <gradator@gradator.net>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see http://www.gnu.org/licenses/.
 */


/*
 *   HOW-TO Wire the stuff
 *
 *   TCP port 	Name	DB9 pin		Wiring (example)
 *
 *  		DTR	4		_________________________.
 *					                         |
 *   13000	CTS	8               ___________ \____________|
 *   13001	CD	1		___________ \____________|
 *   13002	RI	9		___________ \____________|
 *   13003	DSR	6		___________ \____________|
 *
 *
 *   Note: there is a negative source on RTS (pin 7) that can be used instead of DTR
 */


#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/termios.h>
#include <sys/ioctl.h>
#include <signal.h>
#include <time.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <getopt.h>

#define FALSE 0
#define TRUE !FALSE


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


int stsmon_listentoport(uint32_t bindaddr, uint16_t port) {

	struct sockaddr_in src;
	int fd, flags, opt;

	/* listening for network connections */
	if( (fd = socket(AF_INET, SOCK_STREAM, 0) ) < 0) {
		fprintf(stderr, "socket() failed: %s\n", strerror(errno));
		return -1;
	}

	/* set listenfd to non-blocking */
	flags = fcntl(fd, F_GETFL);
	if(flags >= 0) {
		flags |= O_NONBLOCK;
		fcntl(fd, F_SETFL, flags);
	}

	/* add the ability to listen on a TIME_WAIT */
	opt = 1;
	if( setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (char*)&opt, sizeof(opt) ) )  {
		fprintf(stderr, "setsockopt() failed on socket %d: %s\n", fd, strerror(errno));
	}

	src.sin_addr.s_addr = bindaddr;
	src.sin_family = AF_INET;
	src.sin_port = htons(port);
	if( bind(fd, (struct sockaddr*)&src, sizeof(src) ) < 0) {
		fprintf(stderr, "bind() failed on socket %d: %s\n", fd, strerror(errno));
		close(fd);
		return -1;
	}

	if( listen(fd, SOMAXCONN) < 0) {
		fprintf(stderr, "listen() failed on socket %d: %s\n", fd, strerror(errno));
		close(fd);
		return -1;
	}

	return fd;
}


static void usage_exit(int ret_code, char *progname)  {
	printf ("Usage: %s [OPTION]...\n"
		"Quick and dirty tool to monitor dry contacts connected on serial port\n\n"
		"  -f, --foreground\t\tDo not daemonise, default is to daemonise\n"
		"  -d, --device=DEVICE\t\tDevice to use, default to /dev/ttyS0\n"
		"  -b, --bind=IP\t\t\tListen to the specified IP address\n"
		"  -p, --baseport=PORT\t\tBase port, will listen from BASEPORT to BASEPORT+3, default to 13000\n"
		"  -l, --logfile=LOGFILE\t\tPath to logfile, default is to log on stdout\n"
		"  -i, --interval=SECONDS\tDelay between each probe, default to 1s\n"
		"      --namects=NAME\t\tSet the name of the CTS(Clear To Send) input\n"
		"      --namecd=NAME\t\tSet the name of the CD(Carrier Detected) input\n"
		"      --nameri=NAME\t\tSet the name of the RI(Ring Indicator) input\n"
		"      --namedsr=NAME\t\tSet the name of the DSR(Data Set Ready) input\n"
		"  -h, --help\t\t\tDisplay this help and exit\n"
		"  -v, --version\t\t\tOutput version information and exit\n",
		progname);
	exit(ret_code);
}


int main(int argc, char *argv[]) {
	int serialfd;
	int status;

	int listencts = -1;
	int listencd = -1;
	int listenri = -1;
	int listendsr = -1;

	char *logfile = NULL;
	char *device = "/dev/ttyS0";
	int foreground = FALSE;
	long waittime = 100;
	uint32_t bindaddr = INADDR_ANY;
	uint16_t baseport = 13000;
	char *namects = "CTS";
	char *namecd = "CD";
	char *nameri = "RI";
	char *namedsr = "DSR";

	struct option long_options[] = {
		{ "foreground", no_argument, NULL, 'f' },
		{ "device", required_argument, NULL, 'd' },
		{ "bind", required_argument, NULL, 'b' },
		{ "baseport", required_argument, NULL, 'p' },
		{ "logfile", required_argument, NULL, 'l' },
		{ "interval", required_argument, NULL, 'i' },
		{ "namects", required_argument, NULL, 1000 },
		{ "namecd", required_argument, NULL, 1001 },
		{ "nameri", required_argument, NULL, 1002 },
		{ "namedsr", required_argument, NULL, 1003 },
		{ "help", no_argument, NULL, 'h' },
		{ "version", no_argument, NULL, 'v' },
		{ 0, 0, 0, 0 }
	};

	while(1) {
		int option_index = 0, c;
		c = getopt_long(argc, argv, "fd:b:p:l:i:hv", long_options, &option_index);
		if(c == -1)
			break;

		switch(c) {
			case 'f':
				foreground = TRUE;
				break;

			case 'd':
				device = strdup(optarg);
				break;

			case 'b':
				bindaddr = inet_addr(optarg);
				break;

			case 'p':
				baseport = atoi(optarg);
				break;

			case 'l':
				logfile = strdup(optarg);
				break;

			case 'i':
				waittime = (long)(atof(optarg)*100.0);
				break;

			case 1000:
				namects = strdup(optarg);
				break;

			case 1001:
				namecd = strdup(optarg);
				break;

			case 1002:
				nameri = strdup(optarg);
				break;

			case 1003:
				namedsr = strdup(optarg);
				break;

			case 'h':
				usage_exit(0, argv[0]);

			case 'v':
#ifdef VERSION
				fputs("stsmon " VERSION "\n", stdout);
#else
				fputs("stsmon\n", stdout);
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

	signal(SIGPIPE, SIG_IGN);

	serialfd = open(device, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if(serialfd < 0) {
		perror(device);
		exit(-1);
	}

	addlogline("Starting stsmon", logfile);

	if(!foreground) {
		close(STDIN_FILENO);
		close(STDOUT_FILENO);
		close(STDERR_FILENO);
		if(fork()) exit(0);
	}

	// power-up DTR and power-down RTS
	// can be used as a ~12v power source
	ioctl(serialfd, TIOCMGET, &status);
	status |= TIOCM_DTR;
	status &= ~TIOCM_RTS;
	ioctl(serialfd, TIOCMSET, &status);

	while(1) {
		char line[128];

		ioctl(serialfd, TIOCMGET, &status);

//		printf("%.2X\n", status);
//		puts("----------------------");

		// inputs
		if( status & TIOCM_CTS ) {
//			puts("CTS (clear to send)");
			if(listencts < 0) {
				listencts = stsmon_listentoport(bindaddr, baseport+0);

				snprintf(line, 128, "%s on", namects);
				addlogline(line, logfile);
			}
		}
		else {
			if(listencts >= 0) {
				close(listencts);
				listencts = -1;

				snprintf(line, 128, "%s off", namects);
				addlogline(line, logfile);
			}
		}
		while(listencts >= 0) {
			int fd = accept(listencts, NULL, NULL);
			if(fd < 0) break;
			shutdown(fd, SHUT_RDWR);
			close(fd);
		}

		if( status & TIOCM_CD ) {
//			puts("DCD (data carrier detect)");
			if(listencd < 0) {
				listencd = stsmon_listentoport(bindaddr, baseport+1);

				snprintf(line, 128, "%s on", namecd);
				addlogline(line, logfile);
			}
		}
		else {
			if(listencd >= 0) {
				close(listencd);
				listencd = -1;

				snprintf(line, 128, "%s off", namecd);
				addlogline(line, logfile);
			}
		}
		while(listencd >= 0) {
			int fd = accept(listencd, NULL, NULL);
			if(fd < 0) break;
			shutdown(fd, SHUT_RDWR);
			close(fd);
		}

		if( status & TIOCM_RI ) {
//			puts("RI (ring)");
			if(listenri < 0) {
				listenri = stsmon_listentoport(bindaddr, baseport+2);

				snprintf(line, 128, "%s on", nameri);
				addlogline(line, logfile);
			}
		}
		else {
			if(listenri >= 0) {
				close(listenri);
				listenri = -1;

				snprintf(line, 128, "%s off", nameri);
				addlogline(line, logfile);
			}
		}
		while(listenri >= 0) {
			int fd = accept(listenri, NULL, NULL);
			if(fd < 0) break;
			shutdown(fd, SHUT_RDWR);
			close(fd);
		}

		if( status & TIOCM_DSR ) {
//			puts("DSR (data set ready)");
			if(listendsr < 0) {
				listendsr = stsmon_listentoport(bindaddr, baseport+3);

				snprintf(line, 128, "%s on", namedsr);
				addlogline(line, logfile);
			}
		}
		else {
			if(listendsr >= 0) {
				close(listendsr);
				listendsr = -1;

				snprintf(line, 128, "%s off", namedsr);
				addlogline(line, logfile);
			}
		}
		while(listendsr >= 0) {
			int fd = accept(listendsr, NULL, NULL);
			if(fd < 0) break;
			shutdown(fd, SHUT_RDWR);
			close(fd);
		}

/*
		// outputs
		if( status & TIOCM_DTR ) {
			puts("DTR (data terminal ready)");
		}
		if( status & TIOCM_RTS ) {
			puts("RTS (request to send)");
		}
*/
/*
		// unused
		if( status & TIOCM_LE ) {
			puts("DSR (data set ready/line enable)");
		}
		if( status & TIOCM_ST ) {
			puts("Secondary TXD (transmit)");
		}
		if( status & TIOCM_SR ) {
			puts("Secondary RXD (receive)");
		}
*/

		if(waittime/100) sleep(waittime/100);
		if(waittime%100) usleep((waittime%100)*10000);
	}

	close(serialfd);
	return 0;
}


/*

TIOCM_LE		DSR (data set ready/line enable)
TIOCM_DTR		DTR (data terminal ready)
TIOCM_RTS		RTS (request to send)
TIOCM_ST		Secondary TXD (transmit)
TIOCM_SR		Secondary RXD (receive)
TIOCM_CTS		CTS (clear to send)
TIOCM_CAR / TIOCM_CD	DCD (data carrier detect)
TIOCM_RNG / TIOCM_RI	RNG (ring)
TIOCM_DSR		DSR (data set ready)


DB9  	DB25  	Nom  	DTE  	DCE  	Description
x  	1  	PG  	x  	x 	Masse de protection (PG = Protecting Ground)    Ne pas utiliser comme masse du signal !
3 	2 	TD 	S 	E 	Transmission de données (TD = Transmit Data)
2 	3 	RD 	E 	S 	Réception de données (RD = Receive Data)
7 	4 	RTS 	S 	E 	Demande d'autorisation à émettre (RTS = Request To Send)
8 	5 	CTS 	E 	S 	Autorisation d'émettre (CTS = Clear To Send)
6 	6 	DSR 	E 	S 	Prêt à recevoir (DSR = Data Set Ready)
5 	7 	SG 	x 	x 	Masse du signal (SG = Signal Ground)
1 	8 	DCD 	E 	S 	Détection de porteuse (DCD = Data Carrier Detect)
4 	20 	DTR 	S 	E 	Équipement prêt (DTR = Data Terminal Ready)
9 	22 	RI 	E 	S 	Détection de sonnerie (RI = Ring Indicator)


1 = 7.71v
0 = -5.76v

*/
