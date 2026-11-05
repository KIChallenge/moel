# Design

- `brand/`: future logo, typography and voice exploration.
- `mascot/`: character references and exports.

The prototype uses a white canvas, charcoal text and green UI accents, with emerald green, pale mint and restrained coral for the mascot. Sovi is an original rounded green vector companion with a small leaf, expressive eyes and simple listening, speaking, working and confirmation expressions. The same reusable SwiftUI character moves between the path and Focus. Its eyes use the exact vector outlines, pupils and highlights from the app icon; `design/mascot/sovi.png` shows the updated character.

Implementation: `apps/ios/Sovi/DesignSystem/SoviMascot.swift`. Path buttons have 70×60pt faces with 8pt raised bases, bold topic symbols and small date captions. The current day is green; resting entries are neutral gray and remain interactive. Their winding placement suggests the route without a connecting line. Dark appearance, Reduce Motion, Dynamic Type and a straightened route representation are part of the design.

The app icon is `apps/ios/Sovi/Resources/AppIcon.icon`: the supplied layered eyes-and-smile design with Sovi’s sRGB emerald green (`#008E5C`) background in default and dark appearances. SVG shapes, positioning and glass settings are preserved. Edit the source with Icon Composer in Xcode 26+. Preview exports live in `design/brand`.

## Mascot green

The base is **#008E5C**, the color explicitly labeled `sv-grün` in the Sozialversicherung website’s `--g-carrier-color`, `--g-headline-color` and `--g-link-text-color` variables. Checked 5 November 2026 against the [public portal](https://www.sozialversicherung.at/) and its [published stylesheet](https://www.sozialversicherung.at/cdscontent/load?contentid=10007.740392&version=1790783587). This records an observed website color, rather than a formal brand-guideline specification.

Sovi uses a lighter **#2FA979** body highlight, **#006A46** for feet/shadows, and **#D9F0E4** for the face patch. These companion shades are our adaptations. White eyes, charcoal pupils and coral cheeks retain their existing design. The app icon shares the #008E5C base; interface text/button colors retain their existing accessible palette.

## Path symbols

`apps/ios/Sovi/DesignSystem/PathNodeSymbol.swift` defines the shared symbols and raised button faces. The seeded chapters use sunrise, teddy bear, key and sun symbols; the post-hospital journey uses a medical bag, document magnifier, book, walking figure, stethoscope and pills. Administrative drafts use a pencil; incomplete medication instructions use a question bubble. Unrecognized manual entries retain a clear symbol for their type.

Topic matching is display-only and uses the title or original supporting passage. Completing or reading an item adds a status badge while keeping its topic symbol. The path uses neutral gray faces and monochrome symbols, with a vivid green current-day face. Topic colors remain available in detail rows. Button labels, dates and status remain available to VoiceOver.

Native SwiftUI design exports: `design/path/path.png`, `design/path/symbols.png`, and their dark variants. These are rendered previews of the shared components, not simulator screenshots.

## Daily path and entry halos

The 33-year example projects 305 stored entries onto 208 chronological calendar-day buttons. Several entries on one day share the source title (or “Mein Tag” when combined). A day with one entry has no segmented halo; a day with several has exactly one equal segment per entry, including links to an existing task. Sources, menus and actions add no segments. Segments use neutral gray or the current-day green, independent of completion or health.

Historical years stay expanded in the same continuous scrolling path and Sovi sits next to 5 November 2026. The five planned outlook days continue at the same row pitch; the pinned banner changes to Ausblick as they reach the top. `LifePath.swift` owns the projection; `PathDaySheet.swift` opens the entry list and source-linked details.

Current example previews: `design/path/life-path-current.png` and `design/path/life-path-history.png`, rendered from the actual 33-year fixture, shared button/mascot views and continuous layout. All 208 day buttons are in the layout; the images show viewports around the current day and birth. Year headings have no collapse controls.

The supplied test vaccination record replaces the original placeholders with nine entries on eight dates. `design/path/vaccination-path.png` shows the shared two-entry button for 3 November 2025; `vaccination-details.png` shows the concise vaccine fields, optional extra details and source link. Vaccination buttons use the syringe symbol. The halo counts records, never doses due or immunity.

Copy follows the same minimal layout: no profile/snapshot banners or explanatory footers. Topic symbols and small dates identify each button; the companion bubble gives one upcoming item or a check-in. Additional record fields remain accessible through disclosures and original sources.

## Reference-style path

The supplied screenshot informs the compact visual rhythm: 106pt row pitch, a gradual eight-step wave (`.50, .39, .33, .39, .50, .61, .67, .61` of the width), a solid 72pt green banner with a 5pt base, and an outlined HEUTE pointer above the current day. Sovi is 140pt beside the next steps; the gray-outlined speech bubble and the existing top/bottom edge peeks share the same Focus entrance.

The four top values are actual local record counts, not game points or health scores. Gray buttons are active records, not locked steps. Normal path labels stay compact; the expanded straight layout retains full text for accessibility sizes. All 208 days and 34 year boundaries stay in one continuous scroll.
