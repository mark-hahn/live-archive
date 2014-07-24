# live-archive package for Atom editor

### Archives project continuously with fast review of old versions

### Notes:
- Some versions may be unreachable for review if clock changed when saving, such as during a daylight savings time change. All versions will have correct content regardless of clock stability.  

### To-Do
- test big unicode chars.
  '\u00bd + \u00bc = \u00be' =>  ½ + ¼ = ¾ => 9 characters => 12 bytes

- add base texts periodically

- compress base text when sync compression available (node 0.11.12)

- handle locked files
