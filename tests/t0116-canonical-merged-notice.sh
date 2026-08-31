#!/bin/sh

test_description='Verify the abbreviated notice on commit/diff pages a canonical repository publishes'
. ./setup.sh

# Same grokmirror-style deduplication as t0113: a fork sharing bar's object
# database, so every commit of bar's has a valid URL under the fork too.
mkfork() {
	git clone -q --shared --bare repos/bar/.git "repos/$1.git"
}

# A commit that exists only in the fork, so the canonical repository has no
# copy of it and cannot claim it.
mkforkonly() {
	(
		cd "repos/$1.git" &&
		blob=$(echo LOCAL | git hash-object -w --stdin) &&
		tree=$( { git ls-tree HEAD; printf "100644 blob %s\tLOCAL\n" "$blob"; } |
			git mktree) &&
		git commit-tree -p HEAD -m "FORKONLY" "$tree"
	)
}

test_expect_success 'setup' '
	mkfork fork &&
	forkonly=$(mkforkonly fork) &&
	shared=$(cd repos/bar && git rev-parse HEAD) &&
	cat >>cgitrc <<-EOF &&
	repo.url=fork
	repo.path=$PWD/repos/fork.git
	repo.desc=a fork of bar
	EOF
	cat >>cgitrc <<-EOF
	canonical-repo=bar
	EOF
'

test_expect_success 'commit page shows the notice instead of the message and diff' '
	cgit_url "fork/commit/&id=$shared" >output &&
	grep -q "This commit has been merged to bar" output &&
	grep -q "View in the target repository" output &&
	! grep -q "files changed" output
'

test_expect_success 'commit page still shows the metadata table and subject' '
	cgit_url "fork/commit/&id=$shared" >output &&
	grep -q "<th>author</th>" output &&
	grep -q "<th>committer</th>" output &&
	grep -q "<th>commit</th>" output &&
	grep -q "<th>tree</th>" output &&
	grep -q "<th>parent</th>" output &&
	grep -q "commit-subject" output
'

test_expect_success 'the notice links to the same commit in the canonical repo' '
	cgit_url "fork/commit/&id=$shared" >output &&
	grep -q "href=./bar/commit/?id=$shared." output
'

test_expect_success 'diff page shows the notice instead of the diffstat and diff' '
	cgit_url "fork/diff/&id=$shared" >output &&
	grep -q "This diff has been merged to bar" output &&
	! grep -q "diffstat-header" output
'

test_expect_success "the diff page's notice links to the same diff in the canonical repo" '
	cgit_url "fork/diff/&id=$shared" >output &&
	grep -q "href=./bar/diff/?id=$shared." output
'

test_expect_success 'other query parameters survive on the notice link, minus id= and r=' '
	cgit_url "fork/commit/&id=$shared&context=9" >output &&
	grep -q "href=./bar/commit/?id=$shared&amp;context=9." output
'

test_expect_success 'a note in the fork survives on the abbreviated commit page' '
	(cd repos/fork.git && git notes add -m "fork-local note" $shared) &&
	rm -rf cache && mkdir cache &&
	cgit_url "fork/commit/&id=$shared" >output &&
	grep -q "This commit has been merged to bar" output &&
	grep -q "notes-header" output &&
	grep -q "fork-local note" output
'

test_expect_success 'a commit the canonical repo does not have is rendered in full' '
	cgit_url "fork/commit/&id=$forkonly" >output &&
	grep -q "FORKONLY" output &&
	! grep -q "merged to" output
'

test_expect_success 'a diff the canonical repo does not have is rendered in full' '
	cgit_url "fork/diff/&id=$forkonly" >output &&
	! grep -q "merged to" output
'

test_expect_success 'the canonical repo itself renders its own commit in full' '
	cgit_url "bar/commit/&id=$shared" >output &&
	! grep -q "merged to" output
'

test_expect_success 'a repository sharing nothing with the canonical repo is unaffected' '
	cgit_url "foo%2bbar/commit/" >output &&
	grep -q "add a+b" output &&
	! grep -q "merged to" output
'

test_done
