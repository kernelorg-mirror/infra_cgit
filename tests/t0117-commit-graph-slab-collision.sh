#!/bin/sh

test_description='Canonical-repo lookup must not corrupt commit-graph state
shared across repositories'
. ./setup.sh

# The reachability walk in cgit_find_canonical_repo() (ui-shared.c) opens a
# throwaway `struct repository` per candidate canonical repo and tears it
# down again at the end of each loop iteration. If that repository has its
# own commit-graph, tearing it down calls close_commit_graph(), which
# unconditionally wipes commit_graph_data_slab -- a slab that is a single
# process-wide global (commit-graph.c), not scoped to the repository being
# closed. That erases the graph position already cached for any other
# commit currently being served, including one belonging to the repository
# actually serving the request, forcing a later lookup for its tree to fall
# back to NULL.
#
# Reproducing this needs the canonical repo to have a commit-graph, and the
# fork to lack one of its own so its commit gets graph-fast-path-parsed via
# the canonical repo's graph (found through objects/info/alternates from
# the --shared clone) instead of the ordinary buffer-parse path.
mkgraphtip() {
	mkrepo "repos/$1" 2 >/dev/null &&
	git -C "repos/$1" commit-graph write --reachable &&
	git clone -q --shared --bare "repos/$1/.git" "repos/$1-fork.git"
}

test_expect_success 'setup for commit-graph slab collision regression' '
	mkgraphtip graphtip &&
	graphtip_head=$(cd repos/graphtip && git rev-parse HEAD) &&
	cat >>cgitrc <<-EOF &&
	repo.url=graphtip
	repo.path=$PWD/repos/graphtip/.git
	repo.desc=has a commit-graph
	EOF
	cat >>cgitrc <<-EOF &&
	repo.url=graphtip-fork
	repo.path=$PWD/repos/graphtip-fork.git
	repo.desc=a fork with no commit-graph of its own
	EOF
	cat >>cgitrc <<-EOF
	canonical-repo=graphtip
	EOF
'

test_expect_success 'commit page does not crash when the canonical repo has a commit-graph' '
	rm -rf cache && mkdir cache &&
	cgit_url "graphtip-fork/commit/&id=$graphtip_head" >output &&
	grep -q "This commit has been merged to graphtip" output &&
	grep -q "<th>tree</th>" output
'

test_expect_success 'diff page does not crash when the canonical repo has a commit-graph' '
	rm -rf cache && mkdir cache &&
	cgit_url "graphtip-fork/diff/&id=$graphtip_head" >output &&
	grep -q "This diff has been merged to graphtip" output
'

test_done
