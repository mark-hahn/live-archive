# live-archive package for Atom editor

### Archives project continuously with easy review of old versions

### Features:

- Archiving
  - Archives on every save
  - All saved versions are kept forever
  - Archive is highly compressed
    - Text differencing with excellent google diff-match-patch
    - Bit-level binary archive format
    - Large blocks of text compressed with zlib
    - Only twelve bytes overhead per version
  - Archive format and features can change in future
    - Old formatted data still available in same file
  - Archiving is fast, no noticeable delay when saving
  - Archive is enabled by project
    - Enabled when `.live-archive` folder in project root
    - All files for project archived in single folder
    - Directory tree in folder mirrors project
    - Rename folder to pause or resume usage
    - Creation and pausing can also be done using UI

- Reviewing
  - Review pane allows for easy traversal of history
    - Single click in time bar (ruler) jumps to any time
      - Next previous buttons useful for inaccurate click
      - No date or time picker
      - Ticks in ruler show each save
      - Also functions as activity timeline
    - Previous, next, oldest, newest, and resume buttons
    - Resume button allows return to previous review state
  - Reviewing happens in existing current editor pane
    - Old versions of text are editable
    - Old version can be saved as new
    - Warning bar at top of editor when reviewing old version
    - Normal editor usage while non-modal pane is open
  - Each version shows scroll and cursor position from save
  - Review is fast
    - Index allows quick time search
    - Difference scanning is bi-directional (2X speedup)
    - Base versions (entire text) placed intelligently

- Simple UI
  - No settings
  - Saving is transparent
  - Confidence indicator in status bar shows actions
  - Single keystroke to start reviewing currently visible file
  - Review pane is at bottom of editor pane like find-and-replace


- Reliable
  - All disk writes are append-only in single write operations
  - Archive is repairable (should never be needed)
    - Format includes flags to find versions if corrupted
    - Index can be rebuilt
  - Archive can be easily backed up with no file locks
  - Cannot lose anything due to user error
    - All saves immutable
    - Current version archived when starting review
  - Can be used with auto-save package
    - Frequent archiving is no problem

### Status
- Pre-alpha
- Not in APM
- Save/restore engine finished with working tests.
- Saving finished.
- Bare-bones reviewing works.  
- Most review features like time bar need implementing.
- DO NOT USE

### Installation

- Search for live-archive package in settings
- or type `apm install live-archive` in command line

### Usage

- Text archived on each buffer save
- No saving UI except confidence indicator in status bar
- Open reviewing pane with `live-archive:open` command
- Default open keystroke is `ctrl-alt-A`
- When hopping between tabs use resume button to continue reviewing

### Note:
- Some versions may be unreachable for review if clock changed when saving
  - Can happen during a daylight savings time change
  - Can happen if computer clock changed
  - Reachable versions still appear in order saved
  - Could be fixed after-the-fact if desired

### To-Do
- More spec tests (as always)

### testing screenshots in readme

![Navigation Block](screenshots/nav-buttons.jpg)

An image should show above.
