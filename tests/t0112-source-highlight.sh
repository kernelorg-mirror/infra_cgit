#!/bin/sh

test_description='Verify client-side source highlighting (prism.js)'
. ./setup.sh

test_expect_success 'setup' '
	test_create_repo repos/hl &&
	(
		cd repos/hl &&
		printf "int main(void) {\n\treturn 0;\n}\n" >hello.c &&
		printf "def hello():\n    return 0\n" >hello.py &&
		printf "no extension here\n" >README &&
		git add hello.c hello.py README &&
		git commit -m "add sources"
	) &&
	cat >>cgitrc <<-EOF
	repo.url=hl
	repo.path=$PWD/repos/hl/.git
	repo.desc=source highlighting test repo
	EOF
'

test_expect_success 'no highlighting by default' '
	cgit_url "hl/tree/hello.c" >output &&
	! grep -q "language-c" output &&
	! grep -q "prism.js" output &&
	! grep -q "prism.css" output &&
	grep -q "<code>" output
'

test_expect_success 'enable client-side highlighting' '
	rm -rf cache && mkdir cache &&
	echo "enable-source-highlight=1" >>cgitrc
'

test_expect_success 'a .c file gets a language-c class and loads prism from <head>' '
	cgit_url "hl/tree/hello.c" >output &&
	grep -q "code class=.language-c." output &&
	sed -n "/<head>/,/<\/head>/p" output >head &&
	grep -q "prism.js" head &&
	grep -q "prism.css" head
'

test_expect_success 'a directory listing loads prism too, so blob links below it work' '
	cgit_url "hl/tree/" >output &&
	grep -q "prism.js" output &&
	grep -q "prism.css" output
'

test_expect_success 'a .py file gets a language-python class' '
	cgit_url "hl/tree/hello.py" >output &&
	grep -q "code class=.language-python." output
'

test_expect_success 'an unrecognized extension falls back to language-none' '
	cgit_url "hl/tree/README" >output &&
	grep -q "code class=.language-none." output
'

test_expect_success 'repo.source-filter takes priority over client-side highlighting' '
	rm -rf cache && mkdir cache &&
	cgit_url "filter-exec/tree/a%2bb" >output &&
	grep -q "<code>a+b HELLO$" output &&
	! grep -q "language-" output &&
	! grep -q "prism.js" output
'

test_expect_success 'repo.source-filter also skips loading prism in <head>' '
	cgit_url "filter-exec/tree/" >output &&
	! grep -q "prism.js" output &&
	! grep -q "prism.css" output
'

test_done
