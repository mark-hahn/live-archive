
dbg  = require('./utils').debug 'larch'

module.exports = 
  activate: ->
    @rootDir    = atom.project.getRootDirectory().path
    @archiveDir = @rootDir + '/.live-archive'

    @fs            = require 'fs'
    @pathUtil      = require 'path'
    @mkdirp        = require 'mkdirp'
    @EditorMgr     = require './editor-mgr'
    @save          = require './save'
    @StatusBarView = require './status-bar-view'

    atom.workspaceView.command "core:save",         => @archive()
    atom.workspaceView.command "live-archive:open", => @openReviewEditor()
    
    atom.workspaceView.eachEditorView (editorView) =>
      editor = editorView.getEditor()
      if editor.liveArchiveEditorMgr then return
      archivePath = editor.getUri().replace /\\/g, '/'
      if (archiveIdx = archivePath.indexOf '/<- ') is -1 then return
      baseName = archivePath[archiveIdx+4...]
      dirPath  = archivePath[@archiveDir.length+1...archiveIdx]
      origPath = @rootDir + '/' + dirPath + '/' + baseName
      #dbg 'eachEditorView', {archiveIdx, baseName, dirPath, origPath}
      new @EditorMgr @, editor, origPath

    atom.workspaceView.on 'pane-container:active-pane-item-changed', =>
      #dbg 'pane-item-changed'
      if not @chkProjFolder() then return
      @EditorMgr.hideAll()

      editorView = atom.workspaceView.getActiveView()
      if not (editor = editorView?.getEditor?())
        #dbg 'no editor in this tab'
        return
      editor.liveArchiveEditorMgr?.show()
    
  noProjFolder: ->
    @setStatusBarMsg 'Archiving Disabled', 2, 1
    no
    
  chkProjFolder: (allowCreate) ->
    if not @fs.existsSync @archiveDir
      if not allowCreate then return @noProjFolder()
      choice = atom.confirm
        message: '    -- Live Archive Not Enabled --\n'
        detailedMessage: 'Live Archive is not enabled on this project because there is ' +
                         'no ./live-archive folder in the root. ' +
                         'Click "Create" to create the folder and enable live archiving.'
        buttons: ['Create', 'Cancel']
      if choice is 1 then return @noProjFolder()
      #dbg 'creating ' + @archiveDir
      @mkdirp @archiveDir
    @setStatusBarMsg 'Archiving', 1
    yes
    
  setStatusBarMsg: (args...) ->
    @statusBarView ?= new @StatusBarView
    @statusBarView.setMsg args...

  archive: ->
    if not @chkProjFolder() then return
    editorView = atom.workspaceView.getActiveView()
    if not (editor = editorView?.getEditor?()) then return
    buffer = editor.getBuffer() 
    if /(\\|\/)\<\-\s/.test buffer.getUri() then return
    lineNum    = editorView.getFirstVisibleScreenRow()
    lineBufOfs = buffer.characterIndexForPosition [lineNum, 0]
    cursor     = editor.getCursor()
    cursBufOfs = buffer.characterIndexForPosition cursor.getBufferPosition()
    charOfs    = cursBufOfs - lineBufOfs
    start      = Date.now()
    text       = buffer.getText()
    base       = no
    changed    = @save.text @rootDir, buffer.getUri(), text, lineNum, charOfs, base, no
    dbg 'live-archive save -', buffer.getUri(),
              '-', Date.now() - start, 'ms',
              (if not changed then '- noChg' else ''), lineNum, charOfs
    @setStatusBarMsg 'Archiving', 2, 1

  openReviewEditor: -> 
    if not (@chkProjFolder yes) then return
    editorView = atom.workspaceView.getActiveView()
    if not (editor = editorView?.getEditor?())
      #dbg 'no editor in this tab'
      return
    origPath = @pathUtil.normalize editor.getUri()
    dirName  = @pathUtil.dirname  origPath    # c:\apps\live-archive\lib
    baseName = @pathUtil.basename origPath    # live-archive.coffee
    relPath  = origPath[@rootDir.length+1...] # lib\live-archive.coffee
    dirPath  = @pathUtil.dirname relPath # lib
    replayTabPath = @pathUtil.normalize @archiveDir + '/' + dirPath + '/<- ' + baseName
                    # c:\apps\live-archive/.live-archive/lib/<- live-archive.coffee

    if baseName[0..1] is '<- '
      #dbg 'you cannot open a review editor for a review file'
      return
    
    ## this doesn't work for unopened tabs
    # for editorView in atom.workspaceView.getEditorViews()
    #   #dbg 'getUri', editorView.getEditor().getUri()
    #   if editorView.getEditor().getUri() is archivePath
    #     #dbg 'select tab'
    #     return
    
    atom.workspaceView.open(replayTabPath).then (editor) =>
      if not (editorMgr = editor.liveArchiveEditorMgr)
        editorMgr = new @EditorMgr @, editor, origPath
        if editorMgr.invalid then return
        #dbg 'openReviewEditor created EditorMgr', editorMgr
      else
        #dbg 'openReviewEditor found EditorMgr', editorMgr

  deactivate: -> @EditorMgr.destroyAll()
  