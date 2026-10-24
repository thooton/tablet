import QtQuick
import "../js/theme.js" as Theme

// The small caps labels: text-[11px]/[12px] font-semibold uppercase
// tracking-wide text-ink-faint.
UiText {
    size: 12
    font.weight: Font.DemiBold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.025 * Theme.px(size)
    color: Theme.inkFaint
}
