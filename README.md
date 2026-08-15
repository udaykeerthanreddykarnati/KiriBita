# KiriBita

A lightweight, native macOS clipboard manager built with Swift and AppKit.

## Features

- **Option + V Popup**: Opens a floating clipboard menu right at your cursor position.
- **Text & Image Support**: Captures copied text, rich strings, and images with thumbnail previews.
- **Top-Down History**: New copies appear at the top (`1.`, `2.`, `3.`) and push older items down.
- **Quick Paste**: Press `1`–`9`, arrow keys + `Enter`, or click to paste directly into your active app.
- **Pinning**: Lock key snippets to the top of your list.
- **Option + Backspace**: Delete items one by one (hold down to clear sequentially).

## Quick Start

### 1. Clone & Build

```bash
git clone https://github.com/udaykeerthanreddykarnati/KiriBita.git
cd KiriBita
swiftc -O ClipManager.swift -o KiriBita -framework AppKit -framework Carbon
./KiriBita
```

### 2. Usage

- Press **`Option + V`** anywhere on your Mac to toggle the clipboard panel.
- Press **`1`–`9`** or **`Enter`** to paste immediately into your active app.
- Press **`Option + Backspace`** while open to delete items one by one.
