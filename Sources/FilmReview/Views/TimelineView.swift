import SwiftUI
import AppKit

struct TimelineSection: View {
    @ObservedObject var model: AppModel
    @State private var zoom: CGFloat = 1
    @State private var visibleRange: ClosedRange<Double> = 0...1

    var body: some View {
        VStack(spacing: 7) {
            TimelineDetailView(model: model, zoom: $zoom, visibleRange: $visibleRange)
                .id(model.project?.videoPath ?? "no-project")
            OverviewTimelineView(model: model, visibleRange: visibleRange)
        }
        .padding(.horizontal, 15)
        .padding(.top, 3)
        .padding(.bottom, 10)
        .background(Theme.background)
    }
}

private struct TimelineOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Detail timeline

private struct TimelineDetailView: View {
    @ObservedObject var model: AppModel
    @Binding var zoom: CGFloat
    @Binding var visibleRange: ClosedRange<Double>

    @State private var hoverTime: Double?

    private var duration: Double { max(model.player.duration, 0.01) }

    var body: some View {
        GeometryReader { geo in
            let viewWidth = max(1, geo.size.width)
            let totalWidth = max(viewWidth, viewWidth * zoom)
            let pps = totalWidth / duration

            ScrollViewReader { proxy in
                VStack(spacing: 6) {
                    header(proxy: proxy)
                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            TimelineTrack(model: model,
                                          totalWidth: totalWidth,
                                          pixelsPerSecond: pps,
                                          visibleRange: visibleRange,
                                          hoverTime: $hoverTime)
                                .frame(width: totalWidth, height: 72)

                            Color.clear
                                .frame(width: 1, height: 1)
                                .position(x: min(max(model.player.currentSeconds * pps, 0), totalWidth),
                                          y: 36)
                                .id("playheadAnchor")
                        }
                        .frame(width: totalWidth, height: 72)
                        .background(
                            GeometryReader { inner in
                                Color.clear.preference(
                                    key: TimelineOffsetKey.self,
                                    value: inner.frame(in: .named("timelineScroll")).minX
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "timelineScroll")
                    .onPreferenceChange(TimelineOffsetKey.self) { minX in
                        let offset = max(0, -minX)
                        let start = min(duration, offset / pps)
                        let end = min(duration, (offset + viewWidth) / pps)
                        if end > start {
                            visibleRange = start...end
                            requestThumbnails(in: start...end, pps: pps)
                        }
                    }
                }
                .onAppear {
                    zoom = 1
                    hoverTime = nil
                    visibleRange = 0...duration
                    requestThumbnails(in: 0...duration, pps: pps)
                }
                .onChange(of: zoom) { _, newZoom in
                    let span = duration / max(1, newZoom)
                    let center = min(max(model.player.currentSeconds, 0), duration)
                    var start = center - span / 2
                    start = min(max(start, 0), max(0, duration - span))
                    visibleRange = start...min(duration, start + span)
                    requestThumbnails(in: visibleRange, pps: pps)
                }
                .onChange(of: model.player.currentSeconds) { _, seconds in
                    guard model.player.isPlaying, zoom > 1.001 else { return }
                    if seconds < visibleRange.lowerBound || seconds > visibleRange.upperBound {
                        proxy.scrollTo("playheadAnchor", anchor: .center)
                    }
                }
            }
        }
        .frame(height: 101)
    }

    private func header(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            SectionLabel(text: "精细时间线")
            Rectangle().fill(Theme.border).frame(width: 1, height: 10)

            if let hoverTime {
                Text(Timecode.string(seconds: hoverTime, fps: model.fps))
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
                Text("悬停")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Text("滚轮横向滚动 · 拖动播放头定位")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            Text(zoom <= 1.001 ? "全片" : String(format: "%.1f×", zoom))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 44, alignment: .trailing)

            IconButton(symbol: "minus.magnifyingglass", help: "缩小时间线", size: 10.5,
                       disabled: zoom <= 1.001) {
                zoom = max(1, zoom / 1.7)
                recenter(proxy: proxy)
            }
            IconButton(symbol: "plus.magnifyingglass", help: "放大时间线", size: 10.5,
                       disabled: zoom >= 64) {
                zoom = min(64, zoom * 1.7)
                recenter(proxy: proxy)
            }
            Button("适应全片") {
                zoom = 1
                recenter(proxy: proxy)
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .help("显示整条影片")
        }
        .frame(height: 20)
    }

    private func recenter(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo("playheadAnchor", anchor: .center)
        }
    }

    private func requestThumbnails(in range: ClosedRange<Double>, pps: CGFloat) {
        guard model.hasProject else { return }
        let step = Self.thumbnailStep(pps: pps, fps: model.fps)
        var times: [Double] = []
        var t = floor(range.lowerBound / step) * step
        let end = min(duration, range.upperBound + step * 2)
        var safety = 0
        while t <= end && safety < 120 {
            times.append(max(0, t))
            t += step
            safety += 1
        }
        model.thumbnails.request(times: times)
    }

    static func thumbnailStep(pps: CGFloat, fps: Double) -> Double {
        let frame = 1.0 / max(1, fps)
        var candidates: [Double] = []
        for multiplier in [1.0, 2, 5, 10, 15, 20] {
            candidates.append(frame * multiplier)
        }
        candidates.append(contentsOf: [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600])
        for candidate in candidates {
            if CGFloat(candidate) * pps >= 72 { return candidate }
        }
        return 600
    }
}

// MARK: - Track

private struct ThumbCell: Identifiable {
    let id: Int
    let time: Double
    let x: CGFloat
    let width: CGFloat
}

private struct TimelineTrack: View {
    @ObservedObject var model: AppModel
    let totalWidth: CGFloat
    let pixelsPerSecond: CGFloat
    let visibleRange: ClosedRange<Double>
    @Binding var hoverTime: Double?

    @State private var dragging = false
    @State private var startedOnMarker = false
    @State private var hoverX: CGFloat?

    private var duration: Double { max(model.player.duration, 0.01) }
    private var fps: Double { model.fps }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                drawBackground(context: context, size: size)
                drawRuler(context: context, size: size)
                drawComments(context: context, size: size)
                drawPlayhead(context: context, size: size)
            }

            // Thumbnails are rendered as views for aspect-fill cropping.
            ForEach(cells) { cell in
                thumbnailCell(cell)
            }

            if let hoverX {
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 1, height: 48)
                    .offset(x: hoverX, y: 18)
                    .allowsHitTesting(false)
            }

            gestureLayer
        }
        .background(Color(red: 0.045, green: 0.045, blue: 0.052))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var cells: [ThumbCell] {
        let step = TimelineDetailView.thumbnailStep(pps: pixelsPerSecond, fps: fps)
        let cellWidth = max(1, CGFloat(step) * pixelsPerSecond)
        let startIndex = Int(floor(max(0, visibleRange.lowerBound) / step))
        let endIndex = Int(ceil(min(duration, visibleRange.upperBound) / step))
        guard endIndex >= startIndex else { return [] }
        return (startIndex...min(endIndex, startIndex + 90)).map { index in
            let time = Double(index) * step
            return ThumbCell(id: index,
                             time: time,
                             x: CGFloat(time) * pixelsPerSecond,
                             width: cellWidth)
        }
    }

    private func thumbnailCell(_ cell: ThumbCell) -> some View {
        Group {
            if let image = model.thumbnails.image(for: cell.time) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color.white.opacity(0.035), Color.white.opacity(0.015)],
                                   startPoint: .top, endPoint: .bottom)
                    Image(systemName: "film")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.10))
                }
            }
        }
        .frame(width: max(1, cell.width - 1), height: 38)
        .clipped()
        .offset(x: cell.x, y: 19)
        .allowsHitTesting(false)
    }

    private var gestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverX = point.x
                    let t = Double(point.x / pixelsPerSecond)
                    hoverTime = min(max(t, 0), duration)
                case .ended:
                    hoverX = nil
                    hoverTime = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !dragging {
                            dragging = true
                            startedOnMarker = false
                            model.player.pause()
                            if let comment = comment(near: value.startLocation.x) {
                                startedOnMarker = true
                                model.selectComment(comment.id)
                                return
                            }
                        }
                        if startedOnMarker && abs(value.translation.width) <= 5 { return }
                        startedOnMarker = false
                        let time = Double(value.location.x / pixelsPerSecond)
                        model.player.seek(toSeconds: min(max(time, 0), duration), exact: true)
                    }
                    .onEnded { value in
                        if !startedOnMarker {
                            let time = Double(value.location.x / pixelsPerSecond)
                            model.player.seek(toSeconds: min(max(time, 0), duration), exact: true)
                        }
                        dragging = false
                        startedOnMarker = false
                    }
            )
            .help("拖动定位，点击意见标记跳转到对应画面")
    }

    private func comment(near x: CGFloat) -> ReviewComment? {
        let tolerance: CGFloat = 8
        return model.comments
            .map { ($0, abs(CGFloat($0.timeSeconds) * pixelsPerSecond - x)) }
            .filter { $0.1 <= tolerance }
            .min(by: { $0.1 < $1.1 })?.0
    }

    // MARK: Canvas drawing

    private func drawBackground(context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.045, green: 0.045, blue: 0.052)))
        context.fill(Path(CGRect(x: 0, y: 19, width: size.width, height: 38)),
                     with: .color(Color.black.opacity(0.35)))
    }

    private func drawRuler(context: GraphicsContext, size: CGSize) {
        let step = niceTickStep()
        var t = floor(max(0, visibleRange.lowerBound) / step) * step
        let end = min(duration, visibleRange.upperBound + step)
        var count = 0
        while t <= end && count < 80 {
            let x = CGFloat(t) * pixelsPerSecond
            var path = Path()
            path.move(to: CGPoint(x: x, y: 13))
            path.addLine(to: CGPoint(x: x, y: 19))
            context.stroke(path, with: .color(Color.white.opacity(0.18)), lineWidth: 1)
            context.draw(
                Text(tickLabel(t, step: step))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.45)),
                at: CGPoint(x: x + 3, y: 3),
                anchor: .topLeading
            )
            // Minor ticks
            if CGFloat(step) * pixelsPerSecond > 70 {
                for i in 1..<4 {
                    let mx = x + CGFloat(step) * pixelsPerSecond * CGFloat(i) / 4
                    var minor = Path()
                    minor.move(to: CGPoint(x: mx, y: 16))
                    minor.addLine(to: CGPoint(x: mx, y: 19))
                    context.stroke(minor, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
                }
            }
            t += step
            count += 1
        }
        var line = Path()
        line.move(to: CGPoint(x: 0, y: 19))
        line.addLine(to: CGPoint(x: size.width, y: 19))
        context.stroke(line, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
    }

    private func drawComments(context: GraphicsContext, size: CGSize) {
        for comment in model.comments {
            let x = CGFloat(comment.timeSeconds) * pixelsPerSecond
            guard x >= -20, x <= size.width + 20 else { continue }
            let selected = comment.id == model.selectedCommentID
            var line = Path()
            line.move(to: CGPoint(x: x, y: 19))
            line.addLine(to: CGPoint(x: x, y: 57))
            context.stroke(line,
                           with: .color((selected ? Theme.accentBright : Theme.accent).opacity(selected ? 0.95 : 0.5)),
                           lineWidth: selected ? 2 : 1)

            var pin = Path()
            pin.move(to: CGPoint(x: x - 4, y: 57))
            pin.addLine(to: CGPoint(x: x + 4, y: 57))
            pin.addLine(to: CGPoint(x: x, y: 63))
            pin.closeSubpath()
            context.fill(pin, with: .color(selected ? Theme.accentBright : Theme.accent))

            if selected {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 3, y: 61, width: 6, height: 6)),
                    with: .color(.white)
                )
            }
        }
    }

    private func drawPlayhead(context: GraphicsContext, size: CGSize) {
        let x = CGFloat(model.player.currentSeconds) * pixelsPerSecond
        guard x >= -10, x <= size.width + 10 else { return }
        var line = Path()
        line.move(to: CGPoint(x: x, y: 2))
        line.addLine(to: CGPoint(x: x, y: 66))
        context.stroke(line, with: .color(Theme.accentBright), lineWidth: 1.5)
        var handle = Path()
        handle.move(to: CGPoint(x: x - 4.5, y: 0))
        handle.addLine(to: CGPoint(x: x + 4.5, y: 0))
        handle.addLine(to: CGPoint(x: x + 4.5, y: 6))
        handle.addLine(to: CGPoint(x: x, y: 10))
        handle.addLine(to: CGPoint(x: x - 4.5, y: 6))
        handle.closeSubpath()
        context.fill(handle, with: .color(Theme.accentBright))
    }

    private func niceTickStep() -> Double {
        let frame = 1.0 / max(1, fps)
        let candidates: [Double] = [frame, frame * 2, frame * 5, frame * 10, frame * 15, frame * 20,
                                    0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200]
        var chosen = 1800.0
        for candidate in candidates {
            if CGFloat(candidate) * pixelsPerSecond >= 78 { chosen = candidate; break }
        }
        // Keep sub-second ticks on real frame boundaries (0.5s is not a frame
        // boundary at 25 or 29.97 fps).
        if chosen < 1 {
            let frames = max(1, (chosen / frame).rounded())
            return frames * frame
        }
        return chosen
    }

    private func tickLabel(_ seconds: Double, step: Double) -> String {
        if step < 1 {
            return Timecode.string(seconds: seconds, fps: fps)
        }
        let total = Int(seconds.rounded())
        if duration >= 3600 {
            return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Overview

private struct OverviewTimelineView: View {
    @ObservedObject var model: AppModel
    let visibleRange: ClosedRange<Double>
    @State private var hoverTime: Double?
    @State private var startedOnMarker = false
    @State private var dragging = false

    private var duration: Double { max(model.player.duration, 0.01) }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                SectionLabel(text: "全片概览")
                Rectangle().fill(Theme.border).frame(width: 1, height: 10)
                if let hoverTime {
                    Text(Timecode.string(seconds: hoverTime, fps: model.fps))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("点击快速定位 · 白色区域为当前精细范围")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text("\(model.commentCount) 条意见")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(height: 14)

            GeometryReader { geo in
                Canvas { context, size in
                    draw(context: context, size: size)
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoverTime = min(max(Double(point.x / max(1, geo.size.width)) * duration, 0), duration)
                    case .ended:
                        hoverTime = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !dragging {
                                model.player.pause()
                                dragging = true
                                startedOnMarker = false
                                if let comment = comment(near: value.startLocation.x, width: geo.size.width) {
                                    startedOnMarker = true
                                    model.selectComment(comment.id)
                                    return
                                }
                            }
                            if startedOnMarker && abs(value.translation.width) <= 5 { return }
                            startedOnMarker = false
                            let fraction = min(max(value.location.x / max(1, geo.size.width), 0), 1)
                            model.player.seek(toSeconds: Double(fraction) * duration, exact: true)
                        }
                        .onEnded { value in
                            if !startedOnMarker {
                                let fraction = min(max(value.location.x / max(1, geo.size.width), 0), 1)
                                model.player.seek(toSeconds: Double(fraction) * duration, exact: true)
                            }
                            dragging = false
                            startedOnMarker = false
                        }
                )
            }
            .frame(height: 30)
            .background(Color(red: 0.045, green: 0.045, blue: 0.052))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
        .frame(height: 50)
    }

    private func comment(near startX: CGFloat, width: CGFloat) -> ReviewComment? {
        let tolerance: CGFloat = 6
        return model.comments
            .map { ($0, abs(CGFloat($0.timeSeconds / duration) * width - startX)) }
            .filter { $0.1 <= tolerance }
            .min(by: { $0.1 < $1.1 })?.0
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let width = size.width
        guard width > 0 else { return }
        let height = size.height

        // Base track
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(
                        Gradient(colors: [Color(red: 0.10, green: 0.10, blue: 0.11),
                                          Color(red: 0.06, green: 0.06, blue: 0.07)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: height)))

        // Comment distribution
        for comment in model.comments {
            let x = CGFloat(comment.timeSeconds / duration) * width
            let selected = comment.id == model.selectedCommentID
            var line = Path()
            line.move(to: CGPoint(x: x, y: height * 0.22))
            line.addLine(to: CGPoint(x: x, y: height * 0.78))
            context.stroke(line,
                           with: .color((selected ? Theme.accentBright : Theme.accent).opacity(selected ? 1 : 0.72)),
                           lineWidth: selected ? 2 : 1)
            context.fill(
                Path(ellipseIn: CGRect(x: x - (selected ? 3 : 2),
                                       y: height * 0.22 - (selected ? 3 : 2),
                                       width: selected ? 6 : 4,
                                       height: selected ? 6 : 4)),
                with: .color(selected ? .white : Theme.accentBright)
            )
        }

        // Visible detail range
        let startX = CGFloat(visibleRange.lowerBound / duration) * width
        let endX = CGFloat(visibleRange.upperBound / duration) * width
        let viewRect = CGRect(x: startX, y: 0, width: max(2, endX - startX), height: height)
        context.fill(Path(viewRect), with: .color(Color.white.opacity(0.09)))
        context.stroke(Path(viewRect), with: .color(Color.white.opacity(0.35)), lineWidth: 1)

        // Playhead
        let px = CGFloat(model.player.currentSeconds / duration) * width
        var playhead = Path()
        playhead.move(to: CGPoint(x: px, y: 0))
        playhead.addLine(to: CGPoint(x: px, y: height))
        context.stroke(playhead, with: .color(Theme.accentBright), lineWidth: 1.5)
        context.fill(
            Path(ellipseIn: CGRect(x: px - 3, y: 1, width: 6, height: 6)),
            with: .color(.white)
        )
    }
}
