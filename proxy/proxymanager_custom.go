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
