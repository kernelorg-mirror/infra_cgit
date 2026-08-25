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

test_done
