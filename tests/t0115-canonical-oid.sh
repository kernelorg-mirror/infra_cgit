#!/bin/sh

test_description='Verify that an abbreviated id= is redirected to its full form'
. ./setup.sh

test_expect_success 'setup' '
	tip=$(cd repos/foo && git rev-parse HEAD) &&
	echo "$tip" >tip &&
	echo "${tip%${tip#??????}}" >tip-abbrev
'

test_expect_success 'an abbreviated id= is redirected to the full oid' '
	tip=$(cat tip) &&
	abbrev=$(cat tip-abbrev) &&
	cgit_url "foo/commit&id=$abbrev" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /foo/commit?id=$tip\$" output
'

test_expect_success 'a full id= is left alone' '
	tip=$(cat tip) &&
	cgit_url "foo/commit&id=$tip" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'id=HEAD is left alone, not pinned to a commit' '
	cgit_url "foo/commit&id=HEAD" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'an abbreviated id2= alongside a full id= is redirected too' '
	tip=$(cat tip) &&
	root=$(cd repos/foo && git rev-list --reverse HEAD | head -1) &&
	abbrev_root=$(echo "$root" | cut -c1-8) &&
	cgit_url "foo/diff&id=$tip&id2=$abbrev_root" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /foo/diff?id=$tip&id2=$root\$" output
'

test_expect_success 'an ambiguous abbreviation is left for cgit to report as such' '
	cgit_url "foo/commit&id=0" >output &&
	! grep -q "^Status: 301" output
'

test_done
