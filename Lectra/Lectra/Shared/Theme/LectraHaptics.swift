//
//  LectraHaptics.swift
//  Lectra
//
//  Centralised haptic feedback utilities.
//

import UIKit

enum LectraHaptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let notificationFeedback = UINotificationFeedbackGenerator()
    private static let selectionFeedback = UISelectionFeedbackGenerator()

    /// Light impact for tool selection, toggle, card tap.
    static func tap() {
        lightImpact.impactOccurred()
    }

    /// Medium impact for significant interactions.
    static func impact() {
        mediumImpact.impactOccurred()
    }

    /// Notification success for submission complete, sync done.
    static func success() {
        notificationFeedback.notificationOccurred(.success)
    }

    /// Notification warning for errors and failures.
    static func warning() {
        notificationFeedback.notificationOccurred(.warning)
    }

    /// Notification error for critical failures.
    static func error() {
        notificationFeedback.notificationOccurred(.error)
    }

    /// Selection feedback for sidebar nav, picker changes.
    static func selection() {
        selectionFeedback.selectionChanged()
    }
}
