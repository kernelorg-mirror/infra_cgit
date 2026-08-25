#!/bin/sh

test_description='Check handling of a repo.path that is not a git directory'
. ./setup.sh

# A repo.path can stop being a valid git directory at any time: the directory
# is removed, a symlink goes dangling, or the repository format is one this
# build refuses. cgit is supposed to answer with its "config error" page, so
# every page has to survive the failed setup rather than dereference a
# repository that was never opened.

setup_broken_repos() {
	rm -rf broken && mkdir -p broken/empty-dir &&
	git init -q --bare broken/badformat &&
	git -C broken/badformat config core.repositoryformatversion 1 &&
	git -C broken/badformat config extensions.frobnicate true &&
	cat >>cgitrc <<-EOF
	repo.url=gone
	repo.path=$PWD/broken/does-not-exist
	repo.desc=vanished repo

	repo.url=empty-dir
	repo.path=$PWD/broken/empty-dir
	repo.desc=not a git directory

	repo.url=badformat
	repo.path=$PWD/broken/badformat
	repo.desc=unsupported repository format
	EOF
}

test_expect_success 'setup' 'setup_broken_repos'

for repo in gone empty-dir badformat
do
	for page in summary log tree commit diff refs
	do
		test_expect_success "$page of a $repo repo reports a config error" '
			cgit_url "'"$repo"'/'"$page"'" >output &&
			grep -q "config error" output &&
			grep -q "Failed to open" output
		'
	done
done

test_expect_success 'a bogus repo does not crash with an object id either' '
	cgit_url "gone/commit/&id=HEAD" >output &&
	grep -q "config error" output
'

test_done
