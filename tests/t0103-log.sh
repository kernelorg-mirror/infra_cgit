#!/bin/sh

test_description='Check content on log page'
. ./setup.sh

test_expect_success 'generate foo/log' 'cgit_url "foo/log" >tmp'
test_expect_success 'find commit 1' 'grep "commit 1" tmp'
test_expect_success 'find commit 5' 'grep "commit 5" tmp'

test_expect_success 'generate bar/log' 'cgit_url "bar/log" >tmp'
test_expect_success 'find commit 1' 'grep "commit 1" tmp'
test_expect_success 'find commit 50' 'grep "commit 50" tmp'

test_expect_success 'generate "with%20space/log?qt=grep&q=commit+1"' '
	cgit_url "with+space/log&qt=grep&q=commit+1" >tmp
'
test_expect_success 'find commit 1' 'grep "commit 1" tmp'
test_expect_success 'find link with %20 in path' 'grep "/with%20space/log/?qt=grep" tmp'
test_expect_success 'find link with + in arg' 'grep "/log/?qt=grep&amp;q=commit+1" tmp'
test_expect_success 'no links with space in path' '! grep "href=./with space/" tmp'
test_expect_success 'no links with space in arg' '! grep "q=commit 1" tmp'
test_expect_success 'commit 2 is not visible' '! grep "commit 2" tmp'

test_expect_success 'setup a repo with a merge' '
	test_create_repo repos/merge &&
	(
		cd repos/merge &&
		echo base >base &&
		git add base &&
		git commit -m "base commit" &&
		git checkout -b side &&
		for f in side-1 side-2 side-3
		do
			echo $f >$f || return 1
		done &&
		git add side-* &&
		git commit -m "side commit" &&
		git checkout master &&
		echo main >main &&
		git add main &&
		git commit -m "main commit" &&
		git merge --no-ff -m "merge side" side
	) &&
	cat >>cgitrc <<-EOF
	repo.url=merge
	repo.path=$PWD/repos/merge/.git
	EOF
'

# A merge diffed against its first parent counts every change on the merged
# branch, which on large projects costs seconds per log page. git log --stat
# shows no stat for merges either.
test_expect_success 'merges have no file or line counts in the log' '
	cgit_url "merge/log" >tmp &&
	grep "merge side" tmp >row &&
	grep "</td><td></td><td></td></tr>\$" row
'

test_expect_success 'non-merge commits still have file and line counts' '
	grep "side commit" tmp >row &&
	grep "<td>3</td><td><span class=.deletions.>-0</span>/<span class=.insertions.>+3</span></td></tr>\$" row
'

test_done
