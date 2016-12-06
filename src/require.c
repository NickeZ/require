/*
 * EPICS Environment Manager
 * Copyright (C) 2015  Dirk Zimoch
 * Copyright (C) 2015  Cosylab
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author: zimoch,nclaesson
 *
 * Require, load EPICS modules dynamically.
 */
#include <epicsVersion.h>
#if defined (__unix__) && (EPICS_VERSION <= 3 && EPICS_REVISION <= 14)
    #define _GNU_SOURCE
#endif
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include <iocsh.h>
#include <dbAccess.h>
epicsShareFunc int epicsShareAPI iocshCmd (const char *cmd);
#include <epicsExit.h>
#include <epicsExport.h>
#include <envDefs.h>

#include "require.h"

int requireDebug = 0;

#define debug_print(fmt, ...) \
        do { if (requireDebug) printf("require: " fmt, __VA_ARGS__); } while (0)

static int firstTime = 1;

#define DIRSEP "/"
#define PATHSEP ":"
#define PREFIX
#define INFIX
#define NOVERSION -1
#define LIBNAMEPRE "epics_"
#define LIBNAMEPOST "LibRelease"
#define LOC_MODULES "modules"
#define BUILDDIR "builddir"
#define MIN(a,b) (a) < (b) ? (a) : (b)

#if defined (vxWorks)

    #include <symLib.h>
    #include <sysSymTbl.h>
    #include <sysLib.h>
    #include <symLib.h>
    #include <loadLib.h>
    #include <shellLib.h>
    #include <usrLib.h>
    #include <taskLib.h>
    #include <ioLib.h>
    #include <errno.h>

    #define HMODULE MODULE_ID
    #undef  INFIX
    #define INFIX "Lib"
    #define EXT ".munch"

    #define getAddress(module,name) __extension__ \
        ({SYM_TYPE t; char* a=NULL; symFindByName(sysSymTbl, (name), &a, &t); a;})

#elif defined (__unix__)

    #include <signal.h>
    #include <unistd.h>
    #include <fcntl.h>
    #include <dirent.h>
    #include <dlfcn.h>
    #define HMODULE void *

    #define getAddress(module,name) (dlsym(module, name))

    #ifdef CYGWIN32

        #define EXT ".dll"

    #else

        #undef  PREFIX
        #define PREFIX "lib"
        #define EXT ".so"

    #endif

#elif defined (_WIN32)

    #include <dirent.h>
    #include <windows.h>
    #undef  DIRSEP
    #define DIRSEP "\\"
    #undef  PATHSEP
    #define PATHSEP ";"
    #define EXT ".dll"

    #define getAddress(module,name) (GetProcAddress(module, name))
#else

    #warning unknwn OS
    #define getAddress(module,name) NULL

#endif

/* loadlib (library)
Find a loadable library by name and load it.
*/

static HMODULE loadlib(const char* libname)
{
    HMODULE libhandle = NULL;

    if (!libname)
    {
        fprintf (stderr, "missing library name.\n");
        return NULL;
    }

#if defined (__unix__)
    if (!(libhandle = dlopen(libname, RTLD_NOW|RTLD_GLOBAL)))
    {
        fprintf (stderr, "Loading %s library failed: %s.\n",
            libname, dlerror());
    }
#elif defined (_WIN32)
    if (!(libhandle = LoadLibrary(libname)))
    {
        LPVOID lpMsgBuf;

        FormatMessage(
            FORMAT_MESSAGE_ALLOCATE_BUFFER |
            FORMAT_MESSAGE_FROM_SYSTEM,
            NULL,
            GetLastError(),
            MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
            (LPTSTR) &lpMsgBuf,
            0, NULL );
        fprintf (stderr, "Loading %s library failed: %s.\n",
            libname, lpMsgBuf);
        LocalFree(lpMsgBuf);
    }
#elif defined (vxWorks)
    {
        int fd, loaderror;
        fd = open(libname, O_RDONLY, 0);
        loaderror = errno;
        if (fd >= 0)
        {
            errno = 0;
            libhandle = loadModule(fd, LOAD_GLOBAL_SYMBOLS);
            if (errno == S_symLib_SYMBOL_NOT_FOUND)
            {
                libhandle = NULL;
            }
            loaderror = errno;
            close (fd);
        }
        if (libhandle == NULL)
        {
            fprintf(stderr, "Loading %s library failed: %s.\n",
                libname, strerror(loaderror));
        }
    }
#else
    fprintf (stderr, "cannot load libraries on this OS.\n");
#endif
    return libhandle;
}

struct module_list
{
    struct module_list *next;
    char name[100];   /* Module name */
    char version[20]; /* MAJOR.MINOR.PATCH[+], USER or COMMIT_REVISION */
};

struct module_version {
        int major;
        int minor;
        int patch;
        int exact; /* 0 - higher versions also validate against this. */
};

struct module_list *loadedModules = NULL;

/*
 * Add module first in loadedModules list.
 */
static void registerModule(const char* module, const char* version)
{
        struct module_list* m = (struct module_list*) calloc(sizeof (struct module_list),1);
        if (!m) {
                fprintf (stderr, "require: out of memory.\n");
        }
        else {
                strncat (m->name, module, sizeof(m->name) - 1);
                strncat (m->version, version, sizeof(m->version) - 1);
                m->next = loadedModules;
                loadedModules = m;
                int env_var_size = strlen(m->name) + sizeof("REQUIRE__VERSION");
                char *env_var = malloc(env_var_size * sizeof (char));
                if(!env_var) {
                        fprintf(stderr, "Out of memory\n");
                        return;
                }
                snprintf(env_var, env_var_size, "REQUIRE_%s_VERSION", m->name);
                epicsEnvSet(env_var, version);
        }
}

#if defined (vxWorks)
BOOL findLibRelease (
    char      *name,  /* symbol name       */
    int       val,    /* value of symbol   */
    SYM_TYPE  type,   /* symbol type       */
    int       arg,    /* user-supplied arg */
    UINT16    group   /* group number      */
) {
    char libname [20];
    int e;
    if (!strncmp(name, LIBNAMEPRE, strlen(LIBNAMEPRE)) return TRUE;
    e = strlen(name) - 10;
    if (e <= 0 || e > 20) return TRUE;
    if (!strncmp(name+e, LIBNAMEPOST, strlen(LIBNAMEPOST))) return TRUE;
    strncpy(libname, name+len(LIBNAMEPRE), e-1);
    libname[e-1]=0;
    if (!getLibVersion(libname))
    {
        registerModule(libname, (char*)val);
    }
    return TRUE;
}

static void registerExternalModules()
{
    symEach(sysSymTbl, (FUNCPTR)findLibRelease, 0);
}

#elif defined (__linux)

#include <link.h>

int findLibRelease (
    struct dl_phdr_info *info, /* shared library info */
    size_t size,               /* size of info structure */
    void *data                 /* user-supplied arg */
) {
    void *handle;
    char symname [80];
    const char* p;
    char* q;
    char* version;

    //printf("libname: %s\n", info->dlpi_name);

    if (!info->dlpi_name || !info->dlpi_name[0]) return 0;
    p = strrchr(info->dlpi_name, '/');
    if (p) p+=4; else p=info->dlpi_name + 3;
    symname[0] = '_';
    for (q=symname+1; *p && *p != '.' && *p != '-' && q < symname+11; p++, q++) *q=*p;
    strcpy(q, LIBNAMEPOST);
    handle = dlopen(info->dlpi_name, RTLD_NOW|RTLD_GLOBAL);
    version = dlsym(handle, symname);
    dlclose(handle);
    *q = 0;
    if (version)
    {
        registerModule(symname+strlen(LIBNAMEPRE), version);
    }
    return 0;
}

static void registerExternalModules()
{
    dl_iterate_phdr(findLibRelease, NULL);
}

#elif defined (_WIN32)

static void registerExternalModules()
{
    ;
}


#else
static void registerExternalModules()
{
    ;
}
#endif


const char* getLibVersion(const char* libname)
{
    struct module_list* m;

    for (m = loadedModules; m; m=m->next)
    {
        if (strncmp(m->name, libname, sizeof(m->name)) == 0)
        {
            return m->version;
        }
    }
    return NULL;
}

int libversionShow(const char* pattern)
{
    struct module_list* m;

    if (firstTime)
    {
        firstTime=0;
        registerExternalModules();
    }

    for (m = loadedModules; m; m=m->next)
    {
        if (pattern && !strstr(m->name, pattern)) continue;
        printf("%20s %s\n", m->name, m->version);
    }
    return 0;
}

/*
 * Validate other against this.
 */
static int match_version(struct module_version * this, struct module_version * other) {
        return this->major == NOVERSION ||
                (this->exact && (
                 (this->minor == NOVERSION && other->major == this->major) ||
                 (this->patch == NOVERSION && other->major == this->major && other->minor == this->minor) ||
                 (this->major == this->major && other->minor == this->minor && other->patch == this->patch))) ||
                (!this->exact && (
                 (this->minor == NOVERSION && other->major >= this->major) ||
                 (this->patch == NOVERSION && other->major == other->major && other->minor >= this->minor) ||
                 (other->major == this->major && other->minor == this->minor && other->patch >= this->patch)));

}

/*
 * Convert string to struct module_version.
 *
 * @param version String to be converted.
 * @param exact 0 - higher version OK, 1 - higher version not OK.
 * @param res Store result here.
 */

static void ver_conv(const char * version, struct module_version * res)
{
        int matches = sscanf(version, "%d.%d.%d", &(res->major), &(res->minor), &(res->patch));
        res->exact = version[strlen(version)-1] == '+' ? 0 : 1;
        switch(matches) {
        case 2:
                if(res->major < 0 || res->minor < 0)
                        fprintf(stderr, "Require does not support negative versions");
                res->patch = NOVERSION;
                break;
        case 1:
                if(res->major < 0)
                        fprintf(stderr, "Require does not support negative versions");
                res->minor = NOVERSION;
                res->patch = NOVERSION;
                break;
        case 0:
        case EOF:
                res->major = NOVERSION;
                res->minor = NOVERSION;
                res->patch = NOVERSION;
                break;
        default:
                if(res->major < 0 || res->minor < 0 || res->patch < 0)
                        fprintf(stderr, "Require does not support negative versions");
                break;
        }
}

static int validate(const char* module, const char* version, const char* loaded)
{
        struct module_version version_i, loaded_i;

        if (!version || version[0] == '\0' || strcmp(loaded, version) == 0) {
                /* no version requested or exact match */
                return 0;
        }
        if (!isdigit((unsigned char)loaded[0])) {
                /* test version already loaded */
                printf("Warning: %s test version %s already loaded where %s was requested.\n",
                                module, loaded, version);
                return 0;
        }
        ver_conv(version, &version_i);
        ver_conv(loaded, &loaded_i);

        if (match_version(&version_i, &loaded_i)) {
                return 0;
        }
        return -1;
}

/* require (module)
Look if module is already loaded.
If module is already loaded check for version mismatch.
If module is not yet loaded load the library with ld,
load <module>.dbd with dbLoadDatabase (if file exists)
and call <module>_registerRecordDeviceDriver function.

If require is called from the iocsh before iocInit and fails,
it calls epicsExit to abort the application.
*/

/* wrapper to abort statup script */
int require(const char* module, const char* ver)
{
    int status;
    if (firstTime)
    {
        firstTime=0;
        registerExternalModules();
    }

    status = require_priv(module, ver);
    if (status != 0 && !interruptAccept)
    {
        /* require failed in startup script before iocInit */
        fprintf(stderr, "require: Nothing loaded. Aborting startup script.\n");
#ifdef vxWorks
        shellScriptAbort();
#else
        epicsExit(1);
#endif
        return -1;
    } else if(status != 0) {
        fprintf(stderr, "require: Nothing loaded.\n");
    }
    return 0;
}

/*
 * Compare function for struct module_versions. Used with qsort.
 */
static int compare_versions(const void * a, const void * b) {
        const struct module_version *this = a;
        const struct module_version *other = b;
        return this->major > other->major ||
                (this->major == other->major &&
                 this->minor > other->minor ) ||
                (this->major == other->major &&
                 this->minor == other->minor &&
                 this->patch > other->patch );
}

/*
 * Returns 1 if version is found, 0 if not found, negative number if error
 * occurred.
 */
static int find_default(const char * module, const char *defaultdep, char * version) {
        FILE* depfile;
        char buffer[40];
        char *rmodule;
        char *rversion;
        struct stat filestat;
        char *end;

        debug_print("parsing default dependency file %s.\n", defaultdep);
        if(stat(defaultdep, &filestat) != 0) { /* No such file */
                return 0;
        }
        depfile = fopen(defaultdep, "r");
        if(!depfile) {
                fprintf(stderr, "require: Couldn't open %s.\n", defaultdep);
                return -1;
        }
        while (fgets(buffer, sizeof(buffer)-1, depfile))
        {
                rmodule = buffer;
                /* ignore leading spaces */
                while (isspace((int)*rmodule)) rmodule++;
                /* ignore empty lines and comment lines */
                if (*rmodule == 0 || *rmodule == '#') continue;
                /* rmodule at start of module name */
                rversion = rmodule;
                /* find end of module name */
                while (*rversion && !isspace((int)*rversion)) rversion++;
                /* terminate module name */
                *rversion++ = 0;
                /* ignore spaces */
                while (isspace((int)*rversion)) rversion++;
                /* rversion at start of version */
                end = rversion;
                /* find end of version */
                while (*end && !isspace((int)*end)) end++;
                /* terminate version */
                *end = 0;
                if(strlen(module) == strlen(rmodule) && strncmp(module, rmodule, strlen(module)) == 0) {
                        strcpy(version, rversion);
                        debug_print("Default version is: %s.\n", rversion);
                        return 1;
                }
        }
        fclose(depfile);
        return 0;
}

static int arch_installed(const char *module, const char *moduledir) {
        char depfile[256];
        struct stat filestat;
        snprintf(depfile, sizeof(depfile), "%s" DIRSEP EPICSVERSION DIRSEP "lib" DIRSEP T_A DIRSEP "%s.dep", moduledir, module);
        return stat(depfile, &filestat) == 0;
}

int require_priv(const char* module, const char* vers)
{
    char module_incpath[512];
    char version[20];
    struct module_version version_i;
    const char* loaded;
    struct stat filestat;
    HMODULE libhandle;
    char *end; /* end of string */
    const char sep[1] = PATHSEP;

    char *epicsmodules = getenv("EPICS_MODULES_PATH");
    if(!epicsmodules) {
            fprintf(stderr, "require: EPICS_MODULES_PATH is not in environment.\n");
            return -1;
    }
    char *p = getenv("EPICS_MODULE_INCLUDE_PATH");
    if(p) {
            strncpy(module_incpath, p, 511);
    } else {
            strcat(module_incpath, ".");
    }

    debug_print("checking module %s version %s.\n", module, vers);
    if (!module)
    {
        printf("Usage: require \"<module>\" [, \"<version>\"].\n");
        printf("Loads  resources from %s/<module>/<version>.\n", epicsmodules);
        return -1;
    }

    memset(version, 0, sizeof(version));
    if (vers) strncpy(version, vers, sizeof(version));

    loaded = getLibVersion(module);
    if (loaded)
    {
        debug_print("loaded version of %s is %s.\n",
                module, loaded);
        /* Library already loaded. Check Version. */
        if (validate(module, version, loaded) != 0)
        {
            printf("Conflict between requested %s version %s\n"
                "and already loaded version %s.\n",
                module, version, loaded);
            return -1;
        }
        /* Loaded version is ok */
        debug_print("%s %s already loaded.\n", module, loaded);
        return 0;
    }
    else
    {
        const int size = 256;   /* Max size of strings */
        char modulepath[size];  /* Path to loaded module */
        char libname[size];     /* Path to library file */
        char dbdname[size];     /* Path to dbd file */
        char depname[size];     /* Path to dep file */
        char dbname[size];      /* Path to db folder. */
        char startupname[size]; /* Path to startup folder. */
        char binname[size];     /* Path to bin folder. */
        char miscname[size];    /* Path to misc folder. */
        char symbolname[size];  /* Magic symbol name */

        char epics_db_include_path[1024];        /* EPICS env variable */
        char require_startup_include_path[1024]; /* require env variable */
        char require_bin_include_path[1024];     /* require env variable */
        char stream_protocol_path[1024];         /* streamdevice env variable */

        char *p = version;
        DIR *dir;
        struct dirent* ent;
        int tmp;
        char tmp_str[size];

        modulepath[0] = '\0';
        tmp_str[0] = '\0';

        /*
         * Check if any module in the current dir implements this module.
         */
        if(version[0] == '\0' || strcmp(version, "local") == 0) {
                if((dir = opendir(LOC_MODULES))) {
                        debug_print("%s","Looking for modules in \"" LOC_MODULES "\".\n");
                        while((ent = readdir(dir))){
                                sprintf(tmp_str, LOC_MODULES DIRSEP "%s" DIRSEP BUILDDIR, ent->d_name);
                                if(arch_installed(module, tmp_str)) {
                                        strcat(version, "local");
                                        strcpy(modulepath, tmp_str);
                                        debug_print("Found (local) in %s.\n", ent->d_name);
                                        break;
                                }
                        }
                        closedir(dir);
                }
        }

        /*
         * If user requested a named (and not numbered) version, try to find it.
         */
        char ch;
        if(version[0] != '\0' && sscanf(version, "%d.%d.%d%c", &tmp, &tmp, &tmp, &ch) != 3) {
                sprintf(tmp_str, "%s" DIRSEP "%s" DIRSEP "%s", epicsmodules, module, version);
                if(arch_installed(module, tmp_str)) {
                        strcpy(modulepath, tmp_str);
                        debug_print("Found named version (%s).\n", version);
                }
        }

        /*
         * If user didn't request a specific version, look in dependency files.
         */
        char *epicsbase = getenv("EPICS_BASE");
        if (version[0] == '\0' && epicsbase)
        {
                sprintf(tmp_str, "%s" DIRSEP "configure" DIRSEP "default." T_A ".dep", epicsbase);
                int found = find_default(module, tmp_str, version);
                if (!found) {
                        sprintf(tmp_str, "%s" DIRSEP "configure" DIRSEP "default.dep", epicsbase);
                        found = find_default(module, tmp_str, version);
                }
        } else {
                debug_print("%s","EPICS_BASE not defined.\n");
        }

        ver_conv(version, &version_i);
        debug_print("Version (%s) (%d,%d,%d,%c).\n", version, version_i.major, version_i.minor, version_i.patch, version_i.exact == 0 ? '+' : ' ');


        /*
         * If there still isn't a candidate, find all installed versions of the
         * module, sort them and pick the highest valid version.
         */
        if(modulepath[0] == '\0') {
                struct module_version inst_vers[20];
                int vers_c = 0;
                sprintf(tmp_str, "%s" DIRSEP "%s", epicsmodules, module);
                if((dir = opendir(tmp_str))) {
                        debug_print("Looking for versions in %s.\n", tmp_str);
                        while((ent = readdir(dir))){
                                int tmp;
                                char ch;
                                if(sscanf(ent->d_name, "%d.%d.%d%c", &tmp, &tmp, &tmp, &ch) != 3) {
                                        continue;
                                }
                                snprintf(tmp_str, size, "%s" DIRSEP "%s" DIRSEP "%s", epicsmodules, module, ent->d_name);
                                if(!arch_installed(module, tmp_str)) {
                                        debug_print("Found (%s), not available on this platform.\n", ent->d_name);
                                        continue;
                                }
                                ver_conv(ent->d_name, &(inst_vers[vers_c]));
                                debug_print("Found (%d.%d.%d).\n", inst_vers[vers_c].major, inst_vers[vers_c].minor, inst_vers[vers_c].patch);
                                ++vers_c;
                        }
                        closedir(dir);
                } else {
                        debug_print("Failed to open %s.\n", tmp_str);
                }
                if(vers_c > 0 ) {
                        qsort(inst_vers, vers_c, sizeof (struct module_version), compare_versions);
                        int i;
                        for(i=vers_c-1;i>=0;--i) {
                                if(match_version(&version_i, &(inst_vers[i]))) {
                                        sprintf(version, "%d.%d.%d", inst_vers[i].major, inst_vers[i].minor, inst_vers[i].patch);
                                        snprintf(modulepath, size, "%s" DIRSEP "%s" DIRSEP "%s", epicsmodules, module, version);
                                        debug_print("Chosen (%s).\n", version);
                                        break;
                                }
                        }
                }
        }

        if(modulepath[0] != '\0') {

                registerModule(module, version);
                int env_var_size = strlen(module) + sizeof("REQUIRE__PATH");
                char *env_var = malloc(env_var_size * sizeof (char));
                if(!env_var) {
                        fprintf(stderr, "Out of memory\n");
                } else {
                        snprintf(env_var, env_var_size, "REQUIRE_%s_PATH", module);
                        epicsEnvSet(env_var, modulepath);
                }

                snprintf(libname,     size, "%s" DIRSEP EPICSVERSION DIRSEP "lib" DIRSEP T_A DIRSEP PREFIX "%s" INFIX EXT, modulepath, module);
                snprintf(depname,     size, "%s" DIRSEP EPICSVERSION DIRSEP "lib" DIRSEP T_A DIRSEP "%s.dep", modulepath, module);
                snprintf(dbdname,     size, "%s" DIRSEP EPICSVERSION DIRSEP "dbd" DIRSEP "%s.dbd", modulepath, module);
                snprintf(dbname,      size, "%s" DIRSEP "db", modulepath);
                snprintf(binname,     size, "%s" DIRSEP EPICSVERSION DIRSEP "bin" DIRSEP T_A, modulepath);
                snprintf(startupname, size, "%s" DIRSEP "startup", modulepath);
                snprintf(miscname,    size, "%s" DIRSEP "misc", modulepath);

                debug_print("libname is %s.\n", libname);
                debug_print("depname is %s.\n", depname);
                debug_print("dbdname is %s.\n", dbdname);

                /* parse dependency file and load required modules. */
                FILE* depfile;
                char buffer[40];
                char *rmodule; /* required module */
                char *rversion; /* required version */

                if(!(depfile = fopen(depname, "r"))) {
                        printf("Failed to open %s.\n", depname);
                        return -1;
                }
                while (fgets(buffer, sizeof(buffer)-1, depfile))
                {
                        rmodule = buffer;
                        /* ignore leading spaces */
                        while (isspace((int)*rmodule)) rmodule++;
                        /* ignore empty lines and comment lines */
                        if (*rmodule == 0 || *rmodule == '#') continue;
                        /* rmodule at start of module name */
                        rversion = rmodule;
                        /* find end of module name */
                        while (*rversion && *rversion != ',' && !isspace(*rversion)) rversion++;
                        /* terminate module name */
                        *rversion++ = 0;
                        /* Finished if newline is reached */
                        if(*rversion != '\n') {
                                /* ignore spaces */
                                while (isspace((int)*rversion)) rversion++;
                                /* rversion at start of version */
                                end = rversion;
                                /* find end of version */
                                while (*end && !isspace((int)*end)) end++;
                                /* append + to version to allow newer compaible versions */
                                //*end++ = '+';
                                /* terminate version */
                                *end = 0;
                        } else {
                                *rversion = 0;
                        }
                        if(rversion[0] == '\0') {
                                printf("require: %s depends on %s (no version).\n", module, rmodule);
                        } else {
                                printf("require: %s depends on %s (%s).\n", module, rmodule, rversion);
                        }
                        if (require(rmodule, rversion) != 0)
                        {
                                fclose(depfile);
                                return -1;
                        }
                }
                fclose(depfile);

                if (stat(libname, &filestat) == 0) {
                        printf("require: Loading library %s.\n", libname);
                        if (!(libhandle = loadlib(libname))) {
                                debug_print("%s.\n","Loading failed.");
                                return -1;
                        }
                } else {
                        debug_print("%s\n","no Library to load.");
                }

                /* Add path to records if db dir exists. */
                if (stat(dbname, &filestat) == 0) {
                        p = getenv("EPICS_DB_INCLUDE_PATH");
                        if (p) {
                                sprintf(epics_db_include_path, "%s" PATHSEP "%s", p, dbname);
                        } else {
                                sprintf(epics_db_include_path, "." PATHSEP "%s", dbname);
                        }
                        setenv("EPICS_DB_INCLUDE_PATH", epics_db_include_path, 1);
                        printf("require: Adding %s.\n", dbname);
                        debug_print("EPICS_DB_INCLUDE_PATH: %s.\n", epics_db_include_path);
                } else {
                        debug_print("No db-folder found for module %s.\n", module);
                }

                /* Add path to snippets if startup dir exists. */
                if (stat(startupname, &filestat) == 0) {
                        p = getenv("REQUIRE_STARTUP_INCLUDE_PATH");
                        if (p) {
                                sprintf(require_startup_include_path, "%s" PATHSEP "%s", p, startupname);
                        } else {
                                sprintf(require_startup_include_path, "." PATHSEP "%s", startupname);
                        }
                        setenv("REQUIRE_STARTUP_INCLUDE_PATH", require_startup_include_path, 1);
                        printf("require: Adding %s.\n", startupname);
                        debug_print("REQUIRE_STARTUP_INCLUDE_PATH: %s.\n", require_startup_include_path);
                } else {
                        debug_print("No startup-folder found for module %s.\n", module);
                }

                /* Add path to executables if startup dir exists. */
                if (stat(binname, &filestat) == 0) {
                        p = getenv("REQUIRE_BIN_INCLUDE_PATH");
                        if (p) {
                                sprintf(require_bin_include_path, "%s" PATHSEP "%s", p, binname);
                        } else {
                                sprintf(require_bin_include_path, "." PATHSEP "%s", binname);
                        }
                        setenv("REQUIRE_BIN_INCLUDE_PATH", require_bin_include_path, 1);
                        printf("require: Adding %s.\n", binname);
                        debug_print("REQUIRE_BIN_INCLUDE_PATH: %s.\n", require_bin_include_path);
                } else {
                        debug_print("No bin-folder found for module %s.\n", module);
                }

                /* Add path to miscellaneous if misc dir exists. */
                if (stat(miscname, &filestat) == 0) {
                        p = getenv("STREAM_PROTOCOL_PATH");
                        if (p) {
                                sprintf(stream_protocol_path, "%s" PATHSEP "%s", p, miscname);
                        } else {
                                sprintf(stream_protocol_path, "." PATHSEP "%s", miscname);
                        }
                        setenv("STREAM_PROTOCOL_PATH", stream_protocol_path, 1);
                        printf("require: Adding %s.\n", miscname);
                        debug_print("STREAM_PROTOCOL_PATH: %s.\n", stream_protocol_path);
                } else {
                        debug_print("No misc-folder found for module %s.\n", module);
                }

                /* if dbd file exists and is not empty load it */
                if (stat(dbdname, &filestat) == 0 && filestat.st_size > 0) {
                        printf("require: Loading %s.\n", dbdname);
                        if (dbLoadDatabase(dbdname, NULL, NULL) != 0)
                        {
                                fprintf (stderr, "require: can't load %s.\n", dbdname);
                                return -1;
                        }

                        /* when dbd is loaded call register function for 3.14 */
                        sprintf (symbolname, "%s_registerRecordDeviceDriver", module);
                        printf ("require: Calling %s function.\n", symbolname);
#ifdef vxWorks
                        {
                                FUNCPTR f = (FUNCPTR) getAddress(NULL, symbolname);
                                if (f)
                                        f(pdbbase);
                                else
                                        fprintf (stderr, "require: Can't find %s function.\n", symbolname);
                        }
#else
                        iocshCmd(symbolname);
#endif
                } else {
                        debug_print("No dbd file %s.\n", dbdname);
                }
        } else {
                debug_print("Could not find an EPICS module named \"%s\". Looking for "
                            "system libraries.\n", module);
                /* Might be a system library. Search for library in
                 * module_incpath. */
                char fulllibname[size];
                char libdir[size];
                char syslibname[size];
                snprintf(syslibname, sizeof(syslibname), PREFIX "%s" INFIX EXT, module);
                for (p = module_incpath; p != NULL; p = end) {
                        end = strchr(p, sep[0]);
                        if (end) {
                                snprintf (libdir, sizeof(libdir), "%.*s", (int)(end-p), p);
                                end++;
                        } else {
                                snprintf (libdir, sizeof(libdir), "%s", p);
                        }
                        /* ignore empty module_incpath elements */
                        if (libdir[0] == 0) continue;

                        sprintf (fulllibname, "%s" DIRSEP "%s", libdir, syslibname);
                        debug_print("looking for %s.\n", fulllibname);
                        if (stat(fulllibname, &filestat) == 0) break;
#ifdef vxWorks
                        /* now without the .munch */
                        fulllibname[strlen(fulllibname)-6] = 0;
                        debug_print("looking for %s.\n", fulllibname);
                        if (stat(fulllibname, &filestat) == 0) break;
#endif
                }
                if (!p) {
                        debug_print("require: \"%s\" not found in %s.\n",
                                        syslibname, module_incpath);
                        return -1;
                }
                printf("require: Loading system library %s.\n", fulllibname);
                if ((libhandle = loadlib(fulllibname))) {
                        registerModule(module, "system");
                } else {
                        debug_print("%s\n","Loading failed.");
                        return -1;
                }
        }

        return 0;
    }
}

int dbLoadRecordsTemplate(const char *file, const char *subs) {
        const char sep[1] = PATHSEP;
        char template[256];  /* mktemp template */
        char file_exp[256];  /* filename of expanded database */
        char *p, *end;
        char msi_call[1024]; /* msi call */
        char dbflags[1024];  /* -I flags to msi */
        char *include_path;  /* EPICS_DB_INCLUDE_PATH */
        struct stat filestat;
        char subsname[256]; /* Full path to substitutions file */

        /*
         * Generate a temporary filename
         */
        snprintf(template, sizeof(template), "%s", file);
        p = strrchr(template, '.');
        if(p) {
                *p = '\0';
        }
        strncat(template, "_XXXXXX", sizeof(template)-strlen(template));
        mktemp(template);
        snprintf(file_exp, sizeof(file_exp), "%s.db", template);
        debug_print("Generating %s\n", file_exp);

        /*
         * Create dbflags from EPICS_DB_INCLUDE_PATH
         */
        include_path = getenv("EPICS_DB_INCLUDE_PATH");
        dbflags[0] = '\0';
        for(p = include_path; p != NULL; p = end) {
                end = strchr(p, sep[0]);
                if(end) {
                        strncat(dbflags, "-I",sizeof(dbflags)-strlen(dbflags));
                        strncat(dbflags, p, MIN((int)(end-p),sizeof(dbflags)-strlen(dbflags)));
                        strncat(dbflags, " ",sizeof(dbflags)-strlen(dbflags));
                        end++;
                } else {
                        strncat(dbflags, "-I",sizeof(dbflags)-strlen(dbflags));
                        strncat(dbflags, p, sizeof(dbflags)-strlen(dbflags));
                }
        }

        /*
         * Find substitutions file in EPICS_DB_INCLUDE_PATH
         */
        for(p = include_path; p != NULL; p = end) {
                end = strchr(p, sep[0]);
                if(end) {
                        snprintf(subsname, sizeof(subsname), "%.*s" DIRSEP "%s", (int)(end-p), p, file);
                        end++;
                } else {
                        snprintf(subsname, sizeof(subsname), "%s" DIRSEP "%s", p, file);
                }
                debug_print("Trying %s.\n", subsname);
                if(stat(subsname, &filestat) == 0) {
                        break;
                }
        }

        if(stat(subsname, &filestat) != 0) {
                fprintf(stderr, "require: Couldn't find %s\n", file);
                return -1;
        }

        /* There is a high probability of warnings from msi which we can safely
         * ignore (Undefined macros present). */
        snprintf(msi_call, sizeof(msi_call), "msi %s -S%s > %s %s", dbflags, subsname, file_exp, requireDebug == 0 ? "2>/dev/null" : "" );
        debug_print("%s\n", msi_call);

        system(msi_call);
        printf("dbLoadRecords(\"%s\",\"%s\")\n", file_exp, subs);
        dbLoadRecords(file_exp, subs);
        if(!requireDebug) {
                remove(file_exp);
        }
        return 0;
}

int requireSnippet(const char *file, const char *macros) {
        const char sep[1] = PATHSEP;
        char *p, *end;
        char *include_path;  /* REQUIRE_STARTUP_INCLUDE_PATH */
        struct stat filestat;
        char snippetname[256]; /* Full path to snippet */

        /*
         * Find snippet in REQUIRE_STARTUP_INCLUDE_PATH
         */
        include_path = getenv("REQUIRE_STARTUP_INCLUDE_PATH");
        for(p = include_path; p != NULL; p = end) {
                end = strchr(p, sep[0]);
                if(end) {
                        snprintf(snippetname, sizeof(snippetname), "%.*s" DIRSEP "%s", (int)(end-p), p, file);
                        end++;
                } else {
                        snprintf(snippetname, sizeof(snippetname), "%s" DIRSEP "%s", p, file);
                }
                debug_print("Trying %s.\n", snippetname);
                if(stat(snippetname, &filestat) == 0) {
                        break;
                }
        }

        if(stat(snippetname, &filestat) != 0) {
                fprintf(stderr, "require: Couldn't find %s\n", file);
                return -1;
        }
        iocshLoad(snippetname, macros);
        return 0;

}

#if defined(__unix__)
/* Handle sigchld if child process dies */
void signal_callback_handler(int signum) {
	printf("require: Child process died.\n");
}
/*
 * Fork and run an executable from a required module.
 *
 * @param executable   Executable to run. Is searched for in REQUIRE_BIN_INCLUDE_PATH
 * @param args         Arguments 1-31 to pass on to executable. Arg 0 is automatically set to executable.
 * @param outfile      Which file to redirect stdout/stderr to. NULL or '-' is no redirect.
 * @param assertNoPath If assertNoPath exists don't execute executable.
 * @param background   Starts process after forking.
 * @return 0 on success.
 */
int requireExec(const char *executable, const char *args, const char *outfile, const char *assertNoPath, int background) {
        const char sep[1] = PATHSEP;
        char args_int[256];
        char *p, *end;
        char *include_path;  /* REQUIRE_BIN_INCLUDE_PATH */
        struct stat filestat;
        int statres = -1;
        char execname[256]; /* Full path to executable */
        include_path = getenv("REQUIRE_BIN_INCLUDE_PATH");
        if(stat(assertNoPath, &filestat) == 0) {
                printf("require: Path %s exists, won't execute executable.\n", assertNoPath);
                return 0;
        }
        for(p = include_path; p != NULL; p = end) {
                end = strchr(p, sep[0]);
                if(end) {
                        snprintf(execname, sizeof(execname), "%.*s" DIRSEP "%s", (int)(end-p), p, executable);
                        end++;
                } else {
                        snprintf(execname, sizeof(execname), "%s" DIRSEP "%s", p, executable);
                }
                debug_print("Trying %s.\n", execname);
                if((statres = stat(execname, &filestat)) == 0) {
                        break;
                }
        }

        if(statres != 0) {
                fprintf(stderr, "require: Couldn't find %s\n", executable);
                return -1;
        }

        if(!(filestat.st_mode & S_IXUSR)) {
                fprintf(stderr, "require: %s not executable\n", executable);
                return -1;
        }

        pid_t pid = 0;
        int pipefd[2];
        if(background){
                signal(SIGCHLD, signal_callback_handler);
                if(pipe(pipefd) == -1) {
                        fprintf(stderr, "require: Failed to open pipe\n");
                        return -1;
                }
                if((pid = fork()) == -1) {
                        fprintf(stderr, "require: Failed to fork\n");
                        return -1;
                }
        }
        if (pid==0) { /* child process */
                char *argv[32];
                argv[0] = execname;
                int i = 1;
                char *quote;
                int found_quote = 0;
                int cpid = getpid();
                if(background) {
                        close(pipefd[1]);   /* Close write end of pipe */
                        dup2(pipefd[0], 0); /* Redirect stdin to read end of pipe */
                }
                /* Split args into argv[] on space. Honor quotation marks. */
                if(args != NULL && args[0] != '\0') {
                        snprintf(args_int, sizeof(args_int), "%s", args);
                        for (p = args_int; p != NULL; p = end) {
                                end = strchr(p, ' ');
                                quote = strchr(p, '"');
                                if(found_quote) {
                                        found_quote = 0;
                                        p++;
                                        end = strchr(p, '"');
                                        if(!end) {
                                                fprintf(stderr, "[%d]: ERROR: No matching quote\n", cpid);
                                                return -1;
                                        }
                                        *end = '\0';
                                        end++;
                                        end = strchr(end, ' ');
                                } else if(quote == end+1) {
                                        found_quote = 1;
                                }
                                if(end) {
                                        *end = '\0';
                                        end++;
                                }
                                argv[i] = p;
                                debug_print("[%d]: arg %d: %.*s\n", cpid, i, (int)(end-p), p);
                                if(i++ == 30) {
                                        /* The last string has to be NULL */
                                        break;
                                }
                        }
                }
                argv[i] = NULL;
                if(outfile != NULL && strcmp(outfile, "-") != 0){
                        debug_print("[%d]: Executing %s %s &> %s\n", cpid, execname, args, outfile);
                        int fd = open(outfile, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR);
                        dup2(fd, 1);
                        dup2(fd, 2);
                        close(fd);
                } else {
                        debug_print("[%d]: Executing %s %s\n", cpid, execname, args);
                }
                i = 0;
                char *ld_library_path = calloc(2048, sizeof(char));
                if(ld_library_path == NULL) {
                        fprintf(stderr, "require: Out of memory\n");
                }
                struct module_list *iter;
                char *modules_path = getenv("EPICS_MODULES_PATH");
                for (iter = loadedModules; iter != NULL; iter=iter->next) {
                        if(iter != loadedModules) {
                                strcat(ld_library_path, ":");
                        }
                        strcat(ld_library_path, modules_path);
                        strcat(ld_library_path, "/");
                        strcat(ld_library_path, iter->name);
                        strcat(ld_library_path, "/");
                        strcat(ld_library_path, iter->version);
                        strcat(ld_library_path, "/" EPICSVERSION "/lib/" T_A "/");
                }
                setenv("LD_LIBRARY_PATH", ld_library_path, 1);
                free(ld_library_path);
                execv(execname, argv);
                fprintf(stderr, "require: Execv failed, binary is broken or script is missing shebang (#!)\n");
                exit(127); /* only if execv fails */
        } else {
                if(background) {
                        close(pipefd[0]); /* Close read end of pipe */
                }
                printf("require: Executing %s with pid %d\n", execname, pid);
        }
        return 0;
}
#endif

static const iocshArg requireArg0 = { "module", iocshArgString };
static const iocshArg requireArg1 = { "version", iocshArgString };
static const iocshArg * const requireArgs[2] = { &requireArg0, &requireArg1 };
static const iocshFuncDef requireCallFuncDef = { "require", 2, requireArgs };
static void requireCallFunc (const iocshArgBuf *args)
{
    require(args[0].sval, args[1].sval);
}

static const iocshArg libversionShowArg0 = { "pattern", iocshArgString };
static const iocshArg * const libversionArgs[1] = { &libversionShowArg0 };
static const iocshFuncDef libversionShowCallFuncDef = { "libversionShow", 1, libversionArgs };
static void libversionShowCallFunc (const iocshArgBuf *args)
{
    libversionShow(args[0].sval);
}

static const iocshArg ldArg0 = { "library", iocshArgString };
static const iocshArg * const ldArgs[1] = { &ldArg0 };
static const iocshFuncDef ldCallFuncDef = { "ld", 1, ldArgs };
static void ldCallFunc (const iocshArgBuf *args)
{
    loadlib(args[0].sval);
}

static const iocshArg dbLoadRecordsTemplateArg0 = { "file name", iocshArgString };
static const iocshArg dbLoadRecordsTemplateArg1 = { "substitutions", iocshArgString };
static const iocshArg * const dbLoadRecordsTemplateArgs[2] = { &dbLoadRecordsTemplateArg0, &dbLoadRecordsTemplateArg1 };
static const iocshFuncDef dbLoadRecordsTemplateFuncDef = { "dbLoadRecordsTemplate", 2, dbLoadRecordsTemplateArgs };
static void dbLoadRecordsTemplateCallFunc (const iocshArgBuf *args)
{
    dbLoadRecordsTemplate(args[0].sval, args[1].sval);
}

static const iocshArg requireSnippetArg0 = { "snippet", iocshArgString };
static const iocshArg requireSnippetArg1 = { "substitutions", iocshArgString };
static const iocshArg * const requireSnippetArgs[2] = { &requireSnippetArg0, &requireSnippetArg1 };
static const iocshFuncDef requireSnippetFuncDef = { "requireSnippet", 2, requireSnippetArgs };
static void requireSnippetCallFunc (const iocshArgBuf *args)
{
    requireSnippet(args[0].sval, args[1].sval);
}

static const iocshArg requireExecArg0 = { "executable", iocshArgString };
static const iocshArg requireExecArg1 = { "args", iocshArgString };
static const iocshArg requireExecArg2 = { "outfile", iocshArgString };
static const iocshArg requireExecArg3 = { "assertNoPath", iocshArgString };
static const iocshArg * const requireExecArgs[4] = { &requireExecArg0, &requireExecArg1, &requireExecArg2, &requireExecArg3 };
static const iocshFuncDef requireExecFuncDef = { "requireExec", 4, requireExecArgs };
static void requireExecCallFunc (const iocshArgBuf *args)
{
    requireExec(args[0].sval, args[1].sval, args[2].sval, args[3].sval, 1);
}

static void requireRegister(void)
{
    if (firstTime) {
        firstTime = 0;
        iocshRegister (&ldCallFuncDef, ldCallFunc);
        iocshRegister (&libversionShowCallFuncDef, libversionShowCallFunc);
        iocshRegister (&requireCallFuncDef, requireCallFunc);
        iocshRegister (&dbLoadRecordsTemplateFuncDef, dbLoadRecordsTemplateCallFunc);
        iocshRegister (&requireSnippetFuncDef, requireSnippetCallFunc);
#if defined(__unix__)
        iocshRegister (&requireExecFuncDef, requireExecCallFunc);
#endif
        registerExternalModules();
    }
}

epicsExportRegistrar(requireRegister);
epicsExportAddress(int, requireDebug);
