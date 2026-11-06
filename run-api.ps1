# MOAI NEXT Mobile - รัน API (Node.js)
Set-Location $PSScriptRoot\api
if (-not (Test-Path node_modules)) { npm install }
node src/index.js
