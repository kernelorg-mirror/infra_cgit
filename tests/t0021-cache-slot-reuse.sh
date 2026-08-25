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

test_done
