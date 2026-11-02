#!/bin/sh

test_description='Verify enable-object-reachability-check'
. ./setup.sh

# Build a commit that exists in the object database but is not reachable from
# any reference, which is what a repository sharing its object database with
# others looks like from the inside. The marker keeps each such commit
# distinct: the test dates are fixed, so two commits built the same way would
# otherwise be the same object.
mkunreachable() {
	(
		cd "$1" &&
		echo "PAYLOAD$2" >leak.txt &&
		git add leak.txt &&
		tree=$(git write-tree) &&
		git commit-tree -p HEAD -m "SUBJECT$2" "$tree"
	)
}

test_expect_success 'setup' '
	unreachable=$(mkunreachable repos/bar ONE) &&
	tagged=$(mkunreachable repos/bar TWO) &&
	nograph=$(mkunreachable repos/foo THREE) &&
	(cd repos/bar && git reset -q --hard HEAD) &&
	(cd repos/foo && git reset -q --hard HEAD) &&
	(cd repos/bar && git tag -a -m "orphan" orphan "$tagged") &&
	reachable=$(cd repos/bar && git rev-parse HEAD) &&
	test "$unreachable" != "$tagged" &&
	unreachable_blob=$(cd repos/bar && git rev-parse "$unreachable:leak.txt") &&
	lightweight_blob=$(cd repos/bar &&
		echo LIGHTWEIGHT | git hash-object -w --stdin) &&
	annotated_blob=$(cd repos/bar &&
		echo ANNOTATED | git hash-object -w --stdin) &&
	(cd repos/bar && git tag blobtag "$lightweight_blob") &&
	(cd repos/bar && git tag -a -m "blob" annblobtag "$annotated_blob") &&
	cat >>cgitrc <<-EOF
	repo.url=strict
	repo.path=$PWD/repos/bar/.git
	repo.desc=reachability checked
	repo.enable-object-reachability-check=1

	repo.url=strict-nograph
	repo.path=$PWD/repos/foo/.git
	repo.desc=reachability checked without a commit-graph
	repo.enable-object-reachability-check=1
	EOF
'

test_expect_success 'unreachable commit is served when the check is disabled' '
	cgit_url "bar/commit/&id=$unreachable" >output &&
	grep -q "SUBJECTONE" output &&
	grep -q "PAYLOADONE" output
'

test_expect_success 'unreachable commit is refused when the check is enabled' '
	cgit_url "strict/commit/&id=$unreachable" >output &&
	grep -q "Status: 404 Not found" output &&
	grep -q "is not reachable from any reference in this repository" output
'

test_expect_success 'the refusal discloses nothing about the commit' '
	! grep -q "SUBJECTONE" output &&
	! grep -q "PAYLOADONE" output
'

test_expect_success 'reachable commit is still served' '
	cgit_url "strict/commit/&id=$reachable" >output &&
	! grep -q "Status: 404" output &&
	grep -q "$reachable" output
'

test_expect_success 'a commit reachable only from a tag is served' '
	cgit_url "strict/commit/&id=$tagged" >output &&
	! grep -q "Status: 404" output &&
	grep -q "SUBJECTTWO" output
'

# Whether a blob occurs anywhere in the history cannot be answered without
# walking every object in the repository, so the check accepts a blob only when
# a reference points straight at it. Those are exactly the blobs cgit itself
# links to by raw id, from the refs and tag pages.
test_expect_success 'a blob is served by raw id when the check is disabled' '
	cgit_url "bar/blob/&id=$unreachable_blob" >output &&
	grep -q "PAYLOADONE" output
'

test_expect_success 'a blob no reference points at is refused' '
	cgit_url "strict/blob/&id=$unreachable_blob" >output &&
	grep -q "Status: 404 Not found" output &&
	! grep -q "PAYLOADONE" output
'

test_expect_success 'a blob a lightweight tag points at is served' '
	cgit_url "strict/blob/&id=$lightweight_blob" >output &&
	! grep -q "Status: 404" output &&
	grep -q "LIGHTWEIGHT" output
'

test_expect_success 'a blob an annotated tag points at is served' '
	cgit_url "strict/blob/&id=$annotated_blob" >output &&
	! grep -q "Status: 404" output &&
	grep -q "ANNOTATED" output
'

test_expect_success 'ordinary views are unaffected' '
	cgit_url "strict/refs" >output &&
	! grep -q "Status: 404" output &&
	cgit_url "strict/plain/file-50&id=$reachable" >output &&
	! grep -q "Status: 404" output
'

test_expect_success 'an object that does not resolve is still reported as such' '
	cgit_url "strict/commit/&id=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" >output &&
	grep -q "Bad commit reference" output &&
	! grep -q "is not reachable from any reference" output
'

test_expect_success 'an unreachable id2 is refused by the diff view' '
	cgit_url "strict/diff/&id=$reachable&id2=$unreachable" >output &&
	grep -q "Status: 404 Not found" output &&
	grep -q "is not reachable from any reference in this repository" output &&
	! grep -q "PAYLOADONE" output
'

test_expect_success 'an unreachable snapshot is refused' '
	cgit_url "strict/snapshot/$unreachable.tar.gz" >output &&
	grep -q "Status: 404 Not found" output &&
	grep -q "is not reachable from any reference in this repository" output
'

test_expect_success 'the check works without a commit-graph' '
	cgit_url "strict-nograph/commit/&id=$nograph" >output &&
	grep -q "Status: 404 Not found" output &&
	grep -q "is not reachable from any reference in this repository" output
'

# Answering the reachability question walks history, so the refusal is worth
# caching: regenerating it for every crawler request would cost more than the
# slot it occupies.
test_expect_success 'a refusal is cached and replayed' '
	rm -f cache/* &&
	cgit_url "strict/commit/&id=$unreachable" >output &&
	grep -q "Status: 404 Not found" output &&
	test -n "$(ls cache)" &&
	cgit_url "strict/commit/&id=$unreachable" >output.cached &&
	test_cmp output output.cached
'

# The commit-graph that grokmirror writes with --reachable lists exactly the
# commits the repository's references reached when it was written, so it can
# vouch for a commit without walking history. Only a graph in the repository's
# own object directory may do so: git happily loads one from an alternate, and
# an objstore's graph covers every repository sharing it.
test_expect_success 'setup a repository borrowing from one with a commit-graph' '
	git clone -q --bare --shared repos/foo repos/lender.git &&
	(
		cd repos/lender.git &&
		tree=$(git rev-parse HEAD^{tree}) &&
		lent=$(git commit-tree -p HEAD -m "SUBJECTLENT" "$tree") &&
		git update-ref refs/heads/other-fork "$lent" &&
		git commit-graph write --reachable
	) &&
	lent=$(cd repos/lender.git && git rev-parse other-fork) &&
	git clone -q --bare --shared repos/lender.git repos/borrower.git &&
	(cd repos/borrower.git && git update-ref -d refs/heads/other-fork) &&
	test_path_is_missing repos/borrower.git/objects/info/commit-graph &&
	test_path_is_missing repos/borrower.git/objects/info/commit-graphs &&
	cat >>cgitrc <<-EOF
	repo.url=borrower
	repo.path=$PWD/repos/borrower.git
	repo.enable-object-reachability-check=1

	repo.url=lender
	repo.path=$PWD/repos/lender.git
	repo.enable-object-reachability-check=1
	EOF
'

test_expect_success 'a commit in an alternate commit-graph is not vouched for' '
	cgit_url "lender/commit/&id=$lent" >output &&
	! grep -q "Status: 404" output &&
	cgit_url "borrower/commit/&id=$lent" >output &&
	grep -q "Status: 404 Not found" output &&
	! grep -q "SUBJECTLENT" output
'

test_expect_success 'a lower chain layer kept in an alternate is not vouched for' '
	(
		cd repos/lender.git &&
		rm -f objects/info/commit-graph &&
		git commit-graph write --reachable --split
	) &&
	(
		cd repos/borrower.git &&
		tree=$(git rev-parse HEAD^{tree}) &&
		own=$(git commit-tree -p HEAD -m "SUBJECTOWN" "$tree") &&
		git update-ref HEAD "$own" &&
		git commit-graph write --reachable --split
	) &&
	lender_layer=$(head -n1 repos/lender.git/objects/info/commit-graphs/commit-graph-chain) &&
	grep -q "^$lender_layer$" repos/borrower.git/objects/info/commit-graphs/commit-graph-chain &&
	rm -f cache/* &&
	cgit_url "borrower/commit/&id=$lent" >output &&
	grep -q "Status: 404 Not found" output &&
	! grep -q "SUBJECTLENT" output
'

# The commit asked for sits one behind the tip, so that finding it takes the
# walk rather than a match against the tip itself.
test_expect_success 'a reachable commit newer than the commit-graph is served' '
	(
		cd repos/lender.git &&
		git commit-graph write --reachable &&
		tree=$(git rev-parse HEAD^{tree}) &&
		fresh=$(git commit-tree -p other-fork -m "SUBJECTFRESH" "$tree") &&
		tip=$(git commit-tree -p "$fresh" -m "SUBJECTTIP" "$tree") &&
		git update-ref refs/heads/other-fork "$tip"
	) &&
	fresh=$(cd repos/lender.git && git rev-parse other-fork^) &&
	cgit_url "lender/commit/&id=$fresh" >output &&
	! grep -q "Status: 404" output &&
	grep -q "SUBJECTFRESH" output
'

test_done
