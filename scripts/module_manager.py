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

"""This script is run when the user calls 'make install'. It will identify what
has been built and then install it accordingly. There is also the option to
reinstall or uninstall.
"""

from __future__ import print_function
import argparse
import os
import sys
import shutil
import re

def installed_ta(moduledir):
    """Look into moduledir and figure out which epics versions and architectures are built
    by locating the dep-files.
    """
    res = []

    if not os.path.isdir(moduledir):
        return res

    for root, _, files in os.walk(moduledir):
        for name in files:
            if name.endswith('.dep'):
                regex = os.sep.join((r'([\d\.]+)', 'lib', '(.+)'))
                matches = re.search(regex, root)
                if matches:
                    res.append(matches.group(1, 2))
    return res

class ModuleManager(object):
    """Install, uninstall or reinstall an EPICS module."""

    def __init__(self, name, version, prefix, builddir, dry_run):
        self._name = name
        self._version = version
        self._prefix = prefix
        self._builddir = builddir
        self._dry_run = dry_run
        self._install_path = os.path.join(prefix, name, version)
        if not os.path.isdir(prefix):
            raise Exception('Module directory "{}" does not exist.'.format(prefix))

        # Identify which EPICS versions and architectures was built.
        self._targets = installed_ta(self._builddir)

        # Identify which EPICS versions and architectures that are installed
        self._installed = installed_ta(self._install_path)

    def copy(self, source, target):
        """Wrapper of copy to allow dry run"""
        if not self._dry_run:
            # Use copyfile since we might not have permission to change mode/stat.
            shutil.copyfile(source, target)
            # We have to try to set the executable bit on bins..
            if os.sep.join(('', 'bin', '')) in target:
                shutil.copymode(source, target)
        else:
            print('Copy file {} to {}'.format(source, target))

    def mkdir(self, path):
        """Wrapper of mkdir to allow dry run"""
        if not self._dry_run:
            os.makedirs(path)
        else:
            print('Creating directory {}'.format(path))

    def copy_files(self, endswith):
        """Finds files which are in paths that ends with 'endswith' and installs them to the install path.
        Ignores file if it is in a directory named O.*.
        """
        for root, _, files in os.walk(self._builddir):
            for name in files:
                if root.rsplit(os.path.sep, 1)[1].startswith('O.'):
                    continue
                if root.endswith(endswith):
                    rel_root = root[len(self._builddir)+1:]
                    if not os.path.isdir(os.path.join(self._install_path, rel_root)):
                        self.mkdir(os.path.join(self._install_path, rel_root))
                    self.copy(os.path.join(root, name), os.path.join(self._install_path, rel_root, name))

    def copy_recursive(self, path):
        """Finds files which are in paths that contains '/path/'.
        """
        for root, _, files in os.walk(self._builddir):
            for name in files:
                if root.rsplit(os.path.sep, 1)[1].startswith('O.'):
                    continue
                if os.sep.join(('', path, '')) in root or root.endswith(path):
                    rel_root = root[len(self._builddir)+1:]
                    if not os.path.isdir(os.path.join(self._install_path, rel_root)):
                        self.mkdir(os.path.join(self._install_path, rel_root))
                    self.copy(os.path.join(root, name), os.path.join(self._install_path, rel_root, name))

    def install(self, yes):
        """Look for recognized files in the buildpath and copy them to the
        install location.
        """
        if self._installed:
            if not yes:
                install_common = raw_input(
                    'This version is already installed. Do you want to replace the common files (Y,n)? ')
            else:
                install_common = 'y'
        else:
            self.mkdir(self._install_path)
            install_common = 'y'

        not_currently_installed = set(self._targets).difference(self._installed)
        currently_installed = set(self._targets).intersection(self._installed)

        if install_common in ('', 'y', 'Y'):
            # Install common files
            self.copy_files(('db', 'dbd', 'doc', 'misc', 'startup'))
            # Headers/OPIs are special because they can have subdirectories
            self.copy_recursive('include')
            self.copy_recursive('opi')

        # EPICS/ARCH combinations that can be installed immediately.
        for epics_ver, arch in not_currently_installed:
            self.copy_files(arch)

        # EPICS/ARCH combinations to be replaced
        for epics_ver, arch in currently_installed:
            if not yes:
                install_arch = raw_input('{}, {} is already installed. Reinstall (Y,n)? '.format(epics_ver, arch))
            else:
                install_arch = 'y'

            if install_arch in ('', 'y', 'Y'):
                self.copy_files(arch)


    def uninstall(self, yes):
        """Removes the given version of the module, also removes the module directory if it was the only version."""
        if not os.path.isdir(self._install_path):
            raise Exception('Not installed')
        if not self._dry_run:
            if not yes:
                answer = raw_input('Are you sure you want to uninstall (Y,n)? ')
            else:
                answer = 'y'
            if answer in ('', 'y', 'Y'):
                shutil.rmtree(self._install_path)
            if len(os.listdir(os.path.dirname(self._install_path))) == 0:
                os.rmdir(os.path.dirname(self._install_path))
        else:
            print('Remove {}'.format(self._install_path))

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Install EPICS module')
    parser.add_argument('action', choices=['install', 'uninstall', 'reinstall'],
                        help='Select action to execute. Install will overwrite existing installation. ' \
			     'Uinstall will remove the version. Reinstall will first uninstall and then install.')
    parser.add_argument('name', help='Name of EPICS module.')
    parser.add_argument('version', help='Version of EPICS module.')
    parser.add_argument('--arch', action='append', help='Architecture to install (default install all).')
    parser.add_argument('--prefix', metavar='DIR',
                        help='Installation prefix (default {})'.format(os.environ['EPICS_MODULES_PATH']),
                        default='{}'.format(os.environ['EPICS_MODULES_PATH']))
    parser.add_argument('--builddir',
                        help='Path to module build directory. (default builddir)',
                        default='builddir')
    parser.add_argument('-n', '--dry-run', action='store_true',
                        help='Print actions instead of execute.')
    parser.add_argument('-y', '--assumeyes', action='store_true',
                        help='Assume yes. Assume that the answer to any question is yes.')
    parser.add_argument('--assumeno', action='store_true',
                        help='Assume no. Assume that the answer to any question is no.')
    args = parser.parse_args()

    installer = ModuleManager(args.name, args.version, args.prefix, args.builddir, args.dry_run)

    if args.action == 'install':
        print('Installing module {}, version {}'.format(args.name, args.version))
        try:
            installer.install(args.assumeyes)
        except Exception as why:
            print('Unable to install: {}'.format(why))
            sys.exit(-1)
    elif args.action == 'reinstall':
        print('Reinstalling module {}, version {}'.format(args.name, args.version))
        try:
            installer.uninstall(args.assumeyes)
            installer.install(args.assumeyes)
        except Exception as why:
            print('Unable to reinstall: {}'.format(why))
            sys.exit(-1)
    elif args.action == 'uninstall':
        print('Unstalling module {}, version {}'.format(args.name, args.version))
        try:
            installer.uninstall(args.assumeyes)
        except Exception as why:
            print('Unable to uninstall: {}'.format(why))
            sys.exit(-1)


if __name__ == '__main__':
    main()
