# Contributing

This is a fork of [MacDown](https://github.com/MacDownApp/macdown) by
Tzu-ping Chung, brought up to macOS 26 and extended: EPUB and Word export
that survive the trip, diagrams you can zoom, a maths editor, a sidebar,
and a prose checker.

The source is at
[github.com/nicolorisitano82/macdown](https://github.com/nicolorisitano82/macdown).

## Building it

You will need Xcode 26 or later, for the macOS 26 SDK — the deployment
target is macOS 26.0, so an older SDK will not build this. The Command Line
Tools cannot stand in for Xcode.

    git clone https://github.com/nicolorisitano82/macdown.git
    cd macdown
    git submodule update --init
    pod install

Then open `MacDown.xcworkspace` — the workspace, not the project, which on
its own has no pods. CocoaPods is easiest from Homebrew; the Ruby that ships
with macOS is too old for current versions of it.

The README has the longer version, including what to do when a build starts
failing after a pull.

## Worth doing

Some things are known to be missing or half-done. In rough order of how much
they would improve the app:

- **The preview still runs on WebKit's legacy `WebView`**, deprecated since
  macOS 10.14. Moving to `WKWebView` means rewriting the parts that reach
  into the page synchronously — word count, scroll syncing, the MathJax
  bridge, printing — because the modern API is asynchronous. It is the
  single largest thing left.
- **Maths does not survive an EPUB export.** Scripts are stripped from the
  package, quite rightly, and TeX is left visible as its source. The fix is
  the one already used for diagrams: take the SVG MathJax has drawn in the
  preview and inline it.
- **The prose checker's category names are English** even when it is
  flagging Italian, because the lists share their categories. Translating
  them means deciding whether the names follow the application's language or
  the document's, and the second needs to know what language a document is
  in.
- **Releases are unsigned.** Anyone downloading one has to strip the
  quarantine attribute by hand. Fixing it needs an Apple Developer account,
  not code.

Word lists for the prose checker live in
`MacDown/Resources/Data/prose-issues.json` and can be extended or translated
without touching any code or rebuilding.

## Reporting something broken

Open an issue on
[this repository](https://github.com/nicolorisitano82/macdown/issues),
whatever it turns out to be. Whether a fault comes from this fork, from the
MacDown it grew out of, or from one of the libraries underneath is rarely
obvious from the outside, and working that out belongs to whoever picks the
issue up rather than to you.

Say what you did, what happened, and what you expected instead. A document
that reproduces it is worth more than a description of one.

MacDown Next leans on other open source projects: [Hoedown](https://github.com/hoedown/hoedown)
turns Markdown into HTML, [Prism](https://prismjs.com) highlights code,
[PEG Markdown Highlight](https://github.com/ali-rantakari/peg-markdown-highlight)
highlights the editor, [mermaid](https://mermaid.js.org) and
[Graphviz](https://graphviz.org) draw the diagrams, and
[MathJax](https://www.mathjax.org) sets the maths. They have the credit for
the parts they do; the issues still come here.

## License

The original MacDown code is under the MIT License. See the `LICENSE`
directory for that and for the licences of the third-party components, or
the **About MacDown Next** panel in the application.
