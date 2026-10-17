import SwiftUI
import SystemConfiguration
import MetricsKit

/// The single-icon style's popover: every chosen reading as a card, and any module's
/// full detail one click away inside the same popover.
///
/// The view reports nothing visible itself — `MenuBarController` reports every
/// dashboard module visible while the popover is shown. Its own body reads only
/// settings; each card is a leaf view that reads the samples, so a new reading
/// re-evaluates the cards and nothing around them.
struct DashboardPopoverView: View {
    @Bindable var model: AppModel
    /// True when a module item (rather than the logo) opened this dashboard, in which
    /// case every watched module is a card — a hidden logo never leaves the Dashboard
    /// empty.
    let showsAllWatchedModules: Bool
    /// Settings embeds this same live card grid as its visual layout editor.
    var isSettingsPreview = false
    /// The module whose detail replaces the grid; nil shows the grid.
    @State private var selectedModule: MetricID? = nil
    /// Facts no sample carries, read once when the popover appears.
    @State private var systemInfo = DashboardSystemInfo()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which modules appear as cards. The logo item shows the grouped modules; a module
    /// item in `.dashboard` click mode shows every watched module.
    private var cardModules: [MetricID] {
        showsAllWatchedModules ? model.orderedEnabledModules : model.orderedDashboardModules
    }

    private var cards: [DashboardCard] {
        model.orderedCards(for: cardModules, includesDevice: model.showsDeviceCard)
    }

    /// Outer width, padding included. Kept close to a native menu bar popover: the
    /// cards are glanceable summaries, and the full reading is one click away.
    static let width: CGFloat = 320
    /// Around the grid, and inside every card.
    ///
    /// One shared edge inset for the dashboard, its cards, and its detail branch.
    static let padding: CGFloat = ExperienceSpacing.medium
    static let cardSpacing: CGFloat = 8
    static let cardPadding: CGFloat = ExperienceSpacing.small
    /// One of the two columns: the width inside the padding, less the gap, halved.
    static let cardWidth = (width - 2 * padding - cardSpacing) / 2
    /// Keep the two-column cards square as the dashboard width or insets change.
    static let cardHeight = cardWidth

    var body: some View {
        // One container for both states, so moving between them does not count as
        // the popover appearing again.
        VStack(alignment: .leading, spacing: 0) {
            if let selectedModule {
                detail(for: selectedModule)
                    .transition(Self.drillIn)
            } else {
                overview
                    .transition(Self.drillOut)
            }
        }
        .frame(width: Self.width)
        .background {
            DashboardCardBackground(
                fillOpacity: model.dashboardBackgroundOpacity,
                appearance: model.dashboardAppearance,
                cornerRadius: ExperienceRadius.panel
            )
        }
        // The grid and a detail are two depths of one place, so they slide the way a
        // push and a pop do rather than being swapped out from under the pointer. The
        // popover's own height follows: AppKit animates a content-size change while
        // `animates` is on, which it is unless the system asks for less motion.
        .clipped()
        .onAppear {
            systemInfo = DashboardSystemInfo.read()
        }
    }

    /// Pushes in from the trailing edge and leaves the same way, so the gesture reads
    /// as going one level deeper and coming back.
    private static let drillIn = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
    )

    private static let drillOut = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )

    /// Moves between the grid and a module's detail. Honors Reduce Motion, where the
    /// swap is immediate rather than merely faster.
    private func select(_ id: MetricID?) {
        guard let animation = ExperienceMotion.stateChange(
            reduceMotion: reduceMotion
        ) else {
            selectedModule = id
            return
        }
        withAnimation(animation) { selectedModule = id }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: Self.padding) {
            if !isSettingsPreview {
                DashboardHealthBanner(model: model, cards: cardModules) { select($0) }
            }
            cardGrid
            if isSettingsPreview {
                previewActionFooter
            } else {
                actionFooter
            }
        }
        .padding(Self.padding)
    }

    private var cardGrid: some View {
        Grid(
            horizontalSpacing: Self.cardSpacing,
            verticalSpacing: Self.cardSpacing
        ) {
            ForEach(
                DashboardLayout.rows(for: cards),
                id: \.self
            ) { row in
                // A row with one card leaves the second cell empty.
                GridRow {
                    ForEach(row, id: \.self) { card in
                        cell(for: card)
                    }
                    if isSettingsPreview, row.count == 1 {
                        endDropTarget
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for card: DashboardCard) -> some View {
        Group {
            switch card {
            case .module(let id):
                DashboardModuleCard(
                    model: model,
                    id: id,
                    systemInfo: systemInfo
                ) { select($0) }
            case .device:
                DashboardDeviceCard(model: model)
            case .emptyHint:
                DashboardEmptyHintCard(
                    onOpenSettings: { model.onOpenMenuBarSettings?() },
                    appearance: model.dashboardAppearance,
                    backgroundOpacity: model.dashboardBackgroundOpacity
                )
            }
        }
        .modifier(DashboardCardReordering(
            card: card,
            model: model,
            enabled: isSettingsPreview
        ))
    }

    private var endDropTarget: some View {
        RoundedRectangle(cornerRadius: ExperienceRadius.standard)
            .strokeBorder(
                Color.secondary.opacity(0.35),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .overlay {
                Image(systemName: "arrow.down.to.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .dropDestination(for: String.self) { identifiers, _ in
                guard let identifier = identifiers.first else { return false }
                model.moveDashboardCardToEnd(identifier)
                return true
            }
    }

    /// A module's full popover in place of the grid, under a row that leads back.
    private func detail(for id: MetricID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                select(nil)
            } label: {
                Label(
                    String(localized: "dashboard.back", defaultValue: "Dashboard"),
                    systemImage: "chevron.left"
                )
                .font(.callout.weight(.medium))
            }
            .buttonStyle(.borderless)
            .help(String(
                localized: "dashboard.back.help",
                defaultValue: "Back to every reading"
            ))
            .padding([.top, .horizontal], Self.padding)
            // The detail pads itself, so at the popover's own width its content lines
            // up with the back row and the footer. It honors the enabled state: a
            // module taken off the dashboard while its detail is open says Off and
            // offers to turn it back on, rather than going quietly stale.
            DetailPopoverView(
                model: model,
                moduleID: id,
                showsGlobalActions: false,
                honorsEnabledState: true,
                recoveryPlacement: .grouped,
                width: Self.width
            )
            actionFooter
                .padding([.bottom, .horizontal], Self.padding)
        }
    }

    private var actionFooter: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            Divider()
            PopoverActionBar(
                onOpenSettings: { model.onOpenSettings?() },
                onMenuDismissed: { model.onPopoverActionMenuDismissed?() }
            )
        }
    }

    /// The live Dashboard footer's proportions without exposing app actions inside
    /// Settings. This keeps the preview's overall height and alignment faithful.
    private var previewActionFooter: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.small) {
            Divider()
            HStack {
                Spacer(minLength: 0)
                Image(systemName: "ellipsis")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            .padding(.top, ExperienceSpacing.small)
        }
    }
}

// MARK: - Layout and formatting

/// What the Mac's own card is called, in the one place both the card and the Settings
/// row that manages it can read it. Two copies of a name drift.
enum DeviceCardName {
    static var localized: String {
        String(localized: "dashboard.device", defaultValue: "Device")
    }
}

/// One cell of the dashboard grid.
enum DashboardCard: Hashable {
    case module(MetricID)
    /// The Mac itself: macOS version and uptime. Never sampled; it follows the chosen
    /// modules, or leads the grid beside the empty hint when none is chosen.
    case device
    /// Stands in for the modules when none is chosen, so the grid says why it is empty.
    case emptyHint

    var layoutIdentifier: String {
        switch self {
        case .module(let id): id.rawValue
        case .device: "device"
        case .emptyHint: "empty"
        }
    }
}

enum DashboardLayout {
    /// The cards in grid order: the chosen modules, then the device.
    static func cards(
        for modules: [MetricID],
        includesDevice: Bool = true
    ) -> [DashboardCard] {
        let device: [DashboardCard] = includesDevice ? [.device] : []
        guard !modules.isEmpty else { return device + [.emptyHint] }
        return modules.map(DashboardCard.module) + device
    }

    /// The cards in rows of two; an odd count leaves the last row one card short.
    static func rows(
        for modules: [MetricID],
        includesDevice: Bool = true
    ) -> [[DashboardCard]] {
        rows(for: cards(for: modules, includesDevice: includesDevice))
    }

    static func rows(for cards: [DashboardCard]) -> [[DashboardCard]] {
        let cards = cards.isEmpty ? [.emptyHint] : cards
        return stride(from: 0, to: cards.count, by: 2).map {
            Array(cards[$0..<min($0 + 2, cards.count)])
        }
    }
}

private struct DashboardCardReordering: ViewModifier {
    let card: DashboardCard
    let model: AppModel
    let enabled: Bool
    @State private var isTargeted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled, card != .emptyHint {
            content
                .draggable(card.layoutIdentifier)
                .dropDestination(for: String.self) { identifiers, _ in
                    guard let source = identifiers.first,
                          source != card.layoutIdentifier else { return false }
                    model.moveDashboardCard(source, to: card.layoutIdentifier)
                    return true
                } isTargeted: { isTargeted = $0 }
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.standard)
                        .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
                        .opacity(isTargeted ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: removeCard) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .background(.regularMaterial, in: Circle())
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(5)
                    .help("Remove card from Dashboard")
                    .accessibilityLabel("Remove card from Dashboard")
                }
        } else {
            content
        }
    }

    private func removeCard() {
        switch card {
        case .module(let id):
            // Keep a module's existing menu bar items if it was shown in both places.
            model.setPlacement(model.placement(of: id) == .both ? .ownItems : .off, for: id)
        case .device:
            model.showsDeviceCard = false
        case .emptyHint:
            break
        }
    }
}

/// System facts the dashboard shows but no metric sample carries. The startup volume
/// is read when the popover appears; the open Network card refreshes interface details.
struct DashboardSystemInfo: Equatable {
    var localAddress: String?
    /// The primary interface as System Settings names it ("Wi-Fi"), or its BSD name.
    var interfaceName: String?
    var interfaceSymbol = "network"
    /// The startup volume's name in Finder ("Macintosh HD").
    var startupVolumeName: String?

    @MainActor
    static func read() -> DashboardSystemInfo {
        var info = readNetwork()
        info.startupVolumeName = try? URL(fileURLWithPath: "/")
            .resourceValues(forKeys: [.volumeLocalizedNameKey])
            .volumeLocalizedName
        return info
    }

    @MainActor
    static func readNetwork() -> DashboardSystemInfo {
        var info = DashboardSystemInfo()
        if let primary = NetworkInfo.primaryIPv4() {
            info.localAddress = primary.address
            let described = describeInterface(bsdName: primary.interface)
            info.interfaceName = described?.name ?? primary.interface
            info.interfaceSymbol = described?.symbol ?? "network"
        }
        return info
    }

    /// Interface descriptions by BSD name. An interface keeps its name for as long as
    /// the app runs, and listing every interface costs milliseconds, so each is looked
    /// up once rather than on every opening.
    @MainActor
    private static var interfaceDescriptions: [String: (name: String, symbol: String)] = [:]

    /// The localized display name and a fitting symbol for a BSD interface name, from
    /// the local SystemConfiguration store — no network request.
    @MainActor
    private static func describeInterface(
        bsdName: String
    ) -> (name: String, symbol: String)? {
        if let cached = interfaceDescriptions[bsdName] { return cached }
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]
        else { return nil }
        for interface in interfaces
            where SCNetworkInterfaceGetBSDName(interface) as String? == bsdName {
            guard let name = SCNetworkInterfaceGetLocalizedDisplayName(interface)
            else { return nil }
            let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
            let symbol: String
            if type == kSCNetworkInterfaceTypeIEEE80211 as String {
                symbol = "wifi"
            } else if type == kSCNetworkInterfaceTypeEthernet as String {
                symbol = "cable.connector"
            } else {
                symbol = "network"
            }
            let description = (name: name as String, symbol: symbol)
            interfaceDescriptions[bsdName] = description
            return description
        }
        return nil
    }
}

private enum DashboardStyle {
    static let valueSize: CGFloat = 20
    /// Network shows two rates stacked, so each is set a little smaller.
    static let rateSize: CGFloat = 16
    static let ringDiameter: CGFloat = 56
    static let ringLineWidth: CGFloat = 8
    /// Bars in the CPU and GPU history: one per sample, newest on the right.
    static let historyCount = 16
    /// One network sample per base cycle, enough for a compact recent traffic trend.
    static let networkHistoryCount = 30
    static let barSpacing: CGFloat = 2
    static let barMinimumHeight: CGFloat = 20
    /// A reading of zero is still a reading, so its bar keeps a sliver of height.
    static let barFloor: CGFloat = 2
    static let trackOpacity: Double = 0.1
    static let increasedTrackOpacity: Double = 0.22
    static let hoverFillOpacity: Double = 0.11
    static let chipFillOpacity: Double = 0.09
}

// MARK: - Cards

/// A module card: its latest reading at a glance, and a button into its detail.
private struct DashboardModuleCard: View {
    let model: AppModel
    let id: MetricID
    let systemInfo: DashboardSystemInfo
    let onSelect: (MetricID) -> Void

    var body: some View {
        let sample = model.latest[id]
        let state = model.metricState(for: id, isEnabled: true)
        let facts = sample.map(cardFacts(for:))
        Button {
            onSelect(id)
        } label: {
            DashboardCardLayout(
                symbol: MetricSymbol.name(for: id),
                title: id.localizedName
            ) {
                if let sample, let facts {
                    content(for: sample, facts: facts)
                    if state != .live {
                        MetricStatusBadge(state: state)
                    }
                } else {
                    // Absence is not zero: a dash and the reason, no empty chart.
                    DashboardValueText(text: DashboardFormat.missingValue)
                    Spacer(minLength: 0)
                    MetricStatusBadge(state: state)
                }
            }
        }
        .buttonStyle(DashboardCardButtonStyle(
            appearance: model.dashboardAppearance,
            backgroundOpacity: model.dashboardBackgroundOpacity
        ))
        .accessibilityLabel(id.localizedName)
        .accessibilityValue(accessibilityValue(sample: sample, state: state, facts: facts))
        .accessibilityHint(String(
            localized: "dashboard.card.hint",
            defaultValue: "Shows details"
        ))
    }

    private func cardFacts(for sample: MetricSample) -> DashboardCardFacts {
        DashboardCardFacts.make(
            for: id,
            sample: sample,
            // Only CPU and GPU show one; asking for no other keeps the other cards
            // from redrawing on every temperature reading.
            temperature: id == .cpu || id == .gpu ? model.temperature(for: id) : nil,
            systemInfo: systemInfo,
            isOnBattery: model.isOnBattery
        )
    }

    @ViewBuilder
    private func content(for sample: MetricSample, facts: DashboardCardFacts) -> some View {
        let accent = model.accentColor
        let value = DashboardFormat.primaryValue(for: id, sample: sample)
        switch id {
        case .cpu, .gpu:
            DashboardLoadContent(
                value: value,
                caption: facts.captionText,
                history: model.history(id, count: DashboardStyle.historyCount),
                accent: accent
            )
        case .memory:
            DashboardMemoryContent(
                value: value,
                caption: facts.captionText,
                detail: sample.detail,
                chips: facts.chips,
                accent: accent
            )
        case .disk:
            DashboardCapacityContent(
                detail: sample.detail,
                chips: facts.chips,
                accent: accent
            )
        case .battery:
            DashboardBatteryContent(
                percentage: value,
                power: DashboardFormat.batteryPowerWatts(
                    sample: sample,
                    isOnBattery: model.isOnBattery
                ).map(DashboardFormat.batteryPowerText),
                fraction: sample.value,
                caption: facts.captionText,
                estimate: facts.chips.first(where: { $0.symbol == "clock" })?.text
                    ?? DashboardFormat.missingValue,
                estimateLabel: BatteryPowerStatus.resolve(
                    sample.detail,
                    isOnBattery: model.isOnBattery
                ).estimateLabel ?? facts.captionText ?? DashboardFormat.missingValue,
                chargingIconState: BatteryChargeIconState.resolve(
                    isOnBattery: model.isOnBattery,
                    isCharging: (sample.detail["charging"] ?? 0) > 0,
                    isFullyCharged: (sample.detail["fullyCharged"] ?? 0) > 0,
                    isSystemChargeLimitReached:
                        (sample.detail["systemChargeLimitReached"] ?? 0) > 0,
                    isAtFullCapacity: sample.value >= 0.999
                        && (sample.detail["charging"] ?? 0) == 0
                ),
                accent: accent,
                powerHistory: DashboardFormat.batteryPowerHistory(
                    readings: model.batteryPowerReadings(
                        count: DashboardStyle.historyCount
                    )
                )
            )
        case .network:
            let networkSamples = model.historySamples(
                .network,
                count: DashboardStyle.networkHistoryCount
            )
            DashboardNetworkContent(
                down: sample.detail["down"],
                up: sample.detail["up"],
                downloadHistory: networkHistory(networkSamples, direction: "down"),
                uploadHistory: networkHistory(networkSamples, direction: "up"),
                systemInfo: systemInfo,
                accent: accent
            )
        case .fans:
            DashboardValueText(text: value)
            if let caption = facts.captionText {
                DashboardCaption(text: caption)
            }
            // The history is each reading's speed as a share of the fan's maximum,
            // which is only meaningful when this Mac reports a maximum.
            if sample.detail.keys.contains(where: {
                $0.hasPrefix("fan") && $0.hasSuffix("MaxRpm")
            }) {
                DashboardHistoryBars(
                    values: model.history(.fans, count: DashboardStyle.historyCount),
                    accent: accent
                )
            }
        case .sensors:
            DashboardValueText(text: value)
        }
    }

    private func networkHistory(
        _ samples: [MetricSample],
        direction: String
    ) -> [DashboardNetworkPoint] {
        samples.compactMap { sample in
            guard let rate = sample.detail[direction], rate.isFinite, rate >= 0 else { return nil }
            return DashboardNetworkPoint(timestamp: sample.timestamp, rate: rate)
        }
    }

    /// The reading, its state, then every fact the card draws — a card is one button,
    /// so this is all VoiceOver can reach of it.
    private func accessibilityValue(
        sample: MetricSample?,
        state: MetricDataState,
        facts: DashboardCardFacts?
    ) -> String {
        guard let sample, let facts else { return state.localizedName }
        var parts: [String]
        if id == .network {
            parts = [
                DashboardFormat.spokenList([
                    String(localized: "net.down", defaultValue: "Download"),
                    DashboardFormat.rate(sample.detail["down"])
                ]),
                DashboardFormat.spokenList([
                    String(localized: "net.up", defaultValue: "Upload"),
                    DashboardFormat.rate(sample.detail["up"])
                ])
            ]
        } else {
            parts = [DashboardFormat.primaryValue(for: id, sample: sample)]
            if id == .memory {
                parts += DashboardMemoryBreakdown.accessibilityFacts(in: sample.detail)
            } else if id == .battery,
                      let watts = DashboardFormat.batteryPowerWatts(
                        sample: sample,
                        isOnBattery: model.isOnBattery
                      ) {
                parts.append(DashboardFormat.spokenList([
                    String(localized: "battery.power", defaultValue: "Power"),
                    DashboardFormat.batteryPowerText(watts)
                ]))
            }
        }
        parts.append(state.localizedName)
        parts += facts.spoken
        return DashboardFormat.spokenList(parts)
    }
}

/// A chip's content. The card draws it and VoiceOver reads it from the same value.
struct DashboardChipFact: Hashable {
    var symbol: String?
    let text: String
    var tint: Color?
    /// The chip's name: its tooltip, and what VoiceOver says before its text.
    var label: String?

    var spoken: String {
        label.map { DashboardFormat.spokenList([$0, text]) } ?? text
    }
}

/// What a module card states besides its large reading, in reading order. The card
/// draws exactly these and VoiceOver reads exactly these, so neither says less.
struct DashboardCardFacts: Equatable {
    /// Short facts under the reading, drawn on one line.
    var caption: [String] = []
    var chips: [DashboardChipFact] = []
    /// Network only: the interface and local address below the rates.
    var footer: [String] = []

    var captionText: String? {
        caption.isEmpty ? nil : caption.joined(separator: " · ")
    }

    /// Every fact, one entry each, as VoiceOver reads them.
    var spoken: [String] {
        caption + chips.map(\.spoken) + footer
    }

    /// `temperature` is the module's own (CPU or GPU); `isOnBattery` is the system's
    /// providing power source (`AppModel.isOnBattery`).
    static func make(
        for id: MetricID,
        sample: MetricSample,
        temperature: Double?,
        systemInfo: DashboardSystemInfo,
        isOnBattery: Bool?
    ) -> DashboardCardFacts {
        let d = sample.detail
        var facts = DashboardCardFacts()
        switch id {
        case .cpu:
            if let cores = d["coreCount"], cores > 0 {
                let count = Int(cores)
                facts.caption.append(String(
                    localized: "dashboard.cpu.cores",
                    defaultValue: "\(count) cores"
                ))
            }
            if let temperature {
                facts.caption.append(DashboardFormat.temperature(temperature))
            }
        case .gpu:
            if let memory = d["inUseMemory"], memory > 0 {
                facts.caption.append(String(
                    localized: "dashboard.gpu.memoryInUse",
                    defaultValue: "\(MetricFormat.bytes(memory)) in use"
                ))
            }
            if let temperature {
                facts.caption.append(DashboardFormat.temperature(temperature))
            }
        case .memory:
            facts.caption += usedOfTotal(d)
            if let pressurePercent = d["pressurePercent"],
               pressurePercent.isFinite,
               (0...100).contains(pressurePercent) {
                let level = d["pressureLevel"].flatMap {
                    MemoryPressureLevel(rawValue: Int($0))
                }
                facts.chips.append(DashboardChipFact(
                    symbol: "gauge.with.needle",
                    text: "\(Int(pressurePercent.rounded()))%",
                    tint: level?.tint,
                    label: String(localized: "mem.pressure", defaultValue: "Pressure")
                ))
            }
            if let swapUsed = d["swapUsed"],
               let swapTotal = d["swapTotal"], swapTotal > 0 {
                facts.chips.append(DashboardChipFact(
                    symbol: "arrow.left.arrow.right",
                    text: DashboardFormat.memorySwapUsed(swapUsed),
                    label: String(localized: "mem.swap", defaultValue: "Swap")
                ))
            }
        case .disk:
            facts.caption += storageUsedOfTotal(d)
            if let volume = systemInfo.startupVolumeName {
                facts.chips.append(DashboardChipFact(text: volume))
            }
        case .battery:
            let status = BatteryPowerStatus.resolve(d, isOnBattery: isOnBattery)
            facts.caption.append(status.localizedName)
            if let label = status.estimateLabel, let minutes = status.estimate(in: d) {
                facts.chips.append(DashboardChipFact(
                    symbol: "clock",
                    text: DashboardFormat.duration(minutes: minutes),
                    label: label
                ))
            }
            if let health = d["healthPercent"] {
                facts.chips.append(DashboardChipFact(
                    symbol: "heart",
                    text: "\(Int(health))%",
                    label: String(localized: "battery.health", defaultValue: "Health")
                ))
            }
        case .network:
            if let address = systemInfo.localAddress {
                facts.footer = [systemInfo.interfaceName, address].compactMap { $0 }
            }
        case .fans:
            if let fans = d["fanCount"], fans > 0 {
                let count = Int(fans)
                facts.caption.append(String(
                    localized: "dashboard.fans.count",
                    defaultValue: "\(count) fans"
                ))
            }
        case .sensors:
            break
        }
        return facts
    }

    private static func usedOfTotal(_ d: [String: Double]) -> [String] {
        guard let used = d["used"], let total = d["total"], total > 0 else { return [] }
        return [DashboardFormat.usedOfTotal(used: used, total: total)]
    }

    private static func storageUsedOfTotal(_ d: [String: Double]) -> [String] {
        guard let used = d["used"], let total = d["total"], total > 0 else { return [] }
        return [DashboardFormat.storageUsedOfTotal(used: used, total: total)]
    }
}

/// CPU and GPU: the load, a caption, and the recent history as bars.
private struct DashboardLoadContent: View {
    let value: String
    let caption: String?
    let history: [Double]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.tiny) {
            DashboardValueText(text: value)
            if let caption {
                DashboardCaption(text: caption)
            }
        }
        DashboardHistoryBars(values: history, accent: accent)
    }
}

/// Disk: an empty-centered usage ring, storage details, and two compact footer pills.
private struct DashboardCapacityContent: View {
    let detail: [String: Double]
    let chips: [DashboardChipFact]
    let accent: Color

    var body: some View {
        let total = validValue("total")
        let used = validValue("used")
        let usedFraction = fraction(used, total: total)
        let totalText = total.map(MetricFormat.storageBytes) ?? DashboardFormat.missingValue

        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: ExperienceSpacing.small) {
                DashboardRing(fraction: usedFraction ?? 0, accent: accent, diameter: 46)

                Rectangle()
                    .fill(Color.primary.opacity(DashboardStyle.trackOpacity))
                    .frame(width: ExperienceSpacing.hairline, height: 54)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
                    DashboardStorageSummary(
                        title: String(localized: "disk.used", defaultValue: "Used"),
                        amount: used.map(MetricFormat.storageBytes) ?? DashboardFormat.missingValue,
                        marker: accent
                    )
                    DashboardStorageSummary(
                        title: String(localized: "disk.total", defaultValue: "Total"),
                        amount: totalText,
                        marker: Color.primary.opacity(0.36)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: ExperienceSpacing.tiny)
            DashboardChipRow(chips: [
                DashboardChipFact(
                    symbol: nil,
                    text: usedFraction.map { MetricFormat.percent($0, decimals: 1) }
                        ?? DashboardFormat.missingValue,
                    tint: accent,
                    label: String(localized: "disk.used", defaultValue: "Used")
                ),
                DashboardChipFact(
                    symbol: nil,
                    text: chips.first?.text ?? DashboardFormat.missingValue,
                    tint: .secondary
                )
            ])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func validValue(_ key: String) -> Double? {
        guard let value = detail[key], value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func fraction(_ amount: Double?, total: Double?) -> Double? {
        guard let amount, let total, total > 0 else { return nil }
        return min(max(amount / total, 0), 1)
    }
}

private struct DashboardStorageSummary: View {
    let title: String
    let amount: String
    let marker: Color

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.tiny) {
            HStack(spacing: ExperienceSpacing.xSmall) {
                Circle()
                    .fill(Color.primary.opacity(DashboardStyle.chipFillOpacity))
                    .frame(width: 11, height: 11)
                    .overlay {
                        Circle()
                            .fill(marker)
                            .frame(width: 6, height: 6)
                    }
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            DashboardStorageAmount(text: amount)
        }
        .frame(height: 30, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardStorageAmount: View {
    let text: String

    var body: some View {
        let parts = DashboardFormat.split(text)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(parts.number)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Battery card uses a filled battery glyph and recent power draw instead of a
/// circular charge ring.
private struct DashboardBatteryContent: View {
    let percentage: String
    let power: String?
    let fraction: Double
    let caption: String?
    let estimate: String
    let estimateLabel: String
    let chargingIconState: BatteryChargeIconState
    let accent: Color
    let powerHistory: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: ExperienceSpacing.xSmall)
            HStack(alignment: .center, spacing: ExperienceSpacing.xSmall) {
                DashboardBatteryIcon(
                    fraction: fraction,
                    percentage: percentage,
                    accent: accent
                )
                    .frame(width: 46)
                VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
                    BatteryInfoRow(
                        symbol: "bolt.fill",
                        value: power ?? DashboardFormat.missingValue,
                        status: caption ?? DashboardFormat.missingValue,
                        iconColor: chargingIconState.color(accent: accent)
                    )
                    BatteryInfoRow(
                        symbol: "clock",
                        value: estimate,
                        status: estimateLabel,
                        iconColor: .secondary
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 64, alignment: .center)
            Spacer(minLength: ExperienceSpacing.xSmall)
            DashboardHistoryBars(values: powerHistory, accent: accent)
                .frame(height: DashboardStyle.barMinimumHeight)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct BatteryInfoRow: View {
    let symbol: String
    let value: String
    let status: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: ExperienceSpacing.xSmall) {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(height: 30, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension BatteryChargeIconState {
    func color(accent: Color) -> Color {
        switch self {
        case .disconnected: return .gray
        case .connected: return accent
        case .fullyCharged: return .green
        }
    }
}

/// Battery silhouette with a bottom-up accent fill, matching the supplied dashboard
/// reference and keeping charge level readable without a circular ring.
private struct DashboardBatteryIcon: View {
    let fraction: Double
    let percentage: String
    let accent: Color

    var body: some View {
        VStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.primary.opacity(0.16))
                .frame(width: 14, height: 5)
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.16))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(accent)
                        .frame(height: geometry.size.height * min(max(fraction, 0), 1))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    Text(percentage)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 3)
                }
            }
            .frame(width: 42, height: 54)
        }
        .frame(width: 46, height: 60)
        .accessibilityHidden(true)
    }
}

/// A total-memory stacked bar plus a compact legend. The three states share the
/// current accent hue at different strengths so their amounts are easy to compare.
private struct DashboardMemoryContent: View {
    let value: String
    let caption: String?
    let detail: [String: Double]
    let chips: [DashboardChipFact]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.hairline) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.hairline) {
                DashboardValueText(text: value)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            DashboardMemoryBreakdown(detail: detail, accent: accent)
            Spacer(minLength: 0)
            DashboardChipRow(chips: chips)
                .padding(.top, ExperienceSpacing.xSmall + ExperienceSpacing.tiny)
        }
    }
}

struct DashboardMemoryBreakdown: View {
    private struct Part: Identifiable {
        let key: String
        let title: String
        let tintStrength: Double
        let amount: Double

        var id: String { key }
    }

    let detail: [String: Double]
    let accent: Color

    private var parts: [Part] {
        Self.definitions.compactMap { definition in
            let (key, title, tintStrength) = definition
            guard let amount = detail[key], amount >= 0 else { return nil }
            return Part(key: key, title: title, tintStrength: tintStrength, amount: amount)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.tiny) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(parts) { part in
                        Rectangle()
                            .fill(accent.opacity(part.tintStrength))
                            .frame(width: segmentWidth(part, in: geometry.size.width))
                    }
                    Spacer(minLength: 0)
                }
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
            }
            .frame(height: 5)
            .padding(.bottom, ExperienceSpacing.small)

            ForEach(parts) { part in
                HStack(spacing: ExperienceSpacing.xSmall) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(accent.opacity(part.tintStrength))
                        .frame(width: 6, height: 6)
                    Text(part.title)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: ExperienceSpacing.xSmall)
                    Text(MetricFormat.bytes(part.amount))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 8.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

        }
    }

    private func segmentWidth(_ part: Part, in width: CGFloat) -> CGFloat {
        guard let total = detail["total"], total > 0 else { return 0 }
        return width * min(max(part.amount / total, 0), 1)
    }

    static func accessibilityFacts(in detail: [String: Double]) -> [String] {
        var facts: [String] = definitions.compactMap { definition -> String? in
            let (key, title, _) = definition
            guard let amount = detail[key], amount >= 0 else { return nil }
            return DashboardFormat.spokenList([title, MetricFormat.bytes(amount)])
        }
        return facts
    }

    private static let definitions: [(String, String, Double)] = [
        ("active", String(localized: "mem.active", defaultValue: "Active"), 1),
        ("wired", String(localized: "mem.wired", defaultValue: "Wired"), 0.68),
        ("compressed", String(localized: "mem.compressed", defaultValue: "Compressed"), 0.38)
    ]
}

/// Download and upload throughput with independent live histories and the local address.
private struct DashboardNetworkPoint {
    let timestamp: Date
    let rate: Double
}

private struct DashboardNetworkContent: View {
    let down: Double?
    let up: Double?
    let downloadHistory: [DashboardNetworkPoint]
    let uploadHistory: [DashboardNetworkPoint]
    let systemInfo: DashboardSystemInfo
    let accent: Color
    @State private var latestNetworkInfo: DashboardSystemInfo?

    var body: some View {
        let currentNetworkInfo = latestNetworkInfo ?? systemInfo
        let connected = currentNetworkInfo.localAddress != nil
        VStack(alignment: .leading, spacing: 0) {
            DashboardNetworkTrafficRow(
                symbol: "arrow.down",
                label: String(localized: "net.down", defaultValue: "Download"),
                rate: connected ? down : nil,
                history: connected ? downloadHistory : [],
                accent: accent
            )
            Spacer(minLength: ExperienceSpacing.xSmall)
            DashboardNetworkTrafficRow(
                symbol: "arrow.up",
                label: String(localized: "net.up", defaultValue: "Upload"),
                rate: connected ? up : nil,
                history: connected ? uploadHistory : [],
                accent: accent
            )
            Spacer(minLength: ExperienceSpacing.xSmall)
            DashboardNetworkFooter(systemInfo: currentNetworkInfo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                let refreshedInfo = await MainActor.run {
                    DashboardSystemInfo.readNetwork()
                }
                if refreshedInfo != latestNetworkInfo {
                    latestNetworkInfo = refreshedInfo
                }
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    break
                }
            }
        }
    }
}

private struct DashboardNetworkTrafficRow: View {
    let symbol: String
    let label: String
    let rate: Double?
    let history: [DashboardNetworkPoint]
    let accent: Color

    var body: some View {
        HStack(spacing: ExperienceSpacing.xSmall) {
            Circle()
                .fill(Color.primary.opacity(DashboardStyle.chipFillOpacity))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                DashboardNetworkRateText(rate: DashboardFormat.rate(rate))
                Text(label)
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DashboardNetworkGraph(samples: history, accent: accent)
                .frame(width: 32, height: 26)
        }
        .frame(height: 28, alignment: .center)
    }
}

private struct DashboardNetworkRateText: View {
    let rate: String

    var body: some View {
        let parts = DashboardFormat.split(rate)
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.tiny) {
            Text(parts.number)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardNetworkGraph: View {
    let samples: [DashboardNetworkPoint]
    let accent: Color

    var body: some View {
        Canvas { context, size in
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height - 1))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                context.stroke(baseline, with: .color(Color.primary.opacity(0.1)), lineWidth: 1)

                let validSamples = samples.filter { $0.rate.isFinite && $0.rate >= 0 }
                guard validSamples.count > 1,
                      (validSamples.map(\.rate).max() ?? 0) > 0
                else { return }

                let maximum = SparklineScale.maximum(
                    of: validSamples.map(\.rate),
                    floor: SparklineScale.networkFloor
                )
                let points = graphPoints(validSamples, in: size, maximum: maximum)
                let line = smoothPath(through: points)
                var area = line
                if let first = points.first, let last = points.last {
                    area.addLine(to: CGPoint(x: last.x, y: size.height - 1))
                    area.addLine(to: CGPoint(x: first.x, y: size.height - 1))
                    area.closeSubpath()
                }
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [accent.opacity(0.2), accent.opacity(0.015)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
                context.stroke(
                    line,
                    with: .color(accent),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "chart.recentTrend", defaultValue: "Recent trend"))
        .accessibilityValue(graphSummary)
    }

    private func graphPoints(
        _ samples: [DashboardNetworkPoint],
        in size: CGSize,
        maximum: Double
    ) -> [CGPoint] {
        let inset: CGFloat = 1
        let graphWidth = max(size.width - inset * 2, 0)
        let graphHeight = max(size.height - inset * 2, 0)
        guard let firstDate = samples.first?.timestamp,
              let lastDate = samples.last?.timestamp
        else { return [] }
        let duration = lastDate.timeIntervalSince(firstDate)
        return samples.enumerated().map { index, sample in
            let progress = duration > 0
                ? min(max(sample.timestamp.timeIntervalSince(firstDate) / duration, 0), 1)
                : Double(index) / Double(max(samples.count - 1, 1))
            return CGPoint(
                x: inset + graphWidth * CGFloat(progress),
                y: size.height - inset
                    - graphHeight * CGFloat(min(max(sample.rate / maximum, 0), 1))
            )
        }
    }

    private func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let previous = points[max(index - 1, 0)]
            let next = points[min(index + 2, points.count - 1)]
            let controlOne = CGPoint(
                x: start.x + (end.x - previous.x) / 6,
                y: start.y + (end.y - previous.y) / 6
            )
            let controlTwo = CGPoint(
                x: end.x - (next.x - start.x) / 6,
                y: end.y - (next.y - start.y) / 6
            )
            let minimumY = min(start.y, end.y)
            let maximumY = max(start.y, end.y)
            let minimumX = min(start.x, end.x)
            let maximumX = max(start.x, end.x)
            path.addCurve(
                to: end,
                control1: CGPoint(
                    x: min(max(controlOne.x, minimumX), maximumX),
                    y: min(max(controlOne.y, minimumY), maximumY)
                ),
                control2: CGPoint(
                    x: min(max(controlTwo.x, minimumX), maximumX),
                    y: min(max(controlTwo.y, minimumY), maximumY)
                )
            )
        }
        return path
    }

    private var graphSummary: String {
        guard let latest = samples.last(where: { $0.rate.isFinite && $0.rate >= 0 }) else {
            return String(localized: "chart.noReadings", defaultValue: "No readings")
        }
        return DashboardFormat.rate(latest.rate)
    }
}

private struct DashboardNetworkFooter: View {
    let systemInfo: DashboardSystemInfo

    var body: some View {
        VStack(spacing: ExperienceSpacing.small) {
            Rectangle()
                .fill(Color.primary.opacity(DashboardStyle.trackOpacity))
                .frame(height: ExperienceSpacing.hairline)
                .accessibilityHidden(true)

            HStack(spacing: ExperienceSpacing.xSmall) {
                Image(systemName: systemInfo.interfaceSymbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(systemInfo.localAddress ?? DashboardFormat.missingValue)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(systemInfo.interfaceName ?? "")
    }
}

/// The Mac itself. Not a button: there is no module detail behind it.
private struct DashboardDeviceCard: View {
    let model: AppModel

    private static let version = DashboardFormat.systemVersion(
        ProcessInfo.processInfo.operatingSystemVersion
    )

    var body: some View {
        DashboardCardLayout(
            // A Mac with a battery is a laptop.
            symbol: model.availableModules.contains(.battery)
                ? "laptopcomputer"
                : "desktopcomputer",
            title: DeviceCardName.localized
        ) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.tiny) {
                DashboardValueText(text: Self.version)
                // A product name, the same in every language.
                DashboardCaption(text: "macOS")
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "cpu.uptime", defaultValue: "Uptime"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // The uptime reads in days, hours and minutes, so a minute is as often
                // as the string can change. Following the sampling cycle instead would
                // re-evaluate this card sixty times for every time it had news.
                TimelineView(.periodic(from: .now, by: Self.uptimeInterval)) { _ in
                    Text(uptime)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .background {
            DashboardCardBackground(
                fillOpacity: model.dashboardBackgroundOpacity,
                appearance: model.dashboardAppearance
            )
        }
        .accessibilityElement(children: .combine)
    }

    /// Coarsest interval that still keeps the minutes place honest.
    private static let uptimeInterval: TimeInterval = 60

    private var uptime: String {
        // Since boot, sleep included, as `uptime` and System Information count it.
        DashboardFormat.uptime(SystemUptime.sinceBoot)
    }
}

/// Shown beside the device card when no module is chosen.
private struct DashboardEmptyHintCard: View {
    let onOpenSettings: () -> Void
    let appearance: DashboardAppearance
    let backgroundOpacity: Double
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: ExperienceSpacing.small) {
            Text(String(
                localized: "dashboard.empty",
                defaultValue: "No readings chosen"
            ))
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            Button(
                String(
                    localized: "dashboard.empty.action",
                    defaultValue: "Choose in Settings…"
                ),
                action: onOpenSettings
            )
            .buttonStyle(.link)
            .font(.callout)
        }
        .multilineTextAlignment(.center)
        .padding(DashboardPopoverView.cardPadding)
        .frame(width: DashboardPopoverView.cardWidth)
        .frame(height: DashboardPopoverView.cardHeight, alignment: .center)
        .background {
            let shape = RoundedRectangle(cornerRadius: ExperienceRadius.panel, style: .continuous)
            if appearance == .regular {
                shape.strokeBorder(
                    Color.primary.opacity(
                        contrast == .increased
                            ? ExperienceSurface.increasedBorderOpacity
                            : ExperienceSurface.standardBorderOpacity
                    ),
                    style: StrokeStyle(lineWidth: ExperienceSpacing.hairline, dash: [4, 3])
                )
            } else {
                DashboardCardBackground(
                    fillOpacity: backgroundOpacity,
                    appearance: appearance
                )
                    .overlay {
                        shape.strokeBorder(
                            Color.primary.opacity(
                                contrast == .increased
                                    ? ExperienceSurface.increasedBorderOpacity
                                    : ExperienceSurface.standardBorderOpacity
                            ),
                            style: StrokeStyle(lineWidth: ExperienceSpacing.hairline, dash: [4, 3])
                        )
                    }
                }
        }
    }
}

/// The worst alerting condition routed to Compact Health, above the cards.
private struct DashboardHealthBanner: View {
    let model: AppModel
    /// The modules shown as cards, so a condition can tell whether its module is a card
    /// here or must open in the detail window.
    let cards: [MetricID]
    let onSelect: (MetricID) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let conditions = model.healthConditions
        if let worst = conditions.first {
            let tint = worst.severity.dashboardTint
            let shape = RoundedRectangle(
                cornerRadius: ExperienceRadius.panel,
                style: .continuous
            )
            Button {
                // A condition can belong to a module with no card here (thermal
                // pressure is CPU's, even with CPU off the dashboard). Only a card's
                // module is reported visible and sampled while the dashboard is open,
                // so any other opens in the detail window, as Compact Health does.
                if cards.contains(worst.metricID) {
                    onSelect(worst.metricID)
                } else {
                    model.onOpenMetricDetail?(worst.metricID)
                }
            } label: {
                HStack(spacing: ExperienceSpacing.small) {
                    Image(systemName: worst.severity.symbolName)
                        .font(.title3)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(worst.metricID.localizedName)
                            .font(.callout.weight(.semibold))
                        Text(worst.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: ExperienceSpacing.small)
                    if conditions.count > 1 {
                        Text(verbatim: "+\(conditions.count - 1)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, DashboardPopoverView.padding)
                .padding(.vertical, ExperienceSpacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(tint.opacity(0.12)))
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(tint, lineWidth: ExperienceSpacing.hairline)
                    }
                }
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(worst: worst, count: conditions.count))
            .accessibilityHint(String(
                localized: "dashboard.card.hint",
                defaultValue: "Shows details"
            ))
        }
    }

    /// Everything the banner shows by symbol and color as well as in words: the
    /// severity, the module and what is wrong, and how many more conditions there are.
    private func accessibilityLabel(worst: ActiveAlertCondition, count: Int) -> String {
        var parts = [
            worst.severity.localizedName,
            worst.metricID.localizedName,
            worst.summary
        ]
        if count > 1 {
            let more = count - 1
            parts.append(String(
                localized: "dashboard.health.more",
                defaultValue: "\(more) more"
            ))
        }
        return DashboardFormat.spokenList(parts)
    }
}

// MARK: - Card parts

/// Header and content share the same fixed width and height across the Dashboard.
private struct DashboardCardLayout<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall + ExperienceSpacing.tiny) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content
        }
        .padding(DashboardPopoverView.cardPadding)
        .frame(width: DashboardPopoverView.cardWidth, alignment: .leading)
        .frame(height: DashboardPopoverView.cardHeight, alignment: .topLeading)
    }
}

struct DashboardCardBackground: View {
    var fillOpacity = ExperienceSurface.subtleFillOpacity
    var appearance: DashboardAppearance = .regular
    var cornerRadius = ExperienceRadius.panel
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch appearance {
        case .regular:
            shape
                .fill(Color.primary.opacity(fillOpacity))
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(
                            Color.primary.opacity(ExperienceSurface.increasedBorderOpacity),
                            lineWidth: ExperienceSpacing.hairline
                        )
                    }
                }
        case .liquidGlass:
            glassSurface(shape: shape)
        }
    }

    @ViewBuilder
    private func glassSurface(shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            shape
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay { clearTint(shape: shape) }
                .overlay { border(shape: shape) }
        } else {
            supportedGlassSurface(shape: shape)
        }
    }

    @ViewBuilder
    private func supportedGlassSurface(shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            nativeGlassSurface(shape: shape)
        } else {
            fallbackGlassSurface(shape: shape)
        }
        #else
        fallbackGlassSurface(shape: shape)
        #endif
    }

    @ViewBuilder
    private func fallbackGlassSurface(shape: RoundedRectangle) -> some View {
        // Stay transparent on older SDKs too; a material fallback looks frosted.
        shape
            .fill(.clear)
            .overlay { clearTint(shape: shape) }
            .overlay { border(shape: shape) }
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private func nativeGlassSurface(shape: RoundedRectangle) -> some View {
        shape
            .fill(.clear)
            .glassEffect(.clear, in: shape)
            .overlay { clearTint(shape: shape) }
            .overlay { border(shape: shape) }
            .shadow(color: Color.black.opacity(0.025), radius: 3, y: 1)
    }
    #endif

    private func clearTint(shape: RoundedRectangle) -> some View {
        // Keep Clear dark without a material blur or a bright primary-color wash.
        shape.fill(Color.black.opacity(fillOpacity))
    }

    private func border(shape: RoundedRectangle) -> some View {
        shape.strokeBorder(
            Color.primary.opacity(
                contrast == .increased ? ExperienceSurface.increasedBorderOpacity : 0.13
            ),
            lineWidth: ExperienceSpacing.hairline
        )
    }
}

/// A card as a button: brighter under the pointer and while pressed.
private struct DashboardCardButtonStyle: ButtonStyle {
    let appearance: DashboardAppearance
    let backgroundOpacity: Double

    func makeBody(configuration: Configuration) -> some View {
        DashboardCardButton(
            configuration: configuration,
            appearance: appearance,
            backgroundOpacity: backgroundOpacity
        )
    }
}

private struct DashboardCardButton: View {
    let configuration: ButtonStyleConfiguration
    let appearance: DashboardAppearance
    let backgroundOpacity: Double
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .background {
                DashboardCardBackground(fillOpacity: fillOpacity, appearance: appearance)
            }
            .contentShape(
                RoundedRectangle(cornerRadius: ExperienceRadius.panel, style: .continuous)
            )
            .onHover { isHovered = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: ExperienceMotion.quickDuration),
                value: isHovered
            )
    }

    private var fillOpacity: Double {
        // Clear glass has no hover/pressed tint. That interaction lift looked like
        // a white flash because primary resolves to white in the dark appearance.
        guard appearance != .liquidGlass else { return backgroundOpacity }

        if configuration.isPressed {
            let increment = ExperienceSurface.selectedFillOpacity
                - DashboardAppearance.defaultBackgroundOpacity
            return min(backgroundOpacity + increment, DashboardAppearance.maximumBackgroundOpacity + increment)
        }
        let increment = DashboardStyle.hoverFillOpacity
            - DashboardAppearance.defaultBackgroundOpacity
        return isHovered
            ? min(backgroundOpacity + increment, DashboardAppearance.maximumBackgroundOpacity + increment)
            : backgroundOpacity
    }
}

/// A card's large reading. A trailing unit ("KB/s", "RPM") is set smaller than the
/// number, and a long reading shrinks rather than clips.
private struct DashboardValueText: View {
    let text: String
    var size = DashboardStyle.valueSize

    var body: some View {
        let parts = DashboardFormat.split(text)
        valueText(parts)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // Shrinks only to fit the width; a tall row never squeezes it.
            .fixedSize(horizontal: false, vertical: true)
    }

    private func valueText(_ parts: (number: String, unit: String)) -> Text {
        let number = Text(parts.number)
            .font(.system(size: size, weight: .semibold, design: .rounded))
        guard !parts.unit.isEmpty else { return number }
        return number
            + Text(verbatim: " " + parts.unit)
                .font(.system(size: size * 0.55, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
    }
}

private struct DashboardCaption: View {
    let text: String

    var body: some View {
        // One line, shrinking a little before it would wrap: a second line would make
        // the whole row taller for the sake of one caption.
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // Shrinks only to fit the width; a tall row never squeezes it.
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A small fact at the bottom of a card: a symbol and a short value, with its name
/// in the tooltip. VoiceOver reads it through the card's value (`DashboardCardFacts`),
/// since a card is one button and nothing inside it is reachable on its own.
private struct DashboardChip: View {
    let fact: DashboardChipFact
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ExperienceRadius.compact, style: .continuous)
        let color = fact.tint ?? Color.primary
        HStack(spacing: ExperienceSpacing.tiny) {
            if let symbol = fact.symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
            }
            Text(fact.text)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(color)
        .padding(.horizontal, ExperienceSpacing.xSmall)
        .padding(.vertical, ExperienceSpacing.hairline)
        .background(shape.fill(color.opacity(DashboardStyle.chipFillOpacity)))
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(
                    color.opacity(ExperienceSurface.increasedBorderOpacity),
                    lineWidth: ExperienceSpacing.hairline
                )
            }
        }
        .help(fact.label ?? "")
    }
}

/// Chips side by side, or stacked when a translation makes them too wide for a row.
private struct DashboardChipRow: View {
    let chips: [DashboardChipFact]

    var body: some View {
        if !chips.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ExperienceSpacing.xSmall) { chipViews }
                VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) { chipViews }
            }
        }
    }

    private var chipViews: some View {
        ForEach(chips, id: \.self) { DashboardChip(fact: $0) }
    }
}

/// A share of a whole as a ring in the chart color. The number beside it is the
/// reading; the ring only illustrates it.
private struct DashboardRing: View {
    let fraction: Double
    let accent: Color
    let diameter: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let lineWidth = DashboardStyle.ringLineWidth
        ZStack {
            Circle()
                .stroke(
                    Color.primary.opacity(
                        contrast == .increased
                            ? DashboardStyle.increasedTrackOpacity
                            : DashboardStyle.trackOpacity
                    ),
                    lineWidth: lineWidth
                )
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// Recent history as bars on faint tracks, newest on the right. Slots before the first
/// reading stay empty rather than drawn as zero.
private struct DashboardHistoryBars: View {
    let values: [Double]
    let accent: Color
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let slots = DashboardStyle.historyCount
        let recent = Array(values.suffix(slots))
        let firstFilled = slots - recent.count
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: DashboardStyle.barSpacing) {
                ForEach(0..<slots, id: \.self) { slot in
                    let bar = RoundedRectangle(
                        cornerRadius: ExperienceRadius.micro,
                        style: .continuous
                    )
                    bar
                        .fill(Color.primary.opacity(
                            contrast == .increased
                                ? DashboardStyle.increasedTrackOpacity
                                : DashboardStyle.trackOpacity
                        ))
                        .overlay(alignment: .bottom) {
                            if slot >= firstFilled {
                                let value = min(max(recent[slot - firstFilled], 0), 1)
                                bar
                                    .fill(accent)
                                    .frame(height: max(
                                        DashboardStyle.barFloor,
                                        geo.size.height * value
                                    ))
                            }
                        }
                }
            }
        }
        .frame(minHeight: DashboardStyle.barMinimumHeight, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private extension MemoryPressureLevel {
    /// Preserve the native warning and critical colors on the pressure percentage.
    var tint: Color? {
        switch self {
        case .normal: return nil
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

private extension AttentionSeverity {
    var dashboardTint: Color {
        switch self {
        case .info: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
