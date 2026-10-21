# Bose QC Ultra 2: volume swipe gesture (up->down or down->up) toggles Teams mute via Win+Alt+K.
# Volume is restored to its value before the gesture afterwards.
param(
  [string]$DeviceMatch = 'Bose',
  [int]$SwipeGapMs = 250,     # steps closer together than this belong to the same swipe
  [int]$GestureWindowMs = 1000 # max pause between the two swipes
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
  int NotImpl1();
  int NotImpl2();
  int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice dev);
}
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
  int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
}
[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
  int f1(); int f2(); int f3(); int f4();
  int SetMasterVolumeLevelScalar(float v, IntPtr ctx);
  int f6();
  int GetMasterVolumeLevelScalar(out float v);
}
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
public static class BoseVol {
  public static object Open(string id) {
    var e = (IMMDeviceEnumerator)new MMDeviceEnumerator();
    IMMDevice d; if (e.GetDevice(id, out d) != 0 || d == null) return null;
    Guid iid = typeof(IAudioEndpointVolume).GUID; object o;
    return d.Activate(ref iid, 23, IntPtr.Zero, out o) == 0 ? o : null;
  }
  public static float Get(object o) { float f; Marshal.ThrowExceptionForHR(((IAudioEndpointVolume)o).GetMasterVolumeLevelScalar(out f)); return f; }
  public static void Set(object o, float f) { ((IAudioEndpointVolume)o).SetMasterVolumeLevelScalar(f, IntPtr.Zero); }

  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static void SendWinAltK() {
    const uint UP = 2;
    keybd_event(0x5B, 0, 0, UIntPtr.Zero);  // LWin
    keybd_event(0x12, 0, 0, UIntPtr.Zero);  // Alt
    keybd_event(0x4B, 0, 0, UIntPtr.Zero);  // K
    keybd_event(0x4B, 0, UP, UIntPtr.Zero);
    keybd_event(0x12, 0, UP, UIntPtr.Zero);
    keybd_event(0x5B, 0, UP, UIntPtr.Zero);
  }
}
"@

function Open-BoseOutput {
  $ep = Get-PnpDevice -PresentOnly -Class AudioEndpoint -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -eq 'OK' -and $_.FriendlyName -match $DeviceMatch -and $_.FriendlyName -notmatch 'Hands-Free' -and $_.InstanceId -like '*{0.0.0.*' } |
    Select-Object -First 1
  if ($ep) { [BoseVol]::Open(($ep.InstanceId -replace '^SWD\\MMDEVAPI\\', '')) }
}

function Log($msg) { "{0:HH:mm:ss}  {1}" -f (Get-Date), $msg }

# Builds a short WAV tone sequence (frequencies in Hz) as a playable SoundPlayer
function New-Tone([int[]]$Freqs, [int]$NoteMs = 90) {
  $rate = 44100; $n = [int]($rate * $NoteMs / 1000)
  $samples = New-Object System.Collections.Generic.List[int16]
  foreach ($f in $Freqs) {
    for ($i = 0; $i -lt $n; $i++) {
      $env = [math]::Min(1, [math]::Min($i, $n - $i) / ($rate * 0.01))  # 10 ms fade in/out to avoid clicks
      $samples.Add([int16](9000 * $env * [math]::Sin(2 * [math]::PI * $f * $i / $rate)))
    }
  }
  $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
  $data = $samples.Count * 2
  $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $data))
  $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1)
  $w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
  $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$data)
  foreach ($s in $samples) { $w.Write($s) }
  $ms.Position = 0
  $p = New-Object System.Media.SoundPlayer $ms; $p.Load(); $p
}
$toneMuted = New-Tone 880, 440    # high -> low
$toneUnmuted = New-Tone 440, 880  # low -> high
$muted = $false  # assumption: not muted at startup

$vol = $null
$prev = $null
$swipe = $null      # current swipe: @{ Dir; Start; End; From }
$lastSwipe = $null  # previous completed swipe
$ignoreUntil = [datetime]::MinValue

Log "Bose Mute-Toggle running. Gesture: volume up->down or down->up. Press Ctrl+C to quit."
Log "Assuming mic is NOT muted at startup. Tone high->low = muted, low->high = unmuted."
while ($true) {
  try {
    if (-not $vol) {
      $vol = Open-BoseOutput
      if (-not $vol) { Start-Sleep -Seconds 3; continue }
      $prev = [BoseVol]::Get($vol)
      Log "Headphones found ($([math]::Round($prev * 100))%)."
    }
    $now = Get-Date
    $cur = [BoseVol]::Get($vol)

    if ($now -lt $ignoreUntil) { $prev = $cur; Start-Sleep -Milliseconds 30; continue }

    # Finish the current swipe once no more steps arrive
    if ($swipe -and ($now - $swipe.End).TotalMilliseconds -gt $SwipeGapMs) {
      if ($lastSwipe -and $lastSwipe.Dir -ne $swipe.Dir -and
          ($swipe.Start - $lastSwipe.End).TotalMilliseconds -le $GestureWindowMs) {
        [BoseVol]::SendWinAltK()
        [BoseVol]::Set($vol, $lastSwipe.From)
        $ignoreUntil = $now.AddMilliseconds(300)
        $muted = -not $muted
        if ($muted) { $toneMuted.Play() } else { $toneUnmuted.Play() }
        Log "Gesture detected -> $(if ($muted) { 'MUTED' } else { 'unmuted' }), volume restored to $([math]::Round($lastSwipe.From * 100))%."
        $lastSwipe = $null
      } else {
        $lastSwipe = $swipe
      }
      $swipe = $null
    }

    if ([math]::Abs($cur - $prev) -gt 0.005) {
      $dir = [math]::Sign($cur - $prev)
      if ($swipe -and $swipe.Dir -eq $dir) {
        $swipe.End = $now
      } else {
        if ($swipe) { $lastSwipe = $swipe }  # direction change without a pause
        $swipe = @{ Dir = $dir; Start = $now; End = $now; From = $prev }
      }
      $prev = $cur
    }
    Start-Sleep -Milliseconds 30
  } catch {
    if ($vol) { Log "Headphones disconnected, waiting for connection..." }
    $vol = $null; $swipe = $null; $lastSwipe = $null
    Start-Sleep -Seconds 3
  }
}
