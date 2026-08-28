#!/bin/sh

test_description='Check content on commit page'
. ./setup.sh

test_expect_success 'generate foo/commit' 'cgit_url "foo/commit" >tmp'
test_expect_success 'find tree link' 'grep "<a href=./foo/tree/.>" tmp'
test_expect_success 'find parent link' 'grep -E "<a href=./foo/commit/\?id=.+>" tmp'

test_expect_success 'find commit subject' '
	grep "<div class=.commit-subject.>commit 5<" tmp
'

test_expect_success 'find commit msg' 'grep "<div class=.commit-msg.></div>" tmp'
test_expect_success 'find diffstat' 'grep "<table summary=.diffstat. class=.diffstat.>" tmp'

test_expect_success 'find diff summary' '
	grep "1 files changed, 1 insertions, 0 deletions" tmp
'

test_expect_success 'get root commit' '
	root=$(cd repos/foo && git rev-list --reverse HEAD | head -1) &&
	cgit_url "foo/commit&id=$root" >tmp &&
	grep "</html>" tmp
'

test_expect_success 'root commit contains diffstat' '
	grep "<a href=./foo/diff/file-1.id=[0-9a-f]\{40,64\}.>file-1</a>" tmp
'

test_expect_success 'root commit contains diff' '
	grep ">diff --git a/file-1 b/file-1<" tmp &&
	grep "<div class=.add.>+1</div>" tmp
'

test_expect_success 'generate foo+bar/commit on a non-default branch' '
	tip=$(cd repos/foo+bar && git rev-parse HEAD) &&
	cgit_url "foo%2bbar/commit&h=1%2b2&id=$tip" >tmp
'

test_expect_success 'redundant h= alongside id= is redirected away' '
	tip=$(cd repos/foo+bar && git rev-parse HEAD) &&
	grep -q "^Status: 301 Moved" tmp &&
	grep -q "^Location: /foo+bar/commit?id=$tip\$" tmp
'

test_expect_success 'pinned commit is still resolved without h=' '
	tip=$(cd repos/foo+bar && git rev-parse HEAD) &&
	cgit_url "foo%2bbar/commit&id=$tip" >tmp &&
	grep "<div class=.commit-subject.>add a+b<" tmp
'

test_expect_success 'verify no link carries both h= and id=' '
	tr "<" "\n" <tmp | grep -o "href=[^>]*" >links &&
	! grep -E "[?&;]id=" links | grep -qE "[?&;]h="
'

test_done
