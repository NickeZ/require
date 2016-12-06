#ifndef require_h
#define require_h

int require(const char* libname, const char* version);
int requireExec(const char *executable, const char *args, const char *outfile, const char *assertNoPath, int fork);
const char* getLibVersion(const char* libname);
int libversionShow(const char* pattern);

/* Private function is exposed since 'require' will terminate the application */
int require_priv(const char* module, const char* vers);

#endif
