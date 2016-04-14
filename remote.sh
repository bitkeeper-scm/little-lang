#!/bin/bash
# Copyright 2003-2010,2012-2016 BitMover, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

umask 0

BK_NOTTY=YES
export BK_NOTTY

test X$LOG = X && LOG=LOG-$BK_USER
cd /build
chmod +w .$REPO.$BK_USER
BKDIR=${REPO}-${BK_USER}
CMD=$1
test X$CMD = X && CMD=build

host=`uname -n | sed 's/\.bitkeeper\.com//'`
START="/build/.start-$BK_USER"
ELAPSED="/build/.elapsed-$BK_USER"

# XXX Compat crud, simplify after _timestamp and _sec2hms
#     are integrated and installed on the cluster
bk _timestamp >/dev/null 2>&1
if [ $? -eq 0 ]
then
	TS="bk _timestamp"
else
	TS="date +%s"
fi

failed() {
	test x$1 = x-f && {
		__outfile=$2
		shift;shift;
	}
	case "X$BASH_VERSION" in
		X[234]*) eval 'echo failed in line $((${BASH_LINENO[0]} - $BOS))';;
		*) echo failed ;;
	esac
	test "$*" && echo $*
	test "$__outfile" && {
		echo ----------
		cat "$__outfile"
		echo ----------
	}
	echo '*****************'
	echo '!!!! Failed! !!!!'
	echo '*****************'
	exit 1
}

case $CMD in
    build|save|release|trial|nightly)
	eval $TS > $START
	exec 3>&2
	exec > /build/$LOG 2>&1
	set -e
	rm -rf /build/$BKDIR
	test -d .images && {
		find .images -type f -mtime +3 -print > .list$BK_USER
		test -s .list$BK_USER && xargs /bin/rm -f < .list$BK_USER
		rm -f .list$BK_USER
	}
	sleep 5		# give the other guys time to get rcp'ed and started

	ulimit -c unlimited 2>/dev/null
	bk clone $URL $BKDIR

	DOTBK=`bk dotbk`
	test "X$DOTBK" != X && rm -f "$DOTBK/lease/`bk gethost -r`"

	cd $BKDIR
	bk -U^G get -qT || true
	make bin-tar || failed
	#make src-tar || failed

	# this should never match because it will cause build to exit
	# non-zero
	#grep "Not your lucky day, " /build/$LOG >/dev/null && exit 1

	test -d /build/.little-images || mkdir /build/.little-images
	cp little-*.tar.gz /build/.little-images

	DEST="/home/bk/images/little/"
	if [ X$OSTYPE = Xmsys -o X$OSTYPE = Xcygwin ] ; 
	then	# we're on Windows
		KEYSRC=/build/ssh-keys/images.key
		KEY=images.key.me
		## Make sure the permissions are right for the key
		cp $KEYSRC $KEY || { echo failed to cp $KEYSRC; exit 1; }
		chmod 600 $KEY
		trap "rm -f '$KEY'" 0 1 2 3 15
		CP="scp -i $KEY"
	else
		CP=cp
	fi
	# Copy the images
	$CP /build/.little-images/little-*.tar.gz $DEST || {
		echo "Could not $CP $IMG to $DEST"
		exit 1
	}
	# Leave the directory there only if they asked for a saved build
	test $CMD = save || {
		cd /build	# windows won't remove .
		rm -rf /build/$BKDIR
		# XXX - I'd like to remove /build/.bk-3.0.x.regcheck.lm but I
		# can't on windows, we have it open.
		test X$OSTYPE = Xcygwin || rm -f /build/.${BKDIR}.$BK_USER
	}
	rm -rf /build/.tmp-$BK_USER
	test $CMD = nightly && {
		# make status happy
		echo "All requested tests passed, must be my lucky day"
	}
	;;

    clean)
	rm -rf /build/$BKDIR /build/$LOG
	;;

    status)
	TEST=`sed -n 's/^ERROR: Test \(.*\) failed with.*/\1/p' < $LOG | head -1`
	test -n "$TEST" && {
		echo regressions failed starting with $TEST
		exit 1
	}

	# grep -q is not portable so we use this
	tail -1 $LOG | grep "^Done$" >/dev/null && {
		echo succeeded.
		exit 0
	}

	grep '!!!! Failed! !!!!' $LOG >/dev/null && {
		if grep "^====" $LOG >/dev/null
		then	echo regressions failed.
		else	echo failed to build.
		fi
		exit 1
	}
	echo is not done yet.
	;;

    log)
	cat $LOG
	;;
esac
exit 0
