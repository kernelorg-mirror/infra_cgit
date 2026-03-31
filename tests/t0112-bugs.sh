#!/bin/sh

test_description='Check bugs page access control, nav links, and config'
. ./setup.sh

test_expect_success 'bugs tab not shown by default' '
	cgit_url "foo/summary" >tmp &&
	! grep "bugs" tmp
'

test_expect_success 'enable bugs for foo repo' '
	cat >>cgitrc <<-EOF

	repo.url=bugs-test
	repo.path=$PWD/repos/foo/.git
	repo.desc=bugs test repo
	repo.enable-bugs=1
	EOF
'

test_expect_success 'bugs tab shown when enabled' '
	cgit_url "bugs-test/summary" >tmp &&
	grep ">bugs<" tmp
'

test_expect_success 'bugs page returns 404 when no filter configured' '
	cgit_url "bugs-test/bugs/" >tmp &&
	grep "404" tmp &&
	grep "No bugs-filter configured" tmp
'

test_expect_success 'bugs page returns 403 when not enabled' '
	cgit_url "foo/bugs/" >tmp &&
	grep "403" tmp
'

test_expect_success 'bugs tab not shown when not enabled' '
	cgit_url "foo/summary" >tmp &&
	! grep ">bugs<" tmp
'

test_expect_success 'other nav links do not include bug path' '
	cgit_url "bugs-test/bugs/deadbeef" >tmp &&
	! grep "/log/deadbeef" tmp &&
	! grep "/tree/deadbeef" tmp &&
	! grep "/commit/deadbeef" tmp &&
	! grep "/diff/deadbeef" tmp
'

test_expect_success 'enable-bugs works in global config' '
	sed -i "/^repo.url=bugs-test/,\$d" cgitrc &&
	cat >>cgitrc <<-EOF
	enable-bugs=1

	repo.url=bugs-global
	repo.path=$PWD/repos/foo/.git
	repo.desc=global bugs test
	EOF
'

test_expect_success 'bugs tab shown with global enable-bugs' '
	cgit_url "bugs-global/summary" >tmp &&
	grep ">bugs<" tmp
'

test_expect_success 'repos defined before global enable-bugs do not inherit it' '
	cgit_url "foo/summary" >tmp &&
	! grep ">bugs<" tmp
'

test_expect_success 'cache-bugs-ttl parsed without error' '
	sed -i "/^enable-bugs/a cache-bugs-ttl=30" cgitrc &&
	cgit_url "foo/summary" >tmp &&
	grep "foo" tmp
'

test_done
