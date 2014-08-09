
dbg  = require('./utils').debug 'larch'
dbg2 = require('./utils').debug 'larch', 2

module.exports =
  activate: ->
    @rootDir    = atom.project.getRootDirectory().path
    @archiveDir = @rootDir + '/.live-archive'

    dbg2 'live-archive activated'
    @fs            = require 'fs'
    @pathUtil      = require 'path'
    @mkdirp        = require 'mkdirp'
    @EditorMgr     = require './editor-mgr'
    @save          = require './save'
    @StatusBarView = require './status-bar-view'

    atom.workspaceView.command "core:save",         => @archive()
    atom.workspaceView.command "live-archive:open", => @openReviewEditor()

    atom.workspaceView.on 'pane-container:active-pane-item-changed', =>
      dbg 'pane-item-changed'
      if not @chkProjFolder() then return
      @EditorMgr.hideAll()

      editorView = atom.workspaceView.getActiveView()
      if not (editor = editorView?.getEditor?())
        dbg2 'no editor in this tab'
        return
      editor.liveArchiveEditorMgr?.show()
      # @editorMgr.setStatusBarMsg 'Archiving', 0
          
    @chkProjFolder()
    
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
      dbg 'creating ' + @archiveDir
      @mkdirp @archiveDir
    yes
    
  setStatusBarMsg: (args...) ->
    @statusBarView ?= new @StatusBarView
    @statusBarView.setMsg args...

  archive: ->
    if not @chkProjFolder() then return
    editorView = atom.workspaceView.getActiveView()
    if not (editor = editorView?.getEditor?()) then return
    buffer     = editor.getBuffer()
    lineNum    = editorView.getFirstVisibleScreenRow()
    lineBufOfs = buffer.characterIndexForPosition [lineNum, 0]
    cursor     = editor.getLastSelection().cursor
    cursBufOfs = buffer.characterIndexForPosition cursor.getBufferPosition()
    charOfs    = cursBufOfs - lineBufOfs
    start      = Date.now()
    text       = buffer.getText()
    base       = no
    changed    = @save.text @rootDir, buffer.getUri(), text, lineNum, charOfs, base, no
    dbg2 'live-archive save -', buffer.getUri(),
              '-', Date.now() - start, 'ms',
              (if not changed then '- noChg' else ''), lineNum, charOfs
    @setStatusBarMsg 'Archiving', 2, 1

  openReviewEditor: -> 
    editorView = atom.workspaceView.getActiveView()
    if not (editor = editorView?.getEditor?())
      dbg2 'no editor in this tab'
      return
    uri      = @pathUtil.normalize editor.getUri()
    dirName  = @pathUtil.dirname  uri    # c:\apps\live-archive\lib
    baseName = @pathUtil.basename uri    # live-archive.coffee
    relPath  = uri[@rootDir.length+1...] # lib\live-archive.coffee
    dirPath  = @pathUtil.dirname relPath # lib
    file     = @pathUtil.normalize @archiveDir + '/' + dirPath + '/~ ' + baseName
                    # c:\apps\live-archive/.live-archive/lib/~ live-archive.coffee

    if baseName[0..1] is '~ '
      dbg2 'you cannot open a review editor for a review file'
      return
    
    ## this doesn't work for unopened tabs
    # for editorView in atom.workspaceView.getEditorViews()
    #   dbg2 'getUri', editorView.getEditor().getUri()
    #   if editorView.getEditor().getUri() is file
    #     dbg2 'select tab'
    #     return
    
    atom.workspaceView.open(file).then (editor) =>
      if not (editorMgr = editor.liveArchiveEditorMgr)
        editorMgr = new @EditorMgr @, editor, uri
        if editorMgr.invalid then return
        dbg2 'openReviewEditor created EditorMgr', editorMgr
      dbg2 'openReviewEditor found EditorMgr', editorMgr

  deactivate: -> @EditorMgr.destroyAll()
  