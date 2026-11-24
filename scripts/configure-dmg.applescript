-- Set Finder's persistent view metadata; the icons remain real draggable files.
on run arguments
    set mountPath to item 1 of arguments
    set backgroundFile to (POSIX file (mountPath & "/.background/background.png")) as alias
    tell application "Finder"
        set volumeFolder to (POSIX file mountPath) as alias
        open volumeFolder
        delay 1
        set installWindow to window (name of volumeFolder)
        set current view of installWindow to icon view
        set toolbar visible of installWindow to false
        set statusbar visible of installWindow to false
        set bounds of installWindow to {120, 120, 720, 548}
        set options to icon view options of installWindow
        set arrangement of options to not arranged
        set icon size of options to 128
        set text size of options to 12
        set label position of options to bottom
        set shows item info of options to false
        set shows icon preview of options to true
        set background picture of options to backgroundFile
        set position of item "Loom.app" of installWindow to {155, 171}
        set position of item "Applications" of installWindow to {449, 171}
        update volumeFolder without registering applications
        delay 2
        close installWindow
        delay 2
    end tell
end run
