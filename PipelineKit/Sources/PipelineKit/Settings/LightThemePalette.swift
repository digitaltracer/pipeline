import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public struct LightThemePalette: Sendable {
    public let primary: RGB
    public let windowGradientTop: RGB
    public let windowGradientBottom: RGB
    public let sidebarBackground: RGB
    public let contentBackground: RGB
    public let surface: RGB
    public let surfaceElevated: RGB
    public let inputBackground: RGB
    public let stroke: RGB
    public let divider: RGB
    public let shadowOpacity: Double
    public let placeholder: RGB
    public let destructive: RGB
    public let glassBackgroundOpacity: Double
    public let glassBorderOpacity: Double

    public struct RGB: Sendable, Hashable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        #if canImport(SwiftUI)
        public var color: Color {
            Color(red: red, green: green, blue: blue)
        }
        #endif
    }

    public init(
        primary: RGB,
        windowGradientTop: RGB,
        windowGradientBottom: RGB,
        sidebarBackground: RGB,
        contentBackground: RGB,
        surface: RGB,
        surfaceElevated: RGB,
        inputBackground: RGB,
        stroke: RGB,
        divider: RGB,
        shadowOpacity: Double,
        placeholder: RGB,
        destructive: RGB,
        glassBackgroundOpacity: Double,
        glassBorderOpacity: Double
    ) {
        self.primary = primary
        self.windowGradientTop = windowGradientTop
        self.windowGradientBottom = windowGradientBottom
        self.sidebarBackground = sidebarBackground
        self.contentBackground = contentBackground
        self.surface = surface
        self.surfaceElevated = surfaceElevated
        self.inputBackground = inputBackground
        self.stroke = stroke
        self.divider = divider
        self.shadowOpacity = shadowOpacity
        self.placeholder = placeholder
        self.destructive = destructive
        self.glassBackgroundOpacity = glassBackgroundOpacity
        self.glassBorderOpacity = glassBorderOpacity
    }
}

public extension LightThemePalette {
    static let classic = LightThemePalette(
        primary: RGB(0.15, 0.383, 0.85),
        windowGradientTop: RGB(0.954, 0.958, 0.966),
        windowGradientBottom: RGB(0.932, 0.937, 0.948),
        sidebarBackground: RGB(0.98, 0.98, 0.98),
        contentBackground: RGB(0.954, 0.958, 0.966),
        surface: RGB(1.0, 1.0, 1.0),
        surfaceElevated: RGB(0.909, 0.916, 0.931),
        inputBackground: RGB(0.886, 0.895, 0.914),
        stroke: RGB(0.863, 0.874, 0.897),
        divider: RGB(0.863, 0.874, 0.897),
        shadowOpacity: 0.08,
        placeholder: RGB(0.405, 0.435, 0.495),
        destructive: RGB(0.863, 0.157, 0.157),
        glassBackgroundOpacity: 0.7,
        glassBorderOpacity: 0.3
    )

    static let arcticWhite = LightThemePalette(
        primary: RGB(0.15, 0.383, 0.85),
        windowGradientTop: RGB(1.0, 1.0, 1.0),
        windowGradientBottom: RGB(0.984, 0.984, 0.988),
        sidebarBackground: RGB(0.976, 0.976, 0.982),
        contentBackground: RGB(1.0, 1.0, 1.0),
        surface: RGB(1.0, 1.0, 1.0),
        surfaceElevated: RGB(0.963, 0.966, 0.973),
        inputBackground: RGB(0.949, 0.953, 0.961),
        stroke: RGB(0.886, 0.892, 0.908),
        divider: RGB(0.912, 0.918, 0.931),
        shadowOpacity: 0.05,
        placeholder: RGB(0.470, 0.488, 0.525),
        destructive: RGB(0.863, 0.157, 0.157),
        glassBackgroundOpacity: 0.82,
        glassBorderOpacity: 0.35
    )

    static let warmPaper = LightThemePalette(
        primary: RGB(0.15, 0.383, 0.85),
        windowGradientTop: RGB(0.988, 0.975, 0.952),
        windowGradientBottom: RGB(0.972, 0.954, 0.922),
        sidebarBackground: RGB(0.992, 0.981, 0.961),
        contentBackground: RGB(0.984, 0.971, 0.945),
        surface: RGB(1.0, 0.994, 0.982),
        surfaceElevated: RGB(0.953, 0.933, 0.894),
        inputBackground: RGB(0.941, 0.920, 0.879),
        stroke: RGB(0.884, 0.860, 0.810),
        divider: RGB(0.900, 0.878, 0.830),
        shadowOpacity: 0.09,
        placeholder: RGB(0.495, 0.465, 0.410),
        destructive: RGB(0.820, 0.215, 0.190),
        glassBackgroundOpacity: 0.72,
        glassBorderOpacity: 0.28
    )

    static let slate = LightThemePalette(
        primary: RGB(0.15, 0.383, 0.85),
        windowGradientTop: RGB(0.906, 0.922, 0.945),
        windowGradientBottom: RGB(0.872, 0.891, 0.921),
        sidebarBackground: RGB(0.925, 0.935, 0.951),
        contentBackground: RGB(0.895, 0.910, 0.935),
        surface: RGB(0.965, 0.973, 0.985),
        surfaceElevated: RGB(0.846, 0.867, 0.901),
        inputBackground: RGB(0.820, 0.842, 0.880),
        stroke: RGB(0.760, 0.785, 0.830),
        divider: RGB(0.780, 0.805, 0.845),
        shadowOpacity: 0.10,
        placeholder: RGB(0.355, 0.395, 0.465),
        destructive: RGB(0.843, 0.157, 0.157),
        glassBackgroundOpacity: 0.68,
        glassBorderOpacity: 0.32
    )
}
