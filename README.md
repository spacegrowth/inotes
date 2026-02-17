# iNotes

A minimal macOS menu bar scratchpad. 3 notes, auto-save, keyboard shortcut.

**This app was entirely developed by Claude (Anthropic's AI) in a single conversation with a human providing direction and feedback.**

![macOS](https://img.shields.io/badge/macOS-14.0+-black)

## Features

- Lives in the menu bar — no dock icon, no clutter
- 3 note tabs with instant switching
- Auto-saves to disk (debounced, atomic writes)
- Global keyboard shortcut (default: Cmd+Shift+1, configurable via right-click menu)
- Light/dark mode follows system theme
- Long-press tab names to rename them
- Text editor auto-focuses on open

## Install

### Download (easiest)
1. Go to [Releases](../../releases) and download `iNotes.zip`
2. Unzip and drag `iNotes.app` to `/Applications`
3. Open it — macOS may warn about unidentified developer, right-click > Open to bypass

### Build from source
```bash
brew install xcodegen
git clone https://github.com/YOUR_USERNAME/inotes.git
cd inotes
xcodegen generate
xcodebuild -scheme iNotes -configuration Release -destination 'platform=macOS' build
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/iNotes-*/Build/Products/Release/iNotes.app`

## Usage

- **Click** the pencil icon in the menu bar to open/close
- **Cmd+Shift+1** to toggle from anywhere
- **Right-click** the icon to change the shortcut or quit
- **Long-press** a tab name to rename it
- Notes are saved to `~/Library/Application Support/iNotes/notes.json`

## Tech

- SwiftUI + AppKit (NSPanel, NSTextView, Carbon hotkeys)
- ~770 lines of Swift
- No dependencies, no frameworks, no packages

## License

MIT — do whatever you want with it.
