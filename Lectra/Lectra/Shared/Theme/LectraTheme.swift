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

    /// Secondary accent used for highlights and supporting emphasis.
    static let accentCool   = Color(hex: 0x60D4FF)

    /// Deep desk-ink backdrop.
    static let background   = Color(hex: 0x070C17)

    /// Primary card surface.
    static let cardBG       = Color(hex: 0x141D30)

    /// Elevated surface (toolbars, sheets).
    static let surfaceBG    = Color(hex: 0x1D2940)

    /// Primary text.
    static let textPrimary  = Color.white

    /// Secondary text.
    static let textSecondary = Color(hex: 0xA8B7DA)

    /// Tertiary or disabled text.
    static let textTertiary = Color(hex: 0x7786AB)

    /// Success green for "Annotated" status.
    static let success      = Color(hex: 0x2ED89B)

    /// Warning amber for "Downloading" status.
    static let warning      = Color(hex: 0xFFB44B)

    /// Subtle panel border.
    static let edgeStroke   = Color.white.opacity(0.16)
}

// MARK: - Gradients

enum LectraGradient {
    /// Global app backdrop used by main screens.
    static let appBackdrop = LinearGradient(
        colors: [
            Color(hex: 0x0A1223),
            Color(hex: 0x070C17),
            Color(hex: 0x120D1A)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent wash used for hero surfaces.
    static let spotlight = LinearGradient(
        colors: [
            LectraColor.accent.opacity(0.26),
            LectraColor.accentCool.opacity(0.18),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Drafting-card face gradient.
    static let panel = LinearGradient(
        colors: [
            LectraColor.cardBG,
            Color(hex: 0x111A2B)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Glass & Elevation

enum LectraGlass {
    static let sidebarTint = LinearGradient(
        colors: [
            Color.white.opacity(0.08),
            LectraColor.accentCool.opacity(0.14),
            LectraColor.accent.opacity(0.08),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let floatingToolbarTint = LinearGradient(
        colors: [
            Color.white.opacity(0.08),
            LectraColor.accentCool.opacity(0.12),
            LectraColor.accent.opacity(0.10),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let urgentCardCritical = LinearGradient(
        colors: [
            LectraColor.accent.opacity(0.16),
            LectraColor.warning.opacity(0.10),
            Color.white.opacity(0.06),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let urgentCardWarning = LinearGradient(
        colors: [
            LectraColor.warning.opacity(0.16),
            LectraColor.accentCool.opacity(0.08),
            Color.white.opacity(0.05),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let urgentCardDefault = LinearGradient(
        colors: [
            LectraColor.accentCool.opacity(0.12),
            Color.white.opacity(0.05),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let hairlineStroke = Color.white.opacity(0.18)
    static let innerHighlight = Color.white.opacity(0.10)
}

enum LectraElevation {
    static let floatingRadius: CGFloat = 20
    static let floatingYOffset: CGFloat = 12
    static let libraryCardRadius: CGFloat = 10
    static let libraryCardYOffset: CGFloat = 5
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
    static let tag:   CGFloat = 4
    static let button: CGFloat = 8
    static let card:  CGFloat = 16
    static let sheet: CGFloat = 24
    static let capsule: CGFloat = 22
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

    static let cardTransition: AnyTransition = .asymmetric(
        insertion: .scale(scale: 0.96).combined(with: .opacity),
        removal: .opacity
    )
    static let overlayTransition: AnyTransition = .scale(scale: 0.96).combined(with: .opacity)
    static let statusTransition: AnyTransition = .opacity.combined(with: .scale(scale: 0.92))
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
