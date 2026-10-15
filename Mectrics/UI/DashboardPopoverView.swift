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
            DashboardHealthBanner(model: model, cards: cardModules) { select($0) }
            cardGrid
            actionFooter
        }
        .padding(Self.padding)
    }

    private var cardGrid: some View {
        Grid(
            horizontalSpacing: Self.cardSpacing,
            verticalSpacing: Self.cardSpacing
        ) {
            ForEach(
                DashboardLayout.rows(
                    for: cardModules,
                    includesDevice: model.showsDeviceCard
                ),
                id: \.self
            ) { row in
                // A row with one card leaves the second cell empty.
                GridRow {
                    ForEach(row, id: \.self) { card in
                        cell(for: card)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for card: DashboardCard) -> some View {
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
            // The dashboard's modules are chosen in the Menu Bar pane, whichever pane
            // Settings last showed.
            DashboardEmptyHintCard { model.onOpenMenuBarSettings?() }
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
            PopoverActionBar { model.onOpenSettings?() }
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
        let cards = cards(for: modules, includesDevice: includesDevice)
        return stride(from: 0, to: cards.count, by: 2).map {
            Array(cards[$0..<min($0 + 2, cards.count)])
        }
    }
}

/// System facts the dashboard shows but no sample carries. Reading them touches the
/// system, so it happens once as the popover appears, never from a view's body.
struct DashboardSystemInfo: Equatable {
    var localAddress: String?
    /// The primary interface as System Settings names it ("Wi-Fi"), or its BSD name.
    var interfaceName: String?
    var interfaceSymbol = "network"
    /// The startup volume's name in Finder ("Macintosh HD").
    var startupVolumeName: String?

    @MainActor
    static func read() -> DashboardSystemInfo {
        var info = DashboardSystemInfo()
        if let primary = NetworkInfo.primaryIPv4() {
            info.localAddress = primary.address
            let described = describeInterface(bsdName: primary.interface)
            info.interfaceName = described?.name ?? primary.interface
            info.interfaceSymbol = described?.symbol ?? "network"
        }
        info.startupVolumeName = try? URL(fileURLWithPath: "/")
            .resourceValues(forKeys: [.volumeLocalizedNameKey])
            .volumeLocalizedName
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
        .buttonStyle(DashboardCardButtonStyle())
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
                accent: accent,
                powerHistory: DashboardFormat.batteryPowerHistory(
                    samples: model.historySamples(
                        .battery,
                        count: DashboardStyle.historyCount
                    ),
                    isOnBattery: model.isOnBattery
                )
            )
        case .network:
            DashboardNetworkContent(
                down: sample.detail["down"],
                up: sample.detail["up"],
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
            HStack(spacing: ExperienceSpacing.small) {
                DashboardRing(fraction: usedFraction ?? 0, accent: accent, diameter: 46)

                VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
                    DashboardStorageSummary(
                        title: String(localized: "disk.used", defaultValue: "Used"),
                        amount: used.map(MetricFormat.storageBytes) ?? DashboardFormat.missingValue,
                        capacity: totalText,
                        marker: accent
                    )
                    DashboardStorageSummary(
                        title: String(localized: "disk.total", defaultValue: "Total"),
                        amount: totalText,
                        capacity: nil,
                        marker: Color.primary.opacity(0.36)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: ExperienceSpacing.tiny)
            HStack(spacing: ExperienceSpacing.xSmall) {
                DashboardDiskFooterChip(fact: DashboardChipFact(
                    symbol: "circle.fill",
                    text: usedFraction.map { MetricFormat.percent($0, decimals: 1) }
                        ?? DashboardFormat.missingValue,
                    tint: accent,
                    label: String(localized: "disk.used", defaultValue: "Used")
                ))
                .frame(maxWidth: .infinity)
                DashboardDiskFooterChip(fact: DashboardChipFact(
                    symbol: "externaldrive",
                    text: chips.first?.text ?? DashboardFormat.missingValue,
                    tint: .secondary
                ))
                .frame(maxWidth: .infinity)
            }
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
    let capacity: String?
    let marker: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            if let capacity {
                Text("of \(capacity)")
                    .font(.system(size: 7.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
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
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Uses the same treatment as Memory's footer chips while keeping disk-only width
/// fitting local to this card.
private struct DashboardDiskFooterChip: View {
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
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(color)
        .padding(.horizontal, ExperienceSpacing.xSmall)
        .padding(.vertical, ExperienceSpacing.hairline)
        .frame(maxWidth: .infinity)
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
        .accessibilityElement(children: .combine)
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
                        accent: accent
                    )
                    BatteryInfoRow(
                        symbol: "clock",
                        value: estimate,
                        status: estimateLabel,
                        accent: accent
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
    let accent: Color

    var body: some View {
        HStack(spacing: ExperienceSpacing.xSmall) {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(symbol == "bolt.fill" ? accent : Color.secondary)
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

/// Download and upload as two large rates, then the local address.
private struct DashboardNetworkContent: View {
    let down: Double?
    let up: Double?
    let systemInfo: DashboardSystemInfo
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rateLine(symbol: "arrowtriangle.down.fill", rate: down)
            rateLine(symbol: "arrowtriangle.up.fill", rate: up)
        }
        Spacer(minLength: 0)
        // One line: the symbol says Wi-Fi or Ethernet, the tooltip and VoiceOver name
        // the interface.
        if let address = systemInfo.localAddress {
            Label {
                Text(address)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: systemInfo.interfaceSymbol)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .help(systemInfo.interfaceName ?? "")
        }
    }

    private func rateLine(symbol: String, rate: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.xSmall) {
            // The arrow's shape carries the direction; the accent only decorates it.
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            DashboardValueText(
                text: DashboardFormat.rate(rate),
                size: DashboardStyle.rateSize
            )
        }
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
        .background { DashboardCardBackground() }
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
            RoundedRectangle(cornerRadius: ExperienceRadius.panel, style: .continuous)
                .strokeBorder(
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

private struct DashboardCardBackground: View {
    var fillOpacity = ExperienceSurface.subtleFillOpacity
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ExperienceRadius.panel, style: .continuous)
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
    }
}

/// A card as a button: brighter under the pointer and while pressed.
private struct DashboardCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DashboardCardButton(configuration: configuration)
    }
}

private struct DashboardCardButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .background {
                DashboardCardBackground(fillOpacity: fillOpacity)
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
        if configuration.isPressed { return ExperienceSurface.selectedFillOpacity }
        return isHovered ? DashboardStyle.hoverFillOpacity : ExperienceSurface.subtleFillOpacity
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
