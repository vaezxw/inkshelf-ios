import SwiftUI

// MARK: - Ambient backdrop (glass samples this)

/// 为 Liquid Glass 提供可折射的环境层：柔和光斑 + 纸感底色。
struct GlassAmbientBackground: View {
    var body: some View {
        ZStack {
            InkShelfColors.glassBase

            LinearGradient(
                colors: [
                    InkShelfColors.paper,
                    InkShelfColors.glassBase,
                    Color(red: 0xE4 / 255, green: 0xE8 / 255, blue: 0xEC / 255),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(InkShelfColors.glassOrbWarm)
                .frame(width: 280, height: 280)
                .blur(radius: 56)
                .offset(x: -110, y: -180)

            Circle()
                .fill(InkShelfColors.glassOrbCool)
                .frame(width: 320, height: 320)
                .blur(radius: 64)
                .offset(x: 130, y: 80)

            Circle()
                .fill(InkShelfColors.glassOrbInk)
                .frame(width: 220, height: 220)
                .blur(radius: 48)
                .offset(x: 40, y: 320)

            Circle()
                .fill(InkShelfColors.glassHighlight)
                .frame(width: 160, height: 160)
                .blur(radius: 40)
                .offset(x: -40, y: 140)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass surface helpers

extension View {
    /// iOS 26+ 使用系统 `glassEffect`；更早系统回退到材质。
    @ViewBuilder
    func inkGlass(
        cornerRadius: CGFloat = 16,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, *) {
            if interactive {
                if let tint {
                    self.glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    self.glassEffect(.regular.interactive(), in: shape)
                }
            } else if let tint {
                self.glassEffect(.regular.tint(tint), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// 胶囊形玻璃（工具条、角标等）。
    @ViewBuilder
    func inkGlassCapsule(interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            if interactive {
                if let tint {
                    self.glassEffect(.regular.tint(tint).interactive())
                } else {
                    self.glassEffect(.regular.interactive())
                }
            } else if let tint {
                self.glassEffect(.regular.tint(tint))
            } else {
                self.glassEffect()
            }
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// 整页玻璃环境背景。
    func inkShelfScreenBackground() -> some View {
        background { GlassAmbientBackground() }
    }

    /// 主按钮：iOS 26 `.glassProminent`，否则 `.borderedProminent`。
    @ViewBuilder
    func inkGlassProminentButton() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// 次级按钮：iOS 26 `.glass`，否则 `.bordered`。
    @ViewBuilder
    func inkGlassButton() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Toast / 轻提示玻璃条。
struct GlassToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(InkShelfColors.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .inkGlassCapsule()
    }
}

/// 将一组玻璃控件包进同一采样容器（仅 iOS 26）。
struct InkGlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
