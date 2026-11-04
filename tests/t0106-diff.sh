#!/bin/sh

test_description='Check content on diff page'
. ./setup.sh

test_expect_success 'generate foo/diff' 'cgit_url "foo/diff" >tmp'
test_expect_success 'find diff header' 'grep "a/file-5 b/file-5" tmp'
test_expect_success 'find blob link' 'grep "<a href=./foo/tree/file-5?id=" tmp'
test_expect_success 'find added file' 'grep "new file mode 100644" tmp'

test_expect_success 'find hunk header' '
	grep "<div class=.hunk.>@@ -0,0 +1 @@</div>" tmp
'

test_expect_success 'find added line' '
	grep "<div class=.add.>+5</div>" tmp
'

# max-diff-files keeps cgit from rendering diffs no one can read, which on a
# large repository take minutes and hundreds of megabytes of HTML. The cache is
# emptied so that pages rendered above, before the limit, are not served again.
test_expect_success 'setup a commit changing four files, with a limit of three' '
	(
		cd repos/foo &&
		for n in 1 2 3 4
		do
			echo changed >>file-$n || return 1
		done &&
		git commit -q -a -m "change four files"
	) &&
	echo "max-diff-files=3" >>cgitrc &&
	rm -rf cache && mkdir cache
'

test_expect_success 'a diff over the limit is refused' '
	cgit_url "foo/diff" >tmp &&
	grep "diff changes 4 files, which exceeds the display limit (3 files)" tmp &&
	! grep "class=.diffstat." tmp &&
	! grep "a/file-1 b/file-1" tmp
'

test_expect_success 'a stat-only diff over the limit is refused' '
	cgit_url "foo/diff&dt=2" >tmp &&
	grep "diff changes 4 files" tmp &&
	! grep "class=.diffstat." tmp
'

test_expect_success 'a commit over the limit keeps its message but not its diff' '
	cgit_url "foo/commit" >tmp &&
	grep "change four files" tmp &&
	grep "diff changes 4 files" tmp &&
	! grep "a/file-1 b/file-1" tmp
'

test_expect_success 'a diff exactly at the limit is shown' '
	new=$(cd repos/foo && git rev-parse HEAD~1) &&
	old=$(cd repos/foo && git rev-parse HEAD~4) &&
	cgit_url "foo/diff&id=$new&id2=$old" >tmp &&
	grep "a/file-5 b/file-5" tmp &&
	! grep "exceeds the display limit" tmp
'

test_expect_success 'a path brings a large diff under the limit' '
	cgit_url "foo/diff/file-1" >tmp &&
	grep "a/file-1 b/file-1" tmp &&
	! grep "exceeds the display limit" tmp
'

test_expect_success 'a path brings a large diff under the limit when following renames' '
	cat >>cgitrc <<-EOF &&
	repo.url=foo-follow
	repo.path=$PWD/repos/foo/.git
	repo.enable-follow-links=1
	EOF
	cgit_url "foo-follow/diff/file-1&follow=1" >tmp &&
	grep "a/file-1 b/file-1" tmp &&
	! grep "exceeds the display limit" tmp
'

test_expect_success 'rawdiff is not limited' '
	cgit_url "foo/rawdiff" >tmp &&
	grep "^diff --git a/file-1 b/file-1" tmp &&
	grep "^diff --git a/file-4 b/file-4" tmp
'

test_done
