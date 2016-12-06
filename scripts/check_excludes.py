#!/usr/bin/env python2.7
# pylint: disable=eval-used
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

""" This script is used to determine if an EPICS version should be excluded. It
compares several conditions to the module version and prints the EPICS
version if any is True. Given condition A, condition B and version X it will
be evaluated as (XA || XB).

For example, to exclude 3.15 for version numbers outside the range 1.0 to 2.0, the following arguments would be given:
    --version X --epics-base 3.15 --condition <1.0 --condition >2.0

TODO:
* Argument to switch between or/and behavior.
"""

from __future__ import print_function
import collections
import argparse
import re
import logging

EpicsModule = collections.namedtuple('EpicsModule', 'major minor patch exact')

def module_compare(lhs, rhs, comp):
    """Compare two modules, lhs and rhs, with comp comparator"""
    logger = logging.getLogger(__name__)
    logger.debug('{} {} {} '.format(lhs, comp, rhs))
    if comp == '<' or comp == '>':
        return (eval('lhs.major {} rhs.major'.format(comp)) or
                (lhs.major == rhs.major and eval('lhs.minor {} rhs.minor'.format(comp))) or
                (lhs.major == rhs.major and lhs.minor == rhs.minor and
                 eval('lhs.patch {} rhs.patch'.format(comp))))
    if comp == '<=' or comp == '>=':
        return (eval('lhs.major {} rhs.major'.format(comp[0])) or
                (lhs.major == rhs.major and eval('lhs.minor {} rhs.minor'.format(comp[0]))) or
                (lhs.major == rhs.major and lhs.minor == rhs.minor and
                 eval('lhs.patch {} rhs.patch'.format(comp[0]))) or
                (lhs.major == rhs.major and lhs.minor == rhs.minor and lhs.patch == rhs.patch))
    if comp == '=':
        return lhs.major == rhs.major and lhs.minor == rhs.minor and lhs.patch == rhs.patch

def version_to_tup(version):
    """Converts version string on format "MAJOR.MINOR.PATCH" to named tuple. If any
    value is missing it will be substituted with a zero.
    """
    matches = re.match(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\+?)', version)
    if matches is not None:
        return EpicsModule(int(matches.group(1)), int(matches.group(2)), int(matches.group(3)), not matches.group(4) == '+')
    matches = re.match(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\+?)', version)
    if matches is not None:
        return EpicsModule(int(matches.group(1)), int(matches.group(2)), 0, not matches.group(3) == '+')
    matches = re.match(r'(0|[1-9][0-9]*)(\+?)', version)
    if matches is not None:
        return EpicsModule(int(matches.group(1)), 0, 0, not matches.group(2) == '+')
    return EpicsModule(0, 0, 0, False)

def check(version, conditions):
    """Returns true if any condition is true compared to version, otherwise false"""
    logger = logging.getLogger(__name__)
    matches = re.match(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version)
    if matches is None or len(matches.groups()) != 3:
        logger.debug('Not valid version ({})'.format(version))
        return False
    for condition in conditions:
        matches = re.match(r'^([<>]=?|=)([\d\.]*)(\+?)$', condition)
        if matches is None:
            logger.warning('Illigal condition ({}) always returns False.'.format(condition))
            return False
        comp = matches.group(1)
        rversion = matches.group(2)
        if len(matches.groups()) == 3 and matches.group(3) == '+':
            comp = ">="
        if module_compare(version_to_tup(version), version_to_tup(rversion), comp):
            logger.debug('True')
            return True
    return False

def module_match(version, other):
    """This function will return true IFF other is high enough for version."""
    ver = version_to_tup(version) if isinstance(version, str) else version
    oth = version_to_tup(other) if isinstance(other, str) else other
    return ver.major == 0 or (
        ver.exact and (
            (ver.minor == 0 and oth.major == ver.major) or
            (ver.patch == 0 and oth.major == ver.major and oth.minor == ver.minor) or
            (ver.major == ver.major and oth.minor == ver.minor and oth.patch == ver.patch)
            )
        ) or (
        not ver.exact and (
            (ver.minor == 0 and oth.major >= ver.major) or
            (ver.patch == 0 and oth.major == oth.major and oth.minor >= ver.minor) or
            (oth.major == ver.major and oth.minor == ver.minor and oth.patch >= ver.patch)));

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Output EPICS base version if any condition is true.')
    parser.add_argument('--version', required=True, help='Version of EPICS module.')
    parser.add_argument('--condition', action='append', help='Condition, e.g., "<1.0".')
    parser.add_argument('--epics-base', required=True, help='EPICS base version.')
    parser.add_argument('--debug', action='store_true', help='Enable debug.')
    args = parser.parse_args()

    if args.debug:
        logging.getLogger(__name__).setLevel(logging.DEBUG)

    if check(args.version, args.condition or []):
        print(args.epics_base)

if __name__ == '__main__':
    logging.basicConfig(format='%(filename)s: %(message)s')
    main()
