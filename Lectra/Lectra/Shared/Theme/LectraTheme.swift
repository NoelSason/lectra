//
//  LectraTheme.swift
//  Lectra
//
//  Centralised design tokens for the entire app.
//  All views should reference these tokens instead of hardcoding values.
//

import SwiftUI
import UIKit

// MARK: - Colors

enum LectraColor {
    static let accentHex: UInt = 0xE02520

    /// Primary brand signal used for active tools and critical actions.
    static let accent       = Color(hex: accentHex)
    static let accentUIColor = UIColor(
        red: 224.0 / 255.0,
        green: 37.0 / 255.0,
        blue: 32.0 / 255.0,
        alpha: 1.0
    )

    /// Softer interactive tint for buttons, links, and interactive elements.
    static let accentSoft   = Color(hex: 0xFF6A5C)

    /// Darker accent for gradient endpoints and CTA buttons.
    static let accentDark   = Color(hex: 0xA9181D)

    /// Destructive text and error emphasis.
    static let accentDestructive = Color(hex: 0xFF7A74)

    /// Warm brand highlight used for focus states and supporting emphasis.
    static let accentCool   = Color(hex: 0xF2B8AE)

    /// Deep desk-ink backdrop.
    static let background   = Color(hex: 0x0D0A09)

    /// Primary card surface.
    static let cardBG       = Color(hex: 0x181211)

    /// Elevated surface (toolbars, sheets).
    static let surfaceBG    = Color(hex: 0x211716)

    /// Elevated sheet/modal background (consolidated from multiple hardcoded values).
    static let surfaceElevated = Color(hex: 0x1B1312)

    /// Accent-tinted card background for selected items and CTA surfaces.
    static let surfaceCard  = Color(hex: 0x2A1B1B)

    /// Floating chrome surface for toolbars, rails, and compact control clusters.
    static let surfaceFloating = Color(hex: 0x17100F)

    /// Overlay backdrop surface used by inspector sheets and floating editors.
    static let surfaceOverlay = Color(hex: 0x100B0B)

    /// Warm graphite sidebar surface for the library shell.
    static let sidebarBackground = Color(hex: 0x100C0B)

    /// Slightly raised sidebar control background.
    static let sidebarControl = Color(hex: 0x211819)

    /// Active sidebar row fill.
    static let sidebarSelection = Color(hex: 0x2B1F20)

    /// Hairline divider separating the sidebar from main content.
    static let sidebarDivider = Color(hex: 0xF6F1E7).opacity(0.12)

    /// Primary text.
    static let textPrimary  = Color(hex: 0xF6F1E7)

    /// Secondary text.
    static let textSecondary = Color(hex: 0xD9D0CA)

    /// Tertiary or disabled text.
    static let textTertiary = Color(hex: 0x968C88)

    /// Success green for "Annotated" status.
    static let success      = Color(hex: 0x42D39A)

    /// Warning amber for "Downloading" status.
    static let warning      = Color(hex: 0xF3B75D)

    /// Subtle warning for queued states.
    static let warningSubtle = Color(hex: 0xCFA44B)

    /// Info blue for sync-in-progress, iCloud indicators.
    static let info         = Color(hex: 0x6EA8FF)

    /// Download placeholder gradient start.
    static let placeholderStart = Color(hex: 0xE85D4D)

    /// Download placeholder gradient end.
    static let placeholderEnd = Color(hex: 0x3B1716)

    /// Paper-like preview surface for document thumbnails and blank pages.
    static let paper        = Color(hex: 0xF6F1E7)

    /// Muted paper edge for blank preview placeholders.
    static let paperMuted   = Color(hex: 0xDAD2C4)

    /// Subtle panel border.
    static let edgeStroke   = paper.opacity(0.16)
}

// MARK: - Ink Palette

enum LectraInkPalette {
    static let black      = UIColor(white: 0.0, alpha: 1.0)
    static let white      = UIColor(white: 1.0, alpha: 1.0)
    static let accent     = LectraColor.accentUIColor
    static let yellow     = UIColor(red: 255.0 / 255.0, green: 214.0 / 255.0, blue: 64.0 / 255.0, alpha: 1.0)
    static let blue       = UIColor(red: 0.0 / 255.0, green: 122.0 / 255.0, blue: 255.0 / 255.0, alpha: 1.0)
    static let green      = UIColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1.0)
}

// MARK: - Typography

enum LectraTypography {
    /// 34pt bold — Section titles, splash wordmark.
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)

    /// 28pt bold — Settings headers, large empty states.
    static let displaySmall = Font.system(size: 28, weight: .bold, design: .rounded)

    /// 20pt semibold — Card titles, subsection heads.
    static let title = Font.system(size: 20, weight: .semibold, design: .rounded)

    /// 18pt semibold — Large inline section headers and editor titles.
    static let titleSmall = Font.system(size: 18, weight: .semibold, design: .rounded)

    /// 16pt bold — Buttons, toolbar titles, document titles.
    static let headline = Font.system(size: 16, weight: .bold, design: .rounded)

    /// 16pt semibold — Secondary headlines.
    static let headlineMedium = Font.system(size: 16, weight: .semibold, design: .rounded)

    /// 14pt medium — Body text, descriptions, sidebar items.
    static let body = Font.system(size: 14, weight: .medium, design: .rounded)

    /// 14pt semibold — Emphasized body text.
    static let bodyEmphasis = Font.system(size: 14, weight: .semibold, design: .rounded)

    /// 12pt semibold — Badges, status chips, timestamps.
    static let caption = Font.system(size: 12, weight: .semibold, design: .rounded)

    /// 12pt medium — Secondary captions.
    static let captionMedium = Font.system(size: 12, weight: .medium, design: .rounded)

    /// 11pt medium — Tertiary hints, metadata.
    static let footnote = Font.system(size: 11, weight: .medium, design: .rounded)

    /// 11pt bold — Small bold labels.
    static let footnoteBold = Font.system(size: 11, weight: .bold, design: .rounded)
}

// MARK: - Opacity

enum LectraOpacity {
    /// 0.04 — Faint card backgrounds.
    static let faint: Double = 0.04

    /// 0.08 — Borders, input backgrounds, dividers.
    static let subtle: Double = 0.08

    /// 0.12 — Badge backgrounds, selection fills.
    static let muted: Double = 0.12

    /// 0.16 — Edge strokes, hairline highlights.
    static let medium: Double = 0.16

    /// 0.44 — Faded labels, disabled text.
    static let strong: Double = 0.44

    /// 0.62 — Secondary text in descriptions.
    static let prominent: Double = 0.62

    /// 0.95 — Near-primary text.
    static let primary: Double = 0.95
}

// MARK: - Gradients

enum LectraGradient {
    /// Global app backdrop used by main screens.
    static let appBackdrop = LinearGradient(
        colors: [
            Color(hex: 0x160E0D),
            LectraColor.background,
            Color(hex: 0x15100D)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent wash used for hero surfaces.
    static let spotlight = LinearGradient(
        colors: [
            LectraColor.accent.opacity(0.18),
            LectraColor.accentCool.opacity(0.14),
            LectraColor.warning.opacity(0.06),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Drafting-card face gradient.
    static let panel = LinearGradient(
        colors: [
            LectraColor.cardBG,
            Color(hex: 0x130E0D)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Glass & Elevation

enum LectraGlass {
    static let sidebarTint = LinearGradient(
        colors: [
            LectraColor.paper.opacity(LectraOpacity.subtle),
            LectraColor.accentCool.opacity(0.14),
            LectraColor.accent.opacity(LectraOpacity.subtle),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let floatingToolbarTint = LinearGradient(
        colors: [
            LectraColor.paper.opacity(LectraOpacity.subtle),
            LectraColor.accentCool.opacity(LectraOpacity.muted),
            LectraColor.accent.opacity(0.10),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let urgentCardCritical = LinearGradient(
        colors: [
            LectraColor.accent.opacity(LectraOpacity.medium),
            LectraColor.warning.opacity(0.10),
            LectraColor.paper.opacity(0.06),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let urgentCardWarning = LinearGradient(
        colors: [
            LectraColor.warning.opacity(LectraOpacity.medium),
            LectraColor.accentCool.opacity(LectraOpacity.subtle),
            LectraColor.paper.opacity(0.05),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let urgentCardDefault = LinearGradient(
        colors: [
            LectraColor.accentCool.opacity(LectraOpacity.muted),
            LectraColor.paper.opacity(0.05),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let hairlineStroke = LectraColor.paper.opacity(0.18)
    static let innerHighlight = LectraColor.paper.opacity(0.10)
}

enum LectraElevation {
    static let floatingRadius: CGFloat = 20
    static let floatingYOffset: CGFloat = 12
    static let libraryCardRadius: CGFloat = 10
    static let libraryCardYOffset: CGFloat = 5

    /// No shadow.
    static func none() -> (color: Color, radius: CGFloat, y: CGFloat) {
        (.clear, 0, 0)
    }

    /// Subtle shadow for cards in grids, list rows.
    static func low() -> (color: Color, radius: CGFloat, y: CGFloat) {
        (.black.opacity(0.12), 4, 2)
    }

    /// Medium shadow for elevated panels, document previews.
    static func medium() -> (color: Color, radius: CGFloat, y: CGFloat) {
        (.black.opacity(0.20), 10, 5)
    }

    /// Strong shadow for floating toolbar, auth panel.
    static func high() -> (color: Color, radius: CGFloat, y: CGFloat) {
        (.black.opacity(0.35), 20, 12)
    }
}

// MARK: - Spacing (8pt grid)

enum LectraSpacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Sizing

enum LectraSizing {
    /// Apple-recommended minimum touch target.
    static let minHitTarget: CGFloat = 44
}

// MARK: - Corner Radius

enum LectraRadius {
    /// 4pt — Tiny badges, tags.
    static let tag:     CGFloat = 4
    /// 8pt — Small action buttons.
    static let button:  CGFloat = 8
    /// 10pt — Text fields, grouped row items.
    static let input:   CGFloat = 10
    /// 12pt — Tool buttons, eraser mode buttons, list rows.
    static let control: CGFloat = 12
    /// 14pt — Document card previews, popover backgrounds, editor top bar buttons.
    static let element: CGFloat = 14
    /// 16pt — Content cards, metric tiles.
    static let card:    CGFloat = 16
    /// 20pt — Integration cards, settings sections, icon containers.
    static let panel:   CGFloat = 20
    /// 24pt — Sheets, modals, floating toolbar.
    static let sheet:   CGFloat = 24
    /// 30pt — Auth panel, large hero surfaces.
    static let hero:    CGFloat = 30
}

// MARK: - Motion

enum LectraMotion {
    static let appLaunch = Animation.easeInOut(duration: 0.32)
    static let screenSwap = Animation.easeInOut(duration: 0.26)
    static let startupIntro = Animation.easeOut(duration: 0.18)
    static let startupPulse = Animation.easeOut(duration: 0.34)
    static let startupExit = Animation.easeInOut(duration: 0.18)
    static let overlayPresent = Animation.spring(response: 0.30, dampingFraction: 0.90)
    static let overlayDismiss = Animation.easeOut(duration: 0.20)
    static let gridReflow = Animation.spring(response: 0.34, dampingFraction: 0.92)
    static let toolbarDock = Animation.spring(response: 0.26, dampingFraction: 0.84)
    static let quick = Animation.easeOut(duration: 0.18)
    static let indicatorFade = Animation.easeOut(duration: 0.22)
    static let toast = Animation.spring(response: 0.32, dampingFraction: 0.90)

    /// Smooth tab/section switching.
    static let tabSwitch = Animation.spring(response: 0.28, dampingFraction: 0.88)

    /// Favorite star bounce.
    static let bounce = Animation.spring(response: 0.30, dampingFraction: 0.60)

    /// Folder expand/collapse.
    static let expand = Animation.spring(response: 0.32, dampingFraction: 0.86)

    static let cardTransition: AnyTransition = .asymmetric(
        insertion: .scale(scale: 0.96).combined(with: .opacity),
        removal: .opacity
    )
    static let overlayTransition: AnyTransition = .scale(scale: 0.96).combined(with: .opacity)
    static let statusTransition: AnyTransition = .opacity.combined(with: .scale(scale: 0.92))

    /// Slide-up entry for sheets and modals.
    static let sheetTransition: AnyTransition = .asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .move(edge: .bottom).combined(with: .opacity)
    )
}

// MARK: - Shared View Modifiers

struct LectraCardModifier: ViewModifier {
    var cornerRadius: CGFloat = LectraRadius.card
    var shadow: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LectraColor.surfaceElevated.opacity(0.92))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LectraGradient.spotlight.opacity(0.12))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: shadow ? LectraElevation.low().color : .clear,
                radius: shadow ? LectraElevation.low().radius : 0,
                x: 0,
                y: shadow ? LectraElevation.low().y : 0
            )
    }
}

extension View {
    func lectraCard(cornerRadius: CGFloat = LectraRadius.card, shadow: Bool = true) -> some View {
        modifier(LectraCardModifier(cornerRadius: cornerRadius, shadow: shadow))
    }

    func lectraShadow(_ value: (color: Color, radius: CGFloat, y: CGFloat)) -> some View {
        shadow(color: value.color, radius: value.radius, x: 0, y: value.y)
    }
}

// MARK: - Shared Button Styles

struct LectraPrimaryButtonStyle: ButtonStyle {
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LectraTypography.headline)
            .foregroundColor(LectraColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LectraColor.accent, LectraColor.accentDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .stroke(LectraGlass.innerHighlight, lineWidth: 1)
            )
            .lectraShadow((color: LectraColor.accent.opacity(0.35), radius: 14, y: 8))
            .opacity(disabled ? 0.5 : (configuration.isPressed ? 0.85 : 1.0))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(LectraMotion.quick, value: configuration.isPressed)
    }
}

struct LectraSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LectraTypography.bodyEmphasis)
            .foregroundColor(LectraColor.textPrimary)
            .padding(.horizontal, LectraSpacing.md)
            .frame(minHeight: LectraSizing.minHitTarget)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .fill(LectraColor.surfaceFloating.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(LectraMotion.quick, value: configuration.isPressed)
    }
}

struct LectraDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LectraTypography.bodyEmphasis)
            .foregroundColor(LectraColor.accentDestructive)
            .padding(.horizontal, LectraSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .fill(LectraColor.accent.opacity(LectraOpacity.medium))
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(LectraMotion.quick, value: configuration.isPressed)
    }
}

// MARK: - Color hex initialiser

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
