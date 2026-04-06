//
//  LectraStatusBadge.swift
//  Lectra
//
//  Unified status badge component used across editor, library, and settings.
//

import SwiftUI

struct LectraStatusBadge: View {
    let title: String
    let color: Color

    enum Size {
        case compact
        case regular
        case large

        var font: Font {
            switch self {
            case .compact: return LectraTypography.footnoteBold
            case .regular: return LectraTypography.caption
            case .large:   return LectraTypography.caption
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact: return 6
            case .regular: return LectraSpacing.sm
            case .large:   return 11
            }
        }

        var height: CGFloat {
            switch self {
            case .compact: return 14
            case .regular: return 24
            case .large:   return 32
            }
        }

        var strokeOpacity: Double {
            switch self {
            case .compact: return LectraOpacity.faint
            case .regular: return LectraOpacity.subtle
            case .large: return LectraOpacity.medium
            }
        }
    }

    var size: Size = .regular

    var body: some View {
        Text(title)
            .font(size.font)
            .foregroundColor(color)
            .padding(.horizontal, size.horizontalPadding)
            .frame(height: size.height)
            .background(color.opacity(LectraOpacity.muted))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(size.strokeOpacity), lineWidth: 1)
            )
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status: \(title)")
    }
}
