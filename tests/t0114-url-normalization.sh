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

test_expect_success 'path= touched by the commit is kept' '
	tip=$(cd repos/foo && git rev-parse HEAD) &&
	cgit_url "foo/commit&id=$tip&path=file-5" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'path= not touched by the commit is redirected to the pathless URL' '
	tip=$(cd repos/foo && git rev-parse HEAD) &&
	cgit_url "foo/commit&id=$tip&path=file-1" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /foo/commit?id=$tip\$" output
'

test_expect_success 'the same untouched path= is redirected on diff, patch and rawdiff too' '
	tip=$(cd repos/foo && git rev-parse HEAD) &&
	for page in diff patch rawdiff
	do
		cgit_url "foo/$page&id=$tip&path=file-1" >output &&
		grep -q "^Status: 301 Moved" output &&
		grep -q "^Location: /foo/$page?id=$tip\$" output || return 1
	done
'

test_expect_success 'an arbitrary two-revision diff (id2= set) is never redirected for path=' '
	tip=$(cd repos/foo && git rev-parse HEAD) &&
	root=$(cd repos/foo && git rev-list --reverse HEAD | head -1) &&
	cgit_url "foo/diff&id=$tip&id2=$root&path=file-1" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'path= on tree, which gives path a different meaning, is never redirected' '
	cgit_url "foo/tree&path=file-1" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'an untouched path carried as PATH_INFO redirects to the pathless URL, not itself' '
	tip=$(cd repos/foo && git rev-parse HEAD) &&
	cgit_path_info "/foo/commit/file-1" "id=$tip" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /foo/commit?id=$tip\$" output
'

test_done
