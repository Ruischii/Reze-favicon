import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../services" as Services

Item {
    id: root
    required property var toplevel
    required property var dockTheme

    implicitWidth: 48
    implicitHeight: 48
    Layout.fillHeight: true

    readonly property string className: toplevel?.appId ?? ""
    // We only try to fetch icons for known browsers to avoid wasting resources
    readonly property bool isBrowser: {
        if (!className) return false;
        const lower = className.toLowerCase();
        return lower.includes("firefox") || 
               lower.includes("chrome") || 
               lower.includes("brave") || 
               lower.includes("chromium") || 
               lower.includes("librewolf") || 
               lower.includes("thorium") || 
               lower.includes("vivaldi") || 
               lower.includes("edge") ||
               lower.includes("waterfox") ||
               lower.includes("mullvad") ||
               lower.includes("tor-browser") ||
               lower.includes("floorp") ||
               lower.includes("zen");
    }

    // React to FaviconService cache changes using cacheCounter
    readonly property string faviconPath: {
        const _ = Services.FaviconService.cacheCounter;
        if (isBrowser && toplevel) {
            return Services.FaviconService.getFavicon(toplevel);
        }
        return "";
    }

    readonly property bool useFavicon: faviconPath !== ""
    
    readonly property var iconSubstitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "zen": "zen-browser",
        "zen-alpha": "zen-browser",
        "Zen": "zen-browser",
        "footclient": "foot",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
    })

    /**
     * Fallback logic for non-browser apps or failed favicon fetches.
     * Tries: Hardcoded map -> Desktop Entry -> Icon Theme Heuristics
     */
    function guessIcon(appId) {
        if (!appId || appId.length === 0) return "application-x-executable";
        if (iconSubstitutions[appId]) return iconSubstitutions[appId];
        if (iconSubstitutions[appId.toLowerCase()]) return iconSubstitutions[appId.toLowerCase()];

        const entry = DesktopEntries.byId(appId);
        if (entry) return entry.icon;

        const lower = appId.toLowerCase();
        if (Quickshell.iconPath(appId, true).length > 0) return appId;
        if (Quickshell.iconPath(lower, true).length > 0) return lower;

        const heuristic = DesktopEntries.heuristicLookup(appId);
        if (heuristic) return heuristic.icon;

        const parts = appId.split('.');
        if (parts.length > 1) {
            const last = parts[parts.length - 1].toLowerCase();
            if (Quickshell.iconPath(last, true).length > 0) return last;
        }

        return "application-x-executable";
    }

    readonly property string systemIcon: guessIcon(className)

    property bool hovered: mouseArea.containsMouse

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (toplevel) toplevel.activate();
        }
    }

    Rectangle {
        id: itemBg
        anchors.fill: parent
        anchors.margins: 3
        radius: 12
        color: hovered ? dockTheme.itemHover : "transparent"
        
        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        scale: hovered ? 1.15 : 1.0
        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutBack }
        }

        Image {
            id: faviconImage
            anchors.centerIn: parent
            width: 28
            height: 28
            visible: useFavicon && status !== Image.Error
            source: useFavicon ? faviconPath : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            cache: false
        }

        IconImage {
            id: sysIcon
            anchors.centerIn: parent
            implicitSize: 28
            visible: !useFavicon || faviconImage.status === Image.Error
            source: Quickshell.iconPath(systemIcon, "application-x-executable")
        }
    }

    Rectangle {
        anchors {
            bottom: itemBg.bottom
            bottomMargin: -2
            horizontalCenter: itemBg.horizontalCenter
        }
        width: (toplevel?.activated ?? false) ? 12 : 6
        height: 3
        radius: 99
        color: (toplevel?.activated ?? false) ? dockTheme.dotActive : dockTheme.dotInactive

        Behavior on width {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: 200 }
        }
    }
}
