/* ui-bugs.c: git-bug browsing via Lua filter
 *
 * Copyright (C) 2026 by the Linux Foundation
 *
 * Licensed under GNU General Public License v2
 *   (see COPYING for full license text)
 */

#include "cgit.h"
#include "ui-bugs.h"
#include "html.h"
#include "ui-shared.h"

void cgit_print_bugs(void)
{
	struct cgit_filter *f = ctx.repo->bugs_filter;

	if (!f) {
		cgit_print_error_page(404, "Not Found",
				      "No bugs-filter configured for this repository");
		return;
	}

	cgit_print_layout_start();
	html("<div id='bugs'>");
	cgit_open_filter(f, ctx.qry.path ? ctx.qry.path : "");
	cgit_close_filter(f);
	html("</div>");
	cgit_print_layout_end();
}
