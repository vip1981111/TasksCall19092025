//
//  ThemeManager.swift
//  TasksCall19092025 (أنجز)
//
//  نظام الثيمات — 4 ثيمات احترافية
//

import SwiftUI
import Combine

// MARK: - تعريف الثيمات
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case modernBlue = "أزرق هادئ"
    case purpleVibes = "بنفسجي عصري"
    case tealCoral = "تيل ومرجاني"
    case darkPremium = "داكن فخم"

    var id: String { rawValue }

    // MARK: - ألوان الهيدر
    var headerColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "1A3B5C")
        case .purpleVibes: return Color(hex: "4A1A6B")
        case .tealCoral: return Color(hex: "0D4F4F")
        case .darkPremium: return Color(hex: "1A1A2E")
        }
    }

    var headerGradient: [Color] {
        switch self {
        case .modernBlue: return [Color(hex: "1A3B5C"), Color(hex: "2E86AB")]
        case .purpleVibes: return [Color(hex: "4A1A6B"), Color(hex: "7B2D8E")]
        case .tealCoral: return [Color(hex: "0D4F4F"), Color(hex: "14837B")]
        case .darkPremium: return [Color(hex: "1A1A2E"), Color(hex: "16213E")]
        }
    }

    // MARK: - اللون الرئيسي (Accent)
    var accentColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "2E86AB")
        case .purpleVibes: return Color(hex: "A855F7")
        case .tealCoral: return Color(hex: "14837B")
        case .darkPremium: return Color(hex: "E2B714")
        }
    }

    // MARK: - لون اليوم الحالي / العنصر المميز
    var highlightColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "48B8D0")
        case .purpleVibes: return Color(hex: "A855F7")
        case .tealCoral: return Color(hex: "FF6B6B")
        case .darkPremium: return Color(hex: "E2B714")
        }
    }

    // MARK: - الخلفية العامة
    var backgroundColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "F5F7FA")
        case .purpleVibes: return Color(hex: "FAF5FF")
        case .tealCoral: return Color(hex: "FAFBF9")
        case .darkPremium: return Color(hex: "0F0F23")
        }
    }

    // MARK: - خلفية الكروت
    var cardBackground: Color {
        switch self {
        case .modernBlue: return Color(hex: "EDF2F7")
        case .purpleVibes: return Color(hex: "F3E8FF")
        case .tealCoral: return Color(hex: "E6FAF8")
        case .darkPremium: return Color(hex: "16213E")
        }
    }

    // MARK: - لون النقاط/الأحداث
    var eventDotColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "F4845F")
        case .purpleVibes: return Color(hex: "EC4899")
        case .tealCoral: return Color(hex: "FF6B6B")
        case .darkPremium: return Color(hex: "E2B714")
        }
    }

    // MARK: - لون ثانوي للنقاط
    var secondaryDotColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "F4845F")
        case .purpleVibes: return Color(hex: "EC4899")
        case .tealCoral: return Color(hex: "FFD93D")
        case .darkPremium: return Color(hex: "00D2FF")
        }
    }

    // MARK: - لون أيام الجمعة / النص الخاص
    var specialDayColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "1A3B5C")
        case .purpleVibes: return Color(hex: "5B21B6")
        case .tealCoral: return Color(hex: "0D4F4F")
        case .darkPremium: return Color(hex: "E2B714")
        }
    }

    // MARK: - خلفية قسم التذكيرات
    var reminderBackground: Color {
        switch self {
        case .modernBlue: return Color(hex: "EDF2F7")
        case .purpleVibes: return Color(hex: "F3E8FF")
        case .tealCoral: return Color(hex: "E6FAF8")
        case .darkPremium: return Color(hex: "16213E")
        }
    }

    // MARK: - لون حدود التذكيرات
    var reminderBorderColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "2E86AB")
        case .purpleVibes: return Color(hex: "A855F7")
        case .tealCoral: return Color(hex: "FF6B6B")
        case .darkPremium: return Color(hex: "E2B714")
        }
    }

    // MARK: - خلفية البادجات
    var badgeBackground: Color {
        switch self {
        case .modernBlue: return Color(hex: "48B8D0").opacity(0.2)
        case .purpleVibes: return Color(hex: "DDD6FE")
        case .tealCoral: return Color(hex: "FFE8E8")
        case .darkPremium: return Color(hex: "2D2D44")
        }
    }

    // MARK: - لون نص البادجات
    var badgeTextColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "2E86AB")
        case .purpleVibes: return Color(hex: "5B21B6")
        case .tealCoral: return Color(hex: "FF6B6B")
        case .darkPremium: return Color(hex: "E2B714")
        }
    }

    // MARK: - لون النصوص الرئيسية
    var primaryTextColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "1A3B5C")
        case .purpleVibes: return Color(hex: "4A1A6B")
        case .tealCoral: return Color(hex: "0D4F4F")
        case .darkPremium: return Color(hex: "E8E8E8")
        }
    }

    // MARK: - لون النصوص الثانوية
    var secondaryTextColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "1A3B5C").opacity(0.6)
        case .purpleVibes: return Color(hex: "4A1A6B").opacity(0.6)
        case .tealCoral: return Color(hex: "0D4F4F").opacity(0.6)
        case .darkPremium: return Color(hex: "E8E8E8").opacity(0.6)
        }
    }

    // MARK: - لون خلفية شريط البحث
    var searchBarBackground: Color {
        switch self {
        case .modernBlue: return Color(hex: "2E86AB").opacity(0.12)
        case .purpleVibes: return Color(hex: "A855F7").opacity(0.12)
        case .tealCoral: return Color(hex: "14837B").opacity(0.12)
        case .darkPremium: return Color(hex: "2D2D44")
        }
    }

    // MARK: - لون الـ Chips المحددة
    var selectedChipBackground: Color {
        switch self {
        case .modernBlue: return Color(hex: "2E86AB").opacity(0.18)
        case .purpleVibes: return Color(hex: "A855F7").opacity(0.18)
        case .tealCoral: return Color(hex: "14837B").opacity(0.18)
        case .darkPremium: return Color(hex: "E2B714").opacity(0.18)
        }
    }

    // MARK: - لون الـ Chips غير المحددة
    var unselectedChipBackground: Color {
        switch self {
        case .modernBlue: return Color(hex: "1A3B5C").opacity(0.08)
        case .purpleVibes: return Color(hex: "4A1A6B").opacity(0.08)
        case .tealCoral: return Color(hex: "0D4F4F").opacity(0.08)
        case .darkPremium: return Color(hex: "2D2D44")
        }
    }

    // MARK: - لون زر الإضافة FAB
    var fabColor: Color {
        switch self {
        case .modernBlue: return Color(hex: "2E86AB")
        case .purpleVibes: return Color(hex: "A855F7")
        case .tealCoral: return Color(hex: "FF6B6B")
        case .darkPremium: return Color(hex: "E2B714")
        }
    }

    // MARK: - لون الفلتر النشط
    var activeFilterBackground: Color {
        switch self {
        case .modernBlue: return Color(hex: "1A3B5C")
        case .purpleVibes: return Color(hex: "4A1A6B")
        case .tealCoral: return Color(hex: "0D4F4F")
        case .darkPremium: return Color(hex: "E2B714")
        }
    }

    var activeFilterTextColor: Color {
        switch self {
        case .darkPremium: return Color(hex: "0F0F23")
        default: return .white
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .modernBlue: return .light
        case .purpleVibes: return .light
        case .tealCoral: return .light
        case .darkPremium: return .dark
        }
    }

    var iconName: String {
        switch self {
        case .modernBlue: return "drop.fill"
        case .purpleVibes: return "sparkles"
        case .tealCoral: return "leaf.fill"
        case .darkPremium: return "moon.stars.fill"
        }
    }

    var description: String {
        switch self {
        case .modernBlue: return "أزرق هادئ وأنيق"
        case .purpleVibes: return "بنفسجي عصري ومشرق"
        case .tealCoral: return "تيل وبرتقالي دافئ"
        case .darkPremium: return "داكن فخم بلمسات ذهبية"
        }
    }

    /// هل الثيم مجاني أم يحتاج اشتراك
    var isPremium: Bool {
        switch self {
        case .modernBlue: return false // مجاني
        case .purpleVibes: return true
        case .tealCoral: return true
        case .darkPremium: return true
        }
    }
}

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - مدير الثيمات
@MainActor
final class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "selectedTheme")
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = AppTheme(rawValue: saved) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .modernBlue
        }
    }

    func setTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentTheme = theme
        }
    }

    /// إذا الثيم PRO والمستخدم ما عنده اشتراك — يرجّعه للمجاني
    func validateTheme(isPremium: Bool) {
        if !isPremium && currentTheme.isPremium {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentTheme = .modernBlue
            }
        }
    }
}

// MARK: - عرض اختيار الثيم
struct ThemePickerView: View {
    @ObservedObject var themeManager: ThemeManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Binding var showPaywall: Bool

    var body: some View {
        Section("الثيمات") {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    if theme.isPremium && !subscriptionManager.isPremium {
                        showPaywall = true
                    } else {
                        themeManager.setTheme(theme)
                    }
                } label: {
                    HStack(spacing: 12) {
                        // معاينة الثيم — مربعات ألوان
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.headerColor)
                                .frame(width: 14, height: 44)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.accentColor)
                                .frame(width: 14, height: 44)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.highlightColor)
                                .frame(width: 14, height: 44)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(theme.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)

                                if theme.isPremium && !subscriptionManager.isPremium {
                                    Text("PRO")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundStyle(.orange)
                                        .clipShape(Capsule())
                                }
                            }

                            Text(theme.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if themeManager.currentTheme == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.accentColor)
                                .font(.title3)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
