# How editing works

Details for the editing tools. The [README](../README.md) has the summary.

## Replacing a note

UpNote has no link that edits a note, so `replace_note` creates a corrected copy and moves the
original to Trash. It takes two calls: a preview that changes nothing, then the replacement,
which has to pass back the revision number and the `preview_token` the preview returned. The
token is a digest of the call's arguments, so the replacement can only carry out what the
preview showed; `append_to_note`, `move_note` and `make_section` work the same way. Without `text` it keeps the body
as it is, for a call that only changes tags, the title or the notebook. When `text` is given, the
preview warns if it is empty, keeps fewer than half of the original's lines, or holds markup that
would be removed as unsafe.

The preview refuses when something would be lost for good: attachments or images, links from
other notes, a web share link, or a template. It also refuses a note already in Trash, and one in
a notebook whose title another notebook shares. It warns, and the replacement needs those
warnings accepted, when the note is pinned or bookmarked, sits in more than one
notebook, has been saved 20 or more times, has collapsible sections or a body over 20,000
characters, or was edited in the last ten minutes.

A body over 30,000 characters is refused through MCP: some clients pass such inputs cut, and a
cut body has written a truncated note. Edit large notes through a direct import of `server.py`
instead, passing `server_only=True` to skip this check - see [Editing very large notes](#editing-very-large-notes).

When the replacement is confirmed, the server compares the collapsible-section counts of the body
it sent with the copy UpNote saved. UpNote's re-parser has dropped the section wrappers of large
notes on re-parse (2026-11-09: a 59KB note lost 15 of 16 wrappers, progressively over three
rebuilds). If any wrapper was lost, the original stays in place and the result is `done=false`
naming what was dropped. The preview carries the counts in a `structure` object, `current` for the
note as it is and `sent` for the body submitted, so a flatten shows before applying. A collapsed
section may legitimately come back expanded, so `collapsed_sections` never gates a write; prefer
`make_section` or `append_to_note` for notes that hold sections, and hand edits in the UpNote app
for anything else.

The trigger is not size alone: a 60KB note rebuilt cleanly the same day the 59KB one flattened,
so the gate stays armed on every rebuild however large the note.

The new version keeps the original's tags. UpNote stores a tag as a hashtag link inside the note,
so the server adds one at the end for each tag the new text doesn't already carry, and waits until
UpNote has recorded them. To drop a tag, name it in `remove_tags`: its links are taken out, and
one inside a sentence becomes plain text. `add_tags` adds tags. Pin and bookmark can't be
carried over: no link sets them (tested 2026-10-10; UpNote answers "This link is not supported."
for routes such as `note/pin`), so the preview warns about them.

The original goes to Trash only after the new version is confirmed: in its notebook, with exactly
the expected tags, with every word of the text sent, and only if nobody changed the original in
the meantime. For the tools that keep the content, `append_to_note`, `move_note` and
`make_section`, every line of the original's text must also be in the new version. If anything
fails after the new version was requested, the tool says so, leaves the original in place and
tells Claude not to call again. If the original is edited in the moment before it goes to Trash,
the result says so. The new version gets a new id and creation date, so Version History stays with
the original. If the new version doesn't appear in time, the result gives a `run_select` query that
finds it by its marker, and calling the tool again for that note within five minutes is refused,
or names the late copy once it exists, so a retry can't make a third note. A call on a note already
in Trash names any live note with the same title, to be checked with `get_note` before it is edited.
A late copy the user moved to Trash no longer blocks the note.

Line breaks between HTML tags are removed only outside `<pre>` blocks, Markdown code fences at any
indent and indented code, so a code example keeps its layout. Line breaks inside a `<pre>` are
sent as `&#10;`, which UpNote stores as real ones, so a code block with an empty line isn't split.
The second `$` of a `$$` inside one is sent as `&#36;`: UpNote pairs `$$` into a formula on the raw
text, and a pair reaching into a block would eat its opening tag. For the same reason `![`, `](` and `]:` in a code
block are sent as character references, which read the same, so its content can't form an image or
a link even if it were read as Markdown. A note made outside UpNote's create link may have no title
heading, its title being its first line; that line isn't repeated under the new version's title.
The exception is a note whose first line sits in a code block or a list: that line stays where it
is, so the new version shows it twice, once as the title. A note created by link without a title
stays untitled (tested 2026-10-10), so the title can't be left to the body. HTML sent back from
`get_note` that starts with bare text is wrapped in a `<div>`, so it isn't read as Markdown. In
the note's own HTML, text holding `==` or `$$` is put in a `<span>`, since UpNote would otherwise
turn it into a highlight or a formula; in new Markdown text, `==text==` is still a highlight.

`notebook` puts the new version in another notebook, and `move_note` does only that: it rebuilds
the note unchanged in the notebook you name. UpNote has no link that moves a note, so a move costs
what a replace does: a new id, and pin and bookmark set again by hand.

Hand-written raw HTML, such as a collapsible section copied from the note's own `get_note` html,
survives the round-trip: UpNote re-parses it as native formatting (2026-09-24, UpNote 9.22.2).

## Adding to a note

`append_to_note` takes only the new content, in Markdown, and adds it after everything already in
the note. The server copies the existing content itself, so Claude never resends a long note, and
nothing in it can be dropped or reworded on the way. It rebuilds the note through `replace_note`,
with the same preview, warnings and checks, so the result has a new id and the original goes to
Trash.

`insert_after_heading` adds content next to a heading instead of at the end: `position="after"`
(default) puts it under the heading named, `"before"` above it. The anchor must be a heading that
is not a collapsible section's title. As with `append_to_note`, the caller sends only the new
content, and the bytes already in the note pass through the rebuild unchanged.

Which tool to reach for, by note:

- A small note without collapsible sections: `replace_note` or `insert_after_heading` over MCP.
- A note that holds collapsible sections: `make_section` or `append_to_note` over MCP, or
  `insert_after_heading` for a mid-note insertion; the gate covers all three rebuilds. Avoid a
  full-body `replace_note` - the fewer bytes re-parsed, the less UpNote's re-parser can drop.
- A large note (over 20,000 characters): edit through a direct import of `server.py` regardless
  of tool; MCP refuses bodies over 30,000 characters, and 20-30KB passes the size check but still
  round-trips the whole body. See [Editing very large notes](#editing-very-large-notes).

The existing HTML goes first, then a blank line, then the new Markdown. The blank line makes
UpNote convert what follows as Markdown. If the note ends with a list and the new text starts
with one, UpNote joins them into one list. Tag links are moved below the new content, so a
note's tags stay at its end however often it's appended to. A hashtag inside a sentence stays
where it is.

Every rebuild, by `replace_note`, `append_to_note` or `make_section`, first removes line breaks
between block tags. A browser ignores them, but UpNote's create link turns each one into an empty
`<div>`, so a note would collect them with every rebuild. A line break between inline tags, such
as `</b>` and `<i>`, shows as a space and is kept; UpNote keeps it too (2026-10-10, UpNote 9.22.6).

## Editing very large notes

MCP clients can cut tool inputs of this size, so the tools refuse a body over 30,000 characters.
To edit such a note, import `server.py` directly and call the tool function with `server_only=True`.
Keep the two-step flow: preview first, then apply with the revision and token the preview returned.

```python
import importlib.util
spec = importlib.util.spec_from_file_location("upnote_server", "/path/to/server.py")
srv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(srv)

p = srv.replace_note(note_id="...", text=new_text, server_only=True)   # preview, changes nothing
# read p["warnings"] and p["structure"], then apply:
srv.replace_note(note_id="...", text=new_text, server_only=True,
                 expected_revision=p["revision"], preview_token=p["preview_token"],
                 acknowledge_warnings=bool(p["warnings"]))
```

Run it with the server's venv Python. The same checks apply as over MCP, including the
collapsible-section gate. Edit a note that holds sections by hand in UpNote when the gate refuses.

## Nested sections

UpNote's editor can't put a collapsible section inside another one, but it renders and syncs them
correctly, and keeps them when you edit the note by hand. `make_section` builds them: name a heading
inside an existing section, and the heading with the content under it becomes a section nested there.
The section holds everything to the next heading of the same or higher level, or to the end of its
container, and `collapsed=true` makes it start closed.

Content marked off by hand works too: pass `until` with the text of an end marker, and the section runs
from the heading to that marker, both markers being removed. `title` names the section when the heading
itself is only a marker.

It previews first, the same as `replace_note`, and rebuilds the note the same way, so the result has a
new id. Everything outside the wrapped range is copied through unchanged, apart from the line breaks
between block tags that every rebuild removes. It refuses a heading it
can't find, one that appears twice, one that is already a section's title, one with nothing under it,
an `until` marker it can't find after the heading, and any note whose own title heading holds extra
content, since rebuilding that would duplicate it.
