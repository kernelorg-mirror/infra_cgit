#!/bin/sh

test_description='Verify canonical-repo'
. ./setup.sh

# Two repositories that share an object database with "bar", which is what
# grokmirror-style deduplication produces: every object of the repository they
# were forked from is readable from both, so every one of its commits has a
# valid URL under either of them.
mkfork() {
	git clone -q --shared --bare repos/bar/.git "repos/$1.git"
}

# A commit that exists only in the fork, so that the canonical repository has
# no copy of it and cannot claim it.
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
	mkfork stable &&
	forkonly=$(mkforkonly fork) &&
	shared=$(cd repos/bar && git rev-parse HEAD) &&
	older=$(cd repos/bar && git rev-parse HEAD~5) &&
	cat >>cgitrc <<-EOF
	repo.url=fork
	repo.path=$PWD/repos/fork.git
	repo.desc=a fork of bar

	repo.url=stable
	repo.path=$PWD/repos/stable.git
	repo.desc=another canonical repo
	EOF
'

test_expect_success 'a shared commit is served when no canonical repo is set' '
	cgit_url "fork/commit/&id=$shared" >output &&
	grep -q "commit 50" output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'declare the canonical repositories' '
	rm -rf cache && mkdir cache &&
	cat >>cgitrc <<-EOF
	canonical-repo=foo
	canonical-repo=bar
	canonical-repo=stable
	EOF
'

test_expect_success 'a shared object is redirected out of the fork' '
	cgit_url "fork/patch/&id=$shared" >output &&
	grep -q "^Status: 301 Moved" output &&
	grep -q "^Location: /bar/patch/?id=$shared\$" output
'

test_expect_success 'an earlier canonical repo without the object is skipped' '
	cgit_url "fork/patch/&id=$older" >output &&
	grep -q "^Location: /bar/patch/?id=$older\$" output
'

# Both "bar" and "stable" publish the shared commit, so which of them the fork
# redirects to is decided by nothing but their order in the configuration.
test_expect_success 'the first canonical repo publishing the object wins' '
	grep -v "^canonical-repo=" cgitrc >cgitrc.reordered &&
	cat >>cgitrc.reordered <<-EOF &&
	canonical-repo=foo
	canonical-repo=stable
	canonical-repo=bar
	EOF
	rm -rf cache && mkdir cache &&
	CGIT_CONFIG="$PWD/cgitrc.reordered" \
		QUERY_STRING="url=fork/patch/&id=$shared" cgit >output &&
	grep -q "^Location: /stable/patch/?id=$shared\$" output &&
	rm -rf cache && mkdir cache
'

test_expect_success 'the canonical repo itself serves the object' '
	cgit_url "bar/patch/&id=$shared" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'canonical repos do not redirect to each other' '
	cgit_url "stable/patch/&id=$shared" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'an object the canonical repo does not have is served' '
	cgit_url "fork/patch/&id=$forkonly" >output &&
	grep -q "FORKONLY" output &&
	! grep -q "^Status: 301" output
'

# commit, like the other pages that carry cgit'"'"'s navigation chrome (log, tree,
# refs, ...), is never redirected: its breadcrumbs and repo tabs would go on
# referring to the repository the visitor lands in, with nothing on the page
# to say the fork they asked for was substituted underneath them.
test_expect_success 'a chrome-bearing view is never redirected' '
	cgit_url "fork/commit/&id=$shared" >output &&
	grep -q "commit 50" output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'diff, unlike rawdiff, is a chrome-bearing view and is never redirected' '
	cgit_url "fork/diff/&id=$shared" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'a request naming only a reference is not redirected' '
	cgit_url "fork/log/" >output &&
	grep -q "commit 50" output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'other pages pinned by id are redirected too' '
	cgit_url "fork/patch/&id=$shared" >output &&
	grep -q "^Location: /bar/patch/?id=$shared\$" output
'

test_expect_success 'the redirect keeps other parameters and drops h=' '
	cgit_url "fork/rawdiff/&id=$shared&id2=$older&h=master&context=9" >output &&
	grep -q "^Location: /bar/rawdiff/?id=$shared&id2=$older&context=9\$" output
'

test_expect_success 'an abbreviated id is redirected to the full object name' '
	cgit_url "fork/patch/&id=$(expr substr $shared 1 8)" >output &&
	grep -q "^Location: /bar/patch/?id=$shared\$" output
'

test_expect_success 'a reference named by id= is redirected as an object name' '
	cgit_url "fork/patch/&id=master" >output &&
	grep -q "^Location: /bar/patch/?id=$shared\$" output
'

test_expect_success 'a diff the canonical repo cannot show is not redirected' '
	cgit_url "fork/rawdiff/&id=$shared&id2=$forkonly" >output &&
	! grep -q "^Status: 301" output
'

test_expect_success 'a repository sharing nothing is unaffected' '
	cgit_url "foo/patch/" >output &&
	! grep -q "^Status: 301" output
'

test_done
