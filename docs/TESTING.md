# Testing

The tests run on the server's venv. `test_make_section.py` checks the section-building logic,
and the HTML clean-up `append_to_note` does, against synthetic note markup,
`test_nested_lists.py` checks the nested-list rewrite, and `test_structure_gate.py` checks the
collapsible-section counts and the replace gate's decisions. None touches UpNote or your notes.
Run each test from the repository root:

```bash
~/.claude/mcp-servers/upnote-mcp-venv/bin/python test_make_section.py
~/.claude/mcp-servers/upnote-mcp-venv/bin/python test_nested_lists.py
~/.claude/mcp-servers/upnote-mcp-venv/bin/python test_structure_gate.py
```

`test_readonly.py` compares every read tool except `open_in_upnote`, which changes what the app
shows, with direct queries on your own library: filters, sorting, paging and counts. It also
confirms that `run_select` refuses writes, and that the rebuild tools refuse a stale revision, an
unknown tag, an empty append and a move to the same notebook, all before anything is sent. It
then runs a rebuild of every eligible note against a stand-in for UpNote, with no link sent: an
append, a `replace_note` given the note's own HTML, and the removal of a tag. Each one has to
pass the checks the server makes before it trashes the original. It changes no note, but it
writes pending journals to the server's operation state (see [Shared operation state](DESIGN.md#shared-operation-state)). In the
default folder, a journal it leaves blocks the next run, and the live server, for that note for
5 minutes. Give it a private folder of its own:

```bash
UPNOTE_MCP_STATE_DIR=$(mktemp -d) ~/.claude/mcp-servers/upnote-mcp-venv/bin/python test_readonly.py
```

`test_live.py` checks the tools that change notes: create, append, `make_section`, replace with
a tag removed, move, trash and restore. It works on notes it creates, titled "ZZ live test" with
the time, and checks after each step what UpNote stored: tags kept and last, no empty bullets or
empty `<div>`s, the existing content unchanged, and a fenced code example intact. It also checks
that a stale revision and unaccepted warnings are refused. At the end it moves every note it
created to Trash, where they stay, synced to your other devices, until you empty Trash. The moved
note briefly sits in one of your notebooks and stays listed there in Trash. It needs UpNote
running, takes about ten seconds, and only runs with `--live`. Run it after an UpNote update:

```bash
~/.claude/mcp-servers/upnote-mcp-venv/bin/python test_live.py --live
```

## Synthetic protocol and navigation tests

From the repository root, with Python 3.12+ and `mcp==2.2.0` installed:

```bash
python -m unittest discover -s tests/upnote -p 'test_*.py' -v
```

The suite creates isolated synthetic SQLite data and intercepts every app URL. It
checks the eight non-read tool paths, previews and invalid applies without side
effects, cross-process contention, pending state across restart, ambiguous dispatch,
corrupt journals, literal-backslash warnings, the collapsible-section gate (a
flatten-simulating app mode is refused and the original kept) and the MCP size
guard, and note navigation/error handling.
It does not launch UpNote or read/write your notes. Successful fake-app tests do not
prove compatibility with every UpNote build or editor state.

`UPNOTE_TEST_SERVER` can select a different server file. `UPNOTE_TEST_OUT` can retain
fixtures for debugging; its path must contain a directory named
`upnote-write-validation`. Without overrides, the suite uses this checkout's server
and a temporary directory. Existing formatting checks remain available:

```bash
python test_make_section.py
python test_nested_lists.py
```
