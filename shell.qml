// Entry point for the Quickshell Favicon snippet.
// This file initializes the environment and loads the main dock component.

//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1

import "./components"
import QtQuick
import Quickshell

ShellRoot {
    FaviconDock {}
}
