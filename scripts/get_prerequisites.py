#!/usr/bin/env python2.7
#
# EPICS Environment Manager
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

"""This script is used to automatically detect dependencies between EPICS
modules. For dependency detection it will look into the c/c++-sources for any
included header files. It will also look in substitution files for any included
template files and finally it will look in the template files for custom record
types or device support types.

It will output the dependencies in different formats depending on
usage,
* for gcc: CFLAGS,
* for MSI: DBFLAGS, or
* for generating of a depfile.
"""

from __future__ import print_function
import argparse
import os
import re
import logging
from check_excludes import module_match

def module_key(version):
    """Key for sorting module versions with python built-in sorting algorithms."""
    ver = version.split('.', 2)
    if len(ver) == 3:
        return (int(ver[0]), int(ver[1]), int(ver[2]))
    return (0, 0, 0)

class DependencyResolver(object):
    """Finds EPICS modules dependencies by looking at
    *  the included headers
    *  included templates in substitution files
    *  record types and device support usage in template files.
    """

    # grep -e "recordtype(" /opt/epics/*/dbd/*Record.dbd | sed -r 's/^.*\((.*)\).*/\1/' | sort -u
    EPICS_BASE_RECORDS = ['aai', 'aao', 'ai', 'ao', 'aSub', 'bi', 'bo', 'calc', 'calcout', 'compress', 'dfanout',
                          'event', 'fanout', 'histogram', 'longin', 'longout', 'lsi', 'lso', 'mbbi', 'mbbiDirect',
                          'mbbo', 'mbboDirect', 'permissive', 'printf', 'sel', 'seq', 'state', 'stringin', 'stringout',
                          'sub', 'subArray', 'waveform']

    # grep -e "device(" /opt/epics/*/dbd/* | sed -r 's/^.*"(.*)".*/\1/' | sort -u
    EPICS_BASE_DEVICESUPPORTS = ['Async Soft Channel', 'Db State', 'General Time', 'Raw Soft Channel', 'Soft Channel',
                                 'Soft Timestamp', 'stdio', 'Test Asyn']

    def __init__(self, name, files, prefix, eb_version, ta, ud):
        logger = logging.getLogger(__name__)
        logger.info('Dependency resolver for {}'.format(name))
        self._name = name
        self._files = files
        self._prefix = prefix
        self._eb_version = eb_version
        self._ta = ta
        self._ud = ud
        self._dependencies = set()
        self._matches = {'headers':set(), 'records':set(), 'dtyps':set(), 'templates':set()}
        """If a dependency is user defined either:
        1. Use the version given.
        2. Find the appropriate installed version.
        3. It is a systems library, leave version empty.
        """
        for module in self._ud:
            tmp = module.rsplit(',', 1)
            modulename = tmp[0]
            if len(tmp) == 2:
                moduleversion = tmp[1]
            else:
                moduleversion = module_version(modulename, epics_base_version=self._eb_version, target_arch=self._ta)
            if re.search(r'[^A-Za-z0-9_]', modulename):
                logger.warning('Library {} contains unsupported characters'.format(modulename))
            if modulename == self._name:
                continue # Can't depend on ourselves.
            self._dependencies.add((modulename, moduleversion))

    def resolve(self):
        """Search all source files for includes, template files for custom
        records / device types and substitution files for external templates.
        First find all kinds of matches in sources, then look for matches in
        the installed modules.
        """
        logger = logging.getLogger(__name__)
        for dfile in self._files['dep']:
            if not os.path.isfile(dfile):
                logger.debug('Wasn\'t a dfile {}'.format(dfile))
                continue # Ignore missing files, probably being called during generation of dc-file..
            with open(dfile, 'r') as filehandler:
                for line in filehandler:
                    for match in re.finditer(r'(?<=\s)([^/][^\s]*\.h)', line):
                        self._matches['headers'].add(match.group(1))

        for dbfile in self._files['db']:
            if not os.path.isfile(dbfile):
                logger.debug('Wasn\'t a dbfile: {}'.format(dbfile))
                continue # Probably generated template dbfile
            with open(dbfile, 'r') as filehandler:
                last_record = ''
                for line in filehandler:
                    match = re.match(r'\s*record\s*\(\s*"?([^\s",]+),', line)
                    if match is not None:
                        last_record = match.group(1)
                        if match.group(1) not in self.EPICS_BASE_RECORDS:
                            self._matches['records'].add(match.group(1))
                        else:
                            logger.debug('Skipping: {}'.format(match.group(1)))
                    match = re.match(r'^\s*field\(\s*DTYP\s*,\s*"?([^"]+)"?\s*\)', line)
                    if match is not None:
                        if match.group(1) not in self.EPICS_BASE_DEVICESUPPORTS:
                            self._matches['dtyps'].add((last_record, match.group(1)))
                        else:
                            logger.debug('Skipping: {}'.format(match.group(1)))

        for subsfile in self._files['subs']:
            if not os.path.isfile(subsfile):
                logger.debug('Wasn\'t a subsfile: {}'.format(subsfile))
                continue # Probably generated subs subsfile
            with open(subsfile, 'r') as filehandler:
                for line in filehandler:
                    match = re.match(r'^\s*file\s*"?([^"\s]+)"?', line)
                    if match is not None:
                        self._matches['templates'].add(match.group(1))

        for installed_module in os.listdir(self._prefix):
            modulepath = os.path.join(self._prefix, installed_module)
            if installed_module == self._name:
                continue # Don't depend on ourselves.
            if self.depends_on(installed_module):
                continue # Already depends on this module.
            if not os.path.isdir(modulepath) or os.path.islink(modulepath):
                continue # Sanity check
            for version in os.listdir(modulepath):
                if not os.path.isdir(os.path.join(modulepath, version)):
                    continue # Sanity check
                if not re.match(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$', version):
                    logger.info('Skipping {} {}, not MAJOR.MINOR.PATCH format'.format(installed_module, version))
                    continue # Only allow dependencies on stable versions
                logger.info('Checking against {} {}'.format(installed_module, version))
                db_dir = os.path.join(modulepath, version, 'db')
                header_dir = os.path.join(modulepath, version, self._eb_version, 'include')
                dbd_file = os.path.join(modulepath, version, self._eb_version, 'dbd', '{}.dbd'.format(installed_module))
                if os.path.isdir(header_dir):
                    if self.find_headers(header_dir):
                        self.add_dependency(installed_module)
                        break
                if os.path.isfile(dbd_file):
                    if self.find_records(dbd_file):
                        self.add_dependency(installed_module)
                        break
                    if self.find_dtyps(dbd_file):
                        self.add_dependency(installed_module)
                        break
                if os.path.isdir(db_dir):
                    if self.find_templates(db_dir):
                        self.add_dependency(installed_module)
                        break

    def add_dependency(self, modulename):
        """Add modulename to list of dependencies."""
        logger = logging.getLogger(__name__)
        if modulename in [module.rsplit(',', 1)[0] for module in self._ud]:
            return # Module was already manually listed
        self._dependencies.add((
            modulename, module_version(modulename, epics_base_version=self._eb_version, target_arch=self._ta)))
        logger.info('Found dependency on {}'.format(modulename))

    def depends_on(self, modulename):
        """Test if modulename already is listed amongst dependencies."""
        return modulename in [x[0] for x in self._dependencies]

    def find_headers(self, common_dir):
        """Find any of the matched header files in the common_dir directory."""
        logger = logging.getLogger(__name__)
        for header in self._matches['headers']:
            logger.debug('  header: {}'.format(header))
            for root, _, files in os.walk(common_dir):
                for headerfile in files:
                    includename = os.path.join(root[len(common_dir)+1:], headerfile)
                    if includename == header or headerfile == header:
                        logger.info('Found dependency on header {}'.format(header))
                        return True
        return False

    def find_records(self, dbd_file):
        """Find any of the matched records in the dbd_file file"""
        logger = logging.getLogger(__name__)
        for record in self._matches['records']:
            logger.debug('  record: {}'.format(record))
            with open(dbd_file) as filehandler:
                for line in filehandler:
                    if 'recordtype({})'.format(record) in line:
                        logger.info('Found dependency on record {}'.format(record))
                        return True
        return False

    def find_dtyps(self, dbd_file):
        """Find any of the matched device support types in the dbd_file file"""
        logger = logging.getLogger(__name__)
        for dtyp in self._matches['dtyps']:
            logger.debug('    dtyp: {}'.format(dtyp))
            with open(dbd_file) as filehandler:
                for line in filehandler:
                    if re.match(r'^device\s*\(\s*{}[^"]*"{}"\)'.format(dtyp[0], dtyp[1]), line) is not None:
                        logger.info('Found dependency on dtyp {}'.format(dtyp))
                        return True
        return False

    def find_templates(self, db_dir):
        """Find any of the matched templates in the db_dir directory"""
        logger = logging.getLogger(__name__)
        for template in self._matches['templates']:
            logger.debug('template: {}'.format(template))
            for templfile in os.listdir(db_dir):
                if templfile == template:
                    logger.info('Found dependency on template {}'.format(templfile))
                    return True
        return False

    def list_deps(self):
        """Return a copy of the dependencies"""
        return self._dependencies.copy()


def module_version(module, comp_version='', epics_base_version='', target_arch=''):
    """Look for version in the following order:
    1. Architecture dependent default file
    2. Architecture independent default file
    3. Highest installed version.
    """
    logger = logging.getLogger(__name__)
    epics_base = os.path.join(os.environ['EPICS_BASES_PATH'], 'base-{}'.format(epics_base_version))

    arch_default = os.path.join(epics_base, 'configure', 'default.{}.dep'.format(target_arch))
    if os.path.isfile(arch_default):
        version = search_dep_file(arch_default, module)
        if version:
            return version

    epics_default = os.path.join(epics_base, 'configure', 'default.dep')
    if os.path.isfile(epics_default):
        version = search_dep_file(epics_default, module)
        if version:
            return version

    installed_versions = set()
    module_dir = os.path.join(os.environ['EPICS_MODULES_PATH'], module)
    if os.path.isdir(module_dir):
        for version in os.listdir(module_dir):
            depfile = os.path.join(module_dir, version, epics_base_version, 'lib',
                                   target_arch, '{}.dep'.format(module))
            if os.path.isfile(depfile) and re.match(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$', version):
                installed_versions.add(version)

    if installed_versions:
        sorted_installed_versions = sorted(installed_versions, key=module_key)
        for version in reversed(sorted_installed_versions):
            if module_match(comp_version, version):
                return version

    logger.debug('No version found for module {}'.format(module))

    return None

def search_dep_file(depfile, module):
    """depfile should contain lines of '<module>,<version>'."""
    with open(depfile, 'r') as filehandler:
        for line in filehandler:
            lsplit = line.strip().rsplit(',', 1)
            if lsplit[0] == module:
                return lsplit[1]
    return None

def recursive_solve(module, args, depth=10):
    """Recursive solve is only implemented for headers."""
    logger = logging.getLogger(__name__)
    if depth == 0:
        logger.warning('Reached depth 10, not looking further.')
        return set()
    depth = depth-1
    deps = set()
    deps.add(module)
    if not module[1]:
        return deps # No version, it can only be a system library.
    module_path = os.path.join(args.prefix, module[0], module[1], args.epicsbase, 'include')
    if not os.path.isdir(module_path):
        logger.debug('Could not find {}'.format(module_path))
        return deps
    depfile = os.path.join(os.environ['EPICS_MODULES_PATH'], module[0],
                           module[1], args.epicsbase, 'lib', args.targetarch,
                           '{}.dep'.format(module[0]))
    if not os.path.isfile(depfile):
        logger.warning('Could not find {}'.format(depfile))
        return deps

    with open(depfile) as depfilefh:
        for line in depfilefh:
            depmodule = line.strip().split(',')
            if len(depmodule) == 2:
                rmodule = (depmodule[0], module_version(depmodule[0], depmodule[1], args.epicsbase, args.targetarch))
            else:
                rmodule = (depmodule[0], module_version(depmodule[0], '', args.epicsbase, args.targetarch))
            deps |= recursive_solve(rmodule, args, depth)

    return deps

def format_dbflags(modules, prefix):
    """Format the modules for MSI."""
    res = ' '
    for module in modules:
        if module[1]:
            temp = os.path.join(prefix, module[0], module[1], 'db')
            res += '-I{} '.format(temp)
    return res

def format_make(modules, epics_base, prefix, osclass):
    """Format the modules for make."""
    res = 'DEPENDENCIES_INCLUDES = '
    for module in modules:
        if module[1]:
            temp = os.path.join(prefix, module[0], module[1], epics_base, 'include')
            res += '-I{} '.format(temp)
            temp = os.path.join(prefix, module[0], module[1], epics_base, 'include', 'os', osclass)
            res += '-I{} '.format(temp)
            temp = os.path.join(prefix, module[0], module[1], epics_base, 'include', 'os', 'default')
            res += '-I{} '.format(temp)
    return res

def format_cflags(modules, epics_base, prefix, osclass):
    """Format the modules for c/c++ compiler."""
    res = ' '
    for module in modules:
        if module[1]:
            temp = os.path.join(prefix, module[0], module[1], epics_base, 'include')
            res += '-I{} '.format(temp)
            temp = os.path.join(prefix, module[0], module[1], epics_base, 'include', 'os', osclass)
            res += '-I{} '.format(temp)
            temp = os.path.join(prefix, module[0], module[1], epics_base, 'include', 'os', 'default')
            res += '-I{} '.format(temp)
    return res

def format_dep(modules):
    """Format the modules for the dependency file."""
    res = ''
    for module in modules:
        if module[1]:
            version = module[1].split('.')
            if len(version) > 1:
                res += '{},{}.{}+\n'.format(module[0], version[0], version[1])
            elif len(version) == 1:
                res += '{},{}\n'.format(module[0], version[0])
        else:
            res += '{}\n'.format(module[0])
    return res

def format_vpath(modules, epics_base, prefix, osclass):
    """Format the modules for vpath."""
    res = ' '
    for module in modules:
        print(module[0])
        if module[1]:
            res += os.path.join(prefix, module[0], module[1], epics_base, 'include')
            res += ' '
            res += os.path.join(prefix, module[0], module[1], epics_base, 'include', 'os', osclass)
            res += ' '
            res += os.path.join(prefix, module[0], module[1], epics_base, 'include', 'os', 'default')
            res += ' '
    return res

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Find dependencies on other EPICS modules')
    parser.add_argument('--d-file', '-D', action='append', default=[], help='Makefile (.d) files to parse')
    parser.add_argument('--tmpl-file', '-T', action='append', default=[], help='Source db files to parse')
    parser.add_argument('--subs-file', '-S', action='append', default=[], help='Source sub files to parse')
    parser.add_argument('--prefix', metavar='DIR',
                        help='Installation prefix '
                        '(default {})'.format(os.environ['EPICS_MODULES_PATH']),
                        default='{}'.format(os.environ['EPICS_MODULES_PATH']))
    parser.add_argument('name', help='Name of EPICS module')
    parser.add_argument('epicsbase', help='EPICS base version')
    parser.add_argument('targetarch', help='EPICS target architecture')
    parser.add_argument('osclass', help='EPICS target architecture')
    parser.add_argument('--make', action='store_true',
                        help='Output appropriate for make.')
    parser.add_argument('--vpath', action='store_true',
                        help='Output appropriate for vpath.')
    parser.add_argument('--cflags', action='store_true',
                        help='Output appropriate for CFLAGS.')
    parser.add_argument('--dbflags', action='store_true',
                        help='Output appropriate for DBFLAGS.')
    parser.add_argument('--recursive', action='store_true',
                        help='Recursive dependencies.')
    parser.add_argument('--user-dependency', action='append', default=[],
                        help='Add any user specified dependency <name>[,<version>]. '
                        'Can be system libraries. Overrides any detected depedency.')
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--info', action='store_true')
    args = parser.parse_args()

    if args.debug:
        logging.getLogger(__name__).setLevel(logging.DEBUG)
    elif args.info:
        logging.getLogger(__name__).setLevel(logging.INFO)

    files = {'dep': args.d_file, 'db': args.tmpl_file, 'subs': args.subs_file}

    dpres = DependencyResolver(args.name, files, args.prefix, args.epicsbase, args.targetarch,
                               args.user_dependency)
    dpres.resolve()
    deps = set()

    if args.recursive:
        for module in dpres.list_deps():
            deps |= recursive_solve(module, args)
    else:
        deps = dpres.list_deps()

    if args.cflags:
        print(format_cflags(deps, args.epicsbase, args.prefix, args.osclass))
    elif args.make:
        print(format_make(deps, args.epicsbase, args.prefix, args.osclass))
    elif args.dbflags:
        print(format_dbflags(deps, args.prefix))
    elif args.vpath:
        print(format_vpath(deps, args.epicsbase, args.prefix, args.osclass))
    else:
        print(format_dep(deps))

if __name__ == '__main__':
    logging.basicConfig(format='%(filename)s: %(message)s')
    main()
