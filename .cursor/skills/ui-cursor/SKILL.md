---
name: ui-cursor
description: Apply Cursor+'s design system for consistent UI. Use when adding or changing SwiftUI views, padding, spacing, font sizes, or colors so new and edited UI matches the app's theme and stays consistent.
---

# Cursor+ UI design system

Use **Theme/CursorTheme.swift** for all visual constants. Do not hardcode colors, padding, spacing, or font sizes in views.

## When to use this skill

- Adding or editing SwiftUI views, layout, or styling
- User asks for consistent padding, spacing, or typography
- Reviewing or refactoring UI code

## Rules

1. **Colors** – Use `CursorTheme` semantic colors with `@Environment(\.colorScheme)`:
   - `CursorTheme.textPrimary(for: colorScheme)`, `textSecondary`, `textTertiary`
   - `CursorTheme.surfaceRaised(for: colorScheme)`, `border(for: colorScheme)`
   - `CursorTheme.brandBlue`, `semanticError`, `semanticSuccess`, etc.
   - Never use raw `Color.red`, `Color.gray`, or literal RGB in views.

2. **Spacing and padding** – Use theme constants instead of magic numbers:
   - **Padding:** `CursorTheme.paddingCard` (12), `CursorTheme.paddingPanel` (12), `paddingHeaderHorizontal` (16), `paddingHeaderVertical` (12), `paddingBadgeHorizontal` (5), `paddingBadgeVertical` (2)
   - **Gaps:** `CursorTheme.gapSectionTitleToContent` (16), `gapBetweenSections` (20), `spacingListItems` (8)
   - **Scale:** `spaceXXS` (2), `spaceXS` (4), `spaceS` (8), `spaceM` (12), `spaceL` (16), `spaceXL` (24), `spaceXXL` (32)
   - Replace `.padding(12)` with `.padding(CursorTheme.paddingCard)` or `.padding(CursorTheme.paddingPanel)` as appropriate.

3. **Typography** – Use theme font sizes for consistency:
   - **Captions / small:** `fontTiny` (9), `fontCaption` (10), `fontSmall` (11), `fontSecondary` (12)
   - **Body:** `fontBodySmall` (13), `fontBody` (14), `fontBodyEmphasis` (15)
   - **Titles:** `fontSubtitle` (16), `fontTitleSmall` (17), `fontTitle` (18), `fontTitleLarge` (20), `fontDisplaySmall` (22), `fontDisplay` (24)
   - Example: `.font(.system(size: CursorTheme.fontBody, weight: .regular))`, `.font(.system(size: CursorTheme.fontSecondary, weight: .medium))`
   - List/control icons: `fontIconList` (18) for bullet/checkbox size.

4. **Radii** – Use `CursorTheme.radiusCard` (12) for cards and raised surfaces; use `spaceXS` (4) for small radii (e.g. badges).

5. **When touching existing UI** – Prefer replacing hardcoded numbers with the matching theme constant (same value) so future changes are in one place.

## Reference

- Full list of constants: [reference.md](reference.md)
- Source of truth: `Theme/CursorTheme.swift`

## Example

```swift
// Bad
Text("Title")
    .font(.system(size: 18, weight: .semibold))
    .foregroundColor(.white)
VStack(spacing: 8) { ... }
    .padding(12)

// Good
Text("Title")
    .font(.system(size: CursorTheme.fontTitle, weight: .semibold))
    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
VStack(spacing: CursorTheme.spacingListItems) { ... }
    .padding(CursorTheme.paddingCard)
```
