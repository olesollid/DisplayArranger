![DisplayArranger icon](DisplayArranger/Assets.xcassets/AppIcon.appiconset/icon_256.png)

# DisplayArranger

DisplayArranger is a minimal macOS menu bar app that lets you quickly change your screen arrangement with a single click.

It’s designed to make switching display layouts fast and effortless, without opening System Settings.

## Features

- Menu bar–only app (no dock icon)
- One-click screen arrangement switching
- Arrange up to 3 additional displays around the main display (drag to any edge of any display, with snapping)
- Shows each display's actual wallpaper in the arrangement view
- Application only visible when 2+ displays are detected
- Extremely lightweight and minimal

## Limitations

- **Supports the main display plus up to 3 additional displays** (any further displays are left untouched)
- The main display stays fixed; other displays are arranged around it
- Wallpapers that can't be read (e.g. dynamic/aerial wallpapers, or files outside the App Sandbox) fall back to the placeholder image

## Intended Use

DisplayArranger is primarily meant for **Sidecar** usage with an iPad.  
It’s useful when you frequently connect and disconnect an iPad and want to quickly restore or modify your preferred display arrangement.

## Requirements

- macOS 13.0+
- Two to four connected displays (including Sidecar)

## Status

This is a very bare-bones utility and may lack error handling or advanced configuration.  
Use at your own risk.

