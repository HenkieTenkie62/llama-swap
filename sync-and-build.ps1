# sync-and-build.ps1
# Windows script dat:
# 1. De repo synct met de fork op GitHub
# 2. Een nieuwe branch maakt met de custom endpoints
# 3. Alles pusht naar GitHub
#
# Gebruik: .\sync-and-build.ps1

$ErrorActionPreference = "Stop"

# Configurable variables
$FORK_REPO = "https://github.com/HenkieTenkie62/llama-swap.git"
$BRANCH_NAME = "custom-endpoints"
$IMAGE_NAME = "llama-swap-custom"
$IMAGE_TAG = "latest"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Sync and Build Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
cd $ScriptDir

# Step 1: Check git status
Write-Host "Step 1: Checking git status..." -ForegroundColor Yellow
$currentBranch = git branch --show-current
Write-Host "  Current branch: $currentBranch"

# Step 2: Create or switch to custom branch
Write-Host ""
Write-Host "Step 2: Creating/switching to '$BRANCH_NAME' branch..." -ForegroundColor Yellow

if (git branch --list $BRANCH_NAME) {
    Write-Host "  Branch exists, switching..." -ForegroundColor Gray
    git checkout $BRANCH_NAME
} else {
    Write-Host "  Creating new branch..." -ForegroundColor Gray
    git checkout -b $BRANCH_NAME
}

# Step 3: Add upstream remote if not exists
Write-Host ""
Write-Host "Step 3: Setting up upstream remote..." -ForegroundColor Yellow
$remotes = git remote -v
if ($remotes -notmatch "upstream") {
    Write-Host "  Adding upstream remote..." -ForegroundColor Gray
    git remote add upstream https://github.com/mostlygeek/llama-swap.git
} else {
    Write-Host "  Upstream remote already exists" -ForegroundColor Gray
}

# Step 4: Fetch from upstream
Write-Host ""
Write-Host "Step 4: Fetching from upstream..." -ForegroundColor Yellow
git fetch upstream

# Step 5: Rebase or merge (optional - user can skip this)
Write-Host ""
Write-Host "Step 5: Rebase from upstream/main? (y/n)" -ForegroundColor Yellow
$rebaseChoice = Read-Host "Enter choice"
if ($rebaseChoice -eq "y" -or $rebaseChoice -eq "Y") {
    Write-Host "  Rebasing from upstream/main..." -ForegroundColor Gray
    try {
        git rebase upstream/main
        Write-Host "  Rebase successful!" -ForegroundColor Green
    } catch {
        Write-Host "  Rebase conflict or aborted. Continuing anyway..." -ForegroundColor Yellow
        git rebase --abort 2>$null
    }
}

# Step 6: Check if custom files exist
Write-Host ""
Write-Host "Step 6: Checking custom endpoint files..." -ForegroundColor Yellow
$customFile = Join-Path $ScriptDir "proxy\proxymanager_custom.go"
$extensionPoint = Get-Content (Join-Path $ScriptDir "proxy\proxymanager.go") -Raw

if (Test-Path $customFile) {
    Write-Host "  ✅ proxymanager_custom.go exists" -ForegroundColor Green
} else {
    Write-Host "  ❌ proxymanager_custom.go NOT found!" -ForegroundColor Red
    Write-Host "  Creating it from template..." -ForegroundColor Yellow
    
    # Create the custom endpoints file
    $customContent = @'
package proxy

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
)

// setupCustomEndpoints registers all custom endpoints.
// This method is called from setupGinEngine() as an extension point.
// Add new endpoints here without touching proxymanager.go
func (pm *ProxyManager) setupCustomEndpoints() {
	// Support custom ASR endpoints
	pm.ginEngine.POST("/asr", pm.apiKeyAuth(), pm.trackInflight(), pm.proxyASRHandler)
	pm.ginEngine.POST("/detect-language", pm.apiKeyAuth(), pm.trackInflight(), pm.proxyDetectLanguageHandler)

	// Support custom Marker-api endpoints
	pm.ginEngine.POST("/marker", pm.apiKeyAuth(), pm.trackInflight(), pm.proxyMarkerHandler)
	pm.ginEngine.POST("/marker/upload", pm.apiKeyAuth(), pm.trackInflight(), pm.proxyMarkerUploadHandler)
}

// proxyASRHandler proxies requests to the ASR model endpoint.
func (pm *ProxyManager) proxyASRHandler(c *gin.Context) {
	pm.proxyToModelPath(c, "asr", "/asr")
}

// proxyDetectLanguageHandler proxies requests to the detect-language endpoint.
func (pm *ProxyManager) proxyDetectLanguageHandler(c *gin.Context) {
	pm.proxyToModelPath(c, "asr", "/detect-language")
}

// proxyMarkerHandler proxies requests to the Marker endpoint.
func (pm *ProxyManager) proxyMarkerHandler(c *gin.Context) {
	pm.proxyToModelPath(c, "marker", "/marker")
}

// proxyMarkerUploadHandler proxies file upload requests to the Marker endpoint.
func (pm *ProxyManager) proxyMarkerUploadHandler(c *gin.Context) {
	pm.proxyToModelPath(c, "marker", "/marker/upload")
}

// proxyToModelPath is a generic helper that swaps in the process group for the
// given model and proxies the request to a specific upstream path.
// It works with both ProcessGroup and Matrix backends.
func (pm *ProxyManager) proxyToModelPath(c *gin.Context, modelID string, upstreamPath string) {
	var handler func(modelID string, w http.ResponseWriter, r *http.Request) error

	if pm.matrix != nil {
		handler = pm.matrix.ProxyRequest
	} else {
		processGroup, err := pm.swapProcessGroup(modelID)
		if err != nil {
			pm.sendErrorResponse(c, http.StatusInternalServerError,
				fmt.Sprintf("error swapping process group for %s: %s", modelID, err.Error()))
			return
		}
		handler = processGroup.ProxyRequest
	}

	// Rewrite the path to the upstream endpoint
	c.Request.URL.Path = upstreamPath

	if err := handler(modelID, c.Writer, c.Request); err != nil {
		pm.sendErrorResponse(c, http.StatusInternalServerError,
			fmt.Sprintf("error proxying request: %s", err.Error()))
		pm.proxyLogger.Errorf("Error Proxying Request for custom endpoint %s -> %s", modelID, upstreamPath)
	}
}
'@
    
    Set-Content -Path $customFile -Value $customContent -NoNewline
    Write-Host "  ✅ Created proxymanager_custom.go" -ForegroundColor Green
}

if ($extensionPoint -match "setupCustomEndpoints") {
    Write-Host "  ✅ Extension point in proxymanager.go" -ForegroundColor Green
} else {
    Write-Host "  ❌ Extension point NOT found in proxymanager.go!" -ForegroundColor Red
    Write-Host "  Adding extension point..." -ForegroundColor Yellow
    
    $pmContent = Get-Content (Join-Path $ScriptDir "proxy\proxymanager.go") -Raw
    $extensionCode = @"

	// ---- CUSTOM EXTENSION POINT ----
	pm.setupCustomEndpoints()
	// --------------------------------
"@
    
    $newContent = $pmContent -replace '(\t*gin\.DisableConsoleColor\(\))', "$extensionCode`n`$1"
    Set-Content -Path (Join-Path $ScriptDir "proxy\proxymanager.go") -Value $newContent -NoNewline
    Write-Host "  ✅ Added extension point" -ForegroundColor Green
}

# Step 7: Stage and commit changes
Write-Host ""
Write-Host "Step 7: Staging and committing changes..." -ForegroundColor Yellow
git add proxy/proxymanager_custom.go
git add proxy/proxymanager.go

$changes = git status --porcelain
if ($changes) {
    git commit -m "feat: add custom endpoints (asr, detect-language, marker) via extension point"
    Write-Host "  ✅ Changes committed" -ForegroundColor Green
} else {
    Write-Host "  ℹ️  No changes to commit" -ForegroundColor Gray
}

# Step 8: Push to fork
Write-Host ""
Write-Host "Step 8: Pushing to fork..." -ForegroundColor Yellow

# Check if origin is set correctly
$originUrl = git remote get-url origin
if ($originUrl -notmatch "HenkieTenkie62") {
    Write-Host "  Setting origin to your fork..." -ForegroundColor Gray
    git remote set-url origin $FORK_REPO
}

# Force push (needed after rebase)
git push --force-with-lease origin $BRANCH_NAME
Write-Host "  ✅ Pushed to fork!" -ForegroundColor Green

# Step 9: Build summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Sync and Build Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Branch: $BRANCH_NAME" -ForegroundColor Green
Write-Host "Fork: $FORK_REPO" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps on Linux:" -ForegroundColor Yellow
Write-Host "  1. git clone $FORK_REPO" -ForegroundColor Gray
Write-Host "  2. git checkout $BRANCH_NAME" -ForegroundColor Gray
Write-Host "  3. ./build-and-docker.sh" -ForegroundColor Gray
Write-Host ""
Write-Host "Or build locally on Windows (requires Go):" -ForegroundColor Yellow
Write-Host "  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o llama-swap-linux-amd64 ." -ForegroundColor Gray
Write-Host ""