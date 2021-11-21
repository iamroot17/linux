#!/bin/sh
# Copyright (c) 2007-2015 The OpenRC Authors.
# See the Authors file at the top-level directory of this distribution and
# https://github.com/OpenRC/openrc/blob/master/AUTHORS
#
# This file is part of OpenRC. It is subject to the license terms in
# the LICENSE file found in the top-level directory of this
# distribution and at https://github.com/OpenRC/openrc/blob/master/LICENSE
# This file may not be copied, modified, propagated, or distributed
#    except according to the terms contained in the LICENSE file.

: ${CONSOLE:=/dev/console}
: ${RC_LIBEXECDIR:=/lib/rc}

service_present()
{
	local p="/etc/runlevels/$1/$2"
	# fail if the file doesn't exist
	[ ! -e "$p" ] && return 1
	# succeed if $RC_SYS empty, can't check further, assume script will run
	[ -z "$RC_SYS" ] && return 0
	# fail if file contains "-$RC_SYS", because then it won't run
	grep -Eqi "^[[:space:]]*keyword[[:space:]].*-$RC_SYS([[:space:]]|$)" "$p" && return 1
	# succeed otherwise
	return 0
}

if [ -e "$RC_LIBEXECDIR"/console/unicode ]; then
	termencoding="%G"
	kmode="-u"
else
	termencoding="(K"
	kmode="-a"
fi

# Set the SELinux label on console before everything so we dont lose output
[ -x /sbin/restorecon ] && /sbin/restorecon -F /dev/console

# Try and set a font and as early as we can
if service_present "$RC_DEFAULTLEVEL" consolefont ||
   service_present "$RC_BOOTLEVEL" consolefont; then
	printf "\033%s" "$termencoding" >"$CONSOLE" 2>/dev/null
	if [ -r "$RC_LIBEXECDIR"/console/font ] && \
		command -v setfont > /dev/null 2>&1; then
		[ -c "$CONSOLE" ] && cons="-C $CONSOLE"
		setfont $cons "$RC_LIBEXECDIR"/console/font 2>/dev/null
	fi
fi

# Try and set a keyboard map as early as possible
if service_present "$RC_DEFAULTLEVEL" loadkeys ||
   service_present "$RC_BOOTLEVEL" loadkeys; then
	kbd_mode $kmode -C "$CONSOLE" 2>/dev/null
	if [ -r "$RC_LIBEXECDIR"/console/keymap ]; then
		loadkeys -q "$RC_LIBEXECDIR"/console/keymap 2>/dev/null
	fi
fi

# Ensure we exit 0 so the boot continues
exit 0
