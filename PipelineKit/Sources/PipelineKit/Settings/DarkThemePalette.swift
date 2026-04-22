import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public struct DarkThemePalette: Sendable {
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

public extension DarkThemePalette {
    static let coolBlue = DarkThemePalette(
        primary: RGB(0.236, 0.515, 0.964),
        windowGradientTop: RGB(0.08, 0.093, 0.12),
        windowGradientBottom: RGB(0.064, 0.075, 0.096),
        sidebarBackground: RGB(0.064, 0.075, 0.096),
        contentBackground: RGB(0.08, 0.093, 0.12),
        surface: RGB(0.115, 0.132, 0.165),
        surfaceElevated: RGB(0.164, 0.188, 0.236),
        inputBackground: RGB(0.148, 0.169, 0.212),
        stroke: RGB(0.180, 0.207, 0.259),
        divider: RGB(0.180, 0.207, 0.259),
        shadowOpacity: 0.3,
        placeholder: RGB(0.505, 0.535, 0.595),
        destructive: RGB(0.81, 0.19, 0.19),
        glassBackgroundOpacity: 0.7,
        glassBorderOpacity: 0.1
    )

    static let warmNeutral = DarkThemePalette(
        primary: RGB(0.964, 0.642, 0.236),
        windowGradientTop: RGB(0.11, 0.103, 0.092),
        windowGradientBottom: RGB(0.087, 0.081, 0.072),
        sidebarBackground: RGB(0.087, 0.081, 0.072),
        contentBackground: RGB(0.11, 0.103, 0.092),
        surface: RGB(0.152, 0.142, 0.128),
        surfaceElevated: RGB(0.210, 0.197, 0.178),
        inputBackground: RGB(0.188, 0.176, 0.158),
        stroke: RGB(0.232, 0.218, 0.196),
        divider: RGB(0.232, 0.218, 0.196),
        shadowOpacity: 0.32,
        placeholder: RGB(0.580, 0.555, 0.520),
        destructive: RGB(0.81, 0.25, 0.19),
        glassBackgroundOpacity: 0.7,
        glassBorderOpacity: 0.1
    )

    static let deepOcean = DarkThemePalette(
        primary: RGB(0.285, 0.565, 1.0),
        windowGradientTop: RGB(0.04, 0.06, 0.12),
        windowGradientBottom: RGB(0.026, 0.043, 0.09),
        sidebarBackground: RGB(0.026, 0.043, 0.09),
        contentBackground: RGB(0.04, 0.06, 0.12),
        surface: RGB(0.06, 0.09, 0.17),
        surfaceElevated: RGB(0.090, 0.128, 0.222),
        inputBackground: RGB(0.075, 0.110, 0.195),
        stroke: RGB(0.115, 0.160, 0.260),
        divider: RGB(0.115, 0.160, 0.260),
        shadowOpacity: 0.40,
        placeholder: RGB(0.455, 0.515, 0.625),
        destructive: RGB(0.89, 0.22, 0.22),
        glassBackgroundOpacity: 0.72,
        glassBorderOpacity: 0.12
    )

    static let trueDark = DarkThemePalette(
        primary: RGB(0.280, 0.560, 0.985),
        windowGradientTop: RGB(0.02, 0.02, 0.025),
        windowGradientBottom: RGB(0.008, 0.008, 0.012),
        sidebarBackground: RGB(0.008, 0.008, 0.012),
        contentBackground: RGB(0.02, 0.02, 0.025),
        surface: RGB(0.060, 0.060, 0.070),
        surfaceElevated: RGB(0.095, 0.095, 0.108),
        inputBackground: RGB(0.075, 0.075, 0.088),
        stroke: RGB(0.130, 0.130, 0.148),
        divider: RGB(0.130, 0.130, 0.148),
        shadowOpacity: 0.55,
        placeholder: RGB(0.520, 0.520, 0.560),
        destructive: RGB(0.92, 0.22, 0.22),
        glassBackgroundOpacity: 0.78,
        glassBorderOpacity: 0.08
    )
}
