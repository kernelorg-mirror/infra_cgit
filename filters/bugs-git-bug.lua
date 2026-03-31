-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 by the Linux Foundation
--
-- cgit bugs-filter: renders git-bug data using ezgb.lua
--
-- Requires: ezgb.lua, luagit2, lua-cjson (or lua-json), luaossl
--
-- cgitrc configuration:
--   enable-bugs=1
--   bugs-filter=lua:/path/to/filters/bugs.lua
--
-- Environment variables (set by cgit):
--   CGIT_REPO_PATH  — filesystem path to the repository
--   CGIT_REPO_URL   — repository URL in cgit
--   QUERY_STRING    — CGI query string (for pagination)

local ezgb = require("ezgb")

-- ── Configuration ─────────────────────────────────────────────────────

local PAGE_SIZE = 50

-- ── Helpers ───────────────────────────────────────────────────────────

local function html_linkify(text)
    local pos = 1
    while pos <= #text do
        -- Find the next URL or Message-ID, whichever comes first
        local us, ue = text:find("https?://[%w%.%-_~:/?#%[%]@!$&'()*+,;=%%]+", pos)
        local ms, me, msgid = text:find("Message%-ID:%s*<([^>]+)>", pos)

        if not us and not ms then
            html_txt(text:sub(pos))
            break
        end

        -- Pick whichever match starts first
        if ms and (not us or ms < us) then
            -- Message-ID match — link just the id, not the whole line
            -- Output: Message-ID: <<a href="...">msgid</a>>
            local angle_start = text:find("<", ms)
            if angle_start > pos then
                html_txt(text:sub(pos, angle_start - 1))
            end
            html("&lt;")
            local url = "https://msgid.link/" .. msgid
            html("<a href='")
            html_attr(url)
            html("'>")
            html_txt(msgid)
            html("</a>")
            html("&gt;")
            pos = me + 1
        else
            -- URL match — strip trailing punctuation
            local url = text:sub(us, ue)
            while url:match("[.,;:>%)%]}'\"]+$") do
                url = url:sub(1, -2)
                ue = ue - 1
            end
            if us > pos then
                html_txt(text:sub(pos, us - 1))
            end
            html("<a href='")
            html_attr(url)
            html("'>")
            html_txt(url)
            html("</a>")
            pos = ue + 1
        end
    end
end

local function parse_query_string(qs)
    local params = {}
    if not qs then return params end
    for k, v in qs:gmatch("([^&=]+)=([^&]*)") do
        params[k] = v
    end
    return params
end

local function bugs_base_url()
    -- Derive the bugs/ base from the current request so that links
    -- work regardless of virtual-root / URL-rewriting setup.
    local uri = os.getenv("REQUEST_URI") or ""
    -- Strip query string
    uri = uri:gsub("%?.*$", "")
    -- Ensure the URI is an absolute path to prevent scheme injection
    -- (e.g. javascript: or data:) from a misconfigured proxy.
    if uri:sub(1, 1) ~= "/" then uri = "/" end
    -- Find the /bugs/ segment and truncate there
    local base = uri:match("^(.*/bugs/)")
    if base then return base end
    -- Fallback: append /bugs/ to whatever we have
    return uri:gsub("/$", "") .. "/bugs/"
end

local function bugs_url(path, query)
    local url = bugs_base_url()
    if path and path ~= "" then
        url = url .. path
    end
    if query and query ~= "" then
        url = url .. "?" .. query
    end
    return url
end

local function reltime(ts)
    local diff = os.time() - ts
    if diff < 60 then return "now"
    elseif diff < 3600 then return string.format("%d min. ago", math.floor(diff / 60))
    elseif diff < 86400 then return string.format("%d hours ago", math.floor(diff / 3600))
    elseif diff < 2592000 then return string.format("%d days ago", math.floor(diff / 86400))
    elseif diff < 31536000 then return string.format("%d months ago", math.floor(diff / 2592000))
    else return string.format("%d years ago", math.floor(diff / 31536000)) end
end

-- ── List view ─────────────────────────────────────────────────────────

local function render_list(params)
    local show_closed = params.status == "closed"
    local offset = math.max(0, tonumber(params.ofs) or 0)

    -- Build lightweight summaries for all bugs to get accurate
    -- open/closed counts.  Summaries are cheap (no identity
    -- resolution, no comment text, no op hashing).
    local refs = ezgb.list_bug_refs()
    local open_refs = {}
    local closed_refs = {}
    for _, ref in ipairs(refs) do
        local s = ezgb.build_bug_summary(ref.id)
        if s then
            if s.status == ezgb.STATUS_OPEN then
                open_refs[#open_refs + 1] = s
            else
                closed_refs[#closed_refs + 1] = s
            end
        end
    end

    -- Sort newest first
    local function by_date(a, b) return a.created_at > b.created_at end
    table.sort(open_refs, by_date)
    table.sort(closed_refs, by_date)

    local bugs = show_closed and closed_refs or open_refs

    -- Open/closed counts
    html("<div class='bug-counts'>")
    if show_closed then
        html("<a href='")
        html_attr(bugs_url(""))
        html("'>" .. #open_refs .. " open</a> ")
        html("<a class='active' href='")
        html_attr(bugs_url("", "status=closed"))
        html("'>" .. #closed_refs .. " closed</a>")
    else
        html("<a class='active' href='")
        html_attr(bugs_url(""))
        html("'>" .. #open_refs .. " open</a> ")
        html("<a href='")
        html_attr(bugs_url("", "status=closed"))
        html("'>" .. #closed_refs .. " closed</a>")
    end
    html("</div>\n")

    -- Table
    html("<table summary='bug list' class='list nowrap'>\n")
    html("<tr class='nohover'>")
    html("<th class='left'>Id</th>")
    html("<th class='left'>Title</th>")
    html("<th class='left'>Author</th>")
    html("<th class='left'>Age</th>")
    html("<th class='left'>Comments</th>")
    html("<th class='left'>Labels</th>")
    html("</tr>\n")

    local last = math.min(offset + PAGE_SIZE, #bugs)
    for i = offset + 1, last do
        local bug = bugs[i]
        local lbls = {}
        for l in pairs(bug.labels) do lbls[#lbls + 1] = l end
        table.sort(lbls)

        html("<tr><td class='id'>")
        html("<a href='")
        html_attr(bugs_url(bug.id:sub(1, 12)))
        html("'>")
        html_txt(bug.id:sub(1, 8))
        html("</a></td>")

        html("<td><a href='")
        html_attr(bugs_url(bug.id:sub(1, 12)))
        html("'>")
        html_txt(bug.title)
        html("</a></td>")

        html("<td>")
        local creator = ezgb.resolve_identity(bug.creator_id)
        html_txt(creator.name)
        html("</td>")

        html("<td class='age'>")
        html_txt(reltime(bug.created_at))
        html("</td>")

        html("<td class='comments'>")
        if bug.comment_count > 0 then
            html_txt(tostring(bug.comment_count))
        end
        html("</td>")

        html("<td class='bug-labels'>")
        for _, l in ipairs(lbls) do
            html("<span>")
            html_txt(l)
            html("</span> ")
        end
        html("</td></tr>\n")
    end
    html("</table>\n")

    -- Pager
    if #bugs > PAGE_SIZE then
        html("<div class='pager'>")
        local status_q = show_closed and "status=closed&" or ""
        if offset > 0 then
            local prev_ofs = math.max(0, offset - PAGE_SIZE)
            html("<a href='")
            html_attr(bugs_url("", status_q .. "ofs=" .. prev_ofs))
            html("'>&larr; prev</a> ")
        end
        if last < #bugs then
            html("<a href='")
            html_attr(bugs_url("", status_q .. "ofs=" .. last))
            html("'>next &rarr;</a>")
        end
        html(" (" .. last .. "/" .. #bugs .. ")")
        html("</div>\n")
    end
end

-- ── Detail view ───────────────────────────────────────────────────────

local function render_detail(bid)
    local bug, err = ezgb.build_bug(bid)
    if not bug then
        html("<p class='error'>Bug not found: ")
        html_txt(err or bid)
        html("</p>\n")
        return
    end

    html("<p><a href='")
    html_attr(bugs_url(""))
    html("'>&larr; back to bug list</a></p>\n")

    -- Bug info table
    html("<table summary='bug info' class='commit-info'>\n")
    html("<tr><th>title</th><td>")
    html_txt(bug.title)
    html("</td></tr>\n")

    html("<tr><th>status</th><td>")
    if bug.status == ezgb.STATUS_OPEN then
        html("<span class='bug-status-open'>open</span>")
    else
        html("<span class='bug-status-closed'>closed</span>")
    end
    html("</td></tr>\n")

    html("<tr><th>author</th><td>")
    html_txt(bug.creator.name)
    if bug.creator.email ~= "" and bug.creator.email ~= bug.creator.id then
        html(" &lt;")
        html_txt(bug.creator.email)
        html("&gt;")
    end
    html("</td></tr>\n")

    html("<tr><th>created</th><td>")
    html_txt(os.date("%Y-%m-%d %H:%M:%S", bug.created_at))
    html(" (")
    html_txt(reltime(bug.created_at))
    html(")</td></tr>\n")

    local lbls = {}
    for l in pairs(bug.labels) do lbls[#lbls + 1] = l end
    if #lbls > 0 then
        table.sort(lbls)
        html("<tr><th>labels</th><td class='bug-labels'>")
        for _, l in ipairs(lbls) do
            html("<span>")
            html_txt(l)
            html("</span> ")
        end
        html("</td></tr>\n")
    end

    html("<tr><th>id</th><td>")
    html_txt(bug.id)
    html("</td></tr>\n")

    if next(bug.metadata) then
        for k, v in pairs(bug.metadata) do
            html("<tr><th>")
            html_txt(k)
            html("</th><td>")
            html_txt(v)
            html("</td></tr>\n")
        end
    end
    html("</table>\n")

    -- Comments
    if #bug.comments > 0 then
        html("<h3>" .. #bug.comments .. " comment")
        if #bug.comments ~= 1 then html("s") end
        html("</h3>\n")

        for _, c in ipairs(bug.comments) do
            local anchor = c.id:sub(1, 12)
            html("<div class='comment' id='")
            html_attr(anchor)
            html("'>\n")
            html("<div class='comment-header'>")
            html("<a class='date' href='#")
            html_attr(anchor)
            html("'>")
            html_txt(os.date("%Y-%m-%d %H:%M", c.created_at))
            html("</a> ")
            html("<b>")
            html_txt(c.author.name)
            html("</b> commented")
            html("</div>\n")
            html("<pre class='comment-body'>")
            html_linkify(c.text)
            html("</pre>\n")
            html("</div>\n")
        end
    end
end

-- ── Filter entry points ──────────────────────────────────────────────

local saved_path = ""

function filter_open(path)
    saved_path = path or ""
end

function filter_close()
    local repo_path = os.getenv("CGIT_REPO_PATH")
    if not repo_path then
        html("<p class='error'>CGIT_REPO_PATH not set</p>")
        return 0
    end
    local ok, err = pcall(ezgb.open, repo_path)
    if not ok then
        html("<p class='error'>Failed to open bug database: ")
        html_txt(tostring(err))
        html("</p>")
        return 0
    end

    local params = parse_query_string(os.getenv("QUERY_STRING"))

    if saved_path == "" then
        render_list(params)
    else
        render_detail(saved_path)
    end
    return 0
end

function filter_write(str)
end
