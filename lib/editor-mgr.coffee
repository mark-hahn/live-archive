
fs            = require 'fs'
load          = require './load'
save          = require './save'
StatusView    = require './status-view'
ReplayView    = require './replay-view'
StatusBarView = require './status-bar-view'
dbg           = require('./utils').debug 'edmgr', 1
dbg2          = require('./utils').debug 'edmgr', 2

module.exports =
class EditorMgr

  @projPath   = atom.project.getRootDirectory().path
  @editorMgrs = []
        
  constructor: ->
    cancel = (msg) =>
      dbg msg + ':', @filePath
      @destroy()
      @invalid = yes
      null
    @editor     = atom.workspaceView.getModel().getActiveEditor()
    if not @editor then return cancel 'Not an editor pane'
    @editorView = atom.workspaceView.getActiveView()
    @buffer     = @editor.getBuffer()
    @filePath   = @buffer.getUri()
    if @filePath.indexOf('test.coffee') is -1
      return cancel 'Only a test file may be used when debugging' + @filePath
    @editor.liveArchiveEditorMgr = @
    @updateFileInfo()
    @archive yes
    @workIdx = @curIndex = @lastIndex
    EditorMgr.editorMgrs.push @
    @buffer.on 'contents-modified', =>
      @statusView?.setMsg @getState()
      
    # @enbld = no
    # Object.defineProperties @, 
    #   enabled:
    #     get: -> 
    #       console.log 'get enabled', @enbld, '       ' + @filePath
    #       @enbld
    #     set: (val) -> 
    #       console.log 'set enabled', @enbld, val, '       ' + @filePath
    #       if val is no then debugger
    #       @enbld = val

  show: ->
    itemView = atom.workspaceView.getActiveView()
    paneView = itemView.closest('.pane').view()
    if @statusView
      @replayView.show()
      @statusView.show()
    else
      dbg 'creating replay views'
      @statusView = new StatusView @
      paneView.append @statusView
      @replayView = new ReplayView @
      paneView.append @replayView
    paneView.find('.minimap').view()?.updateMinimapView()
    @statusView.setMsg @getState()
    @setStatusBarMsg 'Archiving', 1
    @enabled = yes
  
  hide: (disable) ->
    if disable then @enabled = no
    if @statusView
      @statusView.hide()
      @replayView.hide()
      itemView = atom.workspaceView.getActiveView()
      paneView = itemView.closest('.pane').view()
      paneView.find('.minimap').view()?.updateMinimapView()

  showing: -> @enabled

  latest: -> @loadEditor()
  
  setStatusBarMsg: (args...) ->
    @statusBarView ?= new StatusBarView @
    @statusBarView.setMsg args...
    
  updateFileInfo: ->
    {@path, @indexFileSize} = load.getPath EditorMgr.projPath, @filePath
    {@lastIndex}            = load.lastTime @path
    
  archive: (auto) ->
    savedIdx   = @curIndex
    lineNum    = @editorView.getFirstVisibleScreenRow()
    lineBufOfs = @buffer.characterIndexForPosition [lineNum, 0]
    cursor     = @editor.getLastSelection().cursor
    cursBufOfs = @buffer.characterIndexForPosition cursor.getBufferPosition()
    charOfs    = cursBufOfs - lineBufOfs
    start      = Date.now()
    text       = @buffer.getText()
    base       = no
    changed    = save.text EditorMgr.projPath, @buffer.getUri(), text, lineNum, charOfs, base, auto
    @lastSafeBuffer = text
    dbg2 'live-archive save -', @buffer.getUri(),
              '-', Date.now() - start, 'ms',
              (if not changed then '- no chg' else ''), lineNum, charOfs
    @updateFileInfo()
    if not auto then @curIndex = @lastIndex
    @setStatusBarMsg 'Archiving', 2, 1
    @statusView?.setMsg @getState()
    if not auto or savedIdx is @workIdx and changed 
      @workIdx = @lastIndex
    
  findGitHead: ->
    start = Date.now()
    if not (repo = atom.project.getRepo()) or
        repo.getPathStatus(@filePath[EditorMgr.projPath.length...]) is 0
      dbg2 'getPathStatus failed'
      , @filePath[EditorMgr.projPath.length+1...]
      , repo.getPathStatus(@filePath[EditorMgr.projPath.length...]) 
      @statusView.setNotFound()
      return @curIndex
    found = no
    for idx in [@lastIndex..0] by -1
      {text} = load.text EditorMgr.projPath, @filePath, idx
      if not (diffs = repo.getLineDiffs(@filePath, text))
        idx = @curIndex
        break
      if diffs.length is 0 then found = yes; break
    dbg 'findGitHead', diffs, idx
    @loadDelay = Date.now() - start
    if not found 
      @statusView.setNotFound()
      return @curIndex
    idx

  findFile: ->
    start = Date.now()
    tgtText = fs.readFileSync @filePath, 'utf8'
    if (startIdx = @curIndex - 1) < 0
      @statusView.setNotFound()
      return @curIndex
    found = no
    for idx in [startIdx..0] by -1
      {text} = load.text EditorMgr.projPath, @filePath, idx
      if text is tgtText then found = yes; break
    dbg 'findFile', idx
    @loadDelay = Date.now() - start
    if not found then @statusView.setNotFound(); return @curIndex
    idx

  unsafe: -> @lastSafeBuffer isnt @buffer.getText()
    
  loadEditor: (btn, $btn) ->
    if @curIndex is @lastIndex or @unsafe() then @archive yes
    @updateFileInfo()
    if not @indexFileSize then return
    
    if btn is 'Work' then @backIdx = @curIndex
    fwdBackInc = Math.floor Math.sqrt @lastIndex
    idx = switch btn
      when '|<'     then 0
      when '<<'     then Math.max 0, @curIndex - fwdBackInc
      when '<'      then Math.max 0, @curIndex - 1
      when '>'      then Math.min @lastIndex, @curIndex + 1 
      when '>>'     then Math.min @lastIndex, @curIndex + fwdBackInc
      when 'Back'   then @backIdx ? @curIndex
      when 'Work'   then @workIdx ? @curIndex
      when 'Git'    then @findGitHead()
      when 'File'   then @findFile()
      when 'SELECT' then @workIdx ? @curIndex
      when 'INPUT'  then @workIdx ? @curIndex
      else               @lastIndex
    start = Date.now()
    {text, index: @curIndex, lineNum, charOfs, @auto} =
      load.text EditorMgr.projPath, @filePath, idx
    @lastSafeBuffer = text
    @loadDelay = Date.now() - start
    
    @buffer.setText text
    @editorView.scrollToBufferPosition [lineNum+2, 0]
    lineOfs = @buffer.characterIndexForPosition [lineNum, 0]
    cursPos = @buffer.positionForCharacterIndex lineOfs + charOfs
    @editor.setCursorBufferPosition cursPos
    atom.workspaceView.focus()
    @statusView?.setMsg @getState()
    
  modified: ->
    @lastSafeBuffer? and 
    @unsafe() and @curIndex isnt @lastIndex
    
  getState: ->
    @updateFileInfo()
    time = load.getTime @curIndex
    {modified: @modified(), time, @curIndex, @lastIndex, @loadDelay, @auto}
    
  destroy: ->
    if @editor then delete @editor.liveArchiveEditorMgr
    for editorMgr, i in EditorMgr.editorMgrs
      if editorMgr is @ then delete EditorMgr.editorMgrs[i]
    @statusView?.destroy
    @replayView?.destroy

  @destroyAll = ->
    for editorMgr in EditorMgr.editorMgrs then editorMgr?.destroy()
    EditorMgr.editorMgrs = []
