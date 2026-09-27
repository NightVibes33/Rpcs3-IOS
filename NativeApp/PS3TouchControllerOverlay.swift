import SwiftUI

struct PS3TouchControllerOverlay: View {
    @ObservedObject var controller: CoreController

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack {
                    HStack {
                        shoulderGroup(left: true)
                        Spacer()
                        shoulderGroup(left: false)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 56)

                    Spacer()

                    HStack(alignment: .bottom) {
                        VStack(spacing: 18) {
                            DPadCluster(controller: controller)
                            VirtualStick { x, y in
                                controller.setVirtualStick(left: true, x: x, y: y)
                            }
                        }

                        Spacer(minLength: 28)

                        VStack(spacing: 18) {
                            FaceButtonCluster(controller: controller)
                            VirtualStick { x, y in
                                controller.setVirtualStick(left: false, x: x, y: y)
                            }
                        }
                    }
                    .padding(.horizontal, max(18, proxy.size.width * 0.035))
                    .padding(.bottom, 22)
                }

                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        TouchPadButton(label: "SELECT", compact: true) {
                            controller.setVirtualButton(UInt64(1 << 15), pressed: $0)
                        }
                        TouchPadButton(label: "PS", compact: true) {
                            controller.setVirtualButton(UInt64(1 << 16), pressed: $0)
                        }
                        TouchPadButton(label: "START", compact: true) {
                            controller.setVirtualButton(UInt64(1 << 14), pressed: $0)
                        }
                    }
                    .padding(.bottom, 36)
                }
            }
        }
        .allowsHitTesting(!controller.hasPhysicalController && controller.touchControllerVisible)
        .opacity(!controller.hasPhysicalController && controller.touchControllerVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: controller.hasPhysicalController)
    }

    @ViewBuilder
    private func shoulderGroup(left: Bool) -> some View {
        HStack(spacing: 8) {
            if left {
                TouchPadButton(label: "L2", compact: true) {
                    controller.setVirtualTrigger(left: true, value: $0 ? 1 : 0)
                }
                TouchPadButton(label: "L1", compact: true) {
                    controller.setVirtualButton(UInt64(1 << 8), pressed: $0)
                }
            } else {
                TouchPadButton(label: "R1", compact: true) {
                    controller.setVirtualButton(UInt64(1 << 9), pressed: $0)
                }
                TouchPadButton(label: "R2", compact: true) {
                    controller.setVirtualTrigger(left: false, value: $0 ? 1 : 0)
                }
            }
        }
    }
}

private struct DPadCluster: View {
    @ObservedObject var controller: CoreController

    var body: some View {
        VStack(spacing: 2) {
            TouchPadButton(systemImage: "chevron.up") {
                controller.setVirtualButton(UInt64(1 << 0), pressed: $0)
            }
            HStack(spacing: 2) {
                TouchPadButton(systemImage: "chevron.left") {
                    controller.setVirtualButton(UInt64(1 << 2), pressed: $0)
                }
                Color.clear.frame(width: 48, height: 48)
                TouchPadButton(systemImage: "chevron.right") {
                    controller.setVirtualButton(UInt64(1 << 3), pressed: $0)
                }
            }
            TouchPadButton(systemImage: "chevron.down") {
                controller.setVirtualButton(UInt64(1 << 1), pressed: $0)
            }
        }
    }
}

private struct FaceButtonCluster: View {
    @ObservedObject var controller: CoreController

    var body: some View {
        VStack(spacing: 2) {
            TouchPadButton(label: "△") {
                controller.setVirtualButton(UInt64(1 << 7), pressed: $0)
            }
            HStack(spacing: 2) {
                TouchPadButton(label: "□") {
                    controller.setVirtualButton(UInt64(1 << 6), pressed: $0)
                }
                Color.clear.frame(width: 48, height: 48)
                TouchPadButton(label: "○") {
                    controller.setVirtualButton(UInt64(1 << 5), pressed: $0)
                }
            }
            TouchPadButton(label: "×") {
                controller.setVirtualButton(UInt64(1 << 4), pressed: $0)
            }
        }
    }
}

private struct TouchPadButton: View {
    var label: String?
    var systemImage: String?
    var compact = false
    let changed: (Bool) -> Void

    init(label: String, compact: Bool = false, changed: @escaping (Bool) -> Void) {
        self.label = label
        self.compact = compact
        self.changed = changed
    }

    init(systemImage: String, compact: Bool = false, changed: @escaping (Bool) -> Void) {
        self.systemImage = systemImage
        self.compact = compact
        self.changed = changed
    }

    var body: some View {
        Group {
            if let label {
                Text(label).font(compact ? .caption.bold() : .title3.bold())
            } else if let systemImage {
                Image(systemName: systemImage).font(.headline.bold())
            }
        }
        .foregroundStyle(.white)
        .frame(width: compact ? 58 : 48, height: compact ? 36 : 48)
        .background(.black.opacity(0.48), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in changed(true) }
                .onEnded { _ in changed(false) }
        )
    }
}

private struct VirtualStick: View {
    @State private var knobOffset: CGSize = .zero
    let changed: (Float, Float) -> Void

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            let travel = max(1, radius - 22)

            ZStack {
                Circle()
                    .fill(.black.opacity(0.34))
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 44, height: 44)
                    .offset(knobOffset)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - proxy.size.width / 2
                        let dy = value.location.y - proxy.size.height / 2
                        let distance = max(1, hypot(dx, dy))
                        let scale = min(1, travel / distance)
                        let x = dx * scale
                        let y = dy * scale
                        knobOffset = CGSize(width: x, height: y)
                        changed(Float(x / travel), Float(-y / travel))
                    }
                    .onEnded { _ in
                        knobOffset = .zero
                        changed(0, 0)
                    }
            )
        }
        .frame(width: 104, height: 104)
    }
}
