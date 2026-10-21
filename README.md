# Life Clock

A native macOS 14+ menu-bar app, movable live desktop card and standard desktop widget. Birthday settings stay on your Mac. No third-party packages are required; city searches stay local unless you explicitly choose **Search online with Apple**.

## Open and run

1. Open `LifeClock.xcodeproj` in Xcode 15 or newer.
2. Select the **LifeClock** scheme and **My Mac**, then Run. The project uses **Sign to Run Locally** (ad-hoc signing), with no development team or App Group required. This is for local use on your Mac.
3. Enter your birthday for the live desktop card and birthday celebration. Birth time is optional; **Use device timezone** selects your Mac's current timezone. Save.
4. Right-click the desktop → **Edit Widgets** → **Life Clock** to add a small or medium widget.
5. Right-click that widget → **Edit Widget**. Set its **Birthday**, optional **Birth time**, **Birth timezone** and **Clock**. Select **Asia/Kolkata** for IST. The device timezone is offered first and as the initial default.

The widget has one clock: **Age** counts from your birthday; **Years remaining** counts down to your chosen **Target age**, default 80 (allowed range 1–150). This is a personal target, not a prediction. Years are always enabled; Months, Days, Hours, Minutes and Seconds have individual switches. Turning a unit off lets larger or smaller selected units express that time. The countdown stops at zero. Apple's calendar formatter may omit zero-valued units. Live calendar updates require macOS 15 or later; macOS 14 shows the same selected units in system-scheduled timeline snapshots. Approximate birth-time information is available to VoiceOver. The old Age format and Show live timer settings are removed; existing birthday and day/hour/minute/second choices are preserved.

After upgrading from the enum-based Clock setting, open **Edit Widget** and select **Years remaining** again, then set your target age. The Clock dropdown accepts the previous raw selections as well as its visible labels.

The standard widget stores its settings through macOS widget configuration, independently of the app. Enter the birthday separately in both places if you use both. Each widget can have a different birthday, clock mode or unit selection. Changing one widget does not change the desktop card or birthday celebration.

If upgrading from the old version, rebuild and replace the installed app, launch the new copy, then remove the old widget and add Life Clock again if **Edit Widget** does not expose the new settings. An unconfigured widget tells you to use **Edit Widget**. It no longer asks you to save your birthday in an app whose settings it cannot read.

For regular use, put the locally signed `LifeClock.app` in `/Applications` or `~/Applications`, launch that copy, then enable launch at login. Avoid moving it afterward. macOS may require approval under **System Settings → General → Login Items**; the app shows an approval button when needed. No notification permission is used.

This version does not use App Groups or shared preferences. The app keeps its own local settings under the existing key, preserving birthdays previously saved by the local unsigned-team build. No local birthday data is deleted. Older installations that actually used a valid signed App Group must re-enter their birthday for the desktop card; this version does not access that group's protected container.

Widget configuration uses Apple's [configurable widget API](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget).

## Using the clock

- **Detailed age:** calendar years, months and days, followed by hours, minutes, seconds and milliseconds on the live card.
- **Decimal years:** completed birthdays plus the fraction of the actual interval between the previous and next birthday, rather than dividing by a fixed 365 days.
- **Total seconds:** elapsed seconds since the saved birth instant, with three decimal places on the live card.
- **Live age card:** a compact live row of years, months, days, hours, minutes and seconds. This is the default desktop-card display.
- **Years remaining:** shows years, months, days, hours, minutes and seconds counting down to your chosen target age, then stays at zero. In app Preferences → Desktop card, select **Years remaining** and edit **Target age (personal estimate)** (1–150, default 80). This setting also applies in wallpaper mode and is separate from each widget's target age.
- For the live age card and countdown, independently toggle milliseconds, microseconds, nanoseconds and picoseconds. Each selected unit appears in its own column with at most three digits (successive groups of the fractional second). Picoseconds are estimated display digits, not true picosecond measurements; clock precision and display refresh are OS-limited. Drag the lower-right corner grip to resize the card; its size is remembered.
- The desktop card has its own format setting in the app. Set each widget’s format separately through **Edit Widget**; the live age card and countdown are desktop-card-only layouts.
- **Wallpaper mode (full screen):** a Desktop-card setting that expands the card to the whole screen frame. It sits just above the wallpaper — below the desktop icons, below all windows and fullscreen apps — and clicks pass through, so icons on the desktop stay clickable. Text is centered, sized from the screen, with proportional gaps; the drag, resize and gear controls are inactive here. Use the menu-bar hourglass to reopen Settings. Keep on top is disabled while wallpaper mode is on. The **Layout** section has a collapse/expand button that hides or shows its controls without changing the clock. Four sliders set horizontal and vertical position (each way limited to the leftover slack, so the pane always stays inside the screen borders), overall size (0.4–2.0, 1.0 = full width; the frosted pane keeps its thickness) and pane roundness (0 = sharp corners, 1.4 default, relative to pane padding) with **Reset to centered full** restoring the default position, size and roundness. Changes apply instantly — there is no Save button. **Frosted glass pane** (on by default) adds the translucent liquid-glass look with gloss, bright rim and shadow on macOS 26+ (falls back to an ultra-thin material on older systems); turn it off for digits directly on the wallpaper. **Full-screen tint / veil** covers the screen with the renderer's scrim/tint behind the digits; it does not create a rounded pane, and the pane roundness slider applies only to the frosted pane mode. A **Glass strength** slider (0 = nearly clear, 1 = most veiled, 0.4 default) scales a grain-free neutral veil — paired low-opacity black and white washes that settle into a soft translucent darkening on light and dark wallpapers alike — plus faint digit-shadowing for legibility. The pane uses a single glass/material layer (no stacked materials), so there is no grainy frost texture. Text colour follows the system light/dark appearance, not the wallpaper image, so digits can need an appearance switch to stay readable.
- Drag the card background to move it. By default it sits behind normal app windows. **Always on top** makes it float above normal windows. Its position is remembered and brought back onto a connected screen after display changes.
- The menu-bar hourglass opens settings, shows/enables the card or quits the app. The card's gear opens settings. Quitting stops the live card and birthday checks; a standard widget may continue showing its scheduled snapshots.
- When subsecond columns are enabled, the live card samples every display frame so each frame advances through the fractional-digit groups. A fixed cadence would sync to whole vsync intervals, whose 50,000 µs steps are zero modulo 1,000 µs and leave the microsecond group frozen. macOS and the screen may limit updates. Otherwise it updates once per second. It pauses while hidden/asleep and updates once a second with Reduce Motion enabled. Every frame is calculated from the current date, so sleep does not lose elapsed time.

## Birthday behaviour and date rules

- The first active session on your birthday shows a 12-second greeting with a dismiss button and brief confetti. Reduce Motion disables confetti. A saved calendar-date marker prevents repeats after unlocks and restarts.
- Checks run on launch, wake, session/unlock changes, local date/timezone changes and a low-frequency 30-second fallback timer. A normal floating window cannot draw over the macOS lock screen. Sleep, screen sleep and lock events dismiss any greeting already open.
- The app must be running. Enable launch at login if you want automatic greetings after restarting. If the app does not run on your birthday, it does not show a belated greeting the next day.
- Birthday greetings follow the Mac's **current local date**, regardless of your birth timezone or birth hour. Age calculations use the saved **birth timezone**.
- February 29 uses February 28 in non-leap years, then returns to February 29 in leap years.
- Without a birth time, the app uses midnight in the selected timezone and labels the age approximate. A future birthday, invalid date or a birth time skipped by daylight-saving changes is rejected. For a repeated hour when clocks move backwards, Foundation chooses its default occurrence; this version does not offer a first/second-occurrence selector.

## Verification commands

Use this command after changes:

```sh
./build.sh
```

It runs the focused tests, builds a normal Debug app, verifies signatures and widget-configuration metadata, saves a ZIP backup of the installed app, replaces `/Applications/LifeClock.app`, registers the new widget and launches the app to refresh its timelines. A failed build or test leaves the installed app untouched; an installation failure attempts to restore the previous app. It stops Life Clock with a normal termination signal during installation, so save any settings edits first. Logs, test results and backups are kept under `.build/logs/`. Xcode's output stays in the logs unless a step fails.

Desktop widget placement remains a one-time manual step: **Edit Widgets → Life Clock**, then **Edit Widget** for its birthday. The command registers the widget but does not claim to place it. If the old static widget remains cached, remove it and add Life Clock again.

The local Debug app and widget build succeeded, and all 13 focused tests passed. The installed app signature was verified. Widget configuration metadata contains the birthday, optional birth time, birth timezone and age-format parameters. Full on-screen widget configuration and timer behaviour still require a manual check on macOS; unit tests do not prove that flow.

To build locally and run the focused tests, use this folder:

```sh
xcodebuild -project LifeClock.xcodeproj -scheme LifeClock -destination 'platform=macOS' build
xcodebuild -project LifeClock.xcodeproj -scheme LifeClock -destination 'platform=macOS' -only-testing:LifeClockTests test
```

The test target compiles the pure age and birthday-policy source directly. It covers exact anniversaries, fractional elapsed time, leap years, decimal-year intervals, timezone midnight, invalid/future dates, DST, month boundaries, sleep-length jumps, locked sessions, duplicate greeting suppression and the next year's birthday. It also covers date-only and timed widget birthday conversion into the selected timezone. It does not simulate macOS window behaviour, widget configuration controls or local signing.

Manual acceptance checks on the locally signed app:

1. Start without saved settings. Save a date-only birthday; check the approximate label. Try a future date; saving must fail. Add a birth time, restart and confirm the saved value.
2. Add both widget sizes with no birthday configured: they must say **Set your birthday** and direct you to **Edit Widget**. Configure each with a different birthday and format. Reopen **Edit Widget** and confirm the saved values. Change the app’s birthday; neither widget should change. Enter a future birthday or invalid birth time: the widget must show a correction message rather than a countdown. Confirm the life timer advances while the app is closed and catches up after sleep. Check the approximate label, long timer and timestamp fit in the small widget. Widget snapshot refresh is system-controlled, so it may not be immediate.
3. Move the card, cover it with another window, switch Always on top, and disable/re-enable it. Reopen settings after using **Show Life Clock**; its card switch must reflect the current setting. Unplug an external display; the card must remain reachable.
4. Sleep and wake the Mac; the age must immediately reflect current time. Check screen sleep separately. Check light/dark appearance, VoiceOver labels and Reduce Motion.
5. To exercise the greeting without changing the system clock, temporarily save a birthday with today's month/day in a past year. Confirm one greeting, dismiss it, then lock/unlock and relaunch: no second greeting that date. Restore your real birthday afterward. A greeting already recorded today intentionally prevents another same-day preview.
6. Confirm the app launches at the next login if enabled, and does not if disabled. Test a real birthday wake/unlock flow to verify OS event delivery; unit tests only prove the eligibility rules.

## Limits and implementation notes

- Milliseconds are a display unit, not a claim that the birth instant or wall clock is accurate to a millisecond. Nanosecond and picosecond modes are intentionally excluded. A 30 Hz screen update skips intermediate millisecond values.
- The desktop card’s birthday is local UserDefaults data; macOS stores each widget’s birthday in its widget configuration. Neither is encrypted secret storage. Birthday data stays local; only an explicit online city search can send the typed city query to Apple for timezone lookup.
- Lock/unlock handling uses workspace events, distributed screen-lock notifications and a Core Graphics session check. Some lock signals/session dictionary fields are not formally documented public contracts; real-device checks are required on future macOS versions. The fallback timer cannot guarantee a greeting at the exact instant of unlock.
- Desktop placement and visibility are subject to macOS window management, Spaces, Show Desktop and Stage Manager. Verify those modes on your setup.
- This project is for local installation. It does not include App Store submission, a notarised installer, automatic updates or a custom app icon.
