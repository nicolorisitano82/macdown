# Contributing

For what is worth working on, see the **Contributing** page in the
application's Help menu, or `MacDown/Resources/contribute.md`. This file is
about how the code here is written.

## Before you start

Some of this codebase will surprise you. These are the parts that have cost
the most time.

**Open the workspace, not the project.** `MacDown.xcworkspace` has the pods;
`MacDown.xcodeproj` on its own does not build.

**The Debug build has its own preferences.** Its bundle identifier ends in
`-debug`, so it reads a different defaults domain from a Release build. A
setting you turn on while debugging is not on in the app you ship, and a
feature can look fine in Debug and be dead in Release for no other reason.
When a feature depends on a preference, test the Release build too.

**The preview runs on WebKit's legacy `WebView`.** It is refreshed by
replacing the document's `innerHTML`, which does *not* re-execute the page's
scripts. Anything injected into the preview has to expose a function that
`MPDocument` can call again after each refresh — see how `mermaid.init.js`
and `diagram-zoom.js` do it. Binding to the `load` event alone means your
code runs once and never again after the first keystroke.

**`Resources/Data` and `Resources/Extensions` are folder references.** Files
dropped in there ship with the app without touching the project file. Adding
a `.m` still means editing the project.

**Deployment target is macOS 26.0**, so Xcode 26 or later is required. The
Command Line Tools cannot stand in for Xcode. The README has the setup
steps.

## Coding style

These rules hold everywhere except in external dependencies.

### The 80-column rule

All code obeys it.

The exception is a URL in a comment that cannot be shortened. Many can:
StackOverflow drops its title slug, and a GitHub commit hash can be cut to
its first seven characters, so all of these are the same page:

    https://github.com/nicolorisitano82/macdown/commit/1612abb9dbd24113751958777a49cffc6767989c
    https://github.com/nicolorisitano82/macdown/commit/1612abb9dbd24
    https://github.com/nicolorisitano82/macdown/commit/1612abb

### Braces and blocks

Braces go on their own line — [Allman style](https://en.wikipedia.org/wiki/Indentation_style#Allman_style).

A block holding a single statement omits its braces, unless it is part of an
`if`/`else if`/`else` chain: within one chain, either all of the blocks have
braces or none do.

### Conditions

Prefer an implicit boolean conversion where it reads as one. `if (str.length)`
says "if the string has anything in it" better than `if (str.length != 0)`,
and the same goes for checking an object against `nil`.

Where the comparison really is against *zero as a number* — an `NSRange`
location, an `NSPoint` coordinate — write `== 0` or `!= 0` and mean it.

When a condition spans lines, the logical operator starts the line:

```objc
while (this_is_very_long
       || this_is_also_very_long)
{
    // ...
}
```

not

```objc
while (this_is_very_long ||
       this_is_also_very_long)
{
    // ...
}
```

Where the wrapping would leave the condition looking like the body, indent it
further:

```objc
if (this_is_very_long
        || this_is_also_very_long)
    foo++;
```

Braces make that unambiguous on their own, so with them the extra
indentation is optional — useful when a line is fighting the 80-column
limit:

```objc
if (this_is_very_long
    || this_is_very_very_truly_long)
{
    foo++;
    bar--;
}
```

### Whitespace

Four spaces, never tabs. No trailing whitespace — Xcode's **Automatically
trim trailing whitespace** does it for you. End files with a newline.

### Comments

Comment the reasoning, not the mechanics: what the code does is already
there to read, why it does it that way usually is not. Most of the comments
worth writing in this codebase record a constraint that is not visible from
the call site — a format that refuses something, an API that behaves
differently than its name suggests, a workaround for a bug in a dependency.

## Version control

### Commit messages

[The general rules](https://cbea.ms/git-commit/) apply: a summary line, a
blank line, then the body wrapped at 72 columns. The summary can run to 72
characters if it must, but not further.

Write the body for someone reading the log in two years with no memory of
the change. Say what was wrong and why the fix is shaped the way it is,
rather than restating the diff.

### Pull requests

Rebase onto `master` before opening one. Git merges `.xib` files and the
project file badly, and a rebase avoids most of the trouble. Smaller commits
help for the same reason: when a merge does go wrong, there is less to
reapply.

Your branch may be asked to be rebased or squashed again after review. The
history stays yours either way.

### Verifying a change

Building is not testing. A change to the preview, to an exporter or to
anything that touches WebKit needs to be run and looked at — most of the
faults this project has had passed the compiler without complaint.

Exporters are worth checking against something other than the app that wrote
the file: open the `.docx` in Word or LibreOffice, put the `.epub` through
[epubcheck](https://www.w3.org/publishing/epubcheck/), unzip either and read
the XML. A file that opens in one reader and not another is the usual way
these break.
