// Info Notch: widens the notch with battery (left) and time (right). Pure AppKit, no SwiftUI, for low RAM.
import AppKit
import IOKit.ps

let sideWidth: CGFloat = 90      // how far the bar extends past each side of the notch
let cornerRadius: CGFloat = 10   // bottom corner radius, matches the notch look

struct Battery { var percent = 100; var charging = false }

func readBattery() -> Battery? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for src in list {
        guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
              let cur = d[kIOPSCurrentCapacityKey] as? Int,
              let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
        let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return Battery(percent: cur * 100 / max, charging: onAC)  // AC = plugged in; bolt shown while on power
    }
    return nil  // desktop Mac: no battery
}

final class BarView: NSView {
    var battery: Battery? = readBattery()
    var timeText = ""
    let notchWidth: CGFloat
    let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f  // ponytail: 24h; use "h:mm" for 12h
    }()

    init(frame: NSRect, notchWidth: CGFloat) {
        self.notchWidth = notchWidth
        super.init(frame: frame)
        tick()
    }
    required init?(coder: NSCoder) { fatalError() }

    func tick() { timeText = fmt.string(from: Date()); needsDisplay = true }
    func refreshBattery() { battery = readBattery(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // Black shape: square top corners (flush with screen), rounded bottom corners.
        let r = cornerRadius, b = bounds
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 0, y: b.maxY))
        p.line(to: NSPoint(x: b.maxX, y: b.maxY))
        p.line(to: NSPoint(x: b.maxX, y: r))
        p.appendArc(withCenter: NSPoint(x: b.maxX - r, y: r), radius: r, startAngle: 0, endAngle: 270, clockwise: true)
        p.line(to: NSPoint(x: r, y: 0))
        p.appendArc(withCenter: NSPoint(x: r, y: r), radius: r, startAngle: 270, endAngle: 180, clockwise: true)
        p.close()
        NSColor.black.setFill(); p.fill()

        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let midY = b.midY - 2   // nudge: the usable area sits slightly below the true centre
        let pad: CGFloat = 16

        // Time, right side
        let ts = NSAttributedString(string: timeText, attributes: [.font: font, .foregroundColor: NSColor.white])
        let tsz = ts.size()
        ts.draw(at: NSPoint(x: b.maxX - pad - tsz.width, y: midY - tsz.height / 2))

        // Battery, left side
        guard let bat = battery else { return }
        let color: NSColor = bat.charging ? .systemGreen : (bat.percent <= 20 ? .systemRed : .white)
        let body = NSRect(x: pad, y: midY - 5.5, width: 23, height: 11)
        let outline = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
        NSColor.white.withAlphaComponent(0.55).setStroke(); outline.lineWidth = 1; outline.stroke()
        let fillW = max(2, (body.width - 3) * CGFloat(bat.percent) / 100)
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: body.minX + 1.5, y: body.minY + 1.5, width: fillW, height: body.height - 3),
                     xRadius: 1.8, yRadius: 1.8).fill()
        NSColor.white.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + 1, y: midY - 2, width: 2, height: 4), xRadius: 1, yRadius: 1).fill()
        if bat.charging {   // bolt over the icon
            let c = NSPoint(x: body.midX, y: body.midY)
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: c.x + 1.5, y: c.y + 5))
            bolt.line(to: NSPoint(x: c.x - 3, y: c.y - 0.5))
            bolt.line(to: NSPoint(x: c.x - 0.3, y: c.y - 0.5))
            bolt.line(to: NSPoint(x: c.x - 1.5, y: c.y - 5))
            bolt.line(to: NSPoint(x: c.x + 3, y: c.y + 0.5))
            bolt.line(to: NSPoint(x: c.x + 0.3, y: c.y + 0.5))
            bolt.close()
            NSColor.black.setStroke(); bolt.lineWidth = 1.2; bolt.stroke()
            NSColor.white.setFill(); bolt.fill()
        }
        let ps = NSAttributedString(string: "\(bat.percent)%", attributes: [.font: font, .foregroundColor: NSColor.white])
        ps.draw(at: NSPoint(x: body.maxX + 8, y: midY - ps.size().height / 2))
    }
}

final class App: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var view: BarView!

    func applicationDidFinishLaunching(_ n: Notification) {
        build()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.build() }
        // Battery: event-driven, no polling.
        let src = IOPSNotificationCreateRunLoopSource({ ctx in
            Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue().view?.refreshBattery()
        }, Unmanaged.passUnretained(self).toOpaque()).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        // Clock: fire on each minute boundary.
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime)!
        let t = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in self?.view.tick() }
        RunLoop.main.add(t, forMode: .common)
    }

    func build() {
        panel?.orderOut(nil)
        // Built-in screen = the one with a notch.
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return }
        let notchW = screen.frame.width - l.width - r.width
        let h = screen.safeAreaInsets.top
        let w = notchW + 2 * sideWidth
        let frame = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        view = BarView(frame: NSRect(origin: .zero, size: frame.size), notchWidth: notchW)
        panel.contentView = view
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar   // same level as Notchy; Notchy's panel is ordered above ours
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.orderFrontRegardless()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no dock icon
let delegate = App()
app.delegate = delegate
app.run()
