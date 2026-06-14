# Backward-compatible entry point — delegates to the full rebrand script.
# Usage: powershell -ExecutionPolicy Bypass -File .\rename-to-encorr.ps1
& "$PSScriptRoot\rebrand-to-encorr.ps1" @args
