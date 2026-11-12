# Nanashi public website

The public installation site continues the native Cold Glass identity. Harbor Blue provides the navy canvas, icy blue action color and neutral glass surfaces. The existing native icon and a synthetic simulator capture connect the site to the actual product.

The page has one primary job: guide the visitor to a valid phone installation. Phone platform detection selects an initial guide and never infers installed apps. Returning iPhone users explicitly select SideStore or AltStore before the direct install action; first-time setup is a separate choice with progressive steps. Android exposes one download action. Desktop visitors receive a compact QR and a copyable URL, with no native iOS protocol links. Source addition, raw package files, checksums and renewal details stay in collapsed help. Unpublished, unavailable and invalid release states never display a fabricated download. The optional Firebase read concerns public release metadata only.

Shared primitives are GlassPanel, GlassLink and PlatformTabs. They adapt actual retrieved 21st sources, with visible source/author links in the page and exact references in README.md. Optical layers are static; only finite control feedback animates. There is no pointer-following runtime, WebGL, canvas loop or external font request.

Accessibility: native links/buttons/details, roving keyboard tab focus, visible focus rings, 44-pixel targets, rem text, reduced-motion and reduced-transparency fallbacks. Mobile has one-column installation and feature layouts. Color and spacing roles are centralized in src/tokens.css.

No private data, 21st preview media, invented testimonials, fabricated release files or promise of permanent Apple signatures is included.

The installation action only opens the selected manager; its confirmation and optional widget choice remain explicit. After-click guidance never claims success. Unknown instance/platform state does not trigger an app launch, and Android visitors switching to the iPhone guide receive device guidance instead of an unsupported protocol URI. The website does not modify existing apps, native data or scheduled automations.

The /installation-sidestore route has one active step and seven freely revisitable stages: computer, USB connection, SideStore installation, iPhone preparation, first renewal, Nanashi installation and renewal automation. It provides direct Mac/Windows installers, phone handoff QR codes and explicit browser-local confirmations. Download links leave for official files or the App Store only; instructions remain in the Nanashi guide. No account data is collected.

The SideStore iPhone preparation step has a direct QR handoff and explicit device instructions. Its final stage offers the actual shared shortcut, with native confirmation, a real renewal test and schedule verification. The shortcut's SideStore action can require rebinding on another account; it does not renew AltStore installations.

The separate /installation-nanashi route reuses the same primitives across five stages: computer bootstrap, iPhone authorization, local connection, Nanashi installation and renewal verification. Its desktop installer prepares AltStore Classic and pairing, not an installed Nanashi app. Only published, validated installer packages become download links or replace the first-install entry point; the existing SideStore guide remains available. The AltStore path requires iOS 17.4 or newer, independently of Nanashi's own deployment target.

The Nanashi installer QR opens https://nanashi-mk.vercel.app/installation-nanashi?step=iphone#installation-etape at stage two. The requested step is consumed once so reloading preserves subsequent navigation. A QR selects instructions on the receiving browser; it never transfers confirmations, authenticates an Apple account or verifies installation. All five QR assets are reproducible locally with scripts/generate-install-qr.py and qrcode 8.2, without a hosted QR service.

AltStore renewal uses its own Background Refresh setting and explicit manual verification. iOS controls background execution, so no fixed renewal time or permanent signature is promised. Existing SideStore automation is not evidence that AltStore has renewed, and retaining the same Apple account is not a claim that app data automatically migrates between copies.
