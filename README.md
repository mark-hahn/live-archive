# Live-Archive package for the Atom editor

### Archives project files continuously with easy review of old versions.

This project can be found at [https://github.com/mark-hahn/live-archive](https://github.com/mark-hahn/live-archive).

### Description

  When Live Archive is enabled for a project then every save on every file will add that version to an archive.  This happens transparently in the background with no noticeable delay (unless you can perceive 10 ms).  The archive is highly compressed.  The biggest source file in this package has 130 versions stored in an archive file smaller than the actual source file.
  
  Later, when that file is open in the Atom editor, the `live-archive:open` command will open up a matching tab that allows fast and easy access to all versions in the archive. This history can be navigated using a number of methods, like clicking on VCR-like buttons, text searching through time, and more.
  
  When viewing a version, all Atom features like syntax highlighting and `Find` are available since it is a normal editing tab.  Plus the changes in that version can be highlighted with colored markers.
  
  There is one especially powerful feature.  You can enable an option to keep the screen focused on one block of text.  When going through time it only shows versions with changes to that block.

### Features

- Archive
  - For simplicity all versions are kept forever
  - Archive is highly compressed
    - Text differencing
    - Bit-level binary archive format
    - Text compressed with zlib
  - All files for project archived in single folder

- Fast Review
    - Ram-based index allows quick search
    - Difference scanning is bi-directional (2X speedup)
    - Bases (entire text versions) interspersed through archive

- Simple UI
  - No settings
  - Saving is transparent
  - Confidence indicator in status bar shows actions
  - Review pane is at bottom of editor pane like find-and-replace

- Reliable (virtually crash-proof)
  - All version saves are append-only in a single write
  - Archive can be backed up while in use

### Installation 

- Search for live-archive package in settings
- or type `apm install live-archive` in command line

### Operation 
  You can open the history tab by pressing `ctrl-alt-A`, using `ctrl-shift-P`, the packages menu, the right-click context menu, or clicking on the `Archive` indicator in the workspace status bar.
  
  When executing this command the first time in a project, a dialog will ask you if you wish to enable Live-Archive by creating the folder `.live-archive` in the project root.  This folder enables everything and includes all archive files in a directory structure mirroring the project's structure.
  
### User Interface

  ![Tabs](https://github.com/mark-hahn/live-archive/blob/master/screenshots/tabs.jpg?raw=true)
  
  The historical views appear in a single new tab. The name of the tab is the same as the original except that `<-` is prepended. This tab is not an editor for a real file. 
  
---

  ![Edit Warning](https://github.com/mark-hahn/live-archive/blob/master/screenshots/edit-history-warning.jpg?raw=true)
  
  Editing (changing) the historical version is not recommended as it may rip a hole in the fabric of space-time, as many science fiction books will tell you.  However, as you can see in the warning, the `Edit` button allows editing for temporary purposes. If you make changes and close the tab the changes will be lost with no further warning. (Secret hint:  You can save an edited version using `Save As`.)  The `Source` button is very useful.  It takes you back to the original source with the cursor positioned at the place you tried to edit.
  
---

  ![Atom Status Bar](https://github.com/mark-hahn/live-archive/blob/master/screenshots/atom-status-bar.jpg?raw=true)

  When Live-Archive is installed the word `Archive` appears in the workspace status bar below all tabs.  This can be clicked to open the historical view.  It also acts as a confidence indicator as it flashes green on every save.  I promise you it isn't annoying.
  
--- 

  ![Live Archive Status Bar](https://github.com/mark-hahn/live-archive/blob/master/screenshots/status-bar.jpg?raw=true)

  Below the historical text is a Live-Archive status bar that give details about the version being shown.
  
---

  Under the status bar is a control bar that contains buttons, toggles, and one text field.  I'll go over the parts of the bar one at a time ...
  
---

  ![Source Buttons](https://github.com/mark-hahn/live-archive/blob/master/screenshots/source-buttons.jpg?raw=true)

  The first two buttons relate to the original source file.  Like the button in the edit warning, `Source` will switch tabs and take you to the same position in the source file, even if it has to open a tab.  The `Revert` button replaces the contents of the source file tab with the historical text in the tab showing.  This isn't as dangerous as it may seem because you may use `Undo` in the source tab after reverting.
  
---

  ![Navigation Buttons](https://github.com/mark-hahn/live-archive/blob/master/screenshots/nav-buttons.jpg?raw=true)

  This is the main bar for navigating through time.  There are the normal VCR-like controls including `<<` and `>>` which hop through multiple versions.  (For the geeks among you they hop a number of versions equal to the square root of the total number of versions.)  
  
  The `Git` button takes you to the version matching the git head version.  There are situations where this version doesn't exist in which case you will see `Not Found` in the status bar.
  
  The `Diff` button is a bit complex but awesome feature.  When this button is toggled on, the currently visible section of text will be locked in place and navigation will show only versions that show a change in that text.  So you can easily see the history of one block of text.
  
---

  ![Difference Buttons](https://github.com/mark-hahn/live-archive/blob/master/screenshots/diff-buttons.jpg?raw=true)

  Toggling on the Hilite button will cause differences between neighboring versions to be highlighted.  Inserts are green and deletes are red.  See the image below.  The `^` and `v` buttons let you navigate the highlights in one version like a normal text find.
  
  The `Scrl` button, when toggled on, will cause the text to scroll vertically when navigating time so that a highlighted change is always showing.  This is useful for quickly remembering the versions.  See the section below titled "Scrolling".
  
  The delete highlights may seem to be on the wrong version at first.  See the section "Differences Quirk" below.
  
  Sample highlights ...
  
  ![Highlights](https://github.com/mark-hahn/live-archive/blob/master/screenshots/highlights.jpg?raw=true)

---

  ![Search](https://github.com/mark-hahn/live-archive/blob/master/screenshots/search-form.jpg?raw=true)

  The search box lets you search for a text string through time.  Entering a string and clicking on `<` or `>` will go through versions until a match is found.  The text is also scrolled to show the match.  Note that each version only shows one match.  If you want to see more matches in the one version use the normal text find feature.
  
  If you toggle on the `In Diffs` feature then matches will be limited to text in a difference, either an insert or delete.  This is usually more useful than normal searches which often find too many matches (I know, it should default to on, but then things wouldn't look right).
  
---

  ![All Version Tabs Buttons](https://github.com/mark-hahn/live-archive/blob/master/screenshots/all-history-panes-buttons.jpg?raw=true)

  These two buttons affect all open tabs containing version histories.  `Sync All` will cause all history tabs to navigate to the same time as the history tab you are viewing.  The `Close All` button closes all history tabs at once.

### Scrolling

  Switching between the source text and history, and between all the versions of the text history, will scroll to matching places in the text whenever possible.  This makes the transitions mostly seamless even when large amounts of text are deleted or inserted above or below the current view.  Note that this is not always possible since the text you are viewing may be totally deleted.  It will sync the scrolling as well as it can.
  
  There are exceptions to this scrolling rule when searching for text or when the `Scrl` or `Diff` features are enabled.

### Differences Quirk

  The highlights for deleted text may seem to be on the wrong version until you get used to them.  They appear on the version before the version that they affect. This is done so that the deleted text can be highlighted while leaving the text matching what was saved.  In other words when looking at the highlights you are seeing inserts that just happened and deletes that are about to happen. (This makes sense to physicists aware of the reversablity of the time arrow).
  
  This also has the effect that some versions will show no highlights and the status will show zero adds and zero deletes.  These are versions that only had deletes when saved.
  
### To-Do
- Time ruler access like a video control bar
- More spec tests (as always)

### License

  Live-Archive is copyrighted under the MIT license.

### Credits

  I would like to thank Github and the contributors to Atom/Atom for this great hackable editor.  I would also like to thank all the users on the Atom forum for putting up with my zillion technical questions over the past month.

### Contributions

*Please please help!*  I've bitten off a lot to chew here.  The UI design and behavior are new and they can use a lot of improvement.
