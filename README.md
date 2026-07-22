<p align="center">
  <img src="MyNiro/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="MyNiro app icon" width="128" />
</p>

# MyNiro

Personal Kia Connect (Europe) companion for iOS — charging, climate, unlock, widgets, and Apple Watch.

> **Disclaimer:** MyNiro is an unofficial, community-built client for Kia Connect.
> It is **not affiliated with, endorsed by, or sponsored by Kia Corporation** or
> any of its subsidiaries. Kia Connect, Kia, and related marks are trademarks of
> their respective owners. Use at your own risk and in accordance with your Kia
> Connect account terms.

## Open in Xcode

```bash
open MyNiro.xcodeproj
```

Sign in with your Kia Connect Europe email, password, and PIN.

## Targets

| Scheme | What |
|---|---|
| **MyNiro** | iOS app + Home Screen widget + Control Center unlock + embedded Watch app/complications |
| **MyNiroWatch** | Watch-only run (simulator / direct Watch install) |

Install on a paired Watch by running **MyNiro** to your iPhone. Then open the MyNiro app once on the Watch, edit the watch face, and pick **MyNiro → Unlock** for a circular slot.

## Regenerating the project

```bash
xcodegen generate   # needs xcodegen on PATH
```

## Stack

- [BetterBlueKit](Packages/BetterBlueKit) (vendored, Kia Europe) — MIT, Copyright Mark Schmidt
- App Group `group.com.holux-design.MyNiro` for widgets / Watch status cache

See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for attribution details.

## Design

Black + green action tiles, Car / Settings tabs. Units are metric (km, °C).

## License

MyNiro app code is licensed under the [MIT License](LICENSE).

BetterBlueKit is vendored under its own [MIT License](Packages/BetterBlueKit/LICENSE).
