import AppKit
import Carbon

// MARK: - THEME MANAGER INTEGRATION
extension NSColor {
    convenience init?(hex: String) {
        var c = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if c.hasPrefix("#") { c.removeFirst() }
        guard c.count == 6, let rgb = UInt32(c, radix: 16) else { return nil }
        self.init(calibratedRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(rgb & 0xFF) / 255.0,
                  alpha: 1.0)
    }
}

class WidgetTheme {
    static let shared = WidgetTheme()
    static let notifName = Notification.Name("com.user.CustomER.themeChanged")

    var textColor: NSColor {
        if let hex = UserDefaults.standard.string(forKey: "custom_text_color_hex"), let c = NSColor(hex: hex) {
            return c
        }
        return NSColor(hex: "#800020") ?? .labelColor
    }

    var bgColor: NSColor {
        if let hex = UserDefaults.standard.string(forKey: "custom_bg_color_hex"), let c = NSColor(hex: hex) {
            return c
        }
        return NSColor(hex: "#FEF9C3") ?? .windowBackgroundColor
    }

    var surfaceColor: NSColor {
        return NSColor.white
    }

    var accentColor: NSColor {
        if let hex = UserDefaults.standard.string(forKey: "custom_accent_color_hex"), let c = NSColor(hex: hex) {
            return c
        }
        return NSColor(hex: "#800020") ?? .controlAccentColor
    }

    var dimColor: NSColor {
        return NSColor(hex: "#595940") ?? NSColor.secondaryLabelColor
    }

    var borderColor: NSColor {
        return NSColor.black
    }

    var fontName: String? {
        return UserDefaults.standard.string(forKey: "custom_font_name")
    }

    func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let customName = fontName, !customName.isEmpty, !customName.hasPrefix("."), !customName.contains("System Font") {
            let isBold = (weight == .bold || weight == .heavy || weight == .black || weight == .semibold)
            let fontTraits: NSFontTraitMask = isBold ? .boldFontMask : []

            if let font = NSFont(name: customName, size: size) {
                return isBold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
            }
            if let font = NSFontManager.shared.font(withFamily: customName, traits: fontTraits, weight: isBold ? 9 : 5, size: size) {
                return font
            }
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
}

// MARK: - DATA MODEL
enum ClipType: String, Codable {
    case text
    case image
}

struct ClipItem: Codable, Identifiable {
    let id: String
    var itemType: ClipType?
    let text: String
    var imageFileName: String?
    let date: Date
    var isPinned: Bool

    var type: ClipType {
        return itemType ?? .text
    }

    var lineCount: Int {
        return text.components(separatedBy: .newlines).count
    }

    var charCount: Int {
        return text.count
    }
}

// MARK: - HISTORY STORE
class HistoryStore {
    static let shared = HistoryStore()
    static let notifName = NSNotification.Name("com.clipmanager.historyChanged")

    private let baseDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClipManager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var fileURL: URL {
        return baseDir.appendingPathComponent("history.json")
    }

    private var imagesDir: URL {
        let dir = baseDir.appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private(set) var items: [ClipItem] = []
    let maxItems = 50

    private init() {
        load()
    }

    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let first = items.first, first.type == .text && first.text == text { return }

        items.removeAll { !$0.isPinned && $0.type == .text && $0.text == text }

        let newItem = ClipItem(id: UUID().uuidString, itemType: .text, text: text, imageFileName: nil, date: Date(), isPinned: false)
        insertNewItem(newItem)
    }

    func addImage(image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let id = UUID().uuidString
        let fileName = "\(id).png"
        let fileDest = imagesDir.appendingPathComponent(fileName)

        do {
            try pngData.write(to: fileDest)
            let width = Int(image.size.width)
            let height = Int(image.size.height)
            let desc = "Image (\(width) × \(height))"

            let newItem = ClipItem(id: id, itemType: .image, text: desc, imageFileName: fileName, date: Date(), isPinned: false)
            insertNewItem(newItem)
        } catch {
            print("Failed to save image to disk: \(error)")
        }
    }

    private func insertNewItem(_ newItem: ClipItem) {
        if let lastPinnedIdx = items.lastIndex(where: { $0.isPinned }) {
            items.insert(newItem, at: lastPinnedIdx + 1)
        } else {
            items.insert(newItem, at: 0)
        }

        let pinnedCount = items.filter { $0.isPinned }.count
        let unpinnedLimit = maxItems - pinnedCount
        let unpinned = items.filter { !$0.isPinned }
        if unpinned.count > unpinnedLimit {
            let overflow = unpinned.suffix(unpinned.count - unpinnedLimit)
            for oldItem in overflow {
                if let f = oldItem.imageFileName {
                    let imgURL = imagesDir.appendingPathComponent(f)
                    try? FileManager.default.removeItem(at: imgURL)
                }
            }
            items.removeAll { item in overflow.contains(where: { $0.id == item.id }) }
        }

        save()
        notify()
    }

    func loadImage(for item: ClipItem) -> NSImage? {
        guard item.type == .image, let f = item.imageFileName else { return nil }
        let imgURL = imagesDir.appendingPathComponent(f)
        return NSImage(contentsOf: imgURL)
    }

    func togglePin(id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isPinned.toggle()
            let pinned = items.filter { $0.isPinned }
            let unpinned = items.filter { !$0.isPinned }
            items = pinned + unpinned
            save()
            notify()
        }
    }

    func delete(id: String) {
        if let item = items.first(where: { $0.id == id }) {
            if let f = item.imageFileName {
                let imgURL = imagesDir.appendingPathComponent(f)
                try? FileManager.default.removeItem(at: imgURL)
            }
            items.removeAll { $0.id == id }
            save()
            notify()
        }
    }

    func clearUnpinned() {
        let unpinned = items.filter { !$0.isPinned }
        for oldItem in unpinned {
            if let f = oldItem.imageFileName {
                let imgURL = imagesDir.appendingPathComponent(f)
                try? FileManager.default.removeItem(at: imgURL)
            }
        }
        items.removeAll { !$0.isPinned }
        save()
        notify()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL)
        }
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: HistoryStore.notifName, object: nil)
        }
    }
}

// MARK: - PASTEBOARD MONITOR
class PasteboardMonitor {
    static let shared = PasteboardMonitor()
    var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastCount else { return }
        lastCount = currentCount

        // 1. First check if pasteboard contains an Image
        if let image = NSImage(pasteboard: NSPasteboard.general) {
            HistoryStore.shared.addImage(image: image)
            return
        }

        // 2. Otherwise check for Text
        var capturedText: String? = nil
        if let text = NSPasteboard.general.string(forType: .string) {
            capturedText = text
        } else if let objects = NSPasteboard.general.readObjects(forClasses: [NSString.self], options: nil) as? [String],
                  let first = objects.first {
            capturedText = first
        }

        if let text = capturedText {
            HistoryStore.shared.add(text: text)
        }
    }
}

// MARK: - CLICKABLE ROW VIEW
class ClipRowView: NSView {
    var itemID: String = ""
    var onSelect: ((String) -> Void)?
    var onPinToggle: ((String) -> Void)?

    private var isHovered = false
    private let trackingArea = NSTrackingArea()

    var isSelected = false {
        didSet {
            needsDisplay = true
            updateColors()
        }
    }

    func updateColors() {
        wantsLayer = true
        layer?.cornerRadius = 0
        let theme = WidgetTheme.shared
        if isSelected {
            layer?.backgroundColor = theme.accentColor.withAlphaComponent(0.20).cgColor
            layer?.borderColor = theme.accentColor.cgColor
            layer?.borderWidth = 1.5
        } else if isHovered {
            layer?.backgroundColor = theme.textColor.withAlphaComponent(0.08).cgColor
            layer?.borderColor = theme.borderColor.withAlphaComponent(0.30).cgColor
            layer?.borderWidth = 1.0
        } else {
            layer?.backgroundColor = theme.surfaceColor.withAlphaComponent(0.85).cgColor
            layer?.borderColor = theme.borderColor.withAlphaComponent(0.18).cgColor
            layer?.borderWidth = 1.0
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        removeTrackingArea(trackingArea)
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateColors()
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if loc.x > bounds.width - 36 {
            onPinToggle?(itemID)
        } else {
            onSelect?(itemID)
        }
    }
}

// MARK: - CUSTOM SEARCH FIELD
class KeyHandlingSearchField: NSTextField {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyDown?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - FLIPPED STACK VIEW
class FlippedStackView: NSStackView {
    override var isFlipped: Bool { return true }
}

// MARK: - CLIPBOARD POPUP CONTROLLER
class ClipPopupController: NSViewController, NSTextFieldDelegate {
    private let titleLabel    = NSTextField()
    private let countLabel    = NSTextField()
    private let clearBtn      = NSButton()
    private let searchField   = KeyHandlingSearchField()
    private let cardView      = NSView()
    private let scrollView    = NSScrollView()
    private let stackView     = FlippedStackView()

    private var filterQuery: String = ""
    private var selectedIndex: Int = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 440))
        buildUI()
        listenForNotifications()
        setupKeyMonitor()
        applyTheme()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        searchField.stringValue = ""
        filterQuery = ""
        selectedIndex = 0
        applyTheme()
        renderHistory()
        view.window?.makeFirstResponder(searchField)
    }

    private func buildUI() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 0
        view.layer?.borderWidth = 1.0

        titleLabel.stringValue = "CLIPBOARD HISTORY"
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        view.addSubview(titleLabel)

        countLabel.stringValue = ""
        countLabel.isEditable = false; countLabel.isBordered = false; countLabel.backgroundColor = .clear
        view.addSubview(countLabel)

        clearBtn.title = "Clear"
        clearBtn.isBordered = false
        clearBtn.wantsLayer = true
        clearBtn.layer?.cornerRadius = 0
        clearBtn.target = self
        clearBtn.action = #selector(clearTapped)
        view.addSubview(clearBtn)

        searchField.placeholderString = "Search clipboard history... (Type or 1-9 to paste)"
        searchField.isBordered = true
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 0
        searchField.onKeyDown = { [weak self] event in
            return self?.handleKeyEvent(event) ?? false
        }
        view.addSubview(searchField)

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 0
        cardView.layer?.borderWidth = 1.0
        view.addSubview(cardView)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        stackView.orientation = .vertical
        stackView.spacing = 6
        stackView.alignment = .leading
        stackView.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = stackView
        cardView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor)
        ])
    }

    private func applyTheme() {
        let theme = WidgetTheme.shared

        view.layer?.backgroundColor = theme.bgColor.cgColor
        view.layer?.borderColor = theme.borderColor.cgColor

        titleLabel.font = theme.font(size: 11, weight: .bold)
        titleLabel.textColor = theme.textColor

        countLabel.font = theme.font(size: 10, weight: .semibold)
        countLabel.textColor = theme.dimColor

        clearBtn.font = theme.font(size: 10, weight: .bold)
        clearBtn.layer?.backgroundColor = theme.accentColor.cgColor
        clearBtn.layer?.borderColor = theme.borderColor.cgColor
        clearBtn.layer?.borderWidth = 1.0
        clearBtn.contentTintColor = theme.surfaceColor

        searchField.font = theme.font(size: 11, weight: .medium)
        searchField.textColor = theme.textColor
        searchField.backgroundColor = theme.surfaceColor
        searchField.layer?.borderColor = theme.borderColor.cgColor

        cardView.layer?.backgroundColor = theme.surfaceColor.cgColor
        cardView.layer?.borderColor = theme.borderColor.cgColor
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width
        let h = view.bounds.height

        titleLabel.frame  = NSRect(x: 14, y: h - 28, width: 140, height: 18)
        countLabel.frame  = NSRect(x: 155, y: h - 28, width: 140, height: 18)
        clearBtn.frame    = NSRect(x: w - 64, y: h - 29, width: 50, height: 20)
        searchField.frame = NSRect(x: 12, y: h - 58, width: w - 24, height: 24)
        cardView.frame    = NSRect(x: 12, y: 12, width: w - 24, height: h - 76)

        scrollView.frame = cardView.bounds
    }

    func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField {
            filterQuery = tf.stringValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            selectedIndex = 0
            renderHistory()
        }
    }

    private func setupKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let w = self.view.window, w.isVisible else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 51 && mods.contains(.option) {
                self.deleteCurrentOrMostRecentItem()
                return nil
            }
            return event
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.deleteWordBackward(_:)) {
            deleteCurrentOrMostRecentItem()
            return true
        }
        return false
    }

    private func listenForNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(onHistoryChanged), name: HistoryStore.notifName, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: WidgetTheme.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: WidgetTheme.notifName, object: nil)
    }

    @objc private func onHistoryChanged() {
        renderHistory()
    }

    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            self.applyTheme()
            self.renderHistory()
        }
    }

    private func getFilteredItems() -> [ClipItem] {
        var items = HistoryStore.shared.items
        if !filterQuery.isEmpty {
            items = items.filter { $0.text.lowercased().contains(filterQuery) }
        }
        return items
    }

    private func renderHistory() {
        stackView.views.forEach { $0.removeFromSuperview() }
        let items = getFilteredItems()
        let theme = WidgetTheme.shared

        countLabel.stringValue = "\(items.count) items"

        let cardW = cardView.bounds.width > 0 ? cardView.bounds.width : 416
        let itemW = max(320, cardW - 24)

        if items.isEmpty {
            let emptyText = filterQuery.isEmpty ? "No clipboard history yet. Copy text or images anywhere!" : "No matches found."
            let emptyLabel = NSTextField(labelWithString: emptyText)
            emptyLabel.font = theme.font(size: 11, weight: .medium)
            emptyLabel.textColor = theme.dimColor
            emptyLabel.alignment = .center
            emptyLabel.heightAnchor.constraint(equalToConstant: 40).isActive = true
            stackView.addArrangedSubview(emptyLabel)
            return
        }

        let df = DateFormatter()
        df.dateFormat = "HH:mm"

        for (idx, item) in items.enumerated() {
            let rowH: CGFloat = 54
            let row = ClipRowView(frame: NSRect(x: 0, y: 0, width: itemW, height: rowH))
            row.itemID = item.id
            row.isSelected = (idx == selectedIndex)
            row.heightAnchor.constraint(equalToConstant: rowH).isActive = true

            row.onSelect = { [weak self] id in
                self?.pasteItemByID(id)
            }
            row.onPinToggle = { id in
                HistoryStore.shared.togglePin(id: id)
            }

            // Index/Hotkey Badge (1..9)
            let badgeText = idx < 9 ? "\(idx + 1)." : "•"
            let idxLabel = NSTextField(labelWithString: badgeText)
            idxLabel.font = theme.font(size: 11, weight: .bold)
            idxLabel.textColor = theme.accentColor
            idxLabel.isEditable = false; idxLabel.isBordered = false; idxLabel.backgroundColor = .clear
            idxLabel.frame = NSRect(x: 8, y: rowH - 24, width: 20, height: 16)
            row.addSubview(idxLabel)

            if item.type == .image, let img = HistoryStore.shared.loadImage(for: item) {
                // Render Thumbnail Image Preview
                let imgView = NSImageView(frame: NSRect(x: 28, y: 7, width: 60, height: 40))
                imgView.image = img
                imgView.imageScaling = .scaleProportionallyUpOrDown
                imgView.wantsLayer = true
                imgView.layer?.borderWidth = 1
                imgView.layer?.borderColor = theme.borderColor.withAlphaComponent(0.3).cgColor
                row.addSubview(imgView)

                let titleLabel = NSTextField(labelWithString: "IMAGE")
                titleLabel.font = theme.font(size: 11, weight: .bold)
                titleLabel.textColor = theme.textColor
                titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
                titleLabel.frame = NSRect(x: 96, y: 22, width: itemW - 132, height: 18)
                row.addSubview(titleLabel)

                let metaStr = "\(df.string(from: item.date)) (\(Int(img.size.width)) × \(Int(img.size.height)))"
                let metaLabel = NSTextField(labelWithString: metaStr)
                metaLabel.font = theme.font(size: 8.5, weight: .semibold)
                metaLabel.textColor = theme.dimColor
                metaLabel.isEditable = false; metaLabel.isBordered = false; metaLabel.backgroundColor = .clear
                metaLabel.frame = NSRect(x: 96, y: 6, width: itemW - 132, height: 14)
                row.addSubview(metaLabel)
            } else {
                // Render Text Snippet Preview
                let cleanText = item.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
                let textLabel = NSTextField(wrappingLabelWithString: cleanText)
                textLabel.font = theme.font(size: 11, weight: .bold)
                textLabel.textColor = theme.textColor
                textLabel.maximumNumberOfLines = 2
                textLabel.lineBreakMode = .byTruncatingTail
                textLabel.isEditable = false; textLabel.isBordered = false; textLabel.backgroundColor = .clear
                textLabel.frame = NSRect(x: 28, y: 18, width: itemW - 64, height: 30)
                row.addSubview(textLabel)

                let linesCount = item.lineCount
                let lineSuffix = linesCount > 1 ? " • \(linesCount) lines" : ""
                let metaStr = "\(df.string(from: item.date)) (\(item.charCount) chars\(lineSuffix))"
                let metaLabel = NSTextField(labelWithString: metaStr)
                metaLabel.font = theme.font(size: 8.5, weight: .semibold)
                metaLabel.textColor = theme.dimColor
                metaLabel.isEditable = false; metaLabel.isBordered = false; metaLabel.backgroundColor = .clear
                metaLabel.frame = NSRect(x: 28, y: 3, width: itemW - 64, height: 14)
                row.addSubview(metaLabel)
            }

            // Pin Icon Indicator
            let pinLabel = NSTextField(labelWithString: item.isPinned ? "PIN" : "")
            pinLabel.font = theme.font(size: 9, weight: .bold)
            pinLabel.textColor = item.isPinned ? NSColor.systemOrange : theme.dimColor
            pinLabel.isEditable = false; pinLabel.isBordered = false; pinLabel.backgroundColor = .clear
            pinLabel.frame = NSRect(x: itemW - 32, y: rowH - 24, width: 28, height: 16)
            pinLabel.alignment = .right
            row.addSubview(pinLabel)

            row.layer?.cornerRadius = 0
            row.updateColors()
            stackView.addArrangedSubview(row)
        }
    }

    private func deleteCurrentOrMostRecentItem() {
        let items = getFilteredItems()
        guard !items.isEmpty else { return }

        let targetIndex = (selectedIndex >= 0 && selectedIndex < items.count) ? selectedIndex : 0
        let targetItem = items[targetIndex]

        HistoryStore.shared.delete(id: targetItem.id)

        let remaining = getFilteredItems()
        if selectedIndex >= remaining.count {
            selectedIndex = max(0, remaining.count - 1)
        }

        renderHistory()
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Option + Backspace (KeyCode 51) -> Delete most recent / highlighted item (holds down to delete sequentially)
        if event.keyCode == 51 && event.modifierFlags.contains(.option) {
            deleteCurrentOrMostRecentItem()
            return true
        }

        let items = getFilteredItems()
        guard !items.isEmpty else { return false }

        switch event.keyCode {
        case 125: // Down Arrow
            if selectedIndex < items.count - 1 {
                selectedIndex += 1
                renderHistory()
            }
            return true

        case 126: // Up Arrow
            if selectedIndex > 0 {
                selectedIndex -= 1
                renderHistory()
            }
            return true

        case 36, 76: // Enter / Return
            if selectedIndex >= 0 && selectedIndex < items.count {
                pasteItemByID(items[selectedIndex].id)
            }
            return true

        case 53: // Escape
            view.window?.orderOut(nil)
            return true

        default:
            if let chars = event.characters, chars.count == 1,
               let num = Int(chars), num >= 1 && num <= 9 {
                let idx = num - 1
                if idx < items.count {
                    pasteItemByID(items[idx].id)
                    return true
                }
            }
            return false
        }
    }

    private func pasteItemByID(_ id: String) {
        guard let item = HistoryStore.shared.items.first(where: { $0.id == id }) else { return }

        let pb = NSPasteboard.general
        pb.clearContents()

        if item.type == .image, let img = HistoryStore.shared.loadImage(for: item) {
            if let tiff = img.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        } else {
            pb.setString(item.text, forType: .string)
        }
        PasteboardMonitor.shared.lastCount = pb.changeCount

        view.window?.orderOut(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let vKeyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            vKeyDown?.flags = .maskCommand
            let vKeyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vKeyUp?.flags = .maskCommand
            vKeyDown?.post(tap: .cgSessionEventTap)
            vKeyUp?.post(tap: .cgSessionEventTap)
        }
    }

    @objc private func clearTapped() {
        HistoryStore.shared.clearUnpinned()
    }
}

// MARK: - MACCY-STYLE POPUP PANEL
class ClipPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
                   styleMask: [.nonactivatingPanel, .utilityWindow, .borderless],
                   backing: .buffered,
                   defer: false)

        self.contentViewController = contentViewController
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hasShadow = true
        self.hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

// MARK: - APPLICATION DELEGATE
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: ClipPanel?
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PasteboardMonitor.shared.start()

        let popupVC = ClipPopupController()
        let panel = ClipPanel(contentViewController: popupVC)
        panel.delegate = self
        self.panel = panel

        setupGlobalHotkey()
    }

    private func setupGlobalHotkey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userPtr) -> OSStatus in
            guard let ptr = userPtr else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async {
                delegate.togglePanel()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        // Option + V (KeyCode 9)
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: 1)
        RegisterEventHotKey(9, UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    @objc func togglePanel() {
        guard let p = panel else { return }

        if p.isVisible {
            p.orderOut(nil)
        } else {
            let mouseLoc = NSEvent.mouseLocation
            let pSize = p.frame.size
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

            var posX = mouseLoc.x - (pSize.width / 2)
            var posY = mouseLoc.y - pSize.height - 10

            posX = max(screenFrame.minX + 10, min(posX, screenFrame.maxX - pSize.width - 10))
            posY = max(screenFrame.minY + 10, min(posY, screenFrame.maxY - pSize.height - 10))

            p.setFrameOrigin(NSPoint(x: posX, y: posY))
            p.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        panel?.orderOut(nil)
    }
}

// MARK: - MAIN ENTRY POINT
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
