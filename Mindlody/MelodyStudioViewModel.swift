import Foundation
import AVFoundation
import SwiftUI
import Combine
import AudioToolbox

@MainActor
final class MelodyStudioViewModel: NSObject, ObservableObject {
    struct LocalRecording: Identifiable, Sendable {
        let id = UUID()
        let url: URL
        let createdAt: Date
        let duration: Double

        var fileName: String { url.lastPathComponent }
    }

    struct AISnapshot: Identifiable, Sendable {
        let id = UUID()
        let label: String
        let createdAt: Date
        let editableNotes: [EditableNote]
        let bpm: Double
        let quantizeUnit: QuantizeUnit
        let scalePreset: ScalePreset
        let tempo: Float
        let beautifyEnabled: Bool
        let styleReverbMix: Float
        let styleGlobalSemitoneShift: Int
        let styleSwingAmount: Double
        let aiEnabled: Bool
        let aiIntensity: Double
        let aiOptimizeRhythm: Bool
        let aiOptimizeTone: Bool
        let aiOptimizeSpace: Bool
        let aiHighPassHz: Float
        let aiPresenceGain: Float
        let aiDrive: Float
        let aiDelayMix: Float
    }

    struct RenderSegment: Sendable {
        let start: Double
        let end: Double
        let cents: Float
    }

    struct ExportRequest: Sendable {
        let sourceURL: URL
        let outputURL: URL
        let segments: [RenderSegment]
        let tempo: Float
        let beautifyEnabled: Bool
        let reverbMix: Float
        let bpm: Double
        let aiEnabled: Bool
        let aiToneEnabled: Bool
        let aiSpaceEnabled: Bool
        let aiHighPassHz: Float
        let aiPresenceGain: Float
        let aiDrive: Float
        let aiDelayMix: Float
        let aiSoloMode: AISoloMode
    }

    struct EditableNote: Identifiable, Sendable {
        let id = UUID()
        var startTime: Double
        var endTime: Double
        var detectedMidi: Double
        var semitoneOffset: Int = 0

        var duration: Double {
            max(0, endTime - startTime)
        }

        var outputMidi: Double {
            detectedMidi + Double(semitoneOffset)
        }
    }

    enum QuantizeUnit: String, CaseIterable, Identifiable {
        case quarter = "1/4"
        case eighth = "1/8"
        case sixteenth = "1/16"

        var id: String { rawValue }

        var denominator: Int {
            switch self {
            case .quarter: return 4
            case .eighth: return 8
            case .sixteenth: return 16
            }
        }
    }

    enum ScalePreset: String, CaseIterable, Identifiable {
        case chromatic = "半音阶"
        case major = "自然大调"
        case minor = "自然小调"
        case pentatonic = "五声音阶"

        var id: String { rawValue }

        var degrees: [Int] {
            switch self {
            case .chromatic: return Array(0...11)
            case .major: return [0, 2, 4, 5, 7, 9, 11]
            case .minor: return [0, 2, 3, 5, 7, 8, 10]
            case .pentatonic: return [0, 2, 4, 7, 9]
            }
        }
    }

    enum StylePreset: String, CaseIterable, Identifiable {
        case popFresh = "Pop清新"
        case lofiChill = "LoFi松弛"
        case edmPulse = "EDM能量"
        case rnbSoul = "R&B氛围"

        var id: String { rawValue }

        var bpmRange: ClosedRange<Double> {
            switch self {
            case .popFresh: return 96...116
            case .lofiChill: return 72...90
            case .edmPulse: return 124...136
            case .rnbSoul: return 82...102
            }
        }

        var quantizeUnit: QuantizeUnit {
            switch self {
            case .popFresh: return .eighth
            case .lofiChill: return .sixteenth
            case .edmPulse: return .sixteenth
            case .rnbSoul: return .eighth
            }
        }

        var scale: ScalePreset {
            switch self {
            case .popFresh: return .major
            case .lofiChill: return .minor
            case .edmPulse: return .minor
            case .rnbSoul: return .minor
            }
        }

        var tempoRate: Float {
            switch self {
            case .popFresh: return 1.0
            case .lofiChill: return 0.92
            case .edmPulse: return 1.08
            case .rnbSoul: return 0.98
            }
        }

        var reverbMix: Float {
            switch self {
            case .popFresh: return 14
            case .lofiChill: return 30
            case .edmPulse: return 24
            case .rnbSoul: return 20
            }
        }

        var globalSemitoneShift: Int {
            switch self {
            case .popFresh: return 0
            case .lofiChill: return -3
            case .edmPulse: return 5
            case .rnbSoul: return -2
            }
        }

        var swingAmount: Double {
            switch self {
            case .popFresh: return 0.08
            case .lofiChill: return 0.18
            case .edmPulse: return 0.04
            case .rnbSoul: return 0.14
            }
        }

        var notePattern: [Int] {
            switch self {
            case .popFresh: return [0, 0, 2, 0, -1, 0, 1, 0]
            case .lofiChill: return [-2, 0, -3, 0, -2, 0]
            case .edmPulse: return [0, 7, 12, 7, 0, 7]
            case .rnbSoul: return [0, -2, 0, 2, -1, 1]
            }
        }

        var beautifyEnabledByDefault: Bool {
            true
        }

        var chordProgression: String {
            switch self {
            case .popFresh: return "I - V - vi - IV"
            case .lofiChill: return "i - bVII - bVI - V"
            case .edmPulse: return "i - bVI - bIII - bVII"
            case .rnbSoul: return "ii - V - I - vi"
            }
        }

        var drumPattern: String {
            switch self {
            case .popFresh: return "四拍主鼓 + 反拍军鼓 + 闭镲八分"
            case .lofiChill: return "轻摇摆鼓点 + 软军鼓 + 颗粒噪声"
            case .edmPulse: return "四踩地板 + 开镲上扬 + clap层叠"
            case .rnbSoul: return "半拍律动 + 切分kick + 细腻打击乐"
            }
        }

        var toneChain: String {
            switch self {
            case .popFresh: return "Bright EQ -> Light Comp -> Short Reverb"
            case .lofiChill: return "Lowpass -> Tape Saturation -> Room Reverb"
            case .edmPulse: return "Exciter -> Comp -> Hall Reverb"
            case .rnbSoul: return "Warm EQ -> Slow Comp -> Plate Reverb"
            }
        }

        var previewAssetName: String {
            switch self {
            case .popFresh: return "PopCard"
            case .lofiChill: return "LoFiCard"
            case .edmPulse: return "EDMCard"
            case .rnbSoul: return "RnBCard"
            }
        }
    }

    enum AISoloMode: String, CaseIterable, Identifiable, Sendable {
        case off = "全量"
        case rhythm = "仅节奏"
        case tone = "仅音色"
        case space = "仅空间"

        var id: String { rawValue }
    }

    enum StudioError: LocalizedError {
        case permissionDenied
        case recorderUnavailable
        case noRecording

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "未获得麦克风权限，请在系统设置中开启。"
            case .recorderUnavailable:
                return "录音器初始化失败。"
            case .noRecording:
                return "请先录制一段旋律。"
            }
        }
    }

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var statusText = "准备就绪"

    @Published var recordingURL: URL?
    @Published var lastExportURL: URL?
    @Published var duration: Double = 0
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    @Published var tempo: Float = 1.0
    @Published var beautifyEnabled = true

    @Published var waveformSamples: [Float] = []
    @Published var pitchSamples: [Float] = []
    @Published var editableNotes: [EditableNote] = []

    @Published var bpm: Double = 100
    @Published var quantizeUnit: QuantizeUnit = .eighth
    @Published var scalePreset: ScalePreset = .major
    @Published var selectedStylePreset: StylePreset = .popFresh
    @Published var styleReverbMix: Float = 18
    @Published var styleGlobalSemitoneShift: Int = 0
    @Published var styleSwingAmount: Double = 0

    @Published var aiIntensity: Double = 0.6
    @Published var aiOptimizeRhythm = true
    @Published var aiOptimizeTone = true
    @Published var aiOptimizeSpace = true
    @Published var aiSoloMode: AISoloMode = .off
    @Published var aiEnabled = false
    @Published private(set) var aiHighPassHz: Float = 50
    @Published private(set) var aiPresenceGain: Float = 0
    @Published private(set) var aiDrive: Float = 0
    @Published private(set) var aiDelayMix: Float = 0
    @Published var aiSnapshots: [AISnapshot] = []
    @Published var isShowingOriginalAB = false
    @Published var aiSnapshotDraftName = ""
    @Published var pinnedAISnapshotID: UUID?

    @Published var metronomeEnabled = false
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var isExportPlaying = false
    @Published var isPianoGenerating = false
    @Published var pianoGenerateProgress: Double = 0
    @Published var isPianoPlaying = false
    @Published var lastPianoURL: URL?
    @Published var localRecordings: [LocalRecording] = []
    @Published var isLocalPreviewPlaying = false
    @Published var localPreviewURL: URL?

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var exportPlayer: AVAudioPlayer?
    private var pianoPlayer: AVAudioPlayer?
    private var localPreviewPlayer: AVAudioPlayer?
    private var originalABSnapshot: AISnapshot?
    private var latestAISnapshot: AISnapshot?

    private var metronomeTimer: DispatchSourceTimer?

    private let pitchWindowSize = 2048
    private let pitchHopSize = 512
    private var pitchFrameDuration: Double = 0

    override init() {
        super.init()
        refreshLocalRecordings()
    }

    deinit {
        metronomeTimer?.cancel()
    }

    func requestMicrophonePermission() async {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return
            case .denied:
                statusText = StudioError.permissionDenied.localizedDescription
            case .undetermined:
                let granted = await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { ok in
                        continuation.resume(returning: ok)
                    }
                }
                if !granted {
                    statusText = StudioError.permissionDenied.localizedDescription
                }
            @unknown default:
                statusText = StudioError.permissionDenied.localizedDescription
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                return
            case .denied:
                statusText = StudioError.permissionDenied.localizedDescription
            case .undetermined:
                let granted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { ok in
                        continuation.resume(returning: ok)
                    }
                }
                if !granted {
                    statusText = StudioError.permissionDenied.localizedDescription
                }
            @unknown default:
                statusText = StudioError.permissionDenied.localizedDescription
            }
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        do {
            try configureSessionForRecord()

            let filename = "melody-\(Int(Date().timeIntervalSince1970)).m4a"
            let url = Self.documentsDirectory.appendingPathComponent(filename)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw StudioError.recorderUnavailable
            }

            self.recorder = recorder
            self.recordingURL = url
            self.lastExportURL = nil
            self.duration = 0
            self.trimStart = 0
            self.trimEnd = 0
            self.waveformSamples = []
            self.pitchSamples = []
            self.editableNotes = []
            self.isRecording = true
            self.statusText = "正在录音..."

            meterTimer?.invalidate()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.recorder?.updateMeters()
                    let power = self.recorder?.averagePower(forChannel: 0) ?? -60
                    let normalized = self.normalizedPowerLevel(from: power)
                    self.waveformSamples.append(normalized)
                    if self.waveformSamples.count > 500 {
                        self.waveformSamples.removeFirst(self.waveformSamples.count - 500)
                    }
                    self.duration = self.recorder?.currentTime ?? 0
                    self.trimEnd = self.duration
                }
            }
        } catch {
            statusText = error.localizedDescription
        }
    }

    func stopRecording() {
        guard let url = recordingURL else {
            statusText = StudioError.noRecording.localizedDescription
            return
        }
        recorder?.stop()
        recorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        isRecording = false
        duration = max(duration, 0)
        trimEnd = duration
        statusText = "录音完成，正在分析音高..."
        isAnalyzing = true
        analysisProgress = 0

        Task {
            do {
                let result = try await OfflinePitchAnalyzer.analyze(
                    url: url,
                    pitchWindowSize: pitchWindowSize,
                    pitchHopSize: pitchHopSize
                ) { progress in
                    Task { @MainActor in
                        self.analysisProgress = progress
                    }
                }

                duration = result.duration
                trimStart = 0
                trimEnd = result.duration
                pitchFrameDuration = result.pitchFrameDuration
                waveformSamples = result.waveformSamples
                pitchSamples = result.pitchSamples
                editableNotes = result.notes
                analysisProgress = 1
                statusText = "可预览与编辑"
                refreshLocalRecordings()
            } catch {
                statusText = "分析失败: \(error.localizedDescription)"
            }
            isAnalyzing = false
        }
    }

    func playOrStopPreview() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlaybackPreview()
        }
    }

    func startPlaybackPreview() {
        guard let url = recordingURL else {
            statusText = StudioError.noRecording.localizedDescription
            return
        }

        do {
            try configureSessionForPlayback()
            let audioFile = try AVAudioFile(forReading: url)
            let startTime = max(0, min(trimStart, duration))
            let endTime = max(startTime, min(trimEnd, duration))
            let rangeDuration = max(0.05, endTime - startTime)

            let sampleRate = audioFile.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition(startTime * sampleRate)
            let frameCount = AVAudioFrameCount(rangeDuration * sampleRate)

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let timePitch = AVAudioUnitTimePitch()
            timePitch.rate = max(0.5, min(2.0, tempo))
            timePitch.pitch = effectiveAveragePitchShiftCents()

            let soloRhythm = aiEnabled && aiSoloMode == .rhythm
            let soloTone = aiEnabled && aiSoloMode == .tone
            let soloSpace = aiEnabled && aiSoloMode == .space
            let toneActive = (aiEnabled && aiOptimizeTone && (aiSoloMode == .off || soloTone))
            let spaceActive = (aiEnabled && aiOptimizeSpace && (aiSoloMode == .off || soloSpace))

            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.mediumHall)
            reverb.wetDryMix = (beautifyEnabled && (spaceActive || (!aiEnabled && !soloRhythm))) ? styleReverbMix : 0

            let eq = AVAudioUnitEQ(numberOfBands: 2)
            let hp = eq.bands[0]
            hp.filterType = .highPass
            hp.frequency = toneActive ? aiHighPassHz : 40
            hp.bypass = !toneActive
            hp.bandwidth = 0.5
            hp.gain = 0

            let presence = eq.bands[1]
            presence.filterType = .parametric
            presence.frequency = 3600
            presence.bandwidth = 0.8
            presence.gain = toneActive ? aiPresenceGain : 0
            presence.bypass = !toneActive

            let distortion = AVAudioUnitDistortion()
            distortion.loadFactoryPreset(.speechWaves)
            distortion.wetDryMix = toneActive ? aiDrive : 0

            let delay = AVAudioUnitDelay()
            delay.delayTime = 60.0 / max(40, min(240, bpm)) * 0.375
            delay.feedback = 18
            delay.wetDryMix = spaceActive ? aiDelayMix : 0

            engine.attach(player)
            engine.attach(timePitch)
            engine.attach(eq)
            engine.attach(distortion)
            engine.attach(delay)
            engine.attach(reverb)

            let format = audioFile.processingFormat
            engine.connect(player, to: timePitch, format: format)
            engine.connect(timePitch, to: eq, format: format)
            engine.connect(eq, to: distortion, format: format)
            engine.connect(distortion, to: delay, format: format)
            engine.connect(delay, to: reverb, format: format)
            engine.connect(reverb, to: engine.mainMixerNode, format: format)

            player.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    self?.isPlaying = false
                    self?.statusText = "预览完成"
                }
            }

            try engine.start()
            player.play()
            self.engine = engine
            self.playerNode = player
            self.isPlaying = true
            self.statusText = "正在预览..."
        } catch {
            statusText = "预览失败: \(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        playerNode?.stop()
        engine?.stop()
        engine = nil
        playerNode = nil
        isPlaying = false
    }

    func toggleMetronome() {
        metronomeEnabled.toggle()
        if metronomeEnabled {
            startMetronome()
        } else {
            stopMetronome()
        }
    }

    func quantizeNotes() {
        guard !editableNotes.isEmpty else {
            statusText = "暂无可量化的音符"
            return
        }

        let beat = 60.0 / max(40, min(240, bpm))
        let grid = beat * (4.0 / Double(quantizeUnit.denominator))
        let minLength = grid * 0.5

        var result: [EditableNote] = []
        result.reserveCapacity(editableNotes.count)

        for note in editableNotes.sorted(by: { $0.startTime < $1.startTime }) {
            let snappedStart = max(0, (note.startTime / grid).rounded() * grid)
            var snappedEnd = max(snappedStart + minLength, (note.endTime / grid).rounded() * grid)
            snappedEnd = min(snappedEnd, duration)

            let snappedMidi = snapMidiToScale(note.outputMidi, scale: scalePreset)
            var newNote = note
            newNote.startTime = snappedStart
            newNote.endTime = snappedEnd
            newNote.semitoneOffset = Int((snappedMidi - note.detectedMidi).rounded())

            if let last = result.last, newNote.startTime < last.endTime {
                newNote.startTime = last.endTime
                newNote.endTime = max(newNote.endTime, newNote.startTime + minLength)
            }

            if newNote.endTime <= duration {
                result.append(newNote)
            }
        }

        editableNotes = result
        statusText = "量化完成（节拍 + 音高）"
    }

    func clearNoteOffsets() {
        editableNotes = editableNotes.map {
            var n = $0
            n.semitoneOffset = 0
            return n
        }
        styleGlobalSemitoneShift = 0
        styleSwingAmount = 0
        styleReverbMix = 18
    }

    func noteDisplayName(_ note: EditableNote) -> String {
        let targetMidi = note.outputMidi
        return midiToNoteName(targetMidi)
    }

    func applySelectedStylePreset() {
        let style = selectedStylePreset

        bpm = ((style.bpmRange.lowerBound + style.bpmRange.upperBound) * 0.5).rounded()
        quantizeUnit = style.quantizeUnit
        scalePreset = style.scale
        tempo = style.tempoRate
        beautifyEnabled = style.beautifyEnabledByDefault
        styleReverbMix = style.reverbMix
        styleGlobalSemitoneShift = style.globalSemitoneShift
        styleSwingAmount = style.swingAmount

        if !editableNotes.isEmpty {
            quantizeNotes()
            applyPatternOffsets(style.notePattern)
            applySwing()
        }

        statusText = "模板已套用：\(style.rawValue) | 风格变换已生效"
    }

    func applyAIOptimization() {
        if originalABSnapshot == nil {
            originalABSnapshot = makeAISnapshot(label: "原始版本")
        }

        let intensity = min(max(aiIntensity, 0), 1)
        aiEnabled = true

        if aiOptimizeRhythm, !editableNotes.isEmpty {
            quantizeNotes()
            let previousSwing = styleSwingAmount
            styleSwingAmount = min(0.28, max(previousSwing, 0.04 + intensity * 0.22))
            applySwing()
            if intensity > 0.55 {
                let pattern = selectedStylePreset.notePattern
                applyPatternOffsets(pattern)
            }
        }

        if aiOptimizeTone {
            aiHighPassHz = Float(45 + intensity * 110)
            aiPresenceGain = Float(1.5 + intensity * 5.5)
            aiDrive = Float(intensity * 26)
        } else {
            aiHighPassHz = 40
            aiPresenceGain = 0
            aiDrive = 0
        }

        if aiOptimizeSpace {
            styleReverbMix = min(45, max(styleReverbMix, Float(12 + intensity * 28)))
            aiDelayMix = Float(4 + intensity * 18)
        } else {
            aiDelayMix = 0
        }

        let snapshot = makeAISnapshot(label: "AI优化 \(Self.snapshotTimeFormatter.string(from: Date()))")
        latestAISnapshot = snapshot
        aiSnapshots.insert(snapshot, at: 0)
        if aiSnapshots.count > 20 {
            aiSnapshots.removeLast(aiSnapshots.count - 20)
        }
        isShowingOriginalAB = false

        statusText = "AI优化已应用：节奏\(aiOptimizeRhythm ? "✓" : "×") 音色\(aiOptimizeTone ? "✓" : "×") 空间\(aiOptimizeSpace ? "✓" : "×")"
    }

    func saveCurrentAISnapshot() {
        let raw = aiSnapshotDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = raw.isEmpty ? "手动快照 \(Self.snapshotTimeFormatter.string(from: Date()))" : raw
        let snapshot = makeAISnapshot(label: label)
        aiSnapshots.insert(snapshot, at: 0)
        if aiSnapshots.count > 20 {
            aiSnapshots.removeLast(aiSnapshots.count - 20)
        }
        aiSnapshotDraftName = ""
        statusText = "已保存快照：\(label)"
    }

    func toggleABCompare() {
        guard let original = originalABSnapshot, let latest = latestAISnapshot else {
            statusText = "请先执行一次AI优化再进行A/B对比"
            return
        }

        if isShowingOriginalAB {
            apply(snapshot: latest)
            isShowingOriginalAB = false
            statusText = "A/B对比：当前为AI版"
        } else {
            apply(snapshot: original)
            isShowingOriginalAB = true
            statusText = "A/B对比：当前为原始版"
        }
    }

    func applyAISnapshot(_ snapshot: AISnapshot) {
        apply(snapshot: snapshot)
        latestAISnapshot = snapshot
        isShowingOriginalAB = false
        statusText = "已应用快照：\(snapshot.label)"
    }

    func clearAISnapshots() {
        aiSnapshots = []
        originalABSnapshot = nil
        latestAISnapshot = nil
        isShowingOriginalAB = false
        pinnedAISnapshotID = nil
        statusText = "已清空AI快照"
    }

    func togglePinAISnapshot(_ snapshot: AISnapshot) {
        if pinnedAISnapshotID == snapshot.id {
            pinnedAISnapshotID = nil
            statusText = "已取消固定导出版"
        } else {
            pinnedAISnapshotID = snapshot.id
            statusText = "已固定导出版：\(snapshot.label)"
        }
    }

    var selectedStyleSummary: String {
        let style = selectedStylePreset
        let bpmText = "\(Int(style.bpmRange.lowerBound))-\(Int(style.bpmRange.upperBound)) BPM"
        return "速度 \(bpmText) | 网格 \(style.quantizeUnit.rawValue) | 音阶 \(style.scale.rawValue) | 摆动 \(Int(style.swingAmount * 100))%"
    }

    func exportEditedAudio() {
        guard let sourceURL = recordingURL else {
            statusText = StudioError.noRecording.localizedDescription
            return
        }

        if let pinnedID = pinnedAISnapshotID, let pinned = aiSnapshots.first(where: { $0.id == pinnedID }) {
            apply(snapshot: pinned)
            statusText = "使用固定快照导出：\(pinned.label)"
        }

        stopPlayback()
        stopExportPlayback()
        isExporting = true
        exportProgress = 0
        statusText = "正在导出..."

        let outputURL = Self.documentsDirectory.appendingPathComponent("mix-\(Int(Date().timeIntervalSince1970)).caf")
        let segments = makeRenderSegments().map { RenderSegment(start: $0.start, end: $0.end, cents: $0.cents) }
        let request = ExportRequest(
            sourceURL: sourceURL,
            outputURL: outputURL,
            segments: segments,
            tempo: tempo,
            beautifyEnabled: beautifyEnabled,
            reverbMix: styleReverbMix,
            bpm: bpm,
            aiEnabled: aiEnabled,
            aiToneEnabled: aiOptimizeTone,
            aiSpaceEnabled: aiOptimizeSpace,
            aiHighPassHz: aiHighPassHz,
            aiPresenceGain: aiPresenceGain,
            aiDrive: aiDrive,
            aiDelayMix: aiDelayMix,
            aiSoloMode: aiSoloMode
        )

        Task {
            do {
                let outputURL = try await OfflineAudioRenderer.render(request: request) { value in
                    Task { @MainActor in
                        self.exportProgress = value
                    }
                }
                lastExportURL = outputURL
                statusText = "导出成功: \(outputURL.lastPathComponent)"
                exportProgress = 1
                refreshLocalRecordings()
            } catch {
                statusText = "导出失败: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    func toggleExportPlayback() {
        if isExportPlaying {
            stopExportPlayback()
        } else {
            startExportPlayback()
        }
    }

    func generatePianoFromHumming() {
        guard recordingURL != nil, !editableNotes.isEmpty else {
            statusText = "请先录音并完成音符分析"
            return
        }

        stopPlayback()
        stopExportPlayback()
        stopLocalPreviewPlayback()
        stopPianoPlayback()

        isPianoGenerating = true
        pianoGenerateProgress = 0
        statusText = "正在生成钢琴曲..."

        let durationRangeStart = max(0, min(trimStart, duration))
        let durationRangeEnd = max(durationRangeStart, min(trimEnd, duration))
        let renderDuration = max(0.2, durationRangeEnd - durationRangeStart)
        let notes = editableNotes
            .filter { $0.endTime > durationRangeStart && $0.startTime < durationRangeEnd }
            .map { note in
                var clipped = note
                clipped.startTime = max(durationRangeStart, note.startTime) - durationRangeStart
                clipped.endTime = min(durationRangeEnd, note.endTime) - durationRangeStart
                if clipped.endTime <= clipped.startTime {
                    clipped.endTime = clipped.startTime + 0.06
                }
                return clipped
            }
            .sorted(by: { $0.startTime < $1.startTime })
        guard !notes.isEmpty else {
            statusText = "当前裁剪区间没有可用音符"
            return
        }

        let outputURL = Self.documentsDirectory.appendingPathComponent("piano-\(Int(Date().timeIntervalSince1970)).caf")

        let request = PianoRenderer.Request(
            notes: notes,
            duration: renderDuration,
            bpm: bpm,
            scale: scalePreset,
            style: selectedStylePreset,
            globalShift: styleGlobalSemitoneShift,
            outputURL: outputURL
        )

        Task {
            do {
                let url = try await PianoRenderer.render(request: request) { value in
                    Task { @MainActor in
                        self.pianoGenerateProgress = value
                    }
                }
                lastPianoURL = url
                pianoGenerateProgress = 1
                refreshLocalRecordings()
                statusText = "钢琴曲已生成：\(url.lastPathComponent)"
            } catch {
                statusText = "钢琴生成失败: \(error.localizedDescription)"
            }
            isPianoGenerating = false
        }
    }

    func togglePianoPlayback() {
        if isPianoPlaying {
            stopPianoPlayback()
        } else {
            startPianoPlayback()
        }
    }

    private func startExportPlayback() {
        guard let url = lastExportURL else {
            statusText = "请先导出音频"
            return
        }
        do {
            try configureSessionForPlayback()
            stopPlayback()
            stopExportPlayback()
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            exportPlayer = player
            isExportPlaying = true
            statusText = "正在播放导出音频..."
        } catch {
            statusText = "导出音频播放失败: \(error.localizedDescription)"
        }
    }

    private func startPianoPlayback() {
        guard let url = lastPianoURL else {
            statusText = "请先生成钢琴曲"
            return
        }
        do {
            try configureSessionForPlayback()
            stopPlayback()
            stopExportPlayback()
            stopLocalPreviewPlayback()
            stopPianoPlayback()
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            pianoPlayer = player
            isPianoPlaying = true
            statusText = "正在播放钢琴曲..."
        } catch {
            statusText = "钢琴曲播放失败: \(error.localizedDescription)"
        }
    }

    private func stopExportPlayback() {
        exportPlayer?.stop()
        exportPlayer = nil
        isExportPlaying = false
    }

    private func stopPianoPlayback() {
        pianoPlayer?.stop()
        pianoPlayer = nil
        isPianoPlaying = false
    }

    func notifyExportPlaybackFinished() {
        isExportPlaying = false
        exportPlayer = nil
        if !isPlaying {
            statusText = "播放完成"
        }
    }

    func handleExportPlaybackDecodeError() {
        isExportPlaying = false
        exportPlayer = nil
        if !isPlaying {
            statusText = "导出音频解码失败"
        }
    }

    func cleanupAudioOnDisappear() {
        if metronomeEnabled {
            toggleMetronome()
        }
        stopPlayback()
        stopExportPlayback()
        stopLocalPreviewPlayback()
        stopPianoPlayback()
    }

    func refreshLocalRecordings() {
        let dir = Self.documentsDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let recordings: [LocalRecording] = urls
            .filter { $0.pathExtension.lowercased() == "m4a" && $0.lastPathComponent.hasPrefix("melody-") }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey])
                let createdAt = values?.creationDate ?? Date.distantPast
                let duration = Self.recordingDuration(url: url)
                return LocalRecording(url: url, createdAt: createdAt, duration: duration)
            }
            .sorted { $0.createdAt > $1.createdAt }

        localRecordings = recordings
    }

    func loadLocalRecording(_ recording: LocalRecording) {
        stopPlayback()
        stopExportPlayback()
        stopLocalPreviewPlayback()
        recordingURL = recording.url
        lastExportURL = nil
        duration = recording.duration
        trimStart = 0
        trimEnd = max(recording.duration, 0.01)
        statusText = "已加载本地录音，正在分析..."
        isAnalyzing = true
        analysisProgress = 0

        Task {
            do {
                let result = try await OfflinePitchAnalyzer.analyze(
                    url: recording.url,
                    pitchWindowSize: pitchWindowSize,
                    pitchHopSize: pitchHopSize
                ) { progress in
                    Task { @MainActor in
                        self.analysisProgress = progress
                    }
                }

                duration = result.duration
                trimStart = 0
                trimEnd = result.duration
                pitchFrameDuration = result.pitchFrameDuration
                waveformSamples = result.waveformSamples
                pitchSamples = result.pitchSamples
                editableNotes = result.notes
                analysisProgress = 1
                statusText = "已加载并分析：\(recording.fileName)"
            } catch {
                statusText = "加载失败: \(error.localizedDescription)"
            }
            isAnalyzing = false
        }
    }

    func deleteLocalRecording(_ recording: LocalRecording) {
        do {
            if localPreviewURL == recording.url {
                stopLocalPreviewPlayback()
            }
            if recordingURL == recording.url {
                stopPlayback()
                recordingURL = nil
                waveformSamples = []
                pitchSamples = []
                editableNotes = []
                duration = 0
                trimStart = 0
                trimEnd = 0
            }
            try FileManager.default.removeItem(at: recording.url)
            refreshLocalRecordings()
            statusText = "已删除：\(recording.fileName)"
        } catch {
            statusText = "删除失败: \(error.localizedDescription)"
        }
    }

    func toggleLocalPreview(for recording: LocalRecording) {
        if isLocalPreviewPlaying, localPreviewURL == recording.url {
            stopLocalPreviewPlayback()
            return
        }
        do {
            try configureSessionForPlayback()
            stopPlayback()
            stopExportPlayback()
            stopLocalPreviewPlayback()
            let p = try AVAudioPlayer(contentsOf: recording.url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            localPreviewPlayer = p
            localPreviewURL = recording.url
            isLocalPreviewPlaying = true
            statusText = "正在预听：\(recording.fileName)"
        } catch {
            statusText = "预听失败: \(error.localizedDescription)"
        }
    }

    private func stopLocalPreviewPlayback() {
        localPreviewPlayer?.stop()
        localPreviewPlayer = nil
        localPreviewURL = nil
        isLocalPreviewPlaying = false
    }

    private func startMetronome() {
        stopMetronome()
        let interval = 60.0 / max(40, min(240, bpm))
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, self.metronomeEnabled else { return }
            AudioServicesPlaySystemSound(1104)
        }
        metronomeTimer = timer
        timer.resume()
    }

    private func stopMetronome() {
        metronomeTimer?.cancel()
        metronomeTimer = nil
    }

    private func configureSessionForRecord() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        if #available(iOS 17.0, *) {
            guard AVAudioApplication.shared.recordPermission == .granted else {
                throw StudioError.permissionDenied
            }
        } else {
            guard session.recordPermission == .granted else {
                throw StudioError.permissionDenied
            }
        }
    }

    private func configureSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func analyzeCurrentRecording() async {
        guard let url = recordingURL else { return }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
            try audioFile.read(into: buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            if frames == 0 { return }

            let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))
            duration = Double(frames) / format.sampleRate
            trimStart = 0
            trimEnd = duration
            pitchFrameDuration = Double(pitchHopSize) / format.sampleRate

            waveformSamples = buildWaveform(samples: samples, targetPoints: 240)
            pitchSamples = buildPitchTrack(samples: samples, sampleRate: format.sampleRate)
            editableNotes = detectNotes(from: pitchSamples, frameDuration: pitchFrameDuration)
        } catch {
            statusText = "分析失败: \(error.localizedDescription)"
        }
    }

    private func buildWaveform(samples: [Float], targetPoints: Int) -> [Float] {
        guard !samples.isEmpty, targetPoints > 0 else { return [] }
        let chunkSize = max(1, samples.count / targetPoints)
        var result: [Float] = []
        result.reserveCapacity(targetPoints)

        var idx = 0
        while idx < samples.count {
            let end = min(samples.count, idx + chunkSize)
            let chunk = samples[idx..<end]
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            result.append(min(1, rms * 6.5))
            idx = end
        }
        return result
    }

    private func buildPitchTrack(samples: [Float], sampleRate: Double) -> [Float] {
        guard samples.count > pitchWindowSize else { return [] }

        let minHz: Float = 80
        let maxHz: Float = 1_000
        let minLag = Int(sampleRate / Double(maxHz))
        let maxLag = Int(sampleRate / Double(minHz))

        var track: [Float] = []
        var i = 0
        while i + pitchWindowSize < samples.count {
            let frame = Array(samples[i..<(i + pitchWindowSize)])
            let energy = frame.reduce(0) { $0 + abs($1) } / Float(pitchWindowSize)
            if energy < 0.01 {
                track.append(0)
                i += pitchHopSize
                continue
            }

            var bestLag = 0
            var bestCorr: Float = 0

            for lag in minLag...maxLag {
                var corr: Float = 0
                var xNorm: Float = 0
                var yNorm: Float = 0

                let count = pitchWindowSize - lag
                for n in 0..<count {
                    let x = frame[n]
                    let y = frame[n + lag]
                    corr += x * y
                    xNorm += x * x
                    yNorm += y * y
                }

                let denom = sqrt(xNorm * yNorm)
                let value = denom > 0 ? corr / denom : 0
                if value > bestCorr {
                    bestCorr = value
                    bestLag = lag
                }
            }

            if bestLag > 0, bestCorr > 0.25 {
                let hz = Float(sampleRate) / Float(bestLag)
                track.append(hz)
            } else {
                track.append(0)
            }

            i += pitchHopSize
        }

        return smooth(track: track)
    }

    private func detectNotes(from pitches: [Float], frameDuration: Double) -> [EditableNote] {
        guard !pitches.isEmpty, frameDuration > 0 else { return [] }

        var notes: [EditableNote] = []
        let minFrames = 3
        var i = 0

        while i < pitches.count {
            if pitches[i] <= 0 {
                i += 1
                continue
            }

            let start = i
            var bucket: [Double] = []
            while i < pitches.count, pitches[i] > 0 {
                let midi = 69 + 12 * log2(Double(pitches[i]) / 440)
                bucket.append(midi)
                i += 1
            }
            let end = i

            if end - start >= minFrames, !bucket.isEmpty {
                let sorted = bucket.sorted()
                let medianMidi = sorted[sorted.count / 2]
                let note = EditableNote(
                    startTime: Double(start) * frameDuration,
                    endTime: Double(end) * frameDuration,
                    detectedMidi: medianMidi
                )
                notes.append(note)
            }
        }

        return notes
    }

    private func smooth(track: [Float]) -> [Float] {
        guard track.count > 4 else { return track }
        var out = track
        for i in 2..<(track.count - 2) {
            let slice = track[(i - 2)...(i + 2)].filter { $0 > 0 }
            if slice.isEmpty {
                out[i] = 0
            } else {
                out[i] = slice.sorted()[slice.count / 2]
            }
        }
        return out
    }

    private func manualAverageCents() -> Float {
        let valid = editableNotes.filter { $0.duration > 0 }
        guard !valid.isEmpty else { return 0 }

        let weighted = valid.reduce(0.0) { partial, note in
            partial + Double(note.semitoneOffset * 100) * note.duration
        }
        let totalDuration = valid.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else { return 0 }
        return Float(weighted / totalDuration)
    }

    private func recommendedPitchShiftCents() -> Float {
        let valid = pitchSamples.filter { $0 > 0 }
        guard !valid.isEmpty else { return 0 }

        let medianHz = valid.sorted()[valid.count / 2]
        let midi = 69 + 12 * log2(medianHz / 440)
        let roundedMidi = round(midi)
        return Float((roundedMidi - midi) * 100)
    }

    private func effectiveAveragePitchShiftCents() -> Float {
        let base = beautifyEnabled ? recommendedPitchShiftCents() : 0
        return base + manualAverageCents() + Float(styleGlobalSemitoneShift * 100)
    }

    private func snapMidiToScale(_ midi: Double, scale: ScalePreset) -> Double {
        if scale == .chromatic {
            return midi.rounded()
        }

        var best = midi
        var bestDistance = Double.greatestFiniteMagnitude

        let octave = Int(floor(midi / 12.0))
        for o in (octave - 2)...(octave + 2) {
            for degree in scale.degrees {
                let candidate = Double(o * 12 + degree)
                let distance = abs(candidate - midi)
                if distance < bestDistance {
                    bestDistance = distance
                    best = candidate
                }
            }
        }

        return best
    }

    private func midiToNoteName(_ midi: Double) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let intMidi = Int(midi.rounded())
        let note = names[(intMidi % 12 + 12) % 12]
        let octave = (intMidi / 12) - 1
        return "\(note)\(octave)"
    }

    private func normalizedPowerLevel(from decibels: Float) -> Float {
        if decibels < -60 { return 0 }
        let minDb: Float = -60
        let normalized = (decibels - minDb) / abs(minDb)
        return min(1, max(0, normalized))
    }

    private func makeRenderSegments() -> [(start: Double, end: Double, cents: Float)] {
        let start = max(0, min(trimStart, duration))
        let end = max(start, min(trimEnd, duration))
        let baseCents = beautifyEnabled ? recommendedPitchShiftCents() : 0

        let notes = editableNotes
            .sorted(by: { $0.startTime < $1.startTime })
            .compactMap { note -> (Double, Double, Float)? in
                let s = max(start, note.startTime)
                let e = min(end, note.endTime)
                guard e > s else { return nil }
                let cents = baseCents + Float((note.semitoneOffset + styleGlobalSemitoneShift) * 100)
                return (s, e, cents)
            }

        if notes.isEmpty {
            return [(start, end, baseCents + Float(styleGlobalSemitoneShift * 100))]
        }

        var segments: [(start: Double, end: Double, cents: Float)] = []
        var cursor = start

        for note in notes {
            if note.0 > cursor {
                segments.append((cursor, note.0, baseCents))
            }
            segments.append((note.0, note.1, note.2))
            cursor = max(cursor, note.1)
        }

        if cursor < end {
            segments.append((cursor, end, baseCents))
        }

        return segments.filter { $0.end - $0.start > 0.01 }
    }

    private func applyPatternOffsets(_ pattern: [Int]) {
        guard !editableNotes.isEmpty, !pattern.isEmpty else { return }
        for idx in editableNotes.indices {
            let delta = pattern[idx % pattern.count]
            editableNotes[idx].semitoneOffset = max(-24, min(24, editableNotes[idx].semitoneOffset + delta))
        }
    }

    private func applySwing() {
        guard editableNotes.count > 1, styleSwingAmount > 0 else { return }

        let beat = 60.0 / max(40, min(240, bpm))
        let grid = beat * (4.0 / Double(quantizeUnit.denominator))
        let push = grid * styleSwingAmount
        var notes = editableNotes.sorted(by: { $0.startTime < $1.startTime })

        for idx in notes.indices where idx % 2 == 1 {
            notes[idx].startTime = min(duration, notes[idx].startTime + push)
            notes[idx].endTime = min(duration, notes[idx].endTime + push)
        }

        for idx in 1..<notes.count {
            if notes[idx].startTime < notes[idx - 1].endTime {
                let overlap = notes[idx - 1].endTime - notes[idx].startTime
                notes[idx].startTime += overlap
                notes[idx].endTime = max(notes[idx].startTime + 0.04, notes[idx].endTime + overlap)
                notes[idx].endTime = min(duration, notes[idx].endTime)
            }
        }

        editableNotes = notes
    }

    private func makeAISnapshot(label: String) -> AISnapshot {
        AISnapshot(
            label: label,
            createdAt: Date(),
            editableNotes: editableNotes,
            bpm: bpm,
            quantizeUnit: quantizeUnit,
            scalePreset: scalePreset,
            tempo: tempo,
            beautifyEnabled: beautifyEnabled,
            styleReverbMix: styleReverbMix,
            styleGlobalSemitoneShift: styleGlobalSemitoneShift,
            styleSwingAmount: styleSwingAmount,
            aiEnabled: aiEnabled,
            aiIntensity: aiIntensity,
            aiOptimizeRhythm: aiOptimizeRhythm,
            aiOptimizeTone: aiOptimizeTone,
            aiOptimizeSpace: aiOptimizeSpace,
            aiHighPassHz: aiHighPassHz,
            aiPresenceGain: aiPresenceGain,
            aiDrive: aiDrive,
            aiDelayMix: aiDelayMix
        )
    }

    private func apply(snapshot: AISnapshot) {
        editableNotes = snapshot.editableNotes
        bpm = snapshot.bpm
        quantizeUnit = snapshot.quantizeUnit
        scalePreset = snapshot.scalePreset
        tempo = snapshot.tempo
        beautifyEnabled = snapshot.beautifyEnabled
        styleReverbMix = snapshot.styleReverbMix
        styleGlobalSemitoneShift = snapshot.styleGlobalSemitoneShift
        styleSwingAmount = snapshot.styleSwingAmount
        aiEnabled = snapshot.aiEnabled
        aiIntensity = snapshot.aiIntensity
        aiOptimizeRhythm = snapshot.aiOptimizeRhythm
        aiOptimizeTone = snapshot.aiOptimizeTone
        aiOptimizeSpace = snapshot.aiOptimizeSpace
        aiHighPassHz = snapshot.aiHighPassHz
        aiPresenceGain = snapshot.aiPresenceGain
        aiDrive = snapshot.aiDrive
        aiDelayMix = snapshot.aiDelayMix
    }

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static let snapshotTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    private static func recordingDuration(url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sr = file.processingFormat.sampleRate
        guard sr > 0 else { return 0 }
        return Double(file.length) / sr
    }
}

extension MelodyStudioViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.pianoPlayer === player {
                self.isPianoPlaying = false
                self.pianoPlayer = nil
                if !self.isPlaying && !self.isExportPlaying && !self.isLocalPreviewPlaying {
                    self.statusText = "钢琴曲播放完成"
                }
            } else if self.localPreviewPlayer === player {
                self.isLocalPreviewPlaying = false
                self.localPreviewURL = nil
                self.localPreviewPlayer = nil
                if !self.isPlaying && !self.isExportPlaying && !self.isPianoPlaying {
                    self.statusText = "预听结束"
                }
            } else {
                self.notifyExportPlaybackFinished()
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in
            if self.pianoPlayer === player {
                self.isPianoPlaying = false
                self.pianoPlayer = nil
                if !self.isPlaying && !self.isExportPlaying && !self.isLocalPreviewPlaying {
                    self.statusText = "钢琴曲解码失败"
                }
            } else if self.localPreviewPlayer === player {
                self.isLocalPreviewPlaying = false
                self.localPreviewURL = nil
                self.localPreviewPlayer = nil
                if !self.isPlaying && !self.isExportPlaying && !self.isPianoPlaying {
                    self.statusText = "本地录音解码失败"
                }
            } else {
                self.handleExportPlaybackDecodeError()
            }
        }
    }
}

private enum PianoRenderer {
    struct Request: Sendable {
        let notes: [MelodyStudioViewModel.EditableNote]
        let duration: Double
        let bpm: Double
        let scale: MelodyStudioViewModel.ScalePreset
        let style: MelodyStudioViewModel.StylePreset
        let globalShift: Int
        let outputURL: URL
    }

    @MainActor
    static func render(
        request: Request,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let notes = request.notes.map { note in
            PianoNoteData(
                startTime: note.startTime,
                endTime: note.endTime,
                outputMidi: note.outputMidi
            )
        }
        let degreeSet = Set(request.scale.degrees)
        let progression = chordProgression(style: request.style, scale: request.scale)
        return try await Task.detached(priority: .userInitiated) {
            let sampleRate = 44_100.0
            let tail = 0.8
            let totalDuration = max(0.3, request.duration + tail)
            let frameCount = Int(totalDuration * sampleRate)
            if frameCount <= 0 {
                throw MelodyStudioViewModel.StudioError.noRecording
            }

            var pcm = [Float](repeating: 0, count: frameCount)
            progress(0.05)

            for (idx, note) in notes.enumerated() {
                let st = max(0, note.startTime)
                let dur = max(0.06, note.endTime - note.startTime)
                let midi = note.outputMidi + Double(request.globalShift)
                addPianoNote(buffer: &pcm, sampleRate: sampleRate, start: st, duration: dur, midi: midi, gain: 0.42)
                if idx % 3 == 0 {
                    progress(0.1 + 0.45 * Double(idx + 1) / Double(max(notes.count, 1)))
                }
            }

            let beatSec = 60.0 / max(40, min(240, request.bpm))
            let tonic = estimateTonicMidi(from: notes, degreeSet: degreeSet)
            let beatCount = Int(ceil(request.duration / beatSec))

            for beat in 0..<beatCount {
                let t = Double(beat) * beatSec
                let chordRoot = tonic + progression[beat % progression.count]
                let chord = [chordRoot, chordRoot + 7, chordRoot + 12]
                addPianoNote(buffer: &pcm, sampleRate: sampleRate, start: t, duration: beatSec * 0.92, midi: Double(chord[0] - 12), gain: 0.26)
                addPianoNote(buffer: &pcm, sampleRate: sampleRate, start: t, duration: beatSec * 0.82, midi: Double(chord[1]), gain: 0.17)
                addPianoNote(buffer: &pcm, sampleRate: sampleRate, start: t, duration: beatSec * 0.82, midi: Double(chord[2]), gain: 0.15)
                if beat % 2 == 0 {
                    progress(0.58 + 0.3 * Double(beat + 1) / Double(max(beatCount, 1)))
                }
            }

            softLimitAndNormalize(&pcm)
            progress(0.95)

            let url = request.outputURL
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            guard let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
                throw MelodyStudioViewModel.StudioError.recorderUnavailable
            }
            audioBuffer.frameLength = AVAudioFrameCount(frameCount)
            if let ch = audioBuffer.floatChannelData?[0] {
                for i in 0..<frameCount {
                    ch[i] = pcm[i]
                }
            }
            try file.write(from: audioBuffer)
            progress(1)
            return url
        }.value
    }

    private struct PianoNoteData: Sendable {
        let startTime: Double
        let endTime: Double
        let outputMidi: Double
    }

    nonisolated private static func addPianoNote(
        buffer: inout [Float],
        sampleRate: Double,
        start: Double,
        duration: Double,
        midi: Double,
        gain: Float
    ) {
        let startIndex = max(0, Int(start * sampleRate))
        let noteFrames = max(1, Int(duration * sampleRate))
        if startIndex >= buffer.count { return }

        let freq = 440.0 * pow(2.0, (midi - 69.0) / 12.0)
        let releaseSec = min(0.22, duration * 0.35)
        let attackSec = min(0.015, duration * 0.2)
        let decaySec = min(0.12, duration * 0.3)
        let sustainLevel: Float = 0.45

        let attack = max(1, Int(attackSec * sampleRate))
        let decay = max(1, Int(decaySec * sampleRate))
        let release = max(1, Int(releaseSec * sampleRate))
        let sustainStart = min(noteFrames, attack + decay)
        let releaseStart = max(sustainStart, noteFrames - release)

        for n in 0..<noteFrames {
            let idx = startIndex + n
            if idx >= buffer.count { break }

            let t = Double(n) / sampleRate
            var env: Float
            if n < attack {
                env = Float(Double(n) / Double(attack))
            } else if n < sustainStart {
                let k = Float(Double(n - attack) / Double(max(1, decay)))
                env = 1 - (1 - sustainLevel) * k
            } else if n < releaseStart {
                env = sustainLevel
            } else {
                let k = Float(Double(n - releaseStart) / Double(max(1, release)))
                env = max(0, sustainLevel * (1 - k))
            }

            let phase = 2.0 * Double.pi * freq * t
            let harmonic = sin(phase) + 0.46 * sin(2 * phase) + 0.19 * sin(3.01 * phase)
            let brightness = exp(-3.6 * t / max(0.05, duration))
            let sample = Float(harmonic) * env * gain * Float(brightness)
            buffer[idx] += sample
        }
    }

    nonisolated private static func softLimitAndNormalize(_ samples: inout [Float]) {
        guard !samples.isEmpty else { return }

        var peak: Float = 0
        for i in samples.indices {
            samples[i] = tanh(samples[i] * 1.25)
            peak = max(peak, abs(samples[i]))
        }
        guard peak > 0 else { return }
        let scale: Float = min(1, 0.95 / peak)
        if scale < 0.999 {
            for i in samples.indices {
                samples[i] *= scale
            }
        }
    }

    nonisolated private static func estimateTonicMidi(
        from notes: [PianoNoteData],
        degreeSet: Set<Int>
    ) -> Int {
        let values = notes.map { Int(round($0.outputMidi)) }
        guard !values.isEmpty else { return 60 }
        let median = values.sorted()[values.count / 2]
        let candidates = stride(from: 48, through: 72, by: 1)
        var best = 60
        var score = Int.max
        for c in candidates {
            let s = values.reduce(0) { partial, m in
                let deg = (m - c) % 12
                let normalized = (deg + 12) % 12
                return partial + (degreeSet.contains(normalized) ? 0 : 1)
            }
            if s < score || (s == score && abs(c - median) < abs(best - median)) {
                score = s
                best = c
            }
        }
        return best
    }

    nonisolated private static func chordProgression(
        style: MelodyStudioViewModel.StylePreset,
        scale: MelodyStudioViewModel.ScalePreset
    ) -> [Int] {
        switch style {
        case .popFresh:
            return [0, 7, 9, 5]
        case .lofiChill:
            return scale == .minor ? [0, 10, 8, 5] : [0, 9, 7, 5]
        case .edmPulse:
            return scale == .minor ? [0, 8, 3, 10] : [0, 5, 9, 7]
        case .rnbSoul:
            return scale == .minor ? [2, 7, 0, 9] : [2, 7, 0, 9]
        }
    }
}

private enum OfflinePitchAnalyzer {
    struct AnalysisResult: Sendable {
        let duration: Double
        let pitchFrameDuration: Double
        let waveformSamples: [Float]
        let pitchSamples: [Float]
        let notes: [MelodyStudioViewModel.EditableNote]
    }

    nonisolated static func analyze(
        url: URL,
        pitchWindowSize: Int,
        pitchHopSize: Int,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> AnalysisResult {
        try await Task.detached(priority: .userInitiated) {
            progress(0.05)

            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                throw MelodyStudioViewModel.StudioError.noRecording
            }
            try audioFile.read(into: buffer)

            guard let channelData = buffer.floatChannelData?[0] else {
                throw MelodyStudioViewModel.StudioError.noRecording
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else {
                throw MelodyStudioViewModel.StudioError.noRecording
            }

            let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))
            progress(0.2)

            let duration = Double(frames) / format.sampleRate
            let pitchFrameDuration = Double(pitchHopSize) / format.sampleRate

            let waveform = buildWaveform(samples: samples, targetPoints: 240)
            progress(0.45)

            let pitchTrack = buildPitchTrack(
                samples: samples,
                sampleRate: format.sampleRate,
                pitchWindowSize: pitchWindowSize,
                pitchHopSize: pitchHopSize
            )
            progress(0.8)

            let notes = detectNotes(from: pitchTrack, frameDuration: pitchFrameDuration)
            progress(1)

            return AnalysisResult(
                duration: duration,
                pitchFrameDuration: pitchFrameDuration,
                waveformSamples: waveform,
                pitchSamples: pitchTrack,
                notes: notes
            )
        }.value
    }

    nonisolated private static func buildWaveform(samples: [Float], targetPoints: Int) -> [Float] {
        guard !samples.isEmpty, targetPoints > 0 else { return [] }
        let chunkSize = max(1, samples.count / targetPoints)
        var result: [Float] = []
        result.reserveCapacity(targetPoints)

        var idx = 0
        while idx < samples.count {
            let end = min(samples.count, idx + chunkSize)
            let chunk = samples[idx..<end]
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            result.append(min(1, rms * 6.5))
            idx = end
        }
        return result
    }

    nonisolated private static func buildPitchTrack(
        samples: [Float],
        sampleRate: Double,
        pitchWindowSize: Int,
        pitchHopSize: Int
    ) -> [Float] {
        guard samples.count > pitchWindowSize else { return [] }

        let minHz: Float = 80
        let maxHz: Float = 1_000
        let minLag = Int(sampleRate / Double(maxHz))
        let maxLag = Int(sampleRate / Double(minHz))

        var track: [Float] = []
        var i = 0
        while i + pitchWindowSize < samples.count {
            let frame = Array(samples[i..<(i + pitchWindowSize)])
            let energy = frame.reduce(0) { $0 + abs($1) } / Float(pitchWindowSize)
            if energy < 0.01 {
                track.append(0)
                i += pitchHopSize
                continue
            }

            var bestLag = 0
            var bestCorr: Float = 0

            for lag in minLag...maxLag {
                var corr: Float = 0
                var xNorm: Float = 0
                var yNorm: Float = 0

                let count = pitchWindowSize - lag
                for n in 0..<count {
                    let x = frame[n]
                    let y = frame[n + lag]
                    corr += x * y
                    xNorm += x * x
                    yNorm += y * y
                }

                let denom = sqrt(xNorm * yNorm)
                let value = denom > 0 ? corr / denom : 0
                if value > bestCorr {
                    bestCorr = value
                    bestLag = lag
                }
            }

            if bestLag > 0, bestCorr > 0.25 {
                let hz = Float(sampleRate) / Float(bestLag)
                track.append(hz)
            } else {
                track.append(0)
            }

            i += pitchHopSize
        }

        return smooth(track: track)
    }

    nonisolated private static func smooth(track: [Float]) -> [Float] {
        guard track.count > 4 else { return track }
        var out = track
        for i in 2..<(track.count - 2) {
            let slice = track[(i - 2)...(i + 2)].filter { $0 > 0 }
            if slice.isEmpty {
                out[i] = 0
            } else {
                out[i] = slice.sorted()[slice.count / 2]
            }
        }
        return out
    }

    nonisolated private static func detectNotes(from pitches: [Float], frameDuration: Double) -> [MelodyStudioViewModel.EditableNote] {
        guard !pitches.isEmpty, frameDuration > 0 else { return [] }

        var notes: [MelodyStudioViewModel.EditableNote] = []
        let minFrames = 3
        var i = 0

        while i < pitches.count {
            if pitches[i] <= 0 {
                i += 1
                continue
            }

            let start = i
            var bucket: [Double] = []
            while i < pitches.count, pitches[i] > 0 {
                let midi = 69 + 12 * log2(Double(pitches[i]) / 440)
                bucket.append(midi)
                i += 1
            }
            let end = i

            if end - start >= minFrames, !bucket.isEmpty {
                let sorted = bucket.sorted()
                let medianMidi = sorted[sorted.count / 2]
                notes.append(
                    MelodyStudioViewModel.EditableNote(
                        startTime: Double(start) * frameDuration,
                        endTime: Double(end) * frameDuration,
                        detectedMidi: medianMidi
                    )
                )
            }
        }

        return notes
    }
}

private enum OfflineAudioRenderer {
    nonisolated static func render(
        request: MelodyStudioViewModel.ExportRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard !request.segments.isEmpty else {
                throw MelodyStudioViewModel.StudioError.noRecording
            }

            let sourceFile = try AVAudioFile(forReading: request.sourceURL)
            let outputFile = try AVAudioFile(forWriting: request.outputURL, settings: sourceFile.processingFormat.settings)

            for (idx, segment) in request.segments.enumerated() {
                try renderSegment(
                    sourceFile: sourceFile,
                    outputFile: outputFile,
                    startTime: segment.start,
                    endTime: segment.end,
                    pitchCents: segment.cents,
                    tempo: request.tempo,
                    beautifyEnabled: request.beautifyEnabled,
                    reverbMix: request.reverbMix,
                    bpm: request.bpm,
                    aiEnabled: request.aiEnabled,
                    aiToneEnabled: request.aiToneEnabled,
                    aiSpaceEnabled: request.aiSpaceEnabled,
                    aiHighPassHz: request.aiHighPassHz,
                    aiPresenceGain: request.aiPresenceGain,
                    aiDrive: request.aiDrive,
                    aiDelayMix: request.aiDelayMix,
                    aiSoloMode: request.aiSoloMode
                )
                progress(Double(idx + 1) / Double(request.segments.count))
            }

            return request.outputURL
        }.value
    }

    nonisolated private static func renderSegment(
        sourceFile: AVAudioFile,
        outputFile: AVAudioFile,
        startTime: Double,
        endTime: Double,
        pitchCents: Float,
        tempo: Float,
        beautifyEnabled: Bool,
        reverbMix: Float,
        bpm: Double,
        aiEnabled: Bool,
        aiToneEnabled: Bool,
        aiSpaceEnabled: Bool,
        aiHighPassHz: Float,
        aiPresenceGain: Float,
        aiDrive: Float,
        aiDelayMix: Float,
        aiSoloMode: MelodyStudioViewModel.AISoloMode
    ) throws {
        let sampleRate = sourceFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(startTime * sampleRate)
        let inputFrameCount = AVAudioFrameCount(max(0.01, endTime - startTime) * sampleRate)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = max(0.5, min(2.0, tempo))
        timePitch.pitch = pitchCents

        let toneActive = aiEnabled && aiToneEnabled && (aiSoloMode == .off || aiSoloMode == .tone)
        let spaceActive = aiEnabled && aiSpaceEnabled && (aiSoloMode == .off || aiSoloMode == .space)

        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = (beautifyEnabled && (spaceActive || !aiEnabled)) ? reverbMix : 0

        let eq = AVAudioUnitEQ(numberOfBands: 2)
        let hp = eq.bands[0]
        hp.filterType = .highPass
        hp.frequency = toneActive ? aiHighPassHz : 40
        hp.bandwidth = 0.5
        hp.gain = 0
        hp.bypass = !toneActive

        let presence = eq.bands[1]
        presence.filterType = .parametric
        presence.frequency = 3600
        presence.bandwidth = 0.8
        presence.gain = toneActive ? aiPresenceGain : 0
        presence.bypass = !toneActive

        let distortion = AVAudioUnitDistortion()
        distortion.loadFactoryPreset(.speechWaves)
        distortion.wetDryMix = toneActive ? aiDrive : 0

        let delay = AVAudioUnitDelay()
        delay.delayTime = 60.0 / max(40, min(240, bpm)) * 0.375
        delay.feedback = 18
        delay.wetDryMix = spaceActive ? aiDelayMix : 0

        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(eq)
        engine.attach(distortion)
        engine.attach(delay)
        engine.attach(reverb)

        let format = sourceFile.processingFormat
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: distortion, format: format)
        engine.connect(distortion, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        try engine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: 4096)

        if #available(iOS 17.0, *) {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await player.scheduleSegment(sourceFile, startingFrame: startFrame, frameCount: inputFrameCount, at: nil)
                semaphore.signal()
            }
            semaphore.wait()
        } else {
            player.scheduleSegment(sourceFile, startingFrame: startFrame, frameCount: inputFrameCount, at: nil, completionHandler: nil)
        }

        try engine.start()
        player.play()

        let expectedOutputFrames = AVAudioFrameCount(Double(inputFrameCount) / Double(timePitch.rate) + sampleRate * 0.02)
        var renderedFrames: AVAudioFramePosition = 0

        while renderedFrames < AVAudioFramePosition(expectedOutputFrames) {
            let frameCount = min(4096, AVAudioFrameCount(AVAudioFramePosition(expectedOutputFrames) - renderedFrames))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else { break }

            let status = try engine.renderOffline(frameCount, to: buffer)
            switch status {
            case .success:
                if buffer.frameLength > 0 {
                    try outputFile.write(from: buffer)
                    renderedFrames += AVAudioFramePosition(buffer.frameLength)
                } else {
                    renderedFrames = AVAudioFramePosition(expectedOutputFrames)
                }
            case .insufficientDataFromInputNode:
                renderedFrames = AVAudioFramePosition(expectedOutputFrames)
            case .cannotDoInCurrentContext:
                continue
            case .error:
                renderedFrames = AVAudioFramePosition(expectedOutputFrames)
            @unknown default:
                renderedFrames = AVAudioFramePosition(expectedOutputFrames)
            }
        }
        player.stop()
        engine.stop()
    }
}
