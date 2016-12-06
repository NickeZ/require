# This module always uses the bundled module.Makefile so that it can be
# built/installed even though it isn't installed.
mkfile_path := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
include ${mkfile_path}/scripts/module.Makefile

# Linux link.h before the EPICS link.h
USR_INCLUDES_Linux=-idirafter ${EPICS_BASE}/include
USR_INCLUDES+=$(USR_INCLUDES_$(OS_CLASS))

USR_CPPFLAGS += -D"T_A=\"${T_A}\"" -D"EPICSVERSION=\"${EPICSVERSION}\"" -D"VERSION=\"$(shell git describe 2> /dev/null || echo unknown)\""

HEADERS  = src/require.h

SOURCES  = src/require.c
DBDS     = src/require.dbd

SOURCES += src/listRecords.c
DBDS    += src/listRecords.dbd

SOURCES += src/updateMenuConvert.c
DBDS    += src/updateMenuConvert.dbd

SOURCES += src/addScan.c
DBDS    += src/addScan.dbd

SOURCES += src/disctools.c
DBDS    += src/disctools.dbd

SOURCES += src/exec.c
DBDS    += src/exec.dbd

SOURCES += src/mlock.c
DBDS    += src/mlock.dbd

HEADERS += src/epicsEndian.h

EXECUTABLES_noarch += $(wildcard scripts/*.py)
EXECUTABLES_noarch += $(addprefix scripts/,iocsh atbuild)
EXECUTABLES += requireExec

TEMPLATES = -none-
SUBSTITUTIONS = -none-

DOC = doc README.md

LD_ENV  = -L .                 -Wl,-rpath,'$$ORIGIN/../../lib/${T_A}' -lrequire
ifeq (${EPICS_MAJORMINOR},3.14)
LD_BASE = -L ${EPICS_BASE_LIB} -Wl,-rpath,${EPICS_BASE_LIB} -lCom -ldbIoc -lregistryIoc
else
LD_BASE = -L ${EPICS_BASE_LIB} -Wl,-rpath,${EPICS_BASE_LIB} -lCom -ldbCore
endif

requireExec: requireExec.o librequire.so
	${CCC} -o $@ $< ${LD_ENV} ${LD_BASE}
