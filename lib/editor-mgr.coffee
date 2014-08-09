
# test

fs            = require 'fs'
load          = require './load'
StatusView    = require './status-view'
ReplayView    = require './replay-view'
dbg           = require('./utils').debug 'edmgr', 1
dbg          = require('./utils').debug 'edmgr', 2

module.exports =
class EditorMgr

  @rootDir    = atom.project.getRootDirectory().path
  @editorMgrs = []
        
  constructor: (@app, @editor, @origPath, @tildePath) ->
    cancel = (msg) =>
      dbg msg + ':', @origPath
      @destroy()
      @invalid = yes
      null
      
    for editorView in atom.workspaceView.getEditorViews()
      if editorView.getEditor() is @editor
        @editorView = editorView
        break
    
    if not @editorView then return cancel 'Unable to find editorView'
    
    @buffer = @editor.getBuffer()
    # if @origPath.indexOf('test.coffee') is -1
    #   return cancel 'Only a test file may be used when debugging' + @origPath
    @editor.liveArchiveEditorMgr = @
    @updateFileInfo()
    @curIndex = @lastIndex
    EditorMgr.editorMgrs.push @
    @buffer.on 'contents-modified', =>
      @statusView?.setMsg @getState()
    @show()
      
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
    @app.setStatusBarMsg 'Archiving', 1
    @loadEditor()
  
  hide: ->
    if @statusView
      @statusView.hide()
      @replayView.hide()
      itemView = atom.workspaceView.getActiveView()
      paneView = itemView.closest('.pane').view()
      paneView.find('.minimap').view()?.updateMinimapView()

  updateFileInfo: ->
    {path: @archivePath, @dataFileSize} = load.getPath EditorMgr.rootDir, @origPath
    @lastIndex                          = load.lastIndex @archivePath
  
  findGitHead: ->
    start = Date.now()
    if not (repo = atom.project.getRepo()) or
        repo.getPathStatus(@origPath[EditorMgr.rootDir.length+1..]) is 0
      @statusView.setNotFound()
      return @curIndex
    found = no
    for idx in [@lastIndex..0] by -1
      {text} = load.text EditorMgr.rootDir, @origPath, idx
      if not (diffs = repo.getLineDiffs(@origPath, text))
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
    tgtText = fs.readFileSync @origPath, 'utf8'
    if (startIdx = @curIndex - 1) < 0
      @statusView.setNotFound()
      return @curIndex
    found = no
    for idx in [startIdx..0] by -1
      {text} = load.text EditorMgr.rootDir, @origPath, idx
      if text is tgtText then found = yes; break
    dbg 'findFile', idx
    @loadDelay = Date.now() - start
    if not found then @statusView.setNotFound(); return @curIndex
    idx

  loadTildeFile: ->
    @buffer.setText fs.readFileSync @tildePath, 'utf8'
    @editorView.scrollToBufferPosition [0, 0]
    @editor.setCursorBufferPosition    [0 ,0]
    atom.workspaceView.focus()

  loadEditor: (btn, $btn) ->
    @updateFileInfo()
    if not @dataFileSize then return
    
    fwdBackInc = Math.floor Math.sqrt @lastIndex
    rtrn = no
    idx = switch btn
      when '~'      then @loadTildeFile(); rtrn = yes
      when '|<'     then 0
      when '<<'     then Math.max 0, @curIndex - fwdBackInc
      when '<'      then Math.max 0, @curIndex - 1
      when '>'      then Math.min @lastIndex, @curIndex + 1 
      when '>>'     then Math.min @lastIndex, @curIndex + fwdBackInc
      when 'Git'    then @findGitHead()
      when 'File'   then @findFile()
      when 'SELECT' then @curIndex
      when 'INPUT'  then @curIndex
      else               @lastIndex
    if rtrn then return
    start = Date.now()
    {text, index: @curIndex, lineNum, charOfs, @auto} =
      load.text EditorMgr.rootDir, @origPath, idx
    @loadDelay = Date.now() - start
    
    @buffer.setText text
    @editorView.scrollToBufferPosition [lineNum+2, 0]
    lineOfs = @buffer.characterIndexForPosition [lineNum, 0]
    cursPos = @buffer.positionForCharacterIndex lineOfs + charOfs
    @editor.setCursorBufferPosition cursPos
    atom.workspaceView.focus()
    @statusView?.setMsg @getState()
    
  modified: -> no
  
  getState: ->
    @updateFileInfo()
    time = load.getTime @curIndex
    {modified: @buffer.isModified(), time, @curIndex, @lastIndex, @loadDelay, @auto}
    
  destroy: ->
    if @editor then delete @editor.liveArchiveEditorMgr
    for editorMgr, i in EditorMgr.editorMgrs
      if editorMgr is @ then delete EditorMgr.editorMgrs[i]
    @statusView?.destroy
    @replayView?.destroy

  @hideAll = -> for editorMgr in EditorMgr.editorMgrs then editorMgr?.hide()

  @destroyAll = ->
    for editorMgr in EditorMgr.editorMgrs then editorMgr?.destroy()
    EditorMgr.editorMgrs = []
