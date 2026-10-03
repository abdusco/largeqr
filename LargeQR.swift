import Cocoa
import CoreImage
import Foundation

let version = "dev" // Replaced in a temporary copy by build.sh.

let usage = """
largeqr - Display a QR code in a fullscreen overlay

Usage:
  largeqr <text> [options]
  printf '%s' 'text' | largeqr [options]

Options:
  --correction-level <L|M|Q|H>   Error correction level (default: M)
  --background-color <rrggbbaa> Overlay background (default: 00000080)
  --padding <number[px|%]>      Padding on each side (default: 5%)
  --hide-after <seconds>       Dismiss automatically after N seconds
  --help                      Show this help
  --version                   Show version
  --                          Treat remaining arguments as text

Click anywhere or press Escape to dismiss.

Examples:
  largeqr 'https://example.com'
  largeqr 'WIFI:T:WPA;S:MyNetwork;P:MyPassword;;' --hide-after 30
  printf '%s' 'Hello world' | largeqr --correction-level H
"""

struct CLIError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

struct Padding {
    var value: CGFloat = 5
    var isPercent = true

    func insets(for size: CGSize) -> CGSize {
        if isPercent {
            return CGSize(width: size.width * value / 100, height: size.height * value / 100)
        }
        return CGSize(width: value, height: value)
    }
}

struct Options {
    var text: String?
    var correctionLevel = "M"
    var backgroundColor = NSColor.black.withAlphaComponent(0.5)
    var padding = Padding()
    var hideAfter: Double?
    var showHelp = false
    var showVersion = false

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var text: [String] = []
        var index = 0

        func nextValue(for option: String) throws -> String {
            guard index + 1 < arguments.count else {
                throw CLIError("Missing value for \(option).")
            }
            index += 1
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--":
                text.append(contentsOf: arguments.dropFirst(index + 1))
                index = arguments.count
                continue
            case "--help":
                options.showHelp = true
            case "--version":
                options.showVersion = true
            case "--correction-level":
                let value = try nextValue(for: argument).uppercased()
                guard ["L", "M", "Q", "H"].contains(value) else {
                    throw CLIError("Correction level must be L, M, Q, or H.")
                }
                options.correctionLevel = value
            case "--background-color":
                var value = try nextValue(for: argument)
                if value.hasPrefix("#") { value.removeFirst() }
                guard value.count == 8,
                      value.unicodeScalars.allSatisfy({
                          (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value)
                      }),
                      let rgba = UInt32(value, radix: 16) else {
                    throw CLIError("Background color must be eight hex digits (rrggbbaa).")
                }
                options.backgroundColor = NSColor(
                    calibratedRed: CGFloat((rgba >> 24) & 0xff) / 255,
                    green: CGFloat((rgba >> 16) & 0xff) / 255,
                    blue: CGFloat((rgba >> 8) & 0xff) / 255,
                    alpha: CGFloat(rgba & 0xff) / 255
                )
            case "--padding":
                var value = try nextValue(for: argument)
                let isPercent = value.hasSuffix("%")
                if isPercent {
                    value.removeLast()
                } else if value.hasSuffix("px") {
                    value.removeLast(2)
                }
                guard let number = Double(value), number.isFinite, number >= 0,
                      !isPercent || number < 50 else {
                    throw CLIError("Padding must be nonnegative; percentages must be less than 50%.")
                }
                options.padding = Padding(value: CGFloat(number), isPercent: isPercent)
            case "--hide-after":
                let value = try nextValue(for: argument)
                guard let number = Double(value), number.isFinite, number > 0 else {
                    throw CLIError("Hide-after must be a positive number of seconds.")
                }
                options.hideAfter = number
            default:
                guard !argument.hasPrefix("-") else {
                    throw CLIError("Unknown option: \(argument). Use -- before text starting with a dash.")
                }
                text.append(argument)
            }
            index += 1
        }
        if !text.isEmpty { options.text = text.joined(separator: " ") }
        return options
    }
}

func readPayload(_ positionalText: String?) throws -> String {
    if let positionalText { return positionalText }
    guard isatty(STDIN_FILENO) == 0 else {
        throw CLIError("No text provided. Pass text as an argument or pipe UTF-8 text to stdin.")
    }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard var text = String(data: data, encoding: .utf8) else {
        throw CLIError("Stdin must contain valid UTF-8 text.")
    }
    while let last = text.last, last == "\n" || last == "\r" || last == "\r\n" {
        text.removeLast()
    }
    return text
}

func generateQRCode(_ text: String, correctionLevel: String) throws -> CGImage {
    guard !text.isEmpty else { throw CLIError("QR text must not be empty.") }
    let data = Data(text.utf8)
    // Core Image encodes the payload in byte mode. Limits are for version 40.
    let byteLimits = ["L": 2953, "M": 2331, "Q": 1663, "H": 1273]
    guard let limit = byteLimits[correctionLevel] else {
        throw CLIError("Correction level must be L, M, Q, or H.")
    }
    guard data.count <= limit else {
        throw CLIError("QR payload is \(data.count) UTF-8 bytes; level \(correctionLevel) supports at most \(limit). Use shorter text or a lower correction level.")
    }
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
        throw CLIError("The system QR generator is unavailable.")
    }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else {
        throw CLIError("Could not generate the QR code. Try a shorter payload.")
    }
    let renderer = CIContext()
    guard let qr = renderer.createCGImage(output, from: output.extent) else {
        throw CLIError("Could not render the QR code. Run largeqr in a local macOS graphical session.")
    }

    // Add four white modules on every side, in addition to any system margin.
    let margin = 4
    let width = qr.width + margin * 2
    let height = qr.height + margin * 2
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw CLIError("Could not allocate the QR image.") }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    context.draw(qr, in: CGRect(x: margin, y: margin, width: qr.width, height: qr.height))
    guard let image = context.makeImage() else { throw CLIError("Could not render the QR image.") }
    return image
}

func imageRect(imageSize: CGSize, bounds: CGRect, backingScale: CGFloat, padding: Padding) throws -> CGRect {
    let insets = padding.insets(for: bounds.size)
    let availableWidth = (bounds.width - insets.width * 2) * backingScale
    let availableHeight = (bounds.height - insets.height * 2) * backingScale
    let scale = floor(min(availableWidth / imageSize.width, availableHeight / imageSize.height))
    guard scale >= 1 else {
        throw CLIError("QR code cannot fit on this screen with the requested padding.")
    }
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return CGRect(
        x: bounds.minX + floor((bounds.width * backingScale - width) / 2) / backingScale,
        y: bounds.minY + floor((bounds.height * backingScale - height) / 2) / backingScale,
        width: width / backingScale,
        height: height / backingScale
    )
}

func fail(_ error: Error) -> Never {
    FileHandle.standardError.write(Data("largeqr: \(error)\n".utf8))
    exit(1)
}

final class QRWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class QRView: NSView {
    let image: CGImage
    let options: Options

    init(frame: CGRect, image: CGImage, options: Options) {
        self.image = image
        self.options = options
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        options.backgroundColor.setFill()
        dirtyRect.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        do {
            let rect = try imageRect(
                imageSize: CGSize(width: image.width, height: image.height), bounds: bounds,
                backingScale: window?.backingScaleFactor ?? 1, padding: options.padding
            )
            context.saveGState()
            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            context.draw(image, in: rect)
            context.restoreGState()
        } catch { fail(error) }
    }

    override func mouseDown(with event: NSEvent) { NSApp.terminate(nil) }
    override func rightMouseDown(with event: NSEvent) { NSApp.terminate(nil) }
    override func otherMouseDown(with event: NSEvent) { NSApp.terminate(nil) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let options: Options
    let image: CGImage
    var window: QRWindow?
    var globalEventMonitor: Any?

    init(options: Options, image: CGImage) {
        self.options = options
        self.image = image
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { fail(CLIError("No screen is available.")) }
        let window = QRWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = QRView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image, options: options)
        window.contentView = view
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { NSApp.terminate(nil) }
        }
        if let seconds = options.hideAfter {
            Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in NSApp.terminate(nil) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
    }
}

// CLI entry point
do {
    let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    if options.showHelp { print(usage); exit(0) }
    if options.showVersion { print("largeqr version: \(version)"); exit(0) }
    let text = try readPayload(options.text)
    let image = try generateQRCode(text, correctionLevel: options.correctionLevel)
    let app = NSApplication.shared
    let delegate = AppDelegate(options: options, image: image)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    withExtendedLifetime(delegate) {}
} catch { fail(error) }
