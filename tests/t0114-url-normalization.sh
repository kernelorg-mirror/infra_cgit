#!/bin/sh

test_description='Verify redirects that collapse redundant URL spellings'
. ./setup.sh

test_expect_success 'setup' '
	(
		cd repos/foo &&
		git branch shadow &&
		git tag shadow master
	)
'

test_expect_success 'h= equal to the default branch is dropped' '
	cgit_url "foo/log&h=master" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /foo/log\$" output
'

test_expect_success 'h= naming a non-default branch is kept' '
	cgit_url "foo+bar/log&h=1%2b2" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'h= alongside id= is dropped even when h= names the default branch' '
	tip=$(cd repos/foo && git rev-parse HEAD) &&
	cgit_url "foo/commit&h=master&id=$tip" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /foo/commit?id=$tip\$" output
'

test_expect_success 'a request naming only h= without a repository default mismatch is otherwise untouched' '
	cgit_url "foo/log" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'refs/heads/ is collapsed to the branch name' '
	cgit_url "foo%2bbar/log&h=refs%2fheads%2f1%2b2" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /foo+bar/log?h=1%2B2\$" output
'

test_expect_success 'refs/heads/ is left alone when a same-named tag would shadow it' '
	cgit_url "foo/log&h=refs%2fheads%2fshadow" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'a plain branch name with no refs/heads/ prefix is untouched' '
	cgit_url "foo%2bbar/log&h=1%2b2" >output &&
	! grep -q "^Status: 301" output
'

test_done
