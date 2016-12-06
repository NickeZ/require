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

"""This script is used to generate an EPICS module's DBD file. It will go
through each given file, line by line, and remove comments and expand any "included"
DBD files recursively. If a project has several DBD files but all are included
in a "super" DBD file, it is therefore enough to simply list the "super" DBD
file.

A special case is the "dbCommon.dbd" which is allowed to be included multiple times.

This script can also be used to emit any record definitions that would have
been included in the final DBD file. A record definition is defined as a file
named %Record.dbd containing a line 'recordtype(%)'.
"""

from __future__ import print_function
import argparse
import re
import os
import logging

class ExpandDBD(object):
    """Class containing module functionality."""
    def __init__(self, target, includedir=None, list_records=False):
        self._includedir = includedir
        if target:
            self._outputfile = open(target, 'w')
        else:
            self._outputfile = None
        self._list_records = list_records
        # Keep a list of added files so that a file never is included twice.
        self._added_files = []
        # Compile commonly used regexes
        self._re = {
            'recdef':  re.compile(r'^\s*recordtype\s*\("?([^"]*)"?\)'),
            'include': re.compile(r'^\s*include\s*"?([^"\s]+)"?'),
            'record':  re.compile(r'^(.*?)Record.dbd')
            }

    def add_dbd(self, dbd):
        """Add a dbd to be concatenated and expanded."""
        logger = logging.getLogger(__name__)
        if dbd not in self._added_files and dbd is not None:
            logger.debug('Including {}'.format(dbd))
            # Allow dbCommon.dbd to be included multiple times.
            # This happens when multiple records are defined in the same dbd.
            if not dbd.endswith('dbCommon.dbd'):
                self._added_files.append(dbd)
            with open(dbd, 'r') as inputfile:
                for line in inputfile:
                    # Skip any comment lines.
                    if line.strip().startswith(('#', '%')):
                        continue

                    # Find record definition.
                    match = self._re['recdef'].search(line)
                    if (match is not None and
                            self._list_records and is_record(dbd, match.group(1))):
                        dbdname = os.path.basename(dbd)
                        subm = self._re['record'].search(dbdname)
                        if subm is not None:
                            print(subm.group(1))

                    # Find includes.
                    match = self._re['include'].search(line)
                    if match is not None:
                        dbdfile = self.find(match.group(1))
                        if dbdfile != None:
                            self.add_dbd(dbdfile)
                            continue

                    # Print the read line to the output file. Remove quote
                    # characters because they are not supported everywhere.
                    if self._outputfile:
                        if 'variable' in line or 'registrar' in line:
                            line = re.sub(r'"([^ \t]*)"', r'\1', line)
                        self._outputfile.write(line)

    def find(self, dbd):
        """Find the dbd file in any of the include paths."""
        logger = logging.getLogger(__name__)
        for directory in self._includedir:
            full_name = os.path.join(directory, dbd)
            if os.path.isfile(full_name):
                return full_name
        logger.debug('Include {} not found'.format(dbd))
        return None

def is_record(filename, recordname):
    """Determine if 'filename' file contains a record definition of 'recordname'.
    Special case: acalcout doesn't follow the naming convention, and thus '.lower()' is needed.
    """
    logger = logging.getLogger(__name__)
    logger.debug('Checking if {} is a record defined in {}'.format(recordname, filename))
    if os.path.isfile(filename):
        with open(filename, 'r') as filehandler:
            for line in filehandler:
                if 'recordtype({})'.format(recordname) in line or 'recordtype({})'.format(recordname.lower()) in line:
                    return True
    else:
        logger.debug('No file: {}'.format(filename))
    return False

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Concatenate DBD files')
    parser.add_argument('-o', '--output-file', metavar='file', help='Output file')
    parser.add_argument('files', metavar='DBD file', nargs='+', help='Input files')
    parser.add_argument('-I', '--include-dir', metavar='dir', action='append',
                        help='Paths to search for included files')
    parser.add_argument('--list-records', action='store_true', help='List all records.')
    parser.add_argument('--debug', action='store_true', help='Enable debug.')
    args = parser.parse_args()

    if args.debug:
        logging.getLogger(__name__).setLevel(logging.DEBUG)

    edbd = ExpandDBD(args.output_file, args.include_dir, args.list_records)

    for dbdfile in args.files:
        edbd.add_dbd(dbdfile)

if __name__ == '__main__':
    logging.basicConfig(format='%(filename)s: %(message)s')
    main()
