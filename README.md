# UpNote MCP server

Let Claude and Codex work with your [UpNote](https://getupnote.com) notes on macOS.
UpNote has no public API, so this MCP server reads the app's local database (read-only)
and makes every change through UpNote's own `upnote://` links.

Ask in plain language:

- "Find my notes about JSON Patch and summarize them."
- "What did I change this week?"
- "Create a note in Get Started with a checklist for tomorrow."
- "Add a follow-up item to my Plans note."
- "In my Plans note, change Triage to In progress." Claude previews the edit first.

It works with Claude Code, Claude Desktop and Codex. It has sixteen tools: search, read, create,
edit, append, insert under a heading, move to another notebook, make a collapsible section,
change tags, move to Trash and back, and open a note in the app.

> **Unofficial and macOS only.** UpNote has no editing API, so this server depends on the
> app's local data format and two undocumented links (trash and restore). It was built against
> UpNote 9.22.2 to 9.22.6 (data version 17) and the author runs it on 9.22.9. An UpNote update
> can break it. The server checks the database format on every connection and fails with a
> clear message instead of returning wrong results.

## Safety and known risks

- **Reads cannot change anything.** The database is opened read-only, and an authorizer
  refuses everything except reading.
- **Writes go through UpNote.** The server never writes to the database. UpNote makes each
  change and syncs it as if you had made it by hand. Text sent to UpNote is cleaned of
  anything that could run code or send data out.
- **An edit makes a new note.** UpNote cannot change a note in place. An edit creates a
  checked new version and then moves the original to Trash, where `restore_note` can bring it
  back. The new note gets a new id and creation date. Version History stays with the original,
  and pin and bookmark must be set again by hand. Every edit shows a preview with warnings first.
  The tools refuse notes that have attachments or images, links from other notes, a web share link,
  or a template.
- **Nothing is deleted for good.** No tool empties Trash.
- **UpNote once emptied a notebook's membership list.** On 2026-10-11 a note created in a
  notebook of 351 left it holding 1 (UpNote 9.22.6, once, during its daily backup and re-sync).
  The notes stayed intact. The server cannot prevent this, but it checks the notebook before and
  after each change and reports a loss. UpNote's daily backup is the way back. See
  [Limits and known issues](#limits-and-known-issues).
- **Full Disk Access.** macOS needs it to read UpNote's data. You grant it to a small launcher
  that runs only this server. See [Full Disk Access](#full-disk-access) for what that allows.

## Requirements

- macOS, with UpNote installed from the Mac App Store. The server reads
  `~/Library/Containers/com.getupnote.desktop/Data/Library/Application Support/UpNote/upnote.sqlite3`.
  Set `UPNOTE_DB` to point it elsewhere.
- [python.org's Python](https://www.python.org/downloads/macos/) 3.12 or newer, and `clang`
  from the Xcode Command Line Tools (`xcode-select --install`) to build the launcher.
  [Full Disk Access](#full-disk-access) explains why the server runs this way.
- UpNote running, for any tool that changes a note or opens the app.

## Install

```bash
git clone https://github.com/andreiGl/upnote-mcp ~/.claude/mcp-servers/upnote-mcp
~/.claude/mcp-servers/upnote-mcp/install.sh
```

The script links the folder into `~/.claude/mcp-servers/`, builds a virtual environment, and
builds and signs the launcher. It changes no client setting. When it finishes, it prints the
next steps, which are:

1. Give the launcher **Full Disk Access**: System Settings, Privacy & Security, Full Disk
   Access, press `+`, then `Cmd+Shift+G` and paste `~/.claude/mcp-servers/upnote-mcp-launcher`.
2. Register the launcher with your client.
3. Restart the client and ask Claude to run `check_upnote_setup`.

### Register with a client

Claude Code, for all projects:

```bash
claude mcp add --scope user upnote -- ~/.claude/mcp-servers/upnote-mcp-launcher
```

Claude Desktop: add the launcher by its absolute path to
`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "upnote": {
      "command": "/Users/you/.claude/mcp-servers/upnote-mcp-launcher"
    }
  }
}
```

Codex:

```bash
codex mcp add upnote -- /Users/you/.claude/mcp-servers/upnote-mcp-launcher
```

Or add this entry to `~/.codex/config.toml`. Merge it with an existing `upnote` entry rather
than adding a duplicate:

```toml
[mcp_servers.upnote]
command = "/Users/you/.claude/mcp-servers/upnote-mcp-launcher"
startup_timeout_sec = 20
tool_timeout_sec = 30
enabled_tools = ["search_notes", "list_notes", "get_note", "list_notebooks", "list_tags", "run_select", "check_upnote_setup", "create_note", "replace_note", "append_to_note", "insert_after_heading", "move_note", "make_section", "move_note_to_trash", "restore_note", "open_in_upnote"]
```

These are the server's sixteen tools. Keep the client's normal approval policy; no blanket
automatic approval is needed.

### Manual install

The script runs these steps:

```bash
/Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12 -m venv ~/.claude/mcp-servers/upnote-mcp-venv
~/.claude/mcp-servers/upnote-mcp-venv/bin/python -m pip install 'mcp==2.2.0'
clang -O2 -o ~/.claude/mcp-servers/upnote-mcp-launcher ~/.claude/mcp-servers/upnote-mcp/launcher.c
codesign -s - -i ca.glotov.upnote-mcp-launcher -f ~/.claude/mcp-servers/upnote-mcp-launcher
```

Keep the `mcp` version in the venv in step with the one `server.py` declares. The launcher
always runs `~/.claude/mcp-servers/upnote-mcp/server.py`, so the checkout must sit at that
path or be linked there.

### macOS access and reconnecting

The launcher may need the [Full Disk Access](#full-disk-access) grant. The host app's permissions
also matter: during local Codex desktop validation, its ChatGPT app needed **Files & Folders,
UpNote** enabled even though the launcher already had access. Read the actual setup error and
grant only the access needed.

Run `check_upnote_setup` before reading or changing notes. Reconnect MCP servers or start fresh
client sessions after a source or configuration change. A running session can keep its old server
process and tool catalog.

## Upgrading

The running server keeps the `server.py` it started with, so restart your clients after an update.
For a plain checkout, run `git pull` in `~/.claude/mcp-servers/upnote-mcp`. A Python-only update
does not need a rebuilt or re-signed launcher. Rebuilding the launcher loses its Full Disk Access
grant: remove it, add it back, and restart Claude.

To switch between versions without a gap, keep each version in its own folder, pause calls in every
client, replace the `~/.claude/mcp-servers/upnote-mcp` link with a temporary sibling link and an
atomic rename, then reconnect the MCP servers. To roll back, restore only that link. Do not restore
a database or unrelated settings.

## Tools

| Tool | What it does |
| :--- | :--- |
| `search_notes` | Finds notes containing all the given words in the title or body, case-insensitive in any language, optionally within a notebook, tag or date range |
| `list_notes` | Lists notes by last update or creation date, newest first, optionally within a notebook, tag or date range |
| `get_note` | Returns one note's text or HTML, in parts for long notes, with its attachments' names |
| `list_notebooks` | Lists notebooks with their paths and note counts |
| `list_tags` | Lists tags with note counts |
| `run_select` | Runs one read-only SQL query, for questions the other tools don't cover. It stops a query after ten seconds, refuses a value or a result over 20 MB or more than 64 columns, and reads attachment download links as NULL |
| `create_note` | Creates a note, optionally in a notebook and with tags, and returns its id once UpNote has saved it |
| `move_note_to_trash` | Moves a note to Trash |
| `restore_note` | Moves a note out of Trash |
| `replace_note` | Edits a note by creating a new version and trashing the original, after a preview; can also move it, remove tags or add them |
| `append_to_note` | Adds content to the end of a note, copying what's already there, the same way as `replace_note` |
| `insert_after_heading` | Adds content just under or just above a heading, copying the rest of the note unchanged, the same way as `replace_note` |
| `move_note` | Moves a note to another notebook by rebuilding it there unchanged, the same way as `replace_note` |
| `make_section` | Turns a heading and what's under it, up to the next heading or a hand-written end marker, into a collapsible section, nested where it sits |
| `open_in_upnote` | Shows a note, notebook, tag or search in the app |
| `check_upnote_setup` | Reports the database path, UpNote's data version, any missing columns, note counts, and which program started the server |

Notes in Trash are left out of searches and lists unless `include_trashed` is set. No tool
deletes a note permanently.

## Formatting

`create_note` and `replace_note` take Markdown. Each of these was checked in UpNote after
creating a note with it:

- Headings, bold, italic, strikethrough, links, and inline code
- Bullet lists nested to any depth, numbered lists, and checkboxes written as `- [ ]` and `- [x]`
- Quotes, dividers, tables, and code blocks with a language, such as `json` or `bash`
- A green highlight written as `==text==`
- Raw HTML for underline with `<u>`, a yellow highlight with
  `<span class="shine-highlight-yellow">`, and UpNote's collapsible sections

UpNote drops `<mark>`. The note title becomes the note's heading, so the body shouldn't repeat it.

UpNote's own Markdown conversion adds an empty bullet after every nested list, whatever the
indent. So before sending, the server rewrites each list that has nesting as HTML in the shape
UpNote's editor uses, with the items' formatting converted too: bold, italic, code, links, bare
URLs, `<https://…>` links, strikethrough, `==green==`, checkboxes, and inline HTML such as `<u>`.
A numbered list keeps its starting number. Flat lists, and lists in code blocks, HTML or HTML
comments, are sent as written. So is a list whose items hold a code block, a quote, a table, or
a paragraph after a blank line, and it keeps the empty bullet.

Tags go in `create_note`'s `tags` parameter. The server adds each one as a hashtag link at the
end of the note, which is how UpNote stores tags, and waits until UpNote has recorded them. A
`#hashtag` typed in the body stays plain text.

## Editing notes

UpNote cannot change a note in place, so `replace_note`, `append_to_note`, `insert_after_heading`,
`move_note` and `make_section` all work the same way:

1. A **preview** changes nothing. It shows the note's revision, a `preview_token` and any warnings.
2. The **apply** call passes the revision and token back, so it can only do what the preview showed.
3. The server creates the new version, waits until UpNote has saved it with the right notebook,
   tags and text, and only then moves the original to Trash.

If a step fails, the original stays in place and the result says so. `append_to_note` takes only the
new content, so Claude never resends a long note. A body over 30,000 characters is refused through
MCP. Notes with collapsible sections have an extra gate against UpNote's re-parser dropping them.
Full rules, warnings and recipes are in [docs/EDITING.md](docs/EDITING.md).

## Limits and known issues

- macOS only, and by default only the App Store build's database location.
- `test_live.py --live` stays on hold: its move step rebuilds a note through a create link that
  names a notebook, the exact action behind the 2026-10-11 membership wipe, which UpNote has not
  fixed. Run it only against a library you can restore from a backup.
- What makes UpNote's re-parser drop collapsible-section wrappers is unknown - a 59KB note
  flattened on 2026-11-09 and a 60KB note rebuilt cleanly the same day, so it is not size alone.
  A targeted experiment (a scratch note, one nested wrapper, growing sizes) would answer it; the
  gate makes it low-stakes meanwhile.
- The trash and restore links are undocumented, so an UpNote update could remove them.
- A search left active in UpNote stays active when `open_in_upnote` shows a notebook or tag, and
  no link clears it.
- Search matches substrings in the title and plain text, so "kafk" finds Kafka; for inflected
  languages, search for word stems. It is not a ranked index.
- Pin and bookmark can't be set: no link does it.
- Creating or replacing a note in a notebook whose title another notebook shares is refused,
  since UpNote's create link names a notebook by title only.
- **UpNote can wipe a notebook's membership when a note is added to it.** Its create link adds the
  note by rebuilding the notebook's list from an in-memory copy, and when that copy is missing it
  writes the new note alone and syncs that to every device. On 2026-10-11 a note created in a
  notebook of 351 left it holding 1 (UpNote 9.22.6; it happened once, during UpNote's daily backup
  and re-sync, and a note created an hour earlier in the same notebook was fine). The notes stay
  intact; only their place in the notebook is lost. The server can't prevent it, but every tool
  that adds a note to a notebook checks the notebook's members before and after. A loss is reported
  in `notebook_members_lost` with the missing ids, and a rebuild then leaves the original in place.
- UpNote keeps a daily backup per account in `~/Library/Containers/com.getupnote.desktop/Data/Library/Application Support/UpNote/UpNote Backup/<account>/data/`,
  one `.upnx` file per day: gzip holding a `version:2` line, then one JSON record per line (`user`,
  `notebooks`, `lists`, `filters`, `tags`, `files`, `notes`). A notebook's members are the `lists`
  record with id `notebooks_<notebook id>`. It is the way back from a wipe like the one above.

## Troubleshooting

- **Start with `check_upnote_setup`.** Ask Claude to run it. It shows which database the server
  reads, UpNote's data version, any columns an UpNote update removed, and which program started
  the server, which is the one macOS checks for access.
- **Check the connection.** In Claude Code, `claude mcp get upnote` should report the server as
  connected. Claude Desktop logs each server to
  `~/Library/Logs/Claude/mcp-server-upnote.log`, and a working start logs
  "Server started and connected successfully".
- **"Cannot open the UpNote database read-only".** macOS blocks reading another app's data
  without Full Disk Access, and granting it to Claude is not enough: the Claude desktop app
  starts MCP servers as their own responsible process, so macOS checks the binary in `command`.
  The desktop app may serve the tools even in a Claude Code session, so fix its config too.
  Check that the launcher from [Install](#install) (`install.sh` builds it) has Full Disk Access.
- **Still blocked with Full Disk Access granted.** Look in System Settings, Privacy & Security,
  Files & Folders, for an entry whose "access data from UpNote" is switched off, often greyed out.
  `tccutil reset SystemPolicyAppData` clears those, and then Claude needs a restart: a server
  already running stays blocked after the reset.
- **Claude Desktop can't start the server.** The app doesn't use your shell's `PATH`, so the
  `command` in its config has to be the launcher's absolute path, without `~`.
- **A change reports it wasn't confirmed.** The tool waited ten seconds without seeing UpNote
  save it. Check the note before trying again, so nothing gets created twice.
- **A notebook is refused because another one has the same title.** UpNote's create link names a
  notebook by title only, so with two notebooks of that title the note could land in either.
  Rename one of them in UpNote.

## Full Disk Access

A grant on uv or Homebrew's Python doesn't last. Homebrew signs them ad hoc, so macOS ties the
grant to one build and drops it on the next `brew upgrade`. `launcher.c` builds a small binary
that starts `server.py` and waits for it. It never changes, so its grant holds. It takes no
arguments and always runs `~/.claude/mcp-servers/upnote-mcp/server.py` with the venv's Python, so
its command line can't point the grant at another program. It builds both paths from the home
folder in the user database, not from `HOME`, so setting `HOME` can't point it elsewhere either.

The launcher doesn't use uv. With uv in the chain, macOS recorded a separate "access data from
UpNote" decision against each Homebrew uv build, switched off and locked, and the server failed
with "unable to open database file" until `tccutil reset SystemPolicyAppData` and a Claude
restart. So the launcher runs a venv built from python.org's Python, which is signed by the
Python Software Foundation rather than ad hoc, and which Homebrew never upgrades.

Rebuilding the launcher changes its signature, so grant it again after a rebuild: remove it from
Full Disk Access, add it back, and restart Claude. It runs whatever `server.py` holds, so the
grant extends to any edit of that file.

## More

- [docs/EDITING.md](docs/EDITING.md): replace, append, move, nested sections, very large notes.
- [docs/DESIGN.md](docs/DESIGN.md): how changes are made and cleaned, shared operation state, opening notes.
- [docs/TESTING.md](docs/TESTING.md): the test suites and how to run them.

## License

MIT. See [LICENSE](LICENSE).
