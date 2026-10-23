# Keeps the user's PC usable while sessions work: every few seconds, puts every Godot, Blender
# and Python process on idle priority and on the first 4 logical cores only (about 25% of the CPU).
# Windowed Godot (the user playing the game) is left alone.
# Run once in the background:  powershell -NoProfile -File tools/pc_guard.ps1
$mask = [IntPtr]0xF
while ($true) {
    Get-Process Godot*, blender*, python* -ErrorAction SilentlyContinue | Where-Object { -not ($_.Name -like 'Godot*' -and $_.MainWindowHandle -ne 0) } | ForEach-Object {
        try {
            if ($_.PriorityClass -ne 'Idle') { $_.PriorityClass = 'Idle' }
            if ($_.ProcessorAffinity -ne $mask) { $_.ProcessorAffinity = $mask }
        } catch {}
    }
    Start-Sleep -Seconds 5
}
