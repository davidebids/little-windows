import SwiftUI

/// Opt-in simulator instrumentation. No monitor, overlay, or counters run in
/// signed-device/release builds. Reports contain timings and anonymous counters.
enum InteractionPerformanceAudit {
    #if DEBUG && targetEnvironment(simulator)
    static let enabled = ProcessInfo.processInfo.environment["LITTLE_WINDOWS_INTERACTION_AUDIT"] == "1"
    static let referenceEnabled = (enabled && ProcessInfo.processInfo.environment["LITTLE_WINDOWS_INTERACTION_REFERENCE"] == "1")
        || ProcessInfo.processInfo.environment["LITTLE_WINDOWS_NATIVE_MENU_REFERENCE"] == "1"
    static let referenceFormEnabled = enabled && ProcessInfo.processInfo.environment["LITTLE_WINDOWS_INTERACTION_REFERENCE"] == "2"
    static let referenceScrollEnabled = enabled && ProcessInfo.processInfo.environment["LITTLE_WINDOWS_INTERACTION_REFERENCE"] == "3"
    private static let counters = AuditCounters()
    @MainActor static func start() {
        guard enabled else { return }
        if !referenceEnabled && !referenceScrollEnabled { InteractionRunLoopAudit.shared.begin("today.ready") }
    }
    @MainActor static func begin(_ name: String) { if enabled { InteractionRunLoopAudit.shared.begin(name) } }
    @MainActor fileprivate static func painted(_ name: String) { if enabled { InteractionRunLoopAudit.shared.painted(name) } }
    static func count(_ name: String) {
        guard enabled else { return }
        counters.increment(name)
    }
    fileprivate static func counts() -> [String: Int] { counters.snapshot() }
    #else
    static let enabled = false
    static let referenceEnabled = false
    static let referenceFormEnabled = false
    static let referenceScrollEnabled = false
    @MainActor static func start() {}
    @MainActor static func begin(_ name: String) {}
    static func count(_ name: String) {}
    #endif
}

extension View {
    func interactionPerformanceAudit() -> some View { modifier(InteractionAuditModifier()) }
    func interactionScrollAudit(_ name: String) -> some View { modifier(InteractionScrollModifier(name: name)) }
    func interactionPaintProbe(_ name: String, revision: String = "initial", alignment: Alignment = .topTrailing) -> some View {
        modifier(InteractionPaintModifier(name: name, revision: revision, alignment: alignment))
    }
}

private struct InteractionScrollModifier: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if InteractionPerformanceAudit.enabled {
            content.overlay(alignment: .topLeading) {
                InteractionScrollAnchor(name: name).frame(width: 1, height: 1)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        } else { content }
        #else
        content
        #endif
    }
}

private struct InteractionPaintModifier: ViewModifier {
    let name: String
    let revision: String
    let alignment: Alignment
    func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if InteractionPerformanceAudit.enabled {
            content.overlay(alignment: alignment) {
                InteractionPaintWitness(name: name, revision: revision).frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)
            }
        } else { content }
        #else
        content
        #endif
    }
}

private struct InteractionAuditModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if InteractionPerformanceAudit.enabled {
            content.overlay(alignment: .bottomTrailing) {
                InteractionAuditReadout().frame(width: 1, height: 1).allowsHitTesting(false)
            }
        } else { content }
        #else
        content
        #endif
    }
}

#if DEBUG && targetEnvironment(simulator)
import UIKit
import QuartzCore
import os

private final class AuditCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    func increment(_ name: String) { lock.lock(); defer { lock.unlock() }; values[name, default: 0] += 1 }
    func snapshot() -> [String: Int] { lock.lock(); defer { lock.unlock() }; return values }
}

private struct InteractionScrollAnchor: UIViewRepresentable {
    let name: String
    func makeUIView(context: Context) -> Anchor { let view = Anchor(); view.isOpaque = false; return view }
    func updateUIView(_ view: Anchor, context: Context) { view.name = name; view.attach(); view.setNeedsDisplay() }
    final class Anchor: UIView {
        var name = ""
        private weak var scroll: UIScrollView?
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        func attach() {
            guard window != nil, !name.isEmpty else { return }
            var parent = superview
            while let view = parent {
                if let scroll = view as? UIScrollView {
                    self.scroll = scroll
                    InteractionScrollFrameAudit.shared.attach(name, to: scroll)
                    return
                }
                parent = view.superview
            }
        }
        override func draw(_ rect: CGRect) {
            if let scroll { InteractionScrollFrameAudit.shared.ready(name, scroll: scroll) }
        }
    }
}

/// The simulator may omit XCTHitchMetric samples. Observe the actual enclosing
/// vertical list's pan/deceleration, excluding XCTest's idle AX queries. SwiftUI
/// scroll-phase callbacks do not reliably describe List's native scroll view.
/// This measures main-thread frame delivery, not render-server/GPU hitches.
@MainActor
private final class InteractionScrollFrameAudit: NSObject {
    static let shared = InteractionScrollFrameAudit()
    private var link: CADisplayLink?
    private var name: String?
    private weak var scrollingView: UIScrollView?
    private var trackers: [String: PanTarget] = [:]
    private let benchmark = ProcessInfo.processInfo.environment["LITTLE_WINDOWS_UI_TESTING"] == "1"
        ? ProcessInfo.processInfo.environment["LITTLE_WINDOWS_SCROLL_BENCHMARK"] : nil
    private var benchmarkStarted = false
    private var benchmarkStep = 0
    private var goal: CGFloat?
    private var viewportFence: CADisplayLink?
    private weak var benchmarkScroll: UIScrollView?
    private let scrollLog = OSLog(subsystem: "com.littlewindows.performance", category: .pointsOfInterest)
    private var started = 0.0
    private var previous = 0.0
    private var nominal = 1.0 / 60
    private var frames = 0
    private var maxGapMS = 0.0
    private var lateMS = 0.0
    private var index = 0
    private(set) var samples: [[String: Any]] = []

    func attach(_ name: String, to scroll: UIScrollView) {
        guard trackers[name]?.scroll !== scroll else { return }
        trackers[name]?.detach()
        trackers[name] = PanTarget(name: name, scroll: scroll)
    }

    func ready(_ name: String, scroll: UIScrollView) {
        guard benchmark == name, !benchmarkStarted else { return }
        benchmarkStarted = true
        // A row's draw can precede the enclosing viewport's commit. Begin at
        // the next display callback, when a user could first see that frame.
        // No warmup scroll or wall-clock settling delay is used.
        benchmarkScroll = scroll
        let fence = CADisplayLink(target: self, selector: #selector(viewportPresented(_:)))
        viewportFence = fence; fence.add(to: .main, forMode: .common)
    }
    @objc private func viewportPresented(_ link: CADisplayLink) {
        link.invalidate(); viewportFence = nil
        guard let benchmark, let scroll = benchmarkScroll else { return }
        nextBenchmarkScroll(benchmark, scroll: scroll)
    }
    private func nextBenchmarkScroll(_ name: String, scroll: UIScrollView) {
        let top = -scroll.adjustedContentInset.top
        let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let target = benchmarkStep.isMultiple(of: 2) ? min(bottom, top + scroll.bounds.height * 1.2) : top
        guard abs(target - scroll.contentOffset.y) > 10 else { finishBenchmark(error: "List has no scrollable coverage"); return }
        setScrolling(name, active: true, scroll: scroll)
        goal = target
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: true)
    }
    private func finishBenchmark(error: String? = nil) {
        var result: [String: Any] = ["scenario": benchmark ?? "", "samples": samples,
            "counts": InteractionPerformanceAudit.counts()]
        if let error { result["error"] = error }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print("SCROLL-BENCHMARK \(text)") }
        fflush(stdout)
    }

    @MainActor private final class PanTarget: NSObject {
        let name: String
        weak var scroll: UIScrollView?
        init(name: String, scroll: UIScrollView) {
            self.name = name; self.scroll = scroll
            super.init()
            scroll.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
        }
        func detach() { scroll?.panGestureRecognizer.removeTarget(self, action: #selector(pan(_:))) }
        @objc private func pan(_ gesture: UIPanGestureRecognizer) {
            guard let scroll else { return }
            switch gesture.state {
            case .began, .changed: InteractionScrollFrameAudit.shared.setScrolling(name, active: true, scroll: scroll)
            case .cancelled, .failed: InteractionScrollFrameAudit.shared.setScrolling(name, active: false, scroll: scroll)
            default: break // A display tick observes the final deceleration state.
            }
        }
    }

    private func setScrolling(_ name: String, active: Bool, scroll: UIScrollView) {
        if active {
            guard self.name == nil else { return }
            self.name = name
            os_signpost(.begin, log: scrollLog, name: "List scroll", signpostID: .exclusive)
            scrollingView = scroll
            started = CACurrentMediaTime(); previous = started
            frames = 0; maxGapMS = 0; lateMS = 0
            let display = CADisplayLink(target: self, selector: #selector(frame(_:)))
            link = display; display.add(to: .main, forMode: .common)
        } else {
            guard self.name == name else { return }
            let end = CACurrentMediaTime()
            os_signpost(.end, log: scrollLog, name: "List scroll", signpostID: .exclusive)
            link?.invalidate(); link = nil; self.name = nil; scrollingView = nil
            index += 1
            samples.append(["index": index, "name": name, "frames": frames,
                "duration": end - started, "maxGapMS": maxGapMS, "lateMS": lateMS])
            if samples.count > 256 { samples.removeFirst(samples.count - 256) }
        }
    }
    @objc private func frame(_ link: CADisplayLink) {
        guard let scroll = scrollingView, let name else { return }
        guard scroll.window != nil, goal != nil || scroll.isDragging || scroll.isDecelerating else {
            setScrolling(name, active: false, scroll: scroll)
            return
        }
        // Use display timestamps, not callback arrival jitter or the idle
        // transition: those can vary without missing a display refresh.
        nominal = max(0.001, link.targetTimestamp - link.timestamp)
        recordGap(max(0, link.timestamp - previous))
        previous = link.timestamp; frames += 1
        if let goal {
            if CACurrentMediaTime() - started > 5 {
                self.goal = nil; setScrolling(name, active: false, scroll: scroll)
                finishBenchmark(error: "Native scroll animation did not complete")
            } else if frames > 2, abs(scroll.contentOffset.y - goal) < 0.5 {
                self.goal = nil; setScrolling(name, active: false, scroll: scroll)
                benchmarkStep += 1
                if benchmarkStep < 4 { DispatchQueue.main.async { self.nextBenchmarkScroll(name, scroll: scroll) } }
                else { finishBenchmark() }
            }
        }
    }
    private func recordGap(_ gap: Double) {
        maxGapMS = max(maxGapMS, gap * 1000)
        if gap > nominal * 1.5 { lateMS += max(0, gap - nominal) * 1000 }
    }
}

@MainActor
private final class InteractionRunLoopAudit {
    static let shared = InteractionRunLoopAudit()
    private var start: CFTimeInterval?
    private var cycle = 0
    private var slowCycles: [[String: Double]] = []
    private var observers: [CFRunLoopObserver] = []
    private var pending: [String: CFTimeInterval] = [:]
    private var pendingCPU: [String: Double] = [:]
    private var paints: [[String: Any]] = []
    private var paintIndex = 0
    private func cpuTime() -> Double {
        var value = timespec(); clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value)
        return Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000
    }
    func begin(_ name: String) {
        if pending[name] == nil { pending[name] = CACurrentMediaTime(); pendingCPU[name] = cpuTime() }
    }
    func painted(_ name: String) {
        guard let start = pending.removeValue(forKey: name) else { return }
        paintIndex += 1
        let cpu = pendingCPU.removeValue(forKey: name) ?? cpuTime()
        paints.append(["index": paintIndex, "name": name, "ms": (CACurrentMediaTime() - start) * 1000,
            "cpuMS": (cpuTime() - cpu) * 1000])
        print("PAINT-AUDIT \(name) wall=\((CACurrentMediaTime()-start)*1000)ms cpu=\((cpuTime()-cpu)*1000)ms")
        if paints.count > 256 { paints.removeFirst(paints.count - 256) }
    }
    private init() {
        // Start before UI callbacks and finish after before-waiting observers.
        // Sleeping/waiting for a network response is deliberately not CPU work.
        let wake = CFRunLoopObserverCreateWithHandler(nil,
            CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeSources.rawValue, true, CFIndex.min) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, self.start == nil else { return }
                    self.start = CACurrentMediaTime()
                }
            }!
        let wait = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.finishCycle() }
        }!
        observers = [wake, wait]
        for observer in observers { CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes) }
    }
    private func finishCycle() {
        guard let start else { return }
        self.start = nil; cycle += 1
        let ms = (CACurrentMediaTime() - start) * 1000
        if ms >= 8 {
            slowCycles.append(["index": Double(cycle), "ms": ms])
            if slowCycles.count > 256 { slowCycles.removeFirst(slowCycles.count - 256) }
        }
    }
    func report() -> String {
        var cpu = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpu)
        let value: [String: Any] = ["cycle": cycle, "slowCycles": slowCycles,
            "uptime": CACurrentMediaTime(), "cpu": Double(cpu.tv_sec) + Double(cpu.tv_nsec) / 1_000_000_000,
            "counts": InteractionPerformanceAudit.counts(), "paints": paints,
            "scrollFrames": InteractionScrollFrameAudit.shared.samples,
            "pending": pending.mapValues { (CACurrentMediaTime() - $0) * 1000 }]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// Marks an actual UIKit draw after the changed SwiftUI subtree has laid out.
/// Unlike an accessibility query, this measures the app's input-to-render work.
private struct InteractionPaintWitness: UIViewRepresentable {
    let name: String
    let revision: String
    func makeUIView(context: Context) -> Witness { Witness() }
    func updateUIView(_ view: Witness, context: Context) {
        guard view.revision != revision else { return }
        view.name = name; view.revision = revision; view.setNeedsDisplay()
    }
    final class Witness: UIView {
        var name = ""
        var revision: String?
        init() { super.init(frame: .zero); isOpaque = false; isAccessibilityElement = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func draw(_ rect: CGRect) { InteractionPerformanceAudit.painted(name) }
    }
}

private struct InteractionAuditReadout: UIViewRepresentable {
    func makeUIView(context: Context) -> Readout {
        _ = InteractionRunLoopAudit.shared
        return Readout()
    }
    func updateUIView(_ uiView: Readout, context: Context) {}
    final class Readout: UIView {
        init() {
            super.init(frame: .zero)
            isAccessibilityElement = true
            accessibilityIdentifier = "performance.audit"
            accessibilityLabel = "Interaction performance audit"
            accessibilityTraits = .staticText
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var accessibilityValue: String? {
            get { InteractionRunLoopAudit.shared.report() }
            set {}
        }
    }
}

/// A native control sample for separating platform/presentation cost from the
/// app's history, weather, and custom view work on the same test host.
struct InteractionAuditReferenceView: View {
    @State private var showingForm = false
    var body: some View {
        NavigationStack {
            List {
                Button("Open reference form") { InteractionPerformanceAudit.begin("native.form"); showingForm = true }
                    .buttonStyle(.borderedProminent)
            }.navigationTitle("Native reference")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Open form from menu") { showingForm = true }
                        } label: { Label("Reference menu", systemImage: "person.crop.circle") }
                        .accessibilityIdentifier("performance.reference-menu")
                    }
                }
        }
        .sheet(isPresented: $showingForm) {
            InteractionAuditReferenceForm { showingForm = false }
                .interactionPaintProbe("native.form")
                .interactionPerformanceAudit()
        }
    }
}

struct InteractionAuditScrollReferenceView: View {
    var body: some View {
        NavigationStack {
            ScrollViewReader { _ in
                List {
                    ForEach(0..<200, id: \.self) { index in
                        if index == 0 { Text("Sample row 1").interactionScrollAudit("reference") }
                        else { Text("Sample row \(index + 1)") }
                    }
                }
                .coordinateSpace(name: "reference.scroll")
            }
            .navigationTitle("Native scrolling")
        }.interactionPerformanceAudit()
    }
}

struct InteractionAuditReferenceForm: View {
    let done: () -> Void
    @State private var layout = false
    var body: some View {
        NavigationStack {
            Form {
                    Section {
                        Picker("Layout", selection: $layout) { Text("Full").tag(false); Text("Essentials").tag(true) }.pickerStyle(.segmented)
                    } header: { Text("Today for Sample Child") } footer: { Text("Choose the layout for this profile. Switching layouts does not pause tracking or reminders.") }
                    Section("Full layout") { NavigationLink("Full Layout Quick Actions") { Text("Actions") } }
                    Section {
                        NavigationLink("Visible Sections") { Text("Sections") }
                        NavigationLink("Tracking & Reminders") { Text("Tracking") }
                    } footer: { Text("These choices follow this profile on devices signed into the same Apple Account when iCloud Sync is on.") }
                    Section { Button("Reset This Layout") {} } footer: { Text("Resets buttons and section visibility. Paused tracking and reminder choices stay as you set them.") }
                }
                .navigationTitle("Reference form").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) } }
        }
    }
}
#endif
