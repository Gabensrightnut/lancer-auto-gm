# Runs heavy jobs (e.g. TripoSG image-to-3D) only when nothing else is happening on the user's PC:
# no keyboard/mouse input for 10 minutes, the game isn't open, and no session holds the GPU lock.
# Jobs are lines in local/idle_queue.txt (bash commands run from the repo root, one per line,
# '#' for comments). Each job is taken off the queue before it runs, runs through
# tools/gpu_lock.sh, and is logged to local/idle_runner.log and local/idle_done.txt.
# Run once in the background:  powershell -NoProfile -WindowStyle Hidden -File tools/idle_runner.ps1
$root = Split-Path -Parent $PSScriptRoot
$local = Join-Path $root 'local'
$queue = Join-Path $local 'idle_queue.txt'
$bash = 'C:\Program Files\Git\bin\bash.exe'
$idleNeeded = 600

Add-Type @'
using System; using System.Runtime.InteropServices;
public static class UserIdle {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint Seconds() {
        LASTINPUTINFO i = new LASTINPUTINFO(); i.cbSize = (uint)Marshal.SizeOf(i);
        GetLastInputInfo(ref i);
        return ((uint)Environment.TickCount - i.dwTime) / 1000;
    }
}
'@

while ($true) {
    Start-Sleep -Seconds 60
    if (-not (Test-Path $queue)) { continue }
    $lines = @(Get-Content $queue | Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') })
    if ($lines.Count -eq 0) { continue }
    if ([UserIdle]::Seconds() -lt $idleNeeded) { continue }
    if (Get-Process Godot* -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) { continue }
    if (Test-Path (Join-Path $local 'gpu.lock')) { continue }
    $job = $lines[0]
    $rest = @(Get-Content $queue | Where-Object { $_ -ne $job })
    [IO.File]::WriteAllLines($queue, [string[]]$rest)
    $script = Join-Path $local 'idle_job.sh'
    [IO.File]::WriteAllText($script, "cd '$($root -replace '\\','/')' && $job`n")
    Add-Content (Join-Path $local 'idle_runner.log') "== $(Get-Date -Format s) $job"
    & $bash "$($root -replace '\\','/')/tools/gpu_lock.sh" run idle -- bash ($script -replace '\\','/') *>> (Join-Path $local 'idle_runner.log')
    Add-Content (Join-Path $local 'idle_done.txt') "$(Get-Date -Format s) exit=$LASTEXITCODE $job"
}
