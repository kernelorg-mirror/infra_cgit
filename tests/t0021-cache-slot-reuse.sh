#!/bin/sh

test_description='Verify that a cache slot never serves stale content'
. ./setup.sh

# With cache-size=1 every key hashes onto the same slot, which makes the
# slot filename deterministic and lets us plant content in it.
slot=cache/00000000
lock=$slot.lock
junk=JUNKJUNKJUNKJUNKJUNKJUNKJUNK

# Simulate a slot left behind by a process that was killed while filling
# it: a key that does not match, followed by far more content than the
# page we are about to generate.
plant_junk() {
	printf 'stale-key\0' >"$1" &&
	for i in $(test_seq 1 2000)
	do
		echo "$junk"
	done >>"$1"
}

test_expect_success 'setup' '
	rm -f cache/* &&
	sed -e "s/^cache-size=.*/cache-size=1/" cgitrc >cgitrc.tmp &&
	mv -f cgitrc.tmp cgitrc &&
	cgit_url "foo/refs" >/dev/null &&
	test -f "$slot"
'

test_expect_success 'a stale lock file is not inherited by the next page' '
	rm -f cache/* &&
	plant_junk "$lock" &&
	cgit_url "foo/refs" >output &&
	! grep -q "$junk" output &&
	test "$(tail -n 1 output)" = "</html>"
'

test_expect_success 'no stale content is left behind in the slot' '
	! grep -q "$junk" "$slot" &&
	cgit_url "foo/refs" >output.cached &&
	! grep -q "$junk" output.cached &&
	test "$(tail -n 1 output.cached)" = "</html>"
'

# The lock file can be renamed over the cache slot by the process that
# holds it in the window between our open() and our F_SETLK. The lock we
# then acquire is on the live cache file, and filling it clobbers a slot
# other processes are streaming. CGIT_TEST_LOCK_DELAY widens that window
# so we can perform the rename at exactly the wrong moment.
rename_lock_during_fill() {
	CGIT_TEST_LOCK_DELAY=2 cgit_url "foo/refs" >output.race &
	cgit_pid=$!
	sleep 1
	mv "$lock" "$slot"
	wait $cgit_pid
}

test_expect_success 'a slot renamed away mid-lock is left alone' '
	rm -f cache/* &&
	plant_junk "$lock" &&
	rename_lock_during_fill &&
	grep -q "$junk" "$slot"
'

test_done
