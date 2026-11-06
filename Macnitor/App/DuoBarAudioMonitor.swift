@preconcurrency import CoreAudio
import Foundation

struct DuoBarAudioOutput: Identifiable, Equatable {
    let uid: String
    let name: String
    var id: String { uid }
}

struct DuoBarAudioState {
    var volume: Double?
    var muted: Bool
    var canSetVolume: Bool
    var canSetMute: Bool
    var outputs: [DuoBarAudioOutput]
    var selectedOutputUID: String?
    var inputs: [DuoBarAudioOutput]
    var selectedInputUID: String?
}

/// Reads and controls the default output through public Core Audio properties.
/// Listeners are installed only while the optional DuoBar presentation is enabled.
@MainActor
final class DuoBarAudioMonitor {
    private typealias Listener = AudioObjectPropertyListenerBlock
    private struct Registration {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let listener: Listener
    }

    var onChange: ((DuoBarAudioState) -> Void)?
    private let queue = DispatchQueue(label: "app.macnitor.duobar-audio", qos: .utility)
    private var registrations: [Registration] = []
    private var outputID = AudioDeviceID(kAudioObjectUnknown)
    private var inputID = AudioDeviceID(kAudioObjectUnknown)
    private var volumeAddress: AudioObjectPropertyAddress?
    private var muteAddress: AudioObjectPropertyAddress?
    private var outputs: [DuoBarAudioOutput] = []
    private var inputs: [DuoBarAudioOutput] = []
    private(set) var volume: Double?
    private(set) var muted = false
    private(set) var canSetVolume = false
    private(set) var canSetMute = false

    func start() {
        guard registrations.isEmpty else { refresh(); return }
        addListener(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice)
        addListener(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultInputDevice)
        addListener(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
        refresh()
    }

    func stop() {
        for registration in registrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(registration.object, &address, queue, registration.listener)
        }
        registrations.removeAll()
        outputID = AudioDeviceID(kAudioObjectUnknown)
        inputID = AudioDeviceID(kAudioObjectUnknown)
        volumeAddress = nil
        muteAddress = nil
        outputs = []
        inputs = []
        publish(volume: nil, muted: false, canSet: false, canSetMute: false, outputs: [], selectedOutputUID: nil, inputs: [], selectedInputUID: nil)
    }

    func refreshStatus() {
        refresh()
    }

    func setVolume(_ value: Double) {
        guard canSetVolume, outputID != kAudioObjectUnknown, var address = volumeAddress else { return }
        var scalar = Float32(min(max(value, 0), 1))
        guard AudioObjectSetPropertyData(outputID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar) == noErr else { return }
        if scalar > 0 { setMuted(false) }
        refresh()
    }

    func setMuted(_ value: Bool) {
        guard outputID != kAudioObjectUnknown, var address = muteAddress, isSettable(outputID, address) else { return }
        var mute: UInt32 = value ? 1 : 0
        guard AudioObjectSetPropertyData(outputID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute) == noErr else { return }
        refresh()
    }

    func setDefaultOutput(uid: String) {
        guard let device = audioDevices().first(where: { deviceUID($0) == uid }),
              device != outputID else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard isSettable(system, address) else { return }
        var selectedDevice = device
        guard AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &selectedDevice) == noErr else { return }
        refresh()
    }

    func setDefaultInput(uid: String) {
        guard let device = audioDevices().first(where: { deviceUID($0) == uid }),
              device != inputID else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = propertyAddress(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard isSettable(system, address) else { return }
        var selectedDevice = device
        guard AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &selectedDevice) == noErr else { return }
        refresh()
    }

    private func refresh() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else {
            outputID = AudioDeviceID(kAudioObjectUnknown)
            publish(volume: nil, muted: false, canSet: false, canSetMute: false, outputs: availableOutputs(), selectedOutputUID: nil, inputs: availableInputs(), selectedInputUID: defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice).flatMap(deviceUID))
            return
        }

        if device != outputID {
            removeDeviceListeners()
            outputID = device
            volumeAddress = firstSettableVolumeAddress(device)
            muteAddress = propertyAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
            addListener(object: device, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
            addListener(object: device, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        }

        let volume = readVolume(device)
        let muted = readMute(device)
        outputs = availableOutputs()
        inputID = defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice) ?? AudioDeviceID(kAudioObjectUnknown)
        let inputs = availableInputs()
        publish(
            volume: volume,
            muted: muted,
            canSet: volumeAddress.map { isSettable(device, $0) } ?? false,
            canSetMute: muteAddress.map { isSettable(device, $0) } ?? false,
            outputs: outputs,
            selectedOutputUID: deviceUID(device),
            inputs: inputs,
            selectedInputUID: inputID == kAudioObjectUnknown ? nil : deviceUID(inputID)
        )
    }

    private func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = propertyAddress(selector, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private func audioDevices() -> [AudioDeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = propertyAddress(kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr,
              dataSize >= UInt32(MemoryLayout<AudioDeviceID>.size) else { return [] }
        var devices = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
        let result = devices.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, bytes.baseAddress!)
        }
        return result == noErr ? devices : []
    }

    private func availableOutputs() -> [DuoBarAudioOutput] {
        availableDevices(scope: kAudioDevicePropertyScopeOutput)
    }

    private func availableInputs() -> [DuoBarAudioOutput] {
        availableDevices(scope: kAudioDevicePropertyScopeInput)
    }

    private func availableDevices(scope: AudioObjectPropertyScope) -> [DuoBarAudioOutput] {
        var seen = Set<String>()
        return audioDevices().compactMap { device -> DuoBarAudioOutput? in
            var streamsAddress = propertyAddress(kAudioDevicePropertyStreams, scope: scope)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streamsAddress, 0, nil, &streamsSize) == noErr,
                  streamsSize >= UInt32(MemoryLayout<AudioStreamID>.size) else { return nil }
            var canBeDefaultAddress = propertyAddress(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: scope)
            var canBeDefault: UInt32 = 1
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &canBeDefaultAddress, 0, nil, &valueSize, &canBeDefault) == noErr,
               canBeDefault == 0 { return nil }
            guard let uid = deviceUID(device), seen.insert(uid).inserted,
                  let name = deviceString(device, selector: kAudioObjectPropertyName) else { return nil }
            var aliveAddress = propertyAddress(kAudioDevicePropertyDeviceIsAlive, scope: kAudioObjectPropertyScopeGlobal)
            var isAlive: UInt32 = 1
            valueSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &aliveAddress, 0, nil, &valueSize, &isAlive) == noErr,
               isAlive == 0 { return nil }
            return DuoBarAudioOutput(uid: uid, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func deviceUID(_ device: AudioDeviceID) -> String? {
        deviceString(device, selector: kAudioDevicePropertyDeviceUID)
    }

    private func deviceString(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = propertyAddress(selector, scope: kAudioObjectPropertyScopeGlobal)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String
    }

    private func readVolume(_ device: AudioDeviceID) -> Double? {
        for scope in [kAudioDevicePropertyScopeOutput, kAudioObjectPropertyScopeGlobal] {
            for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)] {
                var address = propertyAddress(kAudioDevicePropertyVolumeScalar, scope: scope, element: element)
                var value: Float32 = 0
                var size = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                    return min(max(Double(value), 0), 1)
                }
            }
        }
        return nil
    }

    private func readMute(_ device: AudioDeviceID) -> Bool {
        guard var address = muteAddress else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private func firstSettableVolumeAddress(_ device: AudioDeviceID) -> AudioObjectPropertyAddress? {
        for scope in [kAudioDevicePropertyScopeOutput, kAudioObjectPropertyScopeGlobal] {
            for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1)] {
                let address = propertyAddress(kAudioDevicePropertyVolumeScalar, scope: scope, element: element)
                if isSettable(device, address) { return address }
            }
        }
        return nil
    }

    private func propertyAddress(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    private func addListener(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        var address = propertyAddress(selector, scope: scope)
        let listener: Listener = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, listener) == noErr else { return }
        registrations.append(Registration(object: object, address: address, listener: listener))
    }

    private func removeDeviceListeners() {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let deviceRegistrations = registrations.filter { $0.object != systemObject }
        for registration in deviceRegistrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(registration.object, &address, queue, registration.listener)
        }
        registrations.removeAll { $0.object != systemObject }
    }

    private func publish(volume: Double?, muted: Bool, canSet: Bool, canSetMute: Bool, outputs: [DuoBarAudioOutput], selectedOutputUID: String?, inputs: [DuoBarAudioOutput], selectedInputUID: String?) {
        let state = DuoBarAudioState(volume: volume, muted: muted, canSetVolume: canSet, canSetMute: canSetMute, outputs: outputs, selectedOutputUID: selectedOutputUID, inputs: inputs, selectedInputUID: selectedInputUID)
        let oldState = DuoBarAudioState(volume: self.volume, muted: self.muted, canSetVolume: self.canSetVolume, canSetMute: self.canSetMute, outputs: self.outputs, selectedOutputUID: self.outputID == kAudioObjectUnknown ? nil : deviceUID(self.outputID), inputs: self.inputs, selectedInputUID: self.inputID == kAudioObjectUnknown ? nil : deviceUID(self.inputID))
        guard oldState.volume != state.volume || oldState.muted != state.muted || oldState.canSetVolume != state.canSetVolume || oldState.canSetMute != state.canSetMute || oldState.outputs != state.outputs || oldState.selectedOutputUID != state.selectedOutputUID || oldState.inputs != state.inputs || oldState.selectedInputUID != state.selectedInputUID else { return }
        self.volume = volume
        self.muted = muted
        self.canSetVolume = canSet
        self.canSetMute = canSetMute
        self.outputs = outputs
        self.inputs = inputs
        onChange?(state)
    }
}
