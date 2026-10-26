# Klasify design consistency pass

## Source of truth
`components-import.html` is the visual reference for the shared component language. This pass aligns reusable Flutter theme tokens and checks common widgets against the reference values.

## Tokens and mappings checked

- **Page canvas:** `#FAF9F5`; primary action and selected states: `#000000`; text on primary: `#FFFFFF`.
- **Surfaces:** `#F4F4F4` default filled surface, `#EDEDED` neutral chip surface, `#E4E4E4` emphasized/focused surface, `#FFFFFF` card surface.
- **Semantic states:** error `#B3261E` / `#FBDAD6`; success `#1F6B4A` / `#D5EADF`; warning `#FFEDC2`; live accent `#E2512B` in light theme and `#FF8A5C` in dark theme.
- **Shape system:** 16px cards/hero (`AppTheme.cardRadius`), 16px fields and controls (`AppTheme.controlRadius`), 12px weekday chips (`AppTheme.chipRadius`), 10px timeline blocks (`AppTheme.blockRadius`), 28px bottom sheets (`AppTheme.sheetRadius`). The shared chip token is 12px to match `.day { border-radius:12px }` in the reference.
- **Action sizes:** primary and secondary buttons 52px high; weekday controls use 48px minimum targets in the scrollable layout; compact Add Class action switches to icon-only below 380 logical pixels.
- **Inputs:** filled states with transparent borders; focus and validation use background colors rather than visible outlines.
- **Navigation and messaging:** selected navigation uses a neutral filled indicator; status banners and toast components use semantic colors and shared control radii.

## Changes in this pass

1. Updated `AppTheme.chipRadius` from 10px to 12px to match the reference weekday chip shape.
2. Changed `DayChips` to consume the shared `AppTheme.chipRadius` token instead of repeating a hard-coded radius in decoration, Material, and InkWell.
3. Retained 48x48 weekday targets and the existing responsive wrap/scroll behavior.
4. Excluded `android/local.properties` from the deliverable because its SDK paths are machine-specific; `.gitignore` excludes it.

## Verification limits

- ZIP integrity and source-level consistency checks can be performed here.
- Flutter analyze, widget tests, device screenshots, and pixel-by-pixel comparison require a Flutter SDK/runtime and have not been run in this environment.
- This audit records concrete source mappings; it is not a claim that every runtime state has been visually validated.
