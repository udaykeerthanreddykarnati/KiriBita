# KiriBita (切り板)

A lightweight, native macOS clipboard manager built with Swift and AppKit.

## Features

- **Option + V Popup**: Opens a floating clipboard menu right at your cursor position.
- **Text & Image Support**: Captures copied text, rich strings, and images with thumbnail previews.
- **Top-Down History**: New copies appear at the top (`1.`, `2.`, `3.`) and push older items down.
- **Quick Paste**: Press `1`–`9`, arrow keys + `Enter`, or click to paste directly into your active app.
- **Pinning**: Lock key snippets to the top of your list.
- **Option + Backspace**: Delete items one by one (hold down to clear sequentially).

## Requirements

- macOS 12.0+

## Building

```bash
swiftc -O ClipManager.swift -o KiriBita -framework AppKit -framework Carbon
./KiriBita
```
