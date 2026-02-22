pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import QtCore

Singleton {
    id: root
    
    // ─── Where things live ───────────────────────────
    readonly property string homeDir: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "").replace(/\/$/, "")
    // Update this if you want to cache icons somewhere else (CHANGE IN favicon_bridge.py TOO!)
    readonly property string rawCacheDir: homeDir + "/.cache/quickshell/favicons"
    // We use Qt.resolvedUrl so we don't have to worry about where the project is moved
    readonly property string shellDir: Qt.resolvedUrl("..").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string bridgePath: rawCacheDir + "/exact_title_to_url.json"
    
    Component.onCompleted: {
        loadBridge();    // Load what we already know
        startupScan();   // See what icons we already have in cache
        triggerBridge(); // Go grab the latest browser history
        
        // Keep the browser history fresh so new tabs get icons quickly
        bridgeRefreshTimer.running = true;
    }
    
    Timer {
        id: bridgeRefreshTimer
        interval: 5000 // Refresh every 5 seconds. Change this if you feel it making your memory usage go up.
        repeat: true
        onTriggered: {
            triggerBridge();
            
            // Self-healing: If a download gets stuck, clear it after 40 seconds
            const now = Date.now();
            let newDown = Object.assign({}, root.downloading);
            let changed = false;
            for (const d in newDown) {
                if (now - newDown[d] > 40000) { delete newDown[d]; changed = true; }
            }
            if (changed) root.downloading = newDown;
            
            // Give failed domains another chance after 30 seconds
            let newFailed = Object.assign({}, root.failedDomains);
            let failChanged = false;
            for (const d in newFailed) {
                if (now - newFailed[d] > 30000) { delete newFailed[d]; failChanged = true; }
            }
            if (failChanged) root.failedDomains = newFailed;
        }
    }
    
    property var readyDomains: ({})  // The "I have this icon" list
    property var urlMap: ({})        // The "This title = This URL" dictionary
    property var downloading: ({})   // Keep track of what we're currently fetching
    property var failedDomains: ({}) // Let's not bang our head against a wall if a site is down
    property int cacheCounter: 0     // A little poke to tell the UI to refresh
 
    // High-quality icons we shipped in assets/google/
    readonly property var officialDomains: [
        "mail.google.com", "calendar.google.com", "drive.google.com", 
        "docs.google.com", "sheets.google.com", "slides.google.com",
        "meet.google.com", "maps.google.com", "gemini.google.com",
        "youtube.com", "aistudio.google.com", "notebooklm.google.com",
        "photos.google.com", "m3.material.io"
    ]

    signal faviconDownloaded(string domain)

    /**
     * The magic function that finds your icons!
     * It tries a few tricks in order:
     * 1. History: Did you visit this site? We probably mapped it.
     * 2. Regex: Does the window title basically look like a website?
     * 3. Branding: Is it a famous service like "Gmail"?
     * 4. Downloader: If we know the domain but have no icon, so it will snatch it from the web.
     */
    function getFavicon(window) {
        if (!window || !window.title) return "";
        
        const title = window.title;
        const cleanRef = cleanTitle(title);
        
        // Tier 1: Look at the browser history we scanned earlier (Best accuracy!)
        let fullUrl = root.urlMap[cleanRef];
        let domain = "";
        
        if (fullUrl) {
            domain = extractDomain(fullUrl);
        } else {
            // Tier 2: Try to guess the domain from the title (e.g. "github.com")
            // WARNING/NOTE: This is where "hallucinations" happen if a title 
            // has a word that looks like a domain but isn't.
            // This used happen to me where I used my workplace "email site" it uses Gmail's icon.
            domain = extractDomainFromTitle(cleanRef);
        }

        // Tier 3: Use the high-quality icons we shipped with for famous services
        if (!domain || domain === "google.com") {
            const keywords = {
                "Gmail": "mail.google.com",
                "Inbox": "mail.google.com",
                "Google Calendar": "calendar.google.com",
                "Calendar": "calendar.google.com",
                "Google Drive": "drive.google.com",
                "Drive": "drive.google.com",
                "Google Docs": "docs.google.com",
                "Google Sheets": "sheets.google.com",
                "Google Slides": "slides.google.com",
                "Google Meet": "meet.google.com",
                "Google Maps": "maps.google.com",
                "Gemini": "gemini.google.com",
                "YouTube": "youtube.com",
                "Google AI Studio": "aistudio.google.com",
                "NotebookLM": "notebooklm.google.com",
                "Google Photos": "photos.google.com",
                "Material 3": "m3.material.io"
            };

            const lowerTitle = cleanRef.toLowerCase();
            for (const kw in keywords) {
                if (lowerTitle.includes(kw.toLowerCase())) {
                    domain = keywords[kw];
                    break;
                }
            }
        }

        // If we still don't have a domain here, we give up
        if (!domain) return "";

        // Clean up common aliases to use our official icons
        if (domain === "gmail.com") domain = "mail.google.com";
        if (domain === "gemini.ai") domain = "gemini.google.com";
        
        // Priority 1: Check if we have an "Official" high-quality icon
        const officialPath = "file://" + shellDir + "/assets/google/" + domain + ".png";
        if (readyDomains[domain + "_official"] || root.officialDomains.includes(domain)) {
             return officialPath;
        }

        // Priority 2: Use the downloaded icon if we have one
        if (readyDomains[domain]) {
            const ext = readyDomains[domain + "_svg"] ? ".svg" : ".png";
            return "file://" + rawCacheDir + "/" + domain + ext;
        }
        
        // Priority 3: If we have a domain but no icon, go pull it from the web
        if (!downloading[domain] && !failedDomains[domain] && !root.officialDomains.includes(domain)) {
            downloadFavicon(domain, fullUrl);
        }

        // Bonus: If it's a subdomain, try the main domain icon (e.g. blog.github.com -> github.com)
        const parts = domain.split(".");
        if (parts.length > 2) {
            const parent = parts.slice(-2).join(".");
            if (parent !== domain && (readyDomains[parent] || readyDomains[parent + "_official"])) {
                if (readyDomains[parent + "_official"]) return "file://" + shellDir + "/assets/google/" + parent + ".png";
                const parentExt = readyDomains[parent + "_svg"] ? ".svg" : ".png";
                return "file://" + rawCacheDir + "/" + parent + parentExt;
            }
        }
        
        return "";
    }

    // Strip browser names and clutter from window titles
    function cleanTitle(title) {
        if (!title) return "";
        return title.replace(/\s*[-|—|·]\s*(Mozilla Firefox|Brave|Google Chrome|Chromium|Vivaldi|Edge|Zen|Floorp|LibreWolf|Thorium|Waterfox|Mullvad|Tor Browser|Chrome|Firefox|Web Browser|Browser|Quickshell|Antigravity)\s*$/i, "").trim();
    }

    // Grab "example.com" from "https://www.example.com/page"
    function extractDomain(url) {
        if (!url) return "";
        const match = url.match(/https?:\/\/(?:www\.)?([^\/]+)/i);
        return match ? match[1].toLowerCase() : "";
    }

    // Look for things like "github.com" or "user/repo" in a title
    function extractDomainFromTitle(cleanTitle) {
        // Special case for GitHub "user/repo" style titles
        // In Brave, it will show "user/repo" in the title only. I don't know why
        if (/^[\w][\w.-]*\/[\w][\w.-]+([\s:]|$)/.test(cleanTitle)) {
            return "github.com";
        }
        
        // Look for anything that looks like a domain name
        const domainMatch = cleanTitle.match(/(?:https?:\/\/)?(?:www\.)?([a-z0-9-]{2,})\.([a-z]{2,3}(\.[a-z]{2})?|land|nz|ai|io|ly|so|me|dev|app|info|xyz|icu|top|site|online)/i);
        if (domainMatch) {
            return (domainMatch[1] + "." + domainMatch[2]).toLowerCase();
        }
        return "";
    }

    // Start the background process to download an icon
    function downloadFavicon(domain, scrapeUrl) {
        if (downloading[domain]) return;
        let newDown = Object.assign({}, root.downloading);
        newDown[domain] = Date.now();
        root.downloading = newDown;
        
        // The reason the directory is like this, so it would look organized for your shell
        const scriptPath = shellDir + "/scripts/favicons/download_favicon.sh"; // You may change as the way you want
        const targetUrl = scrapeUrl || "";
        
        const download = downloadProcess.createObject(null, {
            command: ["bash", scriptPath, domain, rawCacheDir, targetUrl]
        });
        
        download.onExited.connect((exitCode, exitStatus) => {
            if (exitCode === 0) {
                updateReady(domain);
            } else {
                let newDown = Object.assign({}, root.downloading);
                delete newDown[domain];
                root.downloading = newDown;
                let newFailed = Object.assign({}, root.failedDomains);
                newFailed[domain] = Date.now();
                root.failedDomains = newFailed;
            }
            download.destroy();
        });
        download.running = true;
    }

    // Check what format we got (PNG vs SVG) and update the list
    function updateReady(domain) {
        const checkSvg = checkProcess.createObject(null, {
            command: ["bash", "-c", `[ -f "${rawCacheDir}/${domain}.svg" ] && echo svg || echo png`]
        });
        checkSvg.stdout.onStreamFinished.connect(() => {
            const format = checkSvg.stdout.text.trim();
            let newReady = Object.assign({}, root.readyDomains);
            newReady[domain] = true;
            if (format === "svg") {
                newReady[domain + "_svg"] = true;
            }
            root.readyDomains = newReady;
            
            let newDown = Object.assign({}, root.downloading);
            delete newDown[domain];
            root.downloading = newDown;
            
            root.cacheCounter++; // Poke!
            root.faviconDownloaded(domain);
            checkSvg.destroy();
        });
        checkSvg.running = true;
    }

    // Read the title->URL map file generated by the Python script
    function loadBridge() {
        if (bridgePath === "") return;
        const check = checkProcess.createObject(null, {
            command: ["bash", "-c", `[ -f "${bridgePath}" ] && echo yes || echo no`]
        });
        check.stdout.onStreamFinished.connect(() => {
            if (check.stdout.text.trim() !== "yes") {
                check.destroy();
                return;
            }
            const reader = readFileProcess.createObject(null, {
                path: bridgePath
            });
            reader.onTextChanged.connect(() => {
                try {
                    const raw = reader.text();
                    root.urlMap = JSON.parse(raw);
                } catch(e) {}
            });
            check.destroy();
        });
        check.running = true;
    }

    // Clean up old crap and see what's currently in the cache
    function startupScan() {
        const cleanup = cleanupProcess.createObject(null, {
            command: ["bash", "-c", `find "${rawCacheDir}" -name "*.png" -not -name ".tmp_*" -type f | while read f; do head -c 5 "$f" | grep -qiE "^(<svg|<\\?xml)" && rm -f "$f" && continue; fsize=$(stat -c%s "$f" 2>/dev/null || echo 0); [ "$fsize" -le 400 ] && rm -f "$f"; done; for d in mail.google.com calendar.google.com drive.google.com docs.google.com sheets.google.com slides.google.com meet.google.com maps.google.com gemini.google.com youtube.com aistudio.google.com notebooklm.google.com photos.google.com m3.material.io; do rm -f "${rawCacheDir}/$d.png"; done`]
        });
        cleanup.onExited.connect(() => {
            const scan = scanProcess.createObject(null, {
                command: ["bash", "-c", `ls "${rawCacheDir}" 2>/dev/null; echo "---OFFICIAL---"; ls "${shellDir}/assets/google" 2>/dev/null`]
            });
            scan.stdout.onStreamFinished.connect(() => {
                const output = scan.stdout.text.trim();
                if (!output) return;
                
                const lines = output.split("\n");
                let temp = {};
                let isOfficial = false;
                for (const line of lines) {
                    const f = line.trim();
                    if (!f) continue;
                    if (f === "---OFFICIAL---") {
                        isOfficial = true;
                        continue;
                    }
                    if (f.endsWith(".png") && f.length > 4) {
                        const domain = f.replace(".png", "");
                        temp[isOfficial ? domain + "_official" : domain] = true;
                    } else if (!isOfficial && f.endsWith(".svg") && f.length > 4) {
                        const domain = f.replace(".svg", "");
                        temp[domain] = true;
                        temp[domain + "_svg"] = true; 
                    }
                }
                root.readyDomains = temp;
                root.cacheCounter++;
            });
            scan.running = true;
        });
        cleanup.running = true;
    }

    // Fire off the Python script to scan browser history
    function triggerBridge() {
        const bridge = bridgeProcess.createObject(null, {
            command: ["python3", shellDir + "/scripts/favicons/favicon_bridge.py"] // Change this directory also if you did change the download_favicon.sh directory to make things organized
        });
        bridge.onExited.connect(() => {
            loadBridge();
        });
        bridge.running = true;
    }

    Component { id: downloadProcess; Process { stdout: StdioCollector {} } }
    Component { id: scanProcess; Process { stdout: StdioCollector {} } }
    Component { id: cleanupProcess; Process {} }
    Component { id: bridgeProcess; Process {} }
    Component { id: checkProcess; Process { stdout: StdioCollector {} } }
    Component { id: readFileProcess; FileView {} }
}
