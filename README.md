# Flat Field for KOReader

Turn an e-reader’s screen into a white flat-field panel with adjustable frontlight brightness. A small toolbar at the top contains an **Exit** button, a brightness slider, and a percentage readout; the rest of the screen stays white.

## Features

- Performs a full black refresh followed by a full white refresh when opened to reduce ghosting.
- Adjusts frontlight brightness by tapping or dragging the slider.
- Refreshes only the toolbar when brightness changes, leaving the white area untouched.
- Starts at the current brightness and restores it when the panel closes.
- Prevents low-power standby while open, when supported by KOReader.
- Opens from either the file browser or the reader, without requiring an open book.

## Requirements

- KOReader running on a device with a controllable frontlight.
- A touchscreen for the slider and Exit button.

The plugin checks whether the device reports a frontlight before opening. If it does not, KOReader displays a message instead of the panel.

## Installation

1. Copy the `flatfield.koplugin` folder into your KOReader installation’s `plugins` directory.
2. Make sure the Lua files are directly inside that folder:

   ```text
   koreader/
   └── plugins/
       └── flatfield.koplugin/
           ├── _meta.lua
           └── main.lua
   ```

3. Restart KOReader. If the plugin is disabled, enable **Flat Field** in KOReader’s plugin management menu and restart if prompted.

If downloading a repository archive, rename the extracted folder to `flatfield.koplugin` before copying it.

## Usage

1. Open KOReader’s main menu and select **Flat field panel** in the tools section.
2. The screen briefly flashes black before displaying the white panel.
3. Tap or drag the brightness slider.
4. Tap **Exit** to return to KOReader and restore the previous brightness.

The percentage represents the position within the device’s supported brightness range, rather than a measured light output. Taps outside the controls are consumed by the panel.

## Development checks

Run `luajit tests/test_flatfield.lua` from the plugin folder to check slider gestures, refresh regions, brightness restoration, and toolbar geometry with stubbed KOReader services. Device testing is still needed to assess actual e-ink refresh speed.

## Limitations

- Standby prevention uses KOReader’s optional standby API; the plugin does not explicitly disable automatic suspend or power-off timers.
- I only own a Kindle (11th Generation) - 2024 Release so I can't test features my model doesn't support.
    - Ex: The slider controls brightness only, not frontlight warmth or color temperature.
