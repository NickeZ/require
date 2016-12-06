#!/usr/bin/env sh
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
#
# Author: Niklas Claesson <niklas.claesson@esss.se>
#
# This is a helper script to generate a list of all the sources in the correct
# format. This is usually not necessary to run, but can be convenient when
# adapting some external modules for the EPICS Environment.

function myfind {
	find . \( "$@" \) -not \( -path "./O.*" -o -path "./builddir/*" \) | sort
}

cat <<-'EOF'
	include ${EPICS_ENV_PATH}/module.Makefile
	EOF

echo ""

sources=$(myfind -name "*.c" -o -name "*.cpp" -o -name "*.cc")

headers=$(myfind -name "*.h" -o -name "*.hpp")

dbds=$(myfind -name "*.dbd")

sh=""

for src in $sources; do
    sh+="SOURCES += ${src:2}"$'\n'
done

for hdr in $headers ; do
    sh+="HEADERS += ${hdr:2}"$'\n'
done

sort_sh=$(echo "$sh" | sort -k3)

echo "$sort_sh"

echo ""

for dbd in $dbds ; do
    echo DBDS += ${dbd:2}
done
