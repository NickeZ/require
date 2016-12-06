#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <string.h>

#include <dbAccess.h>
#include <dbStaticLib.h>

#include "require.h"

#ifndef VERSION
#define VERSION "unknown"
#endif

#define BUF_LEN 1024

int requireDebug = 0;

static int verboseFlag;

void usage() {

        printf("Usage: requireExec [options] <module_name>[,<module_version>] [--] <executable_name> <executable_args>\n");
        printf("\n");
        printf("Options:\n");
        printf("  -v, --verbose      print 'require' output\n");
        printf("  -d, --debug        even more output\n");
        printf("  -h, --help         show this help message and exit\n");
        printf("  -V, --version      show version and exit\n");
        printf("  --                 stop parsing options\n");
        printf("\n");
        printf("Examples:\n");
        printf("  requireExec ethercat -- scanner -h \n");
        printf("  requireExec ethercat,4.3 -- scanner -h \n");
        printf("\n");

}

void version() {
        printf("requireExec " VERSION "\n");
}

int main(int argc, char *argv[]){
        int c;
        int status = 0;
        for(;;){
                static struct option long_options[] =
                {
                        {"verbose", no_argument, &verboseFlag, 1},
                        {"debug",   no_argument, &requireDebug, 1},
                        {"help",    no_argument, 0, 'h'},
                        {"version", no_argument, 0, 'V'},
                        {0, 0, 0, 0}
                };
                int option_index = 0;
                c = getopt_long(argc, argv, "hvdV", long_options, &option_index);
                if(c == -1) {
                        break;
                }
                switch(c) {
                case 'd':
                        requireDebug = 1;
                case 'v':
                        verboseFlag = 1;
                case 0:
                        /* Option set a flag */
                        break;
                case '?':
                case 'h':
                        usage();
                        return 0;
                case 'V':
                        version();
                        return 0;
                }
        }
        int nonoptind = 0;
        char *executable = NULL;
        char *module = NULL;
        int args_length = BUF_LEN;
        char args[BUF_LEN] = {0};
        if(optind < argc) {
                int index = 0;
                for(index=optind; index < argc; index++, nonoptind++) {
                        if(nonoptind == 0) {
                                module = argv[index];
                        } else if(nonoptind == 1) {
                                executable = argv[index];
                        } else {
                                args_length -= strlen(argv[index]) + 1;
                                if(args_length < 0) {
                                        fprintf(stderr, "requireExec: Internal buffer for args not long enough\n");
                                        break;
                                }
                                strcat(args, argv[index]);
                                if(index != argc-1) {
                                        strcat(args, " ");
                                }
                        }
                }
                if(executable == NULL) {
                        usage();
                        return -1;
                }
        } else {
                usage();
                return -1;
        }
        char *rversion = NULL;
        if((rversion = strrchr(module,',')) != NULL) {
                *rversion = '\0';
                rversion++;
        }

        /* Add EPICS Base dbd directory to EPICS_DB_INCLUDE_PATH */
        char *penv;
        char *p;
        int  n;
        penv = getenv("EPICS_BASES_PATH");
        if(!penv) {
                fprintf(stderr, "require: EPICS_BASES_PATH not set, terminating\n");
                return -1;
        }
        n = strlen(penv) + sizeof("/base-" EPICSVERSION "/dbd");
        p = malloc(n * sizeof(char));
        strcpy(p, penv);
        strcat(p, "/base-" EPICSVERSION "/dbd");
        setenv("EPICS_DB_INCLUDE_PATH", p, 1);
        free(p);

        /* Add system libraries and local modules to
         * EPICS_MODULE_INCLUDE_PATH */
        char *dirs[] = {"/usr/lib64", "/usr/lib", "/lib64", "/lib", NULL};
        char **dir;

        dir = dirs;
        p = malloc(BUF_LEN * sizeof(char));
        penv = getenv("EPICS_MODULE_INCLUDE_PATH");
        if(penv) {
                strncpy(p, penv, BUF_LEN);
        } else {
                strcpy(p, ".");
        }
        while(*dir != NULL){
                strcat(p, ":");
                strcat(p, *dir++);
        }
        setenv("EPICS_MODULE_INCLUDE_PATH", p, 1);
        free(p);

        p = "base.dbd";
        if (dbLoadDatabase(p, NULL, NULL) != 0) {
                fprintf(stderr, "Can't load base database\n");
                return -1;
        }
        if(!verboseFlag) {
                int stdout_copy = dup(STDOUT_FILENO);
                int stderr_copy = dup(STDERR_FILENO);
                close(STDOUT_FILENO);
                close(STDERR_FILENO);
                /* devnull has to be created as stdout/stderr */
                int devnull1 = open("/dev/null", O_APPEND);
                int devnull2 = open("/dev/null", O_APPEND);
                status = require_priv(module, rversion);
                close(devnull1);
                close(devnull2);
                dup2(stdout_copy, STDOUT_FILENO);
                dup2(stderr_copy, STDERR_FILENO);
                close(stdout_copy);
                close(stderr_copy);
        } else {
                status = require_priv(module, rversion);
        }

        if(status) {
                printf("Failed to load module name: %s, version: %s\n", module, rversion);
                return status;
        }

        requireExec(executable, args, NULL, NULL, 0);
        return 0;
}
