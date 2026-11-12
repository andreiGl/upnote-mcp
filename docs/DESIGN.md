# Design notes

How the server keeps your library safe. The [README](../README.md) has the summary.

## How changes are made

- **Reads** use a read-only SQLite connection. An authorizer refuses everything except reading,
  including writes, PRAGMA and ATTACH.
- **Create** sends UpNote's documented `note/new` link. The body is Markdown, with raw HTML for
  what Markdown can't express, such as UpNote's collapsible sections. The formatting guide Claude
  follows is part of the tool's description.
- **Trash and restore** send `note/moveToTrash` and `note/restore`. Neither is in UpNote's
  documentation, but both are in the app's link handler. The tool checks the note in the
  database first, so UpNote only ever receives ids that exist.
- **The database format is checked on every connection.** If an UpNote update removes a table or
  column the server reads, tools fail with the missing column named instead of returning wrong
  results. `check_upnote_setup` also warns when UpNote's data version, read from `config.json`
  next to the database, isn't the tested version 17.
- **Every change is confirmed.** The tool polls the database until UpNote has saved the change.
  Each step, the note itself, its notebook, its tags and Trash, waits up to ten seconds, so a
  replace can take longer in all. A new note carries an invisible marker, an empty
  `<span data-upnote-mcp="…">`, so the server recognises the note its own link created even if
  another device creates one with the same title meanwhile. A rebuild drops the old marker.
- **Nothing that could run code or send data out is sent.** Before a link goes out, the server
  removes scripts, frames, event-handler attributes, styles that load URLs, `javascript:` and
  `data:` links, and UpNote links that change notes, such as a planted trash link. Remote images
  become links, since showing an image fetches its URL, and that URL could carry text copied from
  another note. Code fences are sent as escaped code blocks, and inline code as escaped `<code>`,
  which reads the same and leaves Markdown nothing to pair: UpNote pairs backticks across a line
  break and `$$` across the whole text, so code written in Markdown isn't always read as code.
  Indented code after a blank line is kept as written when nothing in it could act even read as
  markup (no `![`, no unsafe `upnote:` URL, no tag left open), and otherwise sent as an escaped
  code block. An indented line that continues a paragraph isn't code and is checked as text. One
  limit: indented code inside a list or blockquote, and a fence inside a blockquote or a list nested
  two deep, that holds unsafe markup is checked as text, so its unsafe tags are removed (and
  reported) and a `<` in it may show as `&lt;`. An unclosed `<pre>` is text,
  as an unclosed `<script>` is. Text that only looks like a tag, such as
  `<YOUR_TOKEN>`, `List<String>` or `a<b && c>d`, is shown as written: only a tag Markdown would
  read, naming an element that exists, counts as markup. Autolinks and email addresses in angle
  brackets become links. UpNote turns any URL in plain text into a link after its own clean-up, so
  a plain-text `upnote://` link that would change notes is split where it can't become one. It is
  judged as UpNote reads it: up to the characters UpNote's own linker stops at, with parameter
  names percent-decoded, routes matched exactly and `.` or `..` segments refused, so any shorter part
  UpNote might link is safe too. A safe UpNote link written directly against other text, as in
  `[a](upnote://x-callback-url/view)=`, is split as well and shows as plain text. A first
  line of `---` is sent as `***`, the same horizontal rule, since UpNote would read it as the start
  of front matter and drop the block it closes. Everything removed is reported, in the preview's warnings and in
  `create_note`'s `removed_unsafe`. `open` and `ps` are run by
  absolute path, since the server has Full Disk Access and `PATH` can hold folders any program of
  this user can write to.

## Shared operation state

Rebuild/trash operations serialize per original note with a cross-process lock. A
private pending marker is journaled before dispatch, so another process or a restarted
server checks for the same in-flight copy before requesting another. Journals contain
only a marker and timestamp, not note content.

Default state is `.local/state/upnote-mcp` under the OS account home, independent of a
client profile's `HOME`. An explicit `UPNOTE_MCP_STATE_DIR` override must be the same
for every client operating on the same database. The directory must be owned by the
user and private (0700); pending files and lock files are private (0600). Fixtures use
isolated state. All affected MCP processes must use this version before concurrent
writes are enabled; older processes ignore these locks.

The pending window is five minutes, and `create_note` is not idempotent.
Never blindly retry an uncertain create or apply: read the original and any new copy
first. These checks coordinate requests; they do not make UpNote's URL interface a
transaction or eliminate app-side failures.

## Opening notes after restore

UpNote can leave the editor blank when an `openNote` link targets a restored note.
The server opens its containing notebook first, then opens the note. For an
unfiled note it resets to All Notes; for a trashed note it resets to Trash. The
notebook path was visually verified with disposable notes through Claude and Codex
CLI and desktop clients. The unfiled and Trash reset branches have synthetic test
coverage, rather than live visual acceptance.

The tool returns `sent=true` only for successful URL dispatch. It cannot verify
what the editor displays. An active app search can still constrain navigation. These links change the
visible view and foreground app, so use the tool when the user asks to see content.
