# Bose Mute-Toggle

Mute and unmute your microphone in Microsoft Teams with a swipe on your headphones' volume control. No hotkey or mouse needed.

Built for the **Bose QuietComfort Ultra (2nd gen)**, which has no dedicated mute button. Other Bluetooth headphones should work too (see [Other headphones](#other-headphones)).

## How it works

Swipe the volume **up and then down**, or **down and then up**, within about a second. The script then:

1. sends `Win+Alt+K` (the Windows mic mute shortcut that Teams supports) to toggle mute,
2. sets the volume back to where it was before the gesture,
3. plays a short tone in your headphones:
   - **high → low**: muted
   - **low → high**: unmuted

It watches the headphones' volume level through the Windows Core Audio API. Nothing is installed and no drivers are needed, just a single PowerShell script.

## Requirements

- Windows 10 or 11 (Windows PowerShell 5.1, which comes with Windows)
- Headphones connected via Bluetooth
- Microsoft Teams, or another app that reacts to `Win+Alt+K`

## Usage

1. Download or clone this repository.
2. Double-click **`bose-mute-toggle.cmd`**.
3. Leave the console window open. Close it to quit.

The script waits for the headphones to connect and reconnects on its own if they disconnect.

> **Note:** The script assumes your mic is **not muted** when it starts. If you mute or unmute in Teams some other way (mouse click, `Ctrl+Shift+M`), the tones will be reversed until you restart the script. Muting itself still works.

### Start automatically with Windows

Press `Win+R`, type `shell:startup`, and put a shortcut to `bose-mute-toggle.cmd` in that folder.

## Options

You can pass these parameters when running the script directly:

| Parameter          | Default | Description                                                                 |
|--------------------|---------|-----------------------------------------------------------------------------|
| `-DeviceMatch`     | `Bose`  | Part of the audio device name (regular expression)                         |
| `-SwipeGapMs`      | `250`   | Volume steps closer together than this count as one swipe                   |
| `-GestureWindowMs` | `1000`  | Maximum pause between the two swipes of a gesture                           |

Example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File bose-mute-toggle.ps1 -GestureWindowMs 1500
```

To change the defaults for the double-click launcher, add the parameters to the line in `bose-mute-toggle.cmd`.

### Other headphones

Set `-DeviceMatch` to part of your headphones' name as it appears under *Settings → System → Sound*, for example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File bose-mute-toggle.ps1 -DeviceMatch "WH-1000XM5"
```

This only works if the headphones' volume control changes the Windows volume (absolute volume over Bluetooth). Most current headphones do this.

## Limitations

- **At 0 % or 100 % volume** a swipe past the limit does not change the volume, so the gesture is not detected. Start the gesture in the other direction instead.
- **Accidental triggers:** if you overshoot while adjusting the volume and quickly correct it, that looks like the gesture and toggles mute.
- The mute state is tracked by the script and is not read from Teams (see the note above).
