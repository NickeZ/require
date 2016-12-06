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

"""This script generates the correct module version string from the sources. If
the code is in a git repository, use the information from the repository.
"""

from __future__ import print_function
import getpass
import subprocess
import argparse
import os
import re
import logging

class SemverVersion(object): # pylint: disable=too-few-public-methods
    """Container object for Semver version"""
    def __init__(self, version, prerelease='', metadata=''):
        self.major = version[0]
        self.minor = version[1]
        self.patch = version[2]
        self.prerelease = '-{}'.format(prerelease) if prerelease else ''
        self.metadata = '-{}'.format(metadata) if metadata else ''

    def __repr__(self):
        return '{}.{}.{}{}{}'.format(self.major, self.minor, self.patch, self.prerelease, self.metadata)

    def __eq__(self, other):
        return (self.major, self.minor, self.patch, self.prerelease, self.metadata) == (
            other.major, other.minor, other.patch, other.prerelease, other.metadata)

    def __lt__(self, other):
        if (self.major, self.minor, self.patch) == (other.major, other.minor, other.patch):
            if not self.prerelease:
                # Not having a prerelease tag means that 'self' always is not lesser
                return False
            if not other.prerelease:
                # Not having a prerelease tag means that 'other' always is lesser
                return True
            # If both have prerelease tags, order dot-separated identifiers alphabetically
            return self.prerelease.split('.') < other.prerelease.split('.')
        else:
            return (self.major, self.minor, self.patch) < (other.major, other.minor, other.patch)


def git_version():
    """True if we have git."""
    try:
        output = subprocess.check_output(['git', '--version'])
        return output[11:].strip().split('.')
    except OSError:
        return None
    except subprocess.CalledProcessError:
        return None

def git_in_repo():
    """True if we are in a git directory."""
    return subprocess.call(['git', 'rev-parse'], stdout=FNULL, stderr=FNULL) == 0

def git_dirty():
    """True if any files have been modified but not committed."""
    diff = subprocess.check_output(['git', 'ls-files', '-m'], stderr=FNULL)
    if diff.strip():
        return True
    return False

def git_on_tag():
    """True if there is a tag pointing to the currently checked out commit."""
    tag = git_last_tag()
    if tag:
        commit_range = '{}..HEAD'.format(tag)
        commits = subprocess.check_output(['git', 'log', commit_range, '--oneline'], stderr=FNULL)
        if commits:
            return False
        return True
    return False

def git_unique_description():
    """Return short version of commit sha256 sum."""
    return subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'], stderr=FNULL).strip()

def git_last_tag():
    """Get the most recent tag if there is any."""
    try:
        tag = subprocess.check_output(['git', 'describe', '--tags', '--abbrev=0'], stderr=FNULL).strip()
    except subprocess.CalledProcessError:
        tag = None
    return tag

def git_tags_points_to_head():
    """Returns a string list of all tags that points to current HEAD."""
    git_ver = git_version()
    if git_ver[0] > 1 or (git_ver[0] > 0 and git_ver[1] > 7) or (git_ver[0] > 0 and git_ver[1] > 7 and git_ver[2] > 9):
        # This feature (--points-at) requires git v1.7.10
        tags = subprocess.check_output(['git', 'tag', '--points-at', 'HEAD']).strip().split('\n')
    else:
        tags = subprocess.check_output(
            'git log -n1 --pretty="format:%d" | sed "s/, /\\n/g" | grep tag: | sed "s/tag: \\|)//g"'
            ).strip().split('\n')
    if tags == ['']:
        return []
    return tags


def getuser():
    """Return real username even if user is using sudo"""
    user = getpass.getuser()
    if user == 'root' or 'SUDO_USER' in os.environ:
        env_vars = ['SUDO_USER', 'USER', 'USERNAME']
        for evar in env_vars:
            if evar in os.environ:
                return os.environ[evar]
    return user

def parse_tag(tag, site_prefix):
    """Parses tag according to semver, taking into account a site specific prefix"""
    major = 0
    minor = 0
    patch = 0
    prerelease = ''
    metadata = ''

    matches = re.search(r'\+([A-Za-z0-9.\-]+)', tag)
    if matches:
        metadata = matches.group(1)

    matches = re.search(r'-([A-Za-z0-9.\-]+)', tag)
    if matches:
        prerelease = matches.group(1)

    matches = re.match(site_prefix + r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', tag)
    if matches:
        major = matches.group(1)
        minor = matches.group(2)
        patch = matches.group(3)
    else:
        matches = re.match(site_prefix + r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', tag)
        if matches:
            major = matches.group(1)
            minor = matches.group(2)
        else:
            matches = re.match(site_prefix + r'(0|[1-9][0-9]*)', tag)
            if matches:
                major = matches.group(1)
            else:
                return None
    return SemverVersion((major, minor, patch), prerelease, metadata)


def main():
    """Main function"""

    parser = argparse.ArgumentParser(description='Get version from username or VCS')
    parser.add_argument('--prefix', help='Prefix added to semver matching', default='')
    parser.add_argument('--nightly', action='store_true',
                        help='Use a unique representation of repo instead of username as named version')
    parser.add_argument('--debug', action='store_true')
    args = parser.parse_args()

    logging.basicConfig(format='%(filename)s: %(message)s')
    logger = logging.getLogger(__name__)
    if args.debug:
        logger.setLevel(logging.DEBUG)

    user = getuser()

    # dash is used to separate module from version in some circumstances and cannot be part of version.
    username = user.replace('-', '_')
    if user != username:
        logger.warning('Username contained illigal characters and was changed to {}.'.format(username))

    git_ver = git_version()

    if git_ver and git_in_repo():
        logger.debug('in repo')
        is_dirty = git_dirty()
        if args.nightly:
            if is_dirty:
                print('dirty')
                return
            elif not git_on_tag():
                print(git_unique_description())
                return

        if is_dirty:
            logger.debug('is dirty')
            print(username)
            return

        valid_tags = [parse_tag(x, args.prefix) for x in git_tags_points_to_head()]

        if valid_tags:
            sorted_valid_tags = sorted(valid_tags)
            logger.debug('sorted_valid_tags: {}'.format(sorted_valid_tags))
            print(sorted_valid_tags[-1])
            return
        logger.debug('no tags present which match the regular expression')

    # We are not in a git repository, not on a tag or tag didn't match.
    print(username)

if __name__ == "__main__":
    FNULL = open(os.devnull, 'w')
    main()
    FNULL.close()
