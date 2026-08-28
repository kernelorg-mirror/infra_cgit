#!/bin/sh

test_description='Verify redirects that collapse redundant URL spellings'
. ./setup.sh

test_expect_success 'h= equal to the default branch is dropped' '
	cgit_url "foo/log&h=master" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /foo/log\$" output
'

test_expect_success 'h= naming a non-default branch is kept' '
	cgit_url "foo+bar/log&h=1%2b2" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'h= naming the default branch is dropped alongside id= too' '
	tip=$(cd repos/foo && git rev-parse HEAD) &&
	cgit_url "foo/commit&h=master&id=$tip" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /foo/commit?id=$tip\$" output
'

test_expect_success 'h= naming another branch alongside id= is left alone' '
	tip=$(cd repos/foo && git rev-parse HEAD) &&
	cgit_url "foo/commit&h=shadow&id=$tip" >output &&
	! grep -q "^Status: 301" output
'

# Deciding which branch a commit belongs to costs a history walk, so cgit only
# does it where the operator has enabled the reachability check. 'pinned'
# publishes the same repository with that check on, alongside a branch holding
# a commit that is on no other.
test_expect_success 'setup a repository that resolves h= against id=' '
	(
		cd repos/foo &&
		git branch other master &&
		git checkout -q -b side &&
		echo side >side.txt &&
		git add side.txt &&
		git commit -q -m "only on side" &&
		git checkout -q master
	) &&
	cat >>cgitrc <<-EOF
	repo.url=pinned
	repo.path=$PWD/repos/foo/.git
	repo.desc=reachability checked
	repo.enable-object-reachability-check=1
	EOF
'

test_expect_success 'a commit on the default branch drops the branch that named it' '
	tip=$(cd repos/foo && git rev-parse master) &&
	cgit_url "pinned/commit&h=side&id=$tip" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /pinned/commit?id=$tip\$" output
'

test_expect_success 'a commit only on the named branch keeps it' '
	side=$(cd repos/foo && git rev-parse side) &&
	cgit_url "pinned/commit&h=side&id=$side" >output &&
	! grep -q "^Status: 30" output &&
	grep -q "only on side" output
'

test_expect_success 'a commit on neither branch is refused' '
	side=$(cd repos/foo && git rev-parse side) &&
	cgit_url "pinned/commit&h=other&id=$side" >output &&
	grep -q "^Status: 404 Not found" output &&
	grep -q "is not on branch other" output
'

test_expect_success 'a two-revision diff across branches is served anyway' '
	side=$(cd repos/foo && git rev-parse side) &&
	tip=$(cd repos/foo && git rev-parse master) &&
	cgit_url "pinned/diff&h=other&id=$side&id2=$tip" >output &&
	! grep -q "^Status: 404" output &&
	grep -q "diff --git a/side.txt b/side.txt" output
'


test_expect_success 'a request naming only h= without a repository default mismatch is otherwise untouched' '
	cgit_url "foo/log" >output &&
	! grep -q "^Status: 301" output
'

test_done
