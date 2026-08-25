#!/bin/sh

test_description='Check that the cached repolist recovers from a stale lockfile'
. ./setup.sh

# With scan-path, cgit caches the discovered repolist in an "rc-" file below
# cache-root and refreshes it from a forked child once it is older than
# cache-scanrc-ttl. That refresh used to serialize on the mere existence of a
# lockfile, so a cgit process which died before it could rename the lockfile
# into place left the lockfile behind for good: every later refresh quietly
# gave up on it, and a repository which had since been removed stayed in the
# repolist forever.

scan_url() {
	CGIT_CONFIG="$PWD/cgitrc.scan" QUERY_STRING="url=$1" cgit
}

# The refresh runs in a forked child, so poll for its result rather than
# assuming it has already finished.
wait_for_rescan() {
	i=0
	while test $i -lt 10
	do
		grep -q "^repo.url=doomed" cache-scan/rc-* || return 0
		sleep 1
		i=$((i + 1))
	done
	return 1
}

warm_repolist() {
	rm -rf scan cache-scan &&
	mkdir -p cache-scan &&
	git init -q --bare scan/keep.git &&
	git init -q --bare scan/doomed.git &&
	scan_url "" >/dev/null &&
	grep -q "^repo.url=doomed" cache-scan/rc-*
}

test_expect_success 'setup' '
	cat >cgitrc.scan <<-EOF
	virtual-root=/
	cache-root=$PWD/cache-scan
	cache-size=1021
	cache-scanrc-ttl=0
	scan-path=$PWD/scan
	EOF
'

test_expect_success 'a removed repository leaves an expired repolist' '
	warm_repolist &&
	rm -rf scan/doomed.git &&
	sleep 1 &&
	scan_url "" >/dev/null &&
	wait_for_rescan
'

test_expect_success 'a stale lockfile does not pin the repolist' '
	warm_repolist &&
	rm -rf scan/doomed.git &&
	for rc in cache-scan/rc-*
	do
		: >"$rc.lock" || return 1
	done &&
	sleep 1 &&
	scan_url "" >/dev/null &&
	wait_for_rescan
'

test_expect_success 'the stale lockfile is not left behind' '
	test -z "$(ls cache-scan/rc-*.lock 2>/dev/null)"
'

test_expect_success 'the surviving repository is still listed' '
	grep -q "^repo.url=keep" cache-scan/rc-*
'

test_done
