# EPICS Environment Manager
# Copyright (C) 2015 Dirk Zimoch
# Copyright (C) 2015 Cosylab
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This generic makefile compiles EPICS code (drivers, records, snl, ...)
# for all installed EPICS versions.
# Read this documentation and the inline comments carefully before changing
# anything in this file.
#
# Usage: Create a Makefile containig the line:
#          include ${EPICS_ENV_PATH}/module.Makefile
#        Optionally add variable definitions below that line.
#
# If you don't want to set EPICS_ENV_PATH you may specify the absolute path to
# module.Makefile in every EPICS module instead.
#
# This makefile automatically finds the source files (unless overwritten with
# the SOURCES variable in your Makefile) and generates a library for each EPICS
# version and each target architecture. Therefore, it calls itself recursively.
#
# - First run: (see comment ## RUN 1)
#   Find out what to build
#   Iterate over all installed EPICS versions
#
# - Second run: (see comment ## RUN 2)
#   Find the sources etc.
#   Include EPICS configuration files for this ${EPICSVERSION}
#   Iterate over all target architectures (${T_A}) defined for this version.
#
# - Third run: (see comment ## RUN 3)
#   Compile (or install, uninstall, etc) everything.
#
# Module names are derived from the directory name (unless overwritten with
# the PROJECT variable in your Makefile). The module can be loaded in an EPICS
# shell with:
#   require "<libname>" [,"<version>"]
#
# User variables (add them to your Makefile, or on the command line after
# 'make', none is required):
# PROJECT
#    Basename of the built library.
#    If not defined, it is derived from the directory name (m-epics-<modulename>).
# LIBVERSION
#    Version of the build library.
#    If not defined, it is derived from $USER or git tag.
# USR_DEPENDENCIES
#    Dependencies that cannot be automatically detected or system libraries.
#    Example:
#      USR_DEPENDENCIES += boost_filesystem
#      USR_DEPENDENCIES += asyn,4.23
# SOURCES
#    All source files to compile.
#    If not defined, default is all *.c *.cc *.cpp *.st *.stt in
#    the source directory (where your Makefile is).
#    If you define this, you must list ALL sources.
#    Must be set to -none- if source files exists but shouldn't be included.
# SOURCES_${OS_CLASS}
#    All ${OS_CLASS} specific sources.
#    Must be set _before_ inclusion of this file.
# DBDS
#    All dbd files of the project.
#    If not defined, default is all *.dbd files in the source directory.
#    Must be set to -none- if source files exists but shouldn't be included.
# HEADERS
#    Header files to install (e.g. to be included by other drivers)
#    If not defined, no headers will be installed.
# HEADERS_${OS_CLASS}
#    All headers that should be installed into include/os/${OS_CLASS}.
#    Must be set _before_ inclusion of this file.
# HEADERS_default
#    All headers that should be installed into include/os/default.
# TEMPLATES
#    Template files to install or expanded from substitution files.
#    Must be set to -none- if source files exists but shouldn't be included.
# SUBSTITUTIONS
#    Substitutions files that should not be expanded.
#    Must be set to -none- if source files exists but shouldn't be included.
# DOC
#    Documentation files or directories that should be installed.
# TESTS
#    Test scripts.
# STARTUPS
#    Snippets of startup scripts to install.
#    Must be set to -none- if source files exists but shouldn't be included.
# OPIS
#    Operator interface files or directories that should be installed.
#    Must be set to -none- if source files exists but shouldn't be included.
# EXCLUDE_VERSIONS
#    EPICS versions to skip.
# EXCLUDE_VERSION_<EPICSVERSION>
#    Space separated list of comparisons in regard to LIBVERSION. If any
#    comparison evaluates to true, exclude this EPICS version.
#    Non-numbered LIBVERSION will always evaulate to false.
#    Example:
#       EXCLUDE_VERSION_3.14 = <1.0 >3.0
#       EXCLUDE_VERSION_3.15 = <2.0
# EXCLUDE_ARCHS
#    Skip architectures that start or end with the pattern, e.g., T2 or ppc604.
# USR_CFLAGS, USR_CPPFLAGS, USR_CXXFLAGS
#    Add project specific compiler flags.
#
# Debugging facilities:
# make debug V="VAR1 VAR2"
#    Prints out the values of VAR1 and VAR2 at every recursive call to make.
# make EXPANDDBDFLAGS=--debug
#    Passes --debug flag to expand_dbd.py
# make GETPREREQUISITESFLAGS=--debug
#    Passes --debug flag to get_prerequisites.py
# make GETPREREQUISITESFLAGS=--info
#    Passes --info flag to get_prerequisites.py
#
# Extra build parameters:
# make RELEASE=nightly
#    Generates version based on commit hash if no tag is found.
#
# This is the structure a module will be installed into.
# ${EPICS_MODULES_PATH}/
#  |--<module-1>
#  |  |--<version-1>/
#  |  |  |--<EPICS-VERSION-1>/
#  |  |  |  |--lib/
#  |  |  |  |  |--<EPICS-ARCH-1>/
#  |  |  |  |  |  |--<module-library>
#  |  |  |  |  |  |--<module>.dep
#  |  |  |  |  `--<EPICS-ARCH-2>/
#  |  |  |  |     |--<module-library>
#  |  |  |  |     `--<module>.dep
#  |  |  |  |--bin/
#  |  |  |  |  |--<EPICS-ARCH-1>/
#  |  |  |  |  |  `--<executable>
#  |  |  |  |  `--<EPICS-ARCH-2>/
#  |  |  |  |     `--<module>.dep
#  |  |  |  |--include/
#  |  |  |  |  |--<header-file-1>
#  |  |  |  |  |--<header-file-2>
#  |  |  |  |  `--os
#  |  |  |  |     |--Linux/
#  |  |  |  |     |--vxWorks/
#  |  |  |  |     `--WIN32/
#  |  |  |  `-- dbd
#  |  |  |     `-- <module>.dbd
#  |  |  |--<EPICS-VERSION-2>/
#  |  |  |--db/
#  |  |  |  |--<substitution-1>
#  |  |  |  |--<template-1>
#  |  |  |  |--<template-2>
#  |  |  |  `--<template-3>
#  |  |  |--doc/
#  |  |  |--startup/
#  |  |  |  `--<st.cmd-snippet>
#  |  |  |--test/
#  |  |  |  |--<test-stimuli>
#  |  |  |  `--<test-script>
#  |  |  `--misc/
#  |  |     `--<protocol-file-1>
#  |  |--<version-2>/
#  |  `--<version-3>/
#  |--<module-2>/
#  `--<module-3>/

# Get the location of this file 
MAKEHOME:=$(dir $(lastword ${MAKEFILE_LIST}))
# Get the name of the Makefile that included this file
USERMAKEFILE:=$(lastword $(filter-out $(lastword ${MAKEFILE_LIST}), ${MAKEFILE_LIST}))

# Default rule is build, not install. (different from default EPICS make rules.)
.DEFAULT_GOAL := build
.PHONY := install uninstall build debug debug-out list list-verbose
.PRECIOUS := *.d

include ${MAKEHOME}/CONFIG

rwildcard=$(shell find . -name "$1" -not -path "./${BUILD_DIR}*" -not -path "${IGNORE_PATTERN}" )

# Enable verboser mode by overriding QUIET (make QUIET=).
QUIET = @

# Some shell commands
LN = ln -s
EXISTS = test -e
NM = nm
RMDIR = rm -rf
RM = rm -f
MV= mv -f
CP= cp
MKDIR = mkdir
GETPREREQUISITES = ${PYTHON} ${MAKEHOME}/get_prerequisites.py ${GETPREREQUISITESFLAGS}
# Python 2.7 is required.
VALID_PYTHON_VERSIONS=2.7.%
PYTHON = $(or ${PYTHON_${EPICS_HOST_ARCH}},${PYTHON_${EPICS_HOST_ARCH:_64=}},python)
PYTHON_VERSION := $(shell ${PYTHON} -V 2>&1)
ifndef PYTHON_VERSION
$(error calling '${PYTHON} -V' failed)
endif
ifeq ($(filter ${VALID_PYTHON_VERSIONS}, ${PYTHON_VERSION}),)
$(error Python 2.7 required, found $(or ${PYTHON_VERSION}, no Python at all))
endif

# Check that all correct environment variables are set. If target is version or help we don't need the variables.
ifeq ($(if $(filter version help,${MAKECMDGOALS}), ok),)
    $(foreach env,EPICS_MODULES_PATH EPICS_BASES_PATH EPICS_HOST_ARCH,$(if $(and $(findstring environment,$(origin ${env})),${${env}}),,$(error ${env} is empty or not defined in environment)))
endif

# some generated file names
VERSIONFILE   = $(if $(strip ${SRCS}),${PRJ}_Version${LIBVERSION}.c)
REGISTRYFILE  = ${PRJ}_registerRecordDeviceDriver.cpp
SUBFUNCFILE   = $(if $(if $(strip $(filter $(foreach ext,${SOURCE_EXT},%.${ext}), $(SRCS))),$(shell if grep epicsRegisterFunction $(addprefix ../../,$(filter $(foreach ext,${SOURCE_EXT},%.${ext}), $(SRCS))) ; then echo YES ; fi)),../O.${EPICSVERSION}_Common/${PRJ}_subRecordFunctions.dbd)
BUILD_DIR    ?= builddir
BUILD_PATH    = ${BUILD_DIR}

# call with 'make debug V="VARIABLE1 VARIABLE2"' to read out VARIABLE1 and 2.
debug-out:
	$(foreach v,${V}, \
	  $(info $v = ${$v}))


ifndef EPICSVERSION
###############################################
# First run
# Nothing defined.

INSTALLED_EPICS_VERSIONS := $(patsubst ${EPICS_BASES_PATH}/base-%,%,$(wildcard ${EPICS_BASES_PATH}/base-*[0-9]))
INSTALLED_EPICS_VERSIONS_MAJMIN := $(shell echo "${INSTALLED_EPICS_VERSIONS}" | sed -r 's/(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)[^ ]*/\1.\2/g')
EPICS_VERSIONS            = $(filter-out ${EXCLUDE_VERSIONS:=%},${DEFAULT_EPICS_VERSIONS})
MISSING_EPICS_VERSIONS    = $(filter-out ${BUILD_EPICS_VERSIONS},${EPICS_VERSIONS})
BUILD_EPICS_VERSIONS      = $(filter ${INSTALLED_EPICS_VERSIONS},${EPICS_VERSIONS})
LIBVERSION := $(shell ${PYTHON} ${MAKEHOME}/get_version.py $(if ${TAG_PREFIX},--prefix=${TAG_PREFIX}) $(if ${RELEASE},--${RELEASE}))
# If PROJECT isn't defined, derive it from project directory.
PRJDIR := $(patsubst ${PROJECT_PREFIX}%,%,$(notdir $(shell pwd)))
PRJ = $(if ${PROJECT},${PROJECT},${PRJDIR})

EXCLUDE_VERSIONS += $(foreach v,${INSTALLED_EPICS_VERSIONS_MAJMIN} ${INSTALLED_EPICS_VERSIONS},\
		      $(shell ${PYTHON} ${MAKEHOME}/check_excludes.py ${CHECKEXCLUDESDEBUG} --epics-base $v --version ${LIBVERSION} $(foreach c,${EXCLUDE_VERSION_$v},--condition '$c')))

$(foreach v,${INSTALLED_EPICS_VERSIONS_MAJMIN},\
  $(eval EPICS_VERSIONS_$v = $(filter $v.%,${BUILD_EPICS_VERSIONS})))

MKFLAGS = -f ${USERMAKEFILE} LIBVERSION=${LIBVERSION}
FOR_EACH_EPICS_VERSION = ${QUIET}for VERSION in ${BUILD_EPICS_VERSIONS}; do ${MAKE} ${MKFLAGS} EPICSVERSION=$$VERSION $@ || exit; done

INSTALLED_MODULE_VERSIONS = $(shell ls ${EPICS_MODULES_PATH}/${PRJ} 2>/dev/null | sed -r 's/${PRJ}-(\w+)/\1/' 2>/dev/null)

V = INSTALLED_EPICS_VERSIONS BUILD_EPICS_VERSIONS MISSING_EPICS_VERSIONS $(foreach v,3.14 3.15, EPICS_VERSIONS_$v) BUILDCLASSES

define EPICSVERSION_template
.PHONY: $${BUILD_PATH}/$1

$${BUILD_PATH}/$1:
	$${MKDIR} -p $$@
	$${MAKE} $${MKFLAGS} EPICSVERSION=$1 build
endef

$(foreach ver,${BUILD_EPICS_VERSIONS},$(eval $(call EPICSVERSION_template,${ver})))

# Loop over all EPICS versions for second run.
build: | $(foreach ver,${BUILD_EPICS_VERSIONS},${BUILD_PATH}/${ver})

# Handle cases where user requests build or debug of one specific version.
# make <action>.<version>
${INSTALLED_EPICS_VERSIONS:%=build.%}:
	${MAKE} ${MKFLAGS} EPICSVERSION=${@:build.%=%} build

${INSTALLED_EPICS_VERSIONS:%=debug.%}:
	${MAKE} ${MKFLAGS} EPICSVERSION=${@:debug.%=%} debug

install: build
ifeq (${LIBVERSION},) # Do not install without version.
	$(error "Can't $@ if LIBVERSION is empty.")
endif
	${PYTHON} ${MAKEHOME}/module_manager.py --assumeyes --builddir='${BUILD_PATH}' install '${PRJ}' '${LIBVERSION}'

install.%: build.%
ifeq (${LIBVERSION},) # Do not install without version.
	$(error "Can't $@ if LIBVERSION is empty.")
endif
	${PYTHON} ${MAKEHOME}/module_manager.py --assumeyes --builddir='${BUILD_PATH}' install '${PRJ}' '${LIBVERSION}'

clean:
	${QUIET}echo "Removing ${BUILD_PATH}/O.*"
	${QUIET}if [[ "${BUILD_PATH}" != *"/"* && ! "${BUILD_PATH}" =~ [\.]+ ]] ; then $(RMDIR) ${BUILD_PATH}/O.* ; fi

clean.3.%:
	${QUIET}echo "Removing ${BUILD_PATH}/O.3.%"
	${QUIET}if [[ "${BUILD_PATH}" != *"/"* && ! "${BUILD_PATH}" =~ [\.]+ ]] ; then $(RMDIR) ${BUILD_PATH}/O.${@:clean.%=%}* ; fi

distclean:
	${QUIET}echo "Removing ${BUILD_PATH}"
	${QUIET}if [[ "${BUILD_PATH}" != *"/"* && ! "${BUILD_PATH}" =~ [\.]+ ]] ; then $(RMDIR) ${BUILD_PATH} ; fi

help:
	${QUIET}echo "usage:"
	${QUIET}for target in '' build build.'<EPICS version>' \
	install install.'<EPICS version>' \
	uninstall 'uninstall.<Module version>' \
	list list-verbose clean help version; \
	do echo "  make $$target"; \
	done
	${QUIET}echo "Makefile variables: (defaults)"
	${QUIET}echo "  EPICS_VERSIONS   (${DEFAULT_EPICS_VERSIONS})"
	${QUIET}echo "  PROJECT          (${PRJDIR}) [from current directory name]"
	${QUIET}echo "  SOURCES          ($(foreach ext,${SOURCE_EXT},*.${ext}))"
	${QUIET}echo "  HEADERS          () [only those to install]"
	${QUIET}echo "  TEMPLATES        ($(foreach ext,$(sort ${TEMPLATE_EXT} ${SUBSTITUTIONS_EXP_EXT}),*.${ext}))"
	${QUIET}echo "  SUBSTITUTIONS    ($(foreach ext,${SUBSTITUTIONS_EXT},*.${ext}))"
	${QUIET}echo "  STARTUPS         ($(foreach ext,${STARTUP_EXT},*.${ext}))"
	${QUIET}echo "  MISCS            ($(foreach ext,${PROTOCOL_EXT},*.${ext}))"
	${QUIET}echo "  DBDS             (*.dbd)"
	${QUIET}echo "  EXCLUDE_VERSIONS () [versions not to build, e.g. 3.14]"
	${QUIET}echo "  EXCLUDE_ARCHS    () [target architectures not to build, e.g. eldk]"
	${QUIET}echo "  BUILDCLASSES     (Linux)"

version:
	${QUIET}echo ${LIBVERSION}

debug: debug-out
	${FOR_EACH_EPICS_VERSION}

list:
ifeq (${INSTALLED_MODULE_VERSIONS},)
	${QUIET}echo -none-
else
	${QUIET}$(foreach v,${INSTALLED_MODULE_VERSIONS},\
	    echo $v;)
endif

list-verbose:
ifeq (${INSTALLED_MODULE_VERSIONS},)
	${QUIET}echo -none-
else
	${QUIET}$(foreach v,${INSTALLED_MODULE_VERSIONS},\
	    ls ${EPICS_MODULES_PATH}/${PRJ}/$v/*/lib/*/*.dep | sort | awk -F/ '{print "$v",$$7,$$9}' | column -t;)
endif

uninstall:
ifeq (${INSTALLED_MODULE_VERSIONS},)
	${QUIET}echo "This module is currently not installed."
else
	${QUIET}echo "Please choose version to uninstall from list: $(foreach v,${INSTALLED_MODULE_VERSIONS},uninstall.$v)"
endif

uninstall.%:
	${QUIET}echo "Version is not installed: ${@:uninstall.%=%}"

reinstall: build
ifeq (${LIBVERSION},) # Do not reinstall without version.
	$(error "Can't $@ if LIBVERSION is empty")
endif
	${PYTHON} ${MAKEHOME}/module_manager.py --assumeyes --builddir='${BUILD_PATH}' reinstall '${PRJ}' '${LIBVERSION}'

define RE_UNINSTALLRULES_template
uninstall.${1}:
	${QUIET}echo Uninstalling ${1}
	${PYTHON} ${MAKEHOME}/module_manager.py --assumeyes uninstall '${PRJ}' '${1}'
reinstall.${1}: build
	${QUIET}echo Reinstalling ${1}
	${PYTHON} ${MAKEHOME}/module_manager.py --assumeyes --builddir='${BUILD_PATH}' reinstall '${PRJ}' '${1}'
endef

$(foreach v, ${INSTALLED_MODULE_VERSIONS},$(eval $(call RE_UNINSTALLRULES_template,$v)))

# Make these variables available to subsequent runs (required to make vpath
# work since include is before variable definitions in project Makefile).
export PRJ
export EXCLUDE_ARCHS
export USR_DEPENDENCIES
export DBDS
export SOURCES
export HEADERS
export DOC
export TESTS
export OPIS
export MISCS
export EXCLUDE_VERSIONS
export $(addprefix HEADERS_,${OS_CLASSES_SUFFIXES} ${EPICSVERSIONS_SUFFIXES})
export $(addprefix SOURCES_,${OS_CLASSES_SUFFIXES} ${EPICSVERSIONS_SUFFIXES})


else # EPICSVERSION
###############################################
# Second or third run
# EPICSVERSION defined
# second or third turn (see T_A branch below)

EPICS_BASE=${EPICS_BASES_PATH}/base-${EPICSVERSION}
EPICS_MAJORMINOR=$(shell echo ${EPICSVERSION} | sed -r 's/^((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)).*/\1/')

${EPICS_BASE}/configure/CONFIG:
	$(error "EPICS release ${EPICSVERSION} not installed on this host. File $@ doesn't exist")

# Some TOP and EPICS_BASE tweeking necessary to work around release check in 3.14.10+
# This is dangerous, any module that provides a headerfile already in EPICS base will
# try to overwrite the base headerfile at build time.
CONFIG = ${EPICS_BASE}/configure
EB     = ${EPICS_BASE}
TOP   := ${EPICS_BASE}
-include ${EPICS_BASE}/configure/CONFIG
EPICS_BASE    := ${EB}
SHRLIB_VERSION =
# do not link everything with readline (and curses)
COMMANDLINE_LIBRARY =


ifndef T_A
##########################################
# Second run
# Target architecture NOT DEFINED.
# Figure out which source files.

V = EPICS_BASE EPICSVERSION EPICS_MAJORMINOR CROSS_COMPILER_TARGET_ARCHS EXCLUDE_ARCHS LIBVERSION RELEASE_TOPS

TESTVERSION  := $(shell echo "${LIBVERSION}" | grep -v -E "^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\$$")

ifneq (${TESTVERSION},)
MAJOR_MINOR_PATCH=$(subst ., ,${LIBVERSION})
MAJOR=$(word 1,${MAJOR_MINOR_PATCH})
MINOR=$(word 2,${MAJOR_MINOR_PATCH})
endif

CROSS_COMPILER_TARGET_ARCHS := $(filter-out $(addprefix %,${EXCLUDE_ARCHS}),$(filter-out $(addsuffix %,${EXCLUDE_ARCHS}),${EPICS_HOST_ARCH} ${CROSS_COMPILER_TARGET_ARCHS}))

AUTOSRCS := $(foreach ext,${SOURCE_EXT},$(call rwildcard,*.${ext}))
SOURCES  += ${SOURCES_${EPICS_MAJORMINOR}} ${SOURCES_${EPICSVERSION}} ${SOURCES_${OS_CLASS}}
SRCS      = $(if $(strip ${SOURCES}),$(filter-out -none-,${SOURCES}),${AUTOSRCS})

AUTODBDFILES = $(call rwildcard,*Record.dbd) $(strip $(filter-out %Include.dbd dbCommon.dbd %Record.dbd,$(call rwildcard,*.dbd)))
DBDFILES1    = $(if ${DBDS},$(filter-out -none-,${DBDS}),${AUTODBDFILES})
DBDFILES2    = $(patsubst %.gt,%.dbd,$(notdir $(filter %.gt,${SRCS})))
DBDFILES2   += $(patsubst %.st,%_snl.dbd,$(notdir $(filter %.st,${SRCS})))
DBDFILES2   += $(patsubst %.stt,%_snl.dbd,$(notdir $(filter %.stt,${SRCS})))
DBDFILES     = ${DBDFILES1} ${DBDFILES2}

RECORDS = $(if $(strip ${DBDFILES1}), $(shell ${PYTHON} ${MAKEHOME}/expand_dbd.py ${EXPANDDBDFLAGS} --list-records $(addprefix -I, $(sort $(abspath $(dir ${AUTODBDFILES}) $(dir ${SRCS})))) $(realpath ${DBDFILES1})))

MENUS = $(patsubst %.dbd,%.h,$(call rwildcard,menu*.dbd))

AUTOTMPLS := $(foreach ext,${TEMPLATE_EXT},$(call rwildcard,*.${ext})) $(foreach ext,${SUBSTITUTIONS_EXT},$(patsubst %.${ext},%.${SUBSTITUTIONS_EXP_EXT},$(call rwildcard,*.${ext})))
TMPLS      = $(if $(strip ${TEMPLATES}),$(filter-out -none-,${TEMPLATES}),${AUTOTMPLS})

SUBS = $(if $(strip ${SUBSTITUTIONS}),$(filter-out -none-,${SUBSTITUTIONS}),$(foreach ext,${SUBSTITUTIONS_EXT},$(call rwildcard,*.${ext})))

AUTOMISCS := $(foreach ext,${PROTOCOL_EXT},$(call rwildcard,*.${ext}))
MSCS       = $(if $(strip ${MISCS}),$(filter-out -none-,${MISCS}),${AUTOMISCS})

AUTOSTARTUPS := $(foreach ext,${STARTUP_EXT},$(call rwildcard,*.${ext}))
STARTUPS_INT  = $(if $(strip ${STARTUPS}),$(filter-out -none-,${STARTUPS}),${AUTOSTARTUPS})

DOC_DIRS_INT    = $(foreach v,${DOC},$(if $(shell test -d $v && echo "Y"),$(patsubst %/,%,$v)))
DOC_FILES_INT   = $(foreach v,${DOC},$(if $(shell test -f $v && echo "Y"),$v))
DOC_INT_RELPATH = $(foreach docdir,${DOC_DIRS_INT},$(patsubst ${docdir}/%,%,$(shell find ${docdir} -type f)))

AUTOOPIS       = $(foreach ext,${OPI_EXT},$(call rwildcard,*.${ext}))

OPI_DIRS_INT  = $(foreach v,${OPIS},$(if $(shell test -d $v && echo "Y"),$(patsubst %/,%,$v)))
OPI_FILES_INT = $(foreach v,${OPIS},$(if $(shell test -f $v && echo "Y"),$v))

OPIS_INT_RELPATH = $(foreach opidir,${OPI_DIRS_INT},$(patsubst $(opidir)/%,%,$(shell find $(opidir) -type f)))
OPIS_INT         = $(if $(strip ${OPIS}),${OPI_FILES_INT},${AUTOOPIS})

BUILDDIRS = $(addprefix ${BUILD_PATH}/O.${EPICSVERSION}_, ${CROSS_COMPILER_TARGET_ARCHS})

FOR_EACH_TARGET_ARCH = ${QUIET}for ARCH in ${CROSS_COMPILER_TARGET_ARCHS} ; do ${MAKE} -C ${BUILD_PATH}/O.${EPICSVERSION}_$$ARCH -f ../../${USERMAKEFILE} T_A=$$ARCH $@; done

define OPLACEHOLDER_template
.PHONY: $${BUILD_PATH}/O.$${EPICSVERSION}_$1

$${BUILD_PATH}/O.$${EPICSVERSION}_$1:
	$${MKDIR} -p $$@
	$${MAKE} -C $$@ -f ../../$${USERMAKEFILE} T_A=$1
endef

$(foreach arch,${CROSS_COMPILER_TARGET_ARCHS},$(eval $(call OPLACEHOLDER_template,${arch})))


build: | $(foreach arch,${CROSS_COMPILER_TARGET_ARCHS},${BUILD_PATH}/O.${EPICSVERSION}_${arch})

debug: debug-out
	${QUIET}${MKDIR} -p ${BUILDDIRS}
	${FOR_EACH_TARGET_ARCH}

export RECORDS
export HEADERS
export SRCS
export DBDFILES
export TMPLS
export SUBS
export HEADERS_PREFIX
export EXECUTABLES
export MSCS
export MENUS
export STARTUPS_INT
export OPIS_INT
export OPIS_INT_RELPATH
export OPI_DIRS_INT
export DOC_FILES_INT
export DOC_INT_RELPATH
export DOC_DIRS_INT
export OSHDRS
export $(addprefix HEADERS_,${OS_CLASSES_SUFFIXES} ${EPICSVERSIONS_SUFFIXES})
export $(addprefix SOURCES_,${OS_CLASSES_SUFFIXES} ${EPICSVERSIONS_SUFFIXES})


else # T_A
############################
# Third run, Target Architecture defined.
# Executed in O.* directory.

ifeq ($(filter ${OS_CLASS},${BUILDCLASSES}),)

install%: build
install:  build
build%:   build
build:
	${QUIET}echo Skipping ${T_A} because $(if ${OS_CLASS},${OS_CLASS} is not in BUILDCLASSES = ${BUILDCLASSES},it is not available for R$(EPICSVERSION).)
%:
	${QUIET}true

else ifeq ($(wildcard $(firstword ${CC})),)

install%: build
install:  build
build%:   build
build:
	${QUIET}echo Warning: Skipping ${T_A} because cross compiler $(firstword ${CC}) is not installed.
%:
	${QUIET}true

else

V           = BUILDCLASSES OS_CLASS T_A ARCH_PARTS PRJDBD RECORDS MENUS BPTS HDRS SOURCES SOURCES_${EPICS_MAJORMINOR} SOURCES_${EPICSVERSION} SOURCES_${OS_CLASS} SRCS LIBOBJS DBDS DBDFILES LIBVERSION TESTVERSION PRJTMPLS PRJSTARTUPS OPIS
BUILD_PATH := ../../${BUILD_DIR}
#COMMON_DIR  = ${BUILD_PATH}/include/O.${EPICSVERSION}_Common
PROJECTDEP  = ${BUILD_PATH}/${EPICSVERSION}/lib/${T_A}/${PRJ}.dep
PROJECTLIB  = $(if $(strip ${LIBOBJS}),${BUILD_PATH}/${EPICSVERSION}/lib/${T_A}/${LIB_PREFIX}${PRJ}${SHRLIB_SUFFIX})

PRJDBD         = $(if $(strip ${DBDFILES}),${BUILD_PATH}/${EPICSVERSION}/dbd/${PRJ}.dbd)
PRJTMPLS       = $(addprefix ${BUILD_PATH}/db/,$(notdir ${TMPLS}))
PRJSUBS        = $(addprefix ${BUILD_PATH}/db/,$(notdir ${SUBS}))
PRJEXECUTABLES = $(addprefix ${BUILD_PATH}/${EPICSVERSION}/bin/${T_A}/,$(notdir ${EXECUTABLES}))
HDRS           = $(addprefix ${BUILD_PATH}/${EPICSVERSION}/include/${HEADERS_PREFIX},$(addsuffix Record.h,${RECORDS}) $(sort $(notdir ${MENUS} ${HEADERS})))
OSHDRS         = $(addprefix ${BUILD_PATH}/${EPICSVERSION}/include/os/, \
                     $(foreach osclass,$(strip ${OS_CLASSES_SUFFIXES}),$(addprefix ${osclass}/,$(notdir ${HEADERS_${osclass}}))))
PRJMSCS        = $(addprefix ${BUILD_PATH}/misc/,$(notdir ${MSCS}))
PRJDOC         = $(addprefix ${BUILD_PATH}/doc/,$(notdir ${DOC_FILES_INT}) ${DOC_INT_RELPATH})
PRJTESTS       = $(addprefix ${BUILD_PATH}/test/,$(notdir ${TESTS}))
PRJSTARTUPS    = $(addprefix ${BUILD_PATH}/startup/,$(notdir ${STARTUPS_INT}))
PRJOPIS        = $(addprefix ${BUILD_PATH}/opi/,$(notdir ${OPIS_INT}) ${OPIS_INT_RELPATH})

# Add object files to linking step
LIBOBJS      += $(addsuffix $(OBJ),$(notdir $(basename $(filter-out %.o %.a,$(sort ${SRCS})))))
LIBOBJS      += ${LIBRARIES:%=${INSTALL_BIN}/%Lib}
PRODUCT_OBJS  = ${LIBOBJS}

# Add EPICS base libs to linker
LIBS      = -L ${EPICS_BASE_LIB} ${BASELIBS:%=-l%}
LINK.cpp += ${LIBS}

LOADABLE_LIBRARY = $(if $(strip ${LIBOBJS}),${PRJ}${LIBVERSIONSTR})
LIBRARY_OBJS     = ${LIBOBJS}

BASERULES = ${EPICS_BASE}/configure/RULES_BUILD

# Handle registry stuff automagically if we have a dbd file.
# See ${REGISTRYFILE} rules below.
LIBOBJS += $(if $(strip ${PRJDBD}),$(addsuffix $(OBJ),$(basename ${REGISTRYFILE})))

# If we build a library and use versions, provide a version variable.
ifdef PROJECTLIB
ifdef LIBVERSION
LIBOBJS += $(addsuffix $(OBJ),$(basename ${VERSIONFILE}))
endif # LIBVERSION
endif # PROJECTLIB

ifeq (${EPICS_MAJORMINOR},3.15)
# Do not use 3.15 way of generating dependency files. It will assume that the
# missing header files are local, but they are in fact in other modules.
override undefine HDEPENDS_FILES
CPPFLAGS += -MMD
-include *.d
endif

# Assume that dependant DBDs are in any source directory.
DBDDIRS        = $(sort $(dir ${DBDFILES:%=../../%} ${SRCS:%=../../%}))
DBDDIRS       += ${SHARED_DBD} ${EPICS_BASE}/dbd/
DBDEXPANDPATH  = $(addprefix -I ,${DBDDIRS})
USR_DBDFLAGS  += $(DBDEXPANDPATH)

DBDFILES += ${SUBFUNCFILE}

# We cannot use ${INCLUDES} since it contains dependencies. This is a copy of ${INCLUDES} from base/configure/CONFIG_COMMON.
COMPLETEDEP_INCLUDES = -I. $(SRC_INCLUDES) $(INSTALL_INCLUDES) $(RELEASE_INCLUDES)\
  $(TARGET_INCLUDES) $(USR_INCLUDES) $(CMD_INCLUDES) $(OP_SYS_INCLUDES)\
  $($(BUILD_CLASS)_INCLUDES)

# Complete dependency files (filter out -MMD since we use a different set of dep flags), used by get_prerequisites.py to determine EPICS modules dependencies.
define COMPLETEDEP_template
%.dc: %.$1
	$$(CPP) $$(filter-out -MMD,$$(CPPFLAGS)) $$(COMPLETEDEP_INCLUDES) -M -MG -MF $$@ $$^
endef

$(foreach ext,$(filter-out st stt gt,${SOURCE_EXT}),$(eval $(call COMPLETEDEP_template,${ext})))

COMPLETEDEPS = $(foreach ext,${SOURCE_EXT},$(patsubst %.${ext},%.dc,$(filter %.${ext},$(notdir ${SRCS}))))

GETPREREQUISITES_FLAGS = $(addprefix -D,${COMPLETEDEPS}) \
                         $(addprefix -T,$(addprefix ../db/,$(notdir ${TMPLS}))) \
                         $(addprefix -S../../,${SUBS}) $(if ${USR_DEPENDENCIES}, \
                           $(addprefix --user-dependency=,$(sort ${USR_DEPENDENCIES}))) \
                         '${PRJ}' '${EPICSVERSION}' '${T_A}' '${OS_CLASS}'

.dependencies_includes: ${OSHDRS} ${HDRS} ${COMPLETEDEPS}
	${QUIET}echo "Looking up dependencies"
	${QUIET}${GETPREREQUISITES} --make --recursive ${GETPREREQUISITES_FLAGS} > .dependencies_includes

-include .dependencies_includes

INCLUDES += ${DEPENDENCIES_INCLUDES}


SRC_INCLUDES = $(sort $(addprefix -I, ${BUILD_PATH}/${EPICSVERSION}/include ${BUILD_PATH}/${EPICSVERSION}/include/os/${OS_CLASS} $(dir ${SRCS:%=../../%} ${HEADERS:%=../../%} ${HEADERS_${OS_CLASS}:%=../../%} ${HEADERS_default:%=../../%} ${HDRS})))

SNC        = ${SNCSEQ}/${EPICSVERSION}/bin/$(EPICS_HOST_ARCH)/snc
SNC_CFLAGS = -I ${SNCSEQ}/${EPICSVERSION}/include

${BUILD_PATH}/${EPICSVERSION}/lib/${T_A}/%.so: %.so
	${QUIET}${INSTALL} -d -m 0644 $< $(@D)

build: ${PRJDBD} ${OSHDRS} ${HDRS} ${COMPLETEDEPS} ${PRJTMPLS} ${PRJSUBS} ${PROJECTDEP} ${PRJMSCS} ${PROJECTLIB} ${PRJEXECUTABLES} ${PRJDOC} ${PRJTESTS} ${PRJSTARTUPS} ${PRJOPIS}

debug: debug-out
	${GETPREREQUISITES} ${GETPREREQUISITES_FLAGS}

${BUILD_PATH}/misc/%: %
	${QUIET}echo "Copying misc $@"
	${QUIET}${INSTALL} -d -m 0644 $< $(@D)

${BUILD_PATH}/db/%: %
	${QUIET}echo "Copying db $@"
	${QUIET}${INSTALL} -d -m 0644 $< $(@D)

${BUILD_PATH}/doc/%: %
	${QUIET}echo "Copying doc $@"
	${QUIET}${INSTALL} -d -m 0644 $< $(@D)

${BUILD_PATH}/test/%: %
	${QUIET}echo "Copying test $@"
	${QUIET}${INSTALL} -d -m 0644 $< $(@D)

${BUILD_PATH}/startup/%: %
	${QUIET}echo "Copying startup snippet $@"
	${QUIET}${INSTALL} -d -m 0644 $< $(@D)

${BUILD_PATH}/opi/%: %
	${QUIET}echo "Copying opi file $@"
	${QUIET}${INSTALL} -d -m 0644 $< $(@D)

# The arguments to dbToRecordTypeH changed from 3.14 to 3.15
ifeq (${EPICS_MAJORMINOR}, 3.14)
%Record.h: %Record.dbd
	$(RM) $@; $(DBTORECORDTYPEH) $(USR_DBDFLAGS) $<
else ifeq (${EPICS_MAJORMINOR}, 3.15)
%Record.h: %Record.dbd
	$(RM) $@; $(DBTORECORDTYPEH) $(USR_DBDFLAGS) -o $(notdir $@) $<
endif

ifeq (${EPICS_MAJORMINOR}, 3.14)
menu%.h: menu%.dbd
	$(RM) $(notdir $@); $(DBTOMENUH) $(DBDFLAGS) $< $(notdir $@)
else ifeq (${EPICS_MAJORMINOR}, 3.15)
menu%.h: menu%.dbd
	$(RM) $(notdir $@); $(DBTOMENUH) $(DBDFLAGS) -o $(notdir $@) $<
endif

# Redefine MSI with full path.
MSI=${EPICS_BASE_HOST_BIN}/msi

DBFLAGS_DEPENDENCY := $(shell ${GETPREREQUISITES} --dbflags ${GETPREREQUISITES_FLAGS})

USR_DBFLAGS += $(addprefix -I,$(sort $(dir ${TMPLS:%=../../%}))) ${DBFLAGS_DEPENDENCY}

# MSI has different calling syntax on 3.14 and 3.15. The 3.15 version also knows how
# to generate Make dependency files.

define SUBSTITUTIONS_314_template
$${BUILD_PATH}/db/%.$${SUBSTITUTIONS_EXP_EXT}: %.${1}
	$${QUIET}$${MKDIR} -p $${@D}
	$${QUIET}echo "Expanding substitutions file $$@"
	$${QUIET}$$(RM) $$@
	$$(MSI) $$(DBFLAGS) -S$$< > $$*.tmp
	$$(MV) $$*.tmp $$@
endef

define SUBSTITUTIONS_template
$${BUILD_PATH}/db/%.$${SUBSTITUTIONS_EXP_EXT}: %.${1}
	$${QUIET}$${MKDIR} -p $${@D}
	$${QUIET}echo "Generating dependency file for substitutions file $$@"
	$$(MSI) $$(DBFLAGS) -D -o$$@ -S$$< > $$*.d
	$${QUIET}echo "Expanding substitutions file $$@"
	$${QUIET}$$(RM) $$@
	$$(MSI) $$(DBFLAGS) -S$$< > $$*.tmp
	$$(MV) $$*.tmp $$@
endef

ifeq (${EPICS_MAJORMINOR}, 3.14)
  $(foreach ext,${SUBSTITUTIONS_EXT},$(eval $(call SUBSTITUTIONS_314_template,${ext})))
else
  $(foreach ext,${SUBSTITUTIONS_EXT},$(eval $(call SUBSTITUTIONS_template,${ext})))
  -include *.d
endif

${BUILD_PATH}/${EPICSVERSION}/bin/${T_A}/%: %
	${QUIET}${MKDIR} -p ${@D}
	${QUIET}echo "Copying executable $@"
	${QUIET}$(CP) $< $@

# Build one dbd file by expanding all source dbd files.
# We can't use dbExpand (from the default EPICS make rules)
# because it does't allow undefined record types and menus and so on.
${PRJDBD}: ${DBDFILES}
	${QUIET}${MKDIR} -p $(dir ${PRJDBD})
	${QUIET}echo "Expanding $@ from $(filter %.dbd, $^)"
	${PYTHON} ${MAKEHOME}/expand_dbd.py ${EXPANDDBDFLAGS} -o $@ ${DBDEXPANDPATH} $(filter %.dbd, $^)

# Include default EPICS Makefiles (version dependent)
# avoid library installation when doing 'make build'
INSTALL_LOADABLE_SHRLIBS=
include ${BASERULES}

# The VPATHs are being cleared out in BASERULES. It is important to load them _after_ including BASERULES.
VPATH_HEADERS = $(addprefix ../../,$(dir $(filter-out /%,${HEADERS}))) $(dir $(filter /%,${HEADERS})) $(realpath $(addprefix ../../,$(addsuffix ..,$(dir $(foreach osclass,$(strip ${OS_CLASSES_SUFFIXES}),${HEADERS_${osclass}})))))
vpath %     ../.. $(addprefix ../../,$(sort $(dir $(OPIS_INT)) ${OPI_DIRS_INT})) $(addprefix ../../,${DOC_DIRS_INT} $(dir ${EXECUTABLES} ${SRCS} ${DOC_FILES_INT} ${TESTS} ${MISCS}))
vpath %.h   ${VPATH_HEADERS}
vpath %.hpp ${VPATH_HEADERS}
vpath %.dbd $(addprefix ../../,$(sort $(dir ${DBDFILES} ${MENUS})))

$(foreach ext,${TEMPLATE_EXT},\
  $(eval vpath %.${ext} $$(addprefix ../../,$$(dir $${TMPLS}))))
$(foreach ext,${SUBSTITUTIONS_EXT},\
  $(eval vpath %.${ext} $$(addprefix ../../,$$(dir $${TMPLS} $${SUBS}))))
$(foreach ext,${PROTOCOL_EXT},\
  $(eval vpath %.${ext} $$(addprefix ../../,$$(dir $${MSCS}))))
$(foreach ext,${STARTUP_EXT},\
  $(eval vpath %.${ext} $$(addprefix ../../,$$(dir $${STARTUPS_INT}))))

# Disable header install rule (RULES_BUILD:451) so that local header files won't override EPICS BASE header files
$(INSTALL_INCLUDE)/% : %

#Fix release rules
RELEASE_DBDFLAGS  = -I${EPICS_BASE}/dbd
RELEASE_INCLUDES  = -I${EPICS_BASE}/include
RELEASE_INCLUDES += -I${EPICS_BASE}/include/compiler/${CMPLR_CLASS}
RELEASE_INCLUDES += -I${EPICS_BASE}/include/os/${OS_CLASS}

# Create SNL code from st/stt file
# (RULES.Vx only allows ../%.st, 3.14 has no .st rules at all)
# Important to have %.o: %.st and %.o: %.stt rule before %.o: %.c rule!
# Preprocess in any case because docu and EPICS makefiles mismatch here

CPPSNCFLAGS1  = $(filter -D%, ${OP_SYS_CFLAGS})
CPPSNCFLAGS1 += $(filter-out ${OP_SYS_INCLUDE_CPPFLAGS} ,${CPPFLAGS}) ${CPPSNCFLAGS} ${SNC_CFLAGS}
SNCFLAGS     += -r -o $(*F).c

%$(OBJ) %.c %_snl.dbd: %.st
	${QUIET}echo "Preprocessing $*.st"
	$(RM) $(*F).i
	$(CPP) ${CPPSNCFLAGS1} $< > $(*F).i
	${QUIET}echo "Converting $(*F).i"
	$(RM) $(*F).c
	$(SNC) $(TARGET_SNCFLAGS) $(SNCFLAGS) $(*F).i
	${QUIET}echo "Compiling $(*F).c"
ifeq (${EPICSVERSION},3.14)
	$(COMPILE.c) ${SNC_CFLAGS} $(*F).c
else
	$(COMPILE.c) -c ${SNC_CFLAGS} $(*F).c
endif
	$(RM) $(*F)_snl.dbd
	${QUIET}echo "Building $(*F)_snl.dbd"
	${QUIET}awk '{if(match ($$0,/^[\t ]*epicsExportRegistrar\([\t ]*(\w+)[\t ]*\)/, a)){ print "registrar (" a[1] ")"}}' $(*F).c > $(*F)_snl.dbd

%$(OBJ) %.c %_snl.dbd: %.stt
	${QUIET}echo "Preprocessing $*.stt"
	$(RM) $(*F).i
	$(CPP) ${CPPSNCFLAGS1} $< > $(*F).i
	${QUIET}echo "Converting $(*F).i"
	$(RM) $(*F).c
	$(SNC) $(TARGET_SNCFLAGS) $(SNCFLAGS) $(*F).i
	${QUIET}echo "Compiling $(*F).c"
ifeq (${EPICSVERSION},3.14)
	$(COMPILE.c) ${SNC_CFLAGS} $(*F).c
else
	$(COMPILE.c) -c ${SNC_CFLAGS} $(*F).c
endif
	$(RM) $(*F)_snl.dbd
	${QUIET}echo "Building $(*F)_snl.dbd"
	${QUIET}awk '{if(match ($$0,/^[\t ]*epicsExportRegistrar\([\t ]*(\w+)[\t ]*\)/, a)){ print "registrar (" a[1] ")"}}' $(*F).c > $(*F)_snl.dbd

# Create GPIB code from gt file
%.c %.dbd %.list: %.gt
	${QUIET}echo "Converting $*.gt"
	${LN} $< $(*F).gt
	gdc $(*F).gt

# Create dbd file with references to all subRecord functions. Works with EPICS 3.14+.
# Requires 'epicsRegisterFunction()' calls to be on separate lines.
${SUBFUNCFILE}: $(filter %.c %.C %.cc %.cpp, $(SRCS))
	${QUIET}${MKDIR} -p $(dir ${SUBFUNCFILE})
	${QUIET}echo Generating $@ from exported functions in $^.
	${QUIET}awk '{if(match ($$0,/^[\t ]*epicsRegisterFunction\([\t ]*(\w+)[\t ]*\)/, a)){ print "function (" a[1] ")"}}' $^ > $@

${VERSIONFILE}:
	${QUIET}echo Generating $@
ifneq (${TESTVERSION},)
	${QUIET}echo "double epics_${PRJ}LibVersion = ${MAJOR}.${MINOR};" > $@
endif
	${QUIET}echo "char epics_${PRJ}LibRelease[] = \"${LIBVERSION}\";" >> $@

# EPICS 3.14+:
# Create file to fill registry from dbd file. Remove the call to iocshRegisterCommon because it is already called in softIoc.
# We can safely ignore warnings on 3.15.
ifeq (${EPICS_MAJORMINOR}, 3.14)
${REGISTRYFILE}: ${PRJDBD}
	$(RM) $@.tmp $@
	$(REGISTERRECORDDEVICEDRIVER) $< $(basename $@) | grep -v iocshRegisterCommon > $@.tmp
	$(MV) $@.tmp $@
else
${REGISTRYFILE}: ${PRJDBD}
	${RM} $@ $@.tmp
	$(REGISTERRECORDDEVICEDRIVER) $(REGRDDFLAGS) -l -o $@.tmp $< $(basename $@)
	${QUIET}cat $@.tmp | grep -v iocshRegisterCommon > $@
endif

${BUILD_PATH}/${EPICSVERSION}/include/${HEADERS_PREFIX}%.hpp: %.hpp
	${QUIET}echo "Copying $< $(@D)"
	${QUIET}$(INSTALL) -d -m 0644 $< $(@D)

${BUILD_PATH}/${EPICSVERSION}/include/${HEADERS_PREFIX}%.h: %.h
	${QUIET}echo "Copying $< $(@D)"
	${QUIET}$(INSTALL) -d -m 0644 $< $(@D)

define OS_SPECIFIC_HEADERS_template =
$${BUILD_PATH}/$${EPICSVERSION}/include/os/${1}/%.hpp: ${1}/%.hpp
	$${QUIET}echo "Copying $$< $$(@D)"
	$${QUIET}$$(INSTALL) -d -m 0644 $$< $$(@D)

$${BUILD_PATH}/$${EPICSVERSION}/include/os/${1}/%.h: ${1}/%.h
	$${QUIET}echo "Copying $$< $$(@D)"
	$${QUIET}$$(INSTALL) -d -m 0644 $$< $$(@D)
endef

$(foreach osclass,$(strip ${OS_CLASSES_SUFFIXES}),$(eval $(call OS_SPECIFIC_HEADERS_template,${osclass})))

# 3.14.12 complains if this rule is not overwritten
./%Include.dbd:

# 3.14.12.3 complaines if this rules is not overwritten
$(COMMON_DIR)/%Include.dbd:

CORELIB = ${CORELIB_${OS_CLASS}}

LSUFFIX_YES=$(SHRLIB_SUFFIX)
LSUFFIX_NO=$(LIB_SUFFIX)
LSUFFIX=$(LSUFFIX_$(SHARED_LIBRARIES))

DEPENDENCIES = $(shell ${GETPREREQUISITES} ${GETPREREQUISITES_FLAGS})

# Create dependency file for recursive requires
${PROJECTDEP}: ${LIBOBJS}
	${QUIET}${MKDIR} -p $(dir ${PROJECTDEP})
	${QUIET}echo "Collecting dependencies to $@"
	${QUIET}$(RM) $@
	${QUIET}echo "# Generated file. Do not edit." > $@
	${QUIET}for dep in ${DEPENDENCIES} ; do echo $$dep >> $@; done; true

endif # T_A defined
endif # OS_CLASS in BUILDCLASSES
endif # EPICSVERSION defined

# Cancel implicit rules for source control systems we don't use.
%:: s.%
%:: SCCS/s.%
%:: %,v
%:: RCS/%,v
%:: RCS/%
