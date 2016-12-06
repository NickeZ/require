#!/usr/bin/env python2.7

"""Python script to delete logfiles and signalling procServ to reopen logfiles."""

from __future__ import print_function
import os
import sys
import argparse
import subprocess


def main(args):
    """Main function"""
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    args = parser.parse_args(args)

    try:
        out = subprocess.check_output(['du', '-s', '/var/log/procServ'])
    except OSError as why:
        print('Failed to call "du" {}'.format(why))
        return 1

    # "du" will return size in kbytes
    (size, _) = out.split()
    # Convert string to int
    size = int(size)
    # If logfiles consume more than 50 MB. Throw them away..
    if size > 50000:
        print('Cleaning up logfiles and signalling procServ')
        for (root, _, filenames) in os.walk('/var/log/procServ'):
            for name in filenames:
                try:
                    os.remove(os.path.join(root, name))
                except OSError as why:
                    print('Failed to remove {}: {}'.format(os.path.join(root, name), why))
                    return 2
        try:
            subprocess.call(['pkill', '-SIGHUP', 'procServ'])
        except OSError as why:
            print('Failed to call "pkill" {}'.format(why))
            return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
