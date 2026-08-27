# MacDown

MacDown is an open source Markdown editor for OS X, released under the MIT License. The author stole the idea from [Chen Luo](https://twitter.com/chenluois)’s [Mou](http://mouapp.com) so that people can make crappy clones.

This is a fork of [MacDown](https://github.com/MacDownApp/macdown) by Tzu-ping Chung.

## Screenshot

![screenshot](assets/screenshot.png)

## License

MacDown is released under the terms of MIT License. You may find the content of the license [here](http://opensource.org/licenses/MIT), or inside the `LICENSE` directory.

You may find full text of licenses about third-party components in the `LICENSE` directory, or the **About MacDown** panel in the application.

The following editor themes and CSS files are extracted from [Mou](http://mouapp.com), courtesy of Chen Luo:

* Mou Fresh Air
* Mou Fresh Air+
* Mou Night
* Mou Night+
* Mou Paper
* Mou Paper+
* Tomorrow
* Tomorrow Blue
* Tomorrow+
* Writer
* Writer+
* Clearness
* Clearness Dark
* GitHub
* GitHub2

## Development

### Requirements

* Xcode 26 or later, for the macOS 26 SDK. The deployment target is macOS
  26.0, so an older SDK will not build this.
* Git
* CocoaPods

> The Command Line Tools alone are not enough. `xcodebuild` refuses to run
> against them:
>
>     xcode-select: error: tool 'xcodebuild' requires Xcode, but active
>     developer directory is a command line tools instance
>
> If Xcode is installed but `xcode-select` points elsewhere, either repoint
> it or set `DEVELOPER_DIR` for the build.

> CocoaPods is easiest from Homebrew — `brew install cocoapods` — which
> brings its own Ruby. The Ruby that ships with macOS is too old for current
> CocoaPods, so `gem install cocoapods` against it tends to end without a
> usable `pod`. The `Gemfile` route works too if you already run a modern
> Ruby.

### Environment Setup

After cloning the repository, run the following inside the repository root:

    git submodule update --init
    pod install
    make -C Dependency/peg-markdown-highlight

and open `MacDown.xcworkspace` — the workspace, not the project; the project
alone has no pods. The first command fetches the dependency submodules, the
second installs the CocoaPods dependencies.

If a build fails later on after pulling, the same two commands usually
account for it:

    git submodule update
    pod install

## Credits

MacDown depends a lot on other open source projects, such as [Hoedown](https://github.com/hoedown/hoedown) for Markdown-to-HTML rendering, [Prism](http://prismjs.com) for syntax highlighting (in code blocks), and [PEG Markdown Highlight](https://github.com/ali-rantakari/peg-markdown-highlight) for editor highlighting. If you find problems with those particular features, it is often worth reporting them upstream as well.
