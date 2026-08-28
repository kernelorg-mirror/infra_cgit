#!/bin/sh

test_description='Check content on tree page'
. ./setup.sh

test_expect_success 'generate bar/tree' 'cgit_url "bar/tree" >tmp'
test_expect_success 'find file-1' 'grep "file-1" tmp'
test_expect_success 'find file-50' 'grep "file-50" tmp'

test_expect_success 'generate bar/tree/file-50' 'cgit_url "bar/tree/file-50" >tmp'

test_expect_success 'find line 1' '
	grep "<a id=.n1. href=.#n1.>1</a>" tmp
'

test_expect_success 'no line 2' '
	! grep "<a id=.n2. href=.#n2.>2</a>" tmp
'

test_expect_success 'generate foo+bar/tree' 'cgit_url "foo%2bbar/tree" >tmp'

test_expect_success 'verify a+b link' '
	grep "/foo+bar/tree/a+b" tmp
'

test_expect_success 'generate foo+bar/tree?h=1+2' 'cgit_url "foo%2bbar/tree&h=1%2b2" >tmp'

test_expect_success 'verify a+b?h=1+2 link' '
	grep "/foo+bar/tree/a+b?h=1%2b2" tmp
'

test_expect_success 'generate foo+bar/tree?h=1+2&id=<tip>' '
	tip=$(cd repos/foo+bar && git rev-parse HEAD) &&
	cgit_url "foo%2bbar/tree&h=1%2b2&id=$tip" >tmp
'

test_expect_success 'redundant h= alongside id= is redirected away' '
	tip=$(cd repos/foo+bar && git rev-parse HEAD) &&
	grep -q "^Status: 301 Moved" tmp &&
	grep -q "^Location: /foo+bar/tree?id=$tip\$" tmp
'

test_expect_success 'verify a+b?id=<tip> link' '
	tip=$(cd repos/foo+bar && git rev-parse HEAD) &&
	cgit_url "foo%2bbar/tree&id=$tip" >tmp &&
	grep "/foo+bar/tree/a+b?id=$tip" tmp
'

test_expect_success 'verify no link carries both h= and id=' '
	tr "<" "\n" <tmp | grep -o "href=[^>]*" >links &&
	! grep -E "[?&;]id=" links | grep -qE "[?&;]h="
'

test_done
