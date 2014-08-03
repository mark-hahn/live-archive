
dbg  = require('./utils').debug 'larch'
dbg2 = require('./utils').debug 'larch', 2

module.exports =
  activate: ->
    @archiveDir = atom.project.getRootDirectory().path + '/.live-archive'

    dbg2 'live-archive activated'
    @fs         = require 'fs'
    @mkdirp     = require 'mkdirp'
    @EditorMgr  = require './editor-mgr'

    atom.workspaceView.command "core:save",           => @archive()
    atom.workspaceView.command "live-archive:toggle", => @toggleReplayPane()

    atom.workspaceView.on 'pane-container:active-pane-item-changed', =>
      dbg 'pane-item-changed'
      if not @chkProjFolder() then return
      @editorMgr?.hide()
      @editor = @editorMgr = null
      if @getEditorMgr() and @editorMgr.enabled 
        @editorMgr.show()
        @editorMgr.setStatusBarMsg 'Archiving', 0
        
    @chkProjFolder()
    
  getEditor: ->
    if @editor then return @editor 
    @editorView = atom.workspaceView.getActiveView()
    @editor = @editorView?.getEditor?()
    
  getEditorMgr: -> 
    if @editorMgr then return @editorMgr 
    @editorMgr = @getEditor()?.liveArchiveEditorMgr
    if not @editorMgr
      @editorMgr = new @EditorMgr()
      # if @editorMgr.filePath.indexOf('test.coffee') isnt -1 then debugger
      if @editorMgr.invalid
        delete @editorMgr
        return
    @editorMgr

  noProjFolder: ->
    @editorMgr?.setStatusBarMsg 'Archiving Disabled', 2, 1
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
    
  archive: ->
    if not @chkProjFolder() then return
    @getEditorMgr()?.archive()

  toggleReplayPane: ->
    if not @chkProjFolder(yes) or not @getEditorMgr() then return
    if @editorMgr.showing()
      @editorMgr.latest()
      @editorMgr.hide yes
    else
      @editorMgr.show()

  deactivate: -> @EditorMgr.destroyAll()
  