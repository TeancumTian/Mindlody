import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var studio = MelodyStudioViewModel()
    @State private var selectedNoteID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mindlody")
                            .font(.largeTitle.bold())
                        Text("录下旋律，做音符级微调，再导出和分享。")
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("本地录音") {
                        VStack(alignment: .leading, spacing: 10) {
                            if studio.localRecordings.isEmpty {
                                Text("还没有本地录音，点击“开始录音”创建第一条。")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            } else {
                                ForEach(studio.localRecordings.prefix(6)) { item in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.fileName)
                                                .font(.subheadline.weight(.medium))
                                                .lineLimit(1)
                                            Text("\(formatDate(item.createdAt)) · \(formatDuration(item.duration))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Button(studio.isLocalPreviewPlaying && studio.localPreviewURL == item.url ? "停止" : "预听") {
                                            studio.toggleLocalPreview(for: item)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("加载") {
                                            studio.loadLocalRecording(item)
                                        }
                                        .buttonStyle(.borderedProminent)

                                        Button(role: .destructive) {
                                            studio.deleteLocalRecording(item)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }

                    GroupBox("旋律可视化") {
                        VStack(spacing: 12) {
                            WaveformView(samples: studio.waveformSamples)
                                .frame(height: 110)
                            PitchTrackView(pitches: studio.pitchSamples)
                                .frame(height: 110)
                        }
                    }

                    GroupBox("编辑") {
                        VStack(alignment: .leading, spacing: 14) {
                            LabeledContent("起点", value: String(format: "%.2fs", studio.trimStart))
                            Slider(value: $studio.trimStart, in: 0...max(studio.duration, 0.01))
                                .disabled(studio.duration <= 0)

                            LabeledContent("终点", value: String(format: "%.2fs", studio.trimEnd))
                            Slider(value: $studio.trimEnd, in: studio.trimStart...max(studio.duration, studio.trimStart + 0.01))
                                .disabled(studio.duration <= 0)

                            LabeledContent("速度", value: String(format: "%.2fx", studio.tempo))
                            Slider(value: $studio.tempo, in: 0.7...1.5)

                            Toggle("一键美化（自动轻度校音 + 混响）", isOn: $studio.beautifyEnabled)
                        }
                    }

                    GroupBox("风格模板") {
                        VStack(alignment: .leading, spacing: 12) {
                            StyleCardPreview(style: studio.selectedStylePreset)
                                .frame(height: 140)

                            Picker("模板", selection: $studio.selectedStylePreset) {
                                ForEach(MelodyStudioViewModel.StylePreset.allCases) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .pickerStyle(.menu)

                            Text(studio.selectedStyleSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("和弦: \(studio.selectedStylePreset.chordProgression)")
                                .font(.caption)
                            Text("鼓型: \(studio.selectedStylePreset.drumPattern)")
                                .font(.caption)
                            Text("音色链: \(studio.selectedStylePreset.toneChain)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("套用模板参数") {
                                studio.applySelectedStylePreset()
                            }
                            .buttonStyle(.bordered)
                            .disabled(studio.isRecording || studio.isAnalyzing || studio.isExporting)
                        }
                    }

                    GroupBox("AI优化") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("优化强度", value: "\(Int(studio.aiIntensity * 100))%")
                            Slider(value: $studio.aiIntensity, in: 0...1)

                            Toggle("节奏优化（量化 + 摆动 + 句型）", isOn: $studio.aiOptimizeRhythm)
                            Toggle("音色优化（EQ + 饱和）", isOn: $studio.aiOptimizeTone)
                            Toggle("空间优化（延迟 + 混响）", isOn: $studio.aiOptimizeSpace)

                            Picker("Solo预览", selection: $studio.aiSoloMode) {
                                ForEach(MelodyStudioViewModel.AISoloMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            Button("AI一键优化音乐") {
                                studio.applyAIOptimization()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(studio.recordingURL == nil || studio.isRecording || studio.isAnalyzing || studio.isExporting)

                            if studio.aiEnabled {
                                Text("已应用: HPF \(Int(studio.aiHighPassHz))Hz · Presence \(studio.aiPresenceGain, specifier: "%.1f")dB · Drive \(Int(studio.aiDrive))% · Delay \(Int(studio.aiDelayMix))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                TextField("快照名称（可选）", text: $studio.aiSnapshotDraftName)
                                    .textFieldStyle(.roundedBorder)
                                Button("保存快照") {
                                    studio.saveCurrentAISnapshot()
                                }
                                .buttonStyle(.bordered)
                            }

                            HStack {
                                Button(studio.isShowingOriginalAB ? "切回AI版" : "A/B切到原始版") {
                                    studio.toggleABCompare()
                                }
                                .buttonStyle(.bordered)

                                Button("清空AI快照") {
                                    studio.clearAISnapshots()
                                }
                                .buttonStyle(.bordered)
                                .disabled(studio.aiSnapshots.isEmpty)
                            }

                            if !studio.aiSnapshots.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("AI快照历史")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    ForEach(studio.aiSnapshots.prefix(5)) { snap in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(studio.pinnedAISnapshotID == snap.id ? "📌 \(snap.label)" : snap.label)
                                                    .font(.caption)
                                                Text("\(formatDate(snap.createdAt)) · 强度 \(Int(snap.aiIntensity * 100))%")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button(studio.pinnedAISnapshotID == snap.id ? "取消固定" : "固定导出") {
                                                studio.togglePinAISnapshot(snap)
                                            }
                                            .buttonStyle(.bordered)
                                            Button("应用") {
                                                studio.applyAISnapshot(snap)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    GroupBox("音符级编辑") {
                        VStack(alignment: .leading, spacing: 12) {
                            if studio.editableNotes.isEmpty {
                                Text("先录一段有明显音高的旋律")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("在下方曲线中拖动音符点，上下调整音高")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                NoteCurveEditor(
                                    notes: $studio.editableNotes,
                                    duration: max(studio.duration, 0.01),
                                    selectedNoteID: $selectedNoteID
                                )
                                .frame(height: 180)

                                ForEach($studio.editableNotes) { $note in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(studio.noteDisplayName(note))
                                                .font(.headline)
                                            Spacer()
                                            Text(String(format: "%.2f-%.2fs", note.startTime, note.endTime))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Stepper(value: $note.semitoneOffset, in: -24...24) {
                                            Text("音高微调: \(note.semitoneOffset > 0 ? "+" : "")\(note.semitoneOffset) 半音")
                                        }
                                    }
                                    .padding(8)
                                    .background(
                                        (selectedNoteID == note.id ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.08))
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture {
                                        selectedNoteID = note.id
                                    }
                                }

                                Button("重置所有音符偏移") {
                                    studio.clearNoteOffsets()
                                    selectedNoteID = nil
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    GroupBox("节拍器与量化") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("BPM", value: String(Int(studio.bpm)))
                            Slider(value: $studio.bpm, in: 40...240, step: 1)
                                .onChange(of: studio.bpm) { _, _ in
                                    if studio.metronomeEnabled {
                                        studio.toggleMetronome()
                                        studio.toggleMetronome()
                                    }
                                }

                            Picker("量化网格", selection: $studio.quantizeUnit) {
                                ForEach(MelodyStudioViewModel.QuantizeUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)

                            Picker("音阶", selection: $studio.scalePreset) {
                                ForEach(MelodyStudioViewModel.ScalePreset.allCases) { scale in
                                    Text(scale.rawValue).tag(scale)
                                }
                            }

                            HStack {
                                Button(studio.metronomeEnabled ? "关闭节拍器" : "开启节拍器") {
                                    studio.toggleMetronome()
                                }
                                .buttonStyle(.bordered)

                                Button("量化音高与节拍") {
                                    studio.quantizeNotes()
                                }
                                .buttonStyle(.bordered)
                                .disabled(studio.editableNotes.isEmpty)
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        Button(studio.isRecording ? "停止录音" : "开始录音") {
                            studio.toggleRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(studio.isExporting || studio.isAnalyzing)

                        Button(studio.isPlaying ? "停止预览" : "预览编辑结果") {
                            studio.playOrStopPreview()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(studio.recordingURL == nil || studio.isExporting || studio.isAnalyzing)

                        Button("导出音乐") {
                            studio.exportEditedAudio()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(studio.recordingURL == nil || studio.isExporting || studio.isAnalyzing)

                        Button("按哼唱生成钢琴曲") {
                            studio.generatePianoFromHumming()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(studio.recordingURL == nil || studio.isExporting || studio.isAnalyzing || studio.isPianoGenerating)

                        if studio.isAnalyzing {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "waveform.path.ecg")
                                        .foregroundStyle(.orange)
                                        .symbolEffect(.pulse, options: .repeating, value: studio.isAnalyzing)
                                    Text("正在分析音高...")
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text("\(Int(studio.analysisProgress * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                ProgressView(value: studio.analysisProgress)
                                    .tint(.orange)
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        if studio.isExporting {
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressView(value: studio.exportProgress)
                                Text("导出进度 \(Int(studio.exportProgress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if studio.isPianoGenerating {
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressView(value: studio.pianoGenerateProgress)
                                Text("钢琴生成进度 \(Int(studio.pianoGenerateProgress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let url = studio.lastExportURL {
                            Button(studio.isExportPlaying ? "停止播放导出音频" : "播放导出音频") {
                                studio.toggleExportPlayback()
                            }
                            .buttonStyle(.bordered)

                            ShareLink(item: url) {
                                Label("分享导出文件", systemImage: "square.and.arrow.up")
                            }
                        }

                        if let pianoURL = studio.lastPianoURL {
                            Button(studio.isPianoPlaying ? "停止播放钢琴曲" : "播放钢琴曲") {
                                studio.togglePianoPlayback()
                            }
                            .buttonStyle(.bordered)

                            ShareLink(item: pianoURL) {
                                Label("分享钢琴曲", systemImage: "pianokeys.inverse")
                            }
                        }
                    }

                    Text(studio.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("旋律工作台")
        }
        .task {
            await studio.requestMicrophonePermission()
            studio.refreshLocalRecordings()
        }
        .onChange(of: studio.trimStart) { _, newValue in
            if studio.trimEnd < newValue {
                studio.trimEnd = newValue
            }
        }
        .onDisappear {
            studio.cleanupAudioOnDisappear()
        }
    }
}

private func formatDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "MM-dd HH:mm"
    return f.string(from: date)
}

private func formatDuration(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}

private struct StyleCardPreview: View {
    let style: MelodyStudioViewModel.StylePreset

    var body: some View {
        let name = style.previewAssetName
        ZStack(alignment: .bottomLeading) {
            if UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackGradient(style: style)
            }

            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(style.rawValue)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(style.toneChain)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func fallbackGradient(style: MelodyStudioViewModel.StylePreset) -> some View {
        switch style {
        case .popFresh:
            LinearGradient(colors: [.blue, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lofiChill:
            LinearGradient(colors: [.indigo, .brown], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .edmPulse:
            LinearGradient(colors: [.cyan, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .rnbSoul:
            LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct NoteCurveEditor: View {
    @Binding var notes: [MelodyStudioViewModel.EditableNote]
    let duration: Double
    @Binding var selectedNoteID: UUID?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.12))

                if notes.isEmpty {
                    Text("暂无音符")
                        .foregroundStyle(.secondary)
                } else {
                    Canvas { context, size in
                        let midiRange = midiBounds()
                        let minMidi = midiRange.min
                        let maxMidi = midiRange.max
                        let span = max(1.0, maxMidi - minMidi)

                        var line = Path()

                        for (idx, note) in notes.enumerated() {
                            let x = xPosition(for: note, width: size.width)
                            let y = yPosition(forMidi: note.outputMidi, minMidi: minMidi, span: span, height: size.height)
                            let point = CGPoint(x: x, y: y)

                            if idx == 0 {
                                line.move(to: point)
                            } else {
                                line.addLine(to: point)
                            }
                        }

                        context.stroke(line, with: .color(.green), lineWidth: 2)

                        for note in notes {
                            let x = xPosition(for: note, width: size.width)
                            let y = yPosition(forMidi: note.outputMidi, minMidi: minMidi, span: span, height: size.height)
                            let r: CGFloat = (selectedNoteID == note.id) ? 6 : 4
                            let circleRect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                            context.fill(Path(ellipseIn: circleRect), with: .color(selectedNoteID == note.id ? .orange : .green))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateNote(with: value.location, in: geo.size)
                            }
                    )
                }
            }
        }
    }

    private func xPosition(for note: MelodyStudioViewModel.EditableNote, width: CGFloat) -> CGFloat {
        let centerTime = (note.startTime + note.endTime) * 0.5
        let xRatio = CGFloat(centerTime / max(duration, 0.01))
        return min(width, max(0, xRatio * width))
    }

    private func yPosition(forMidi midi: Double, minMidi: Double, span: Double, height: CGFloat) -> CGFloat {
        let ratio = (midi - minMidi) / span
        return height - CGFloat(ratio) * height
    }

    private func midiBounds() -> (min: Double, max: Double) {
        let values = notes.map { $0.outputMidi } + notes.map { $0.detectedMidi }
        let minV = (values.min() ?? 48) - 2
        let maxV = (values.max() ?? 72) + 2
        return (minV, max(maxV, minV + 4))
    }

    private func updateNote(with location: CGPoint, in size: CGSize) {
        guard !notes.isEmpty else { return }

        let width = max(size.width, 1)
        let targetTime = Double(min(max(0, location.x), width) / width) * max(duration, 0.01)

        guard let idx = nearestIndex(for: targetTime) else { return }
        selectedNoteID = notes[idx].id

        let bounds = midiBounds()
        let clampedY = min(max(0, location.y), size.height)
        let yRatio = 1 - Double(clampedY / max(size.height, 1))
        let targetMidi = bounds.min + yRatio * (bounds.max - bounds.min)

        let detected = notes[idx].detectedMidi
        let offset = Int((targetMidi - detected).rounded())
        notes[idx].semitoneOffset = min(24, max(-24, offset))
    }

    private func nearestIndex(for targetTime: Double) -> Int? {
        guard !notes.isEmpty else { return nil }
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude

        for (idx, note) in notes.enumerated() {
            let center = (note.startTime + note.endTime) * 0.5
            let dist = abs(center - targetTime)
            if dist < bestDistance {
                bestDistance = dist
                bestIndex = idx
            }
        }

        return bestIndex
    }
}

private struct WaveformView: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { _ in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.12))

                if samples.isEmpty {
                    Text("等待录音")
                        .foregroundStyle(.secondary)
                } else {
                    Canvas { context, size in
                        let centerY = size.height / 2
                        let widthPerSample = size.width / CGFloat(max(samples.count, 1))

                        var path = Path()
                        for (idx, sample) in samples.enumerated() {
                            let x = CGFloat(idx) * widthPerSample
                            let h = CGFloat(sample) * (size.height * 0.45)
                            path.move(to: CGPoint(x: x, y: centerY - h))
                            path.addLine(to: CGPoint(x: x, y: centerY + h))
                        }

                        context.stroke(path, with: .color(.blue), lineWidth: 1)
                    }
                }
            }
        }
    }
}

private struct PitchTrackView: View {
    let pitches: [Float]

    var body: some View {
        GeometryReader { _ in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.12))

                if pitches.isEmpty {
                    Text("等待音高分析")
                        .foregroundStyle(.secondary)
                } else {
                    Canvas { context, size in
                        let validMidi = pitches.filter { $0 > 0 }.map { 69 + 12 * log2(Double($0) / 440) }
                        let minMidi = validMidi.min() ?? 40
                        let maxMidi = validMidi.max() ?? 80
                        let span = max(4, maxMidi - minMidi)

                        var path = Path()
                        var hasStarted = false

                        for (idx, hz) in pitches.enumerated() {
                            guard hz > 0 else {
                                hasStarted = false
                                continue
                            }

                            let midi = 69 + 12 * log2(Double(hz) / 440)
                            let x = CGFloat(idx) / CGFloat(max(pitches.count - 1, 1)) * size.width
                            let yRatio = (midi - minMidi) / span
                            let y = size.height - CGFloat(yRatio) * size.height
                            let point = CGPoint(x: x, y: y)

                            if hasStarted {
                                path.addLine(to: point)
                            } else {
                                path.move(to: point)
                                hasStarted = true
                            }
                        }

                        context.stroke(path, with: .color(.orange), lineWidth: 2)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
