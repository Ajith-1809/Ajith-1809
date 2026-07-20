# Create a fixed version of the script
$scriptPath = "E:\webtech\projects\btc\ff\build\packaging\ff_master_fixed.sh"
$fixedScriptPath = "E:\webtech\projects\btc\ff\build\packaging\ff_master_fixed_final.sh"

# Read the current script
$originalScript = Get-Content $scriptPath -Raw

# Find the sus_maps.txt section and add processing logic
# The pattern is looking for: cat > $SUSFS_DIR/sus_maps.txt << EOF
$pattern = 'cat > \$SUSFS_DIR/sus_maps.txt << EOF'

# Split into lines
$lines = $originalScript -split "`n"
$modifiedLines = @()
$inSusMapSection = $false

foreach ($line in $lines) {
    $modifiedLines += $line

    # Check if we're starting the sus_maps.txt section
    if ($line -match $pattern) {
        $inSusMapSection = $true
    }

    # Check if we're at the EOF marker for sus_maps.txt
    if ($inSusMapSection -and $line.Trim() -eq "EOF") {
        # Add processing logic here
        $modifiedLines += ""
        $modifiedLines += "  # Process sus_maps.txt settings"
        $modifiedLines += "  if [ -f \"$SUSFS_DIR/sus_maps.txt\" ]; then"
        $modifiedLines += "    while IFS= read -r map_path; do"
        $modifiedLines += "      [ -z \"$map_path\" ] && continue"
        $modifiedLines += "      case \"$map_path\" in"
        $modifiedLines += "        #*) continue ;;"
        $modifiedLines += "        *) ksu_susfs add_sus_maps \"$map_path\" 2>/dev/null ;;
        esac"
        $modifiedLines += "    done < \"$SUSFS_DIR/sus_maps.txt\""
        $modifiedLines += "  fi"
        $inSusMapSection = $false
    }
}

# Write the fixed script
$fixedScript = $modifiedLines -join "`n"
Set-Content -Path $fixedScriptPath -Value $fixedScript -Encoding UTF8

Write-Host "Created fixed script: $fixedScriptPath"
Write-Host "Note: You may need to verify the syntax of the added sus_maps processing logic.")