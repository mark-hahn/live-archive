# lib\live-archive.coffee

dbg  = require('./utils').debug 'larch'

module.exports = 
  activate: ->
    @fs            = require 'fs'
    @pathUtil      = require 'path'
    @mkdirp        = require 'mkdirp'
    {@load, @save} = require 'text-archive-engine'
    @EditorMgr     = require './editor-mgr'
    @StatusBarView = require './status-bar-view'
 
    atom.workspaceView.command "core:save",         => @archive()
    atom.workspaceView.command "live-archive:open", => @openReviewEditor()
    
    atom.workspaceView.on 'pane-container:active-pane-item-changed', =>
      dbg 'pane-item-changed 4'
      if not @chkProjFolder() then return
      @EditorMgr.hideAll()

      editorView = atom.workspaceView.getActiveView()
      if not (editor = editorView?.getEditor?())
        dbg 'no editor in this tab'
        return
      editor.liveArchiveEditorMgr?.show()
      
    @setStatusBarMsg 'Archive', 1
    setTimeout =>
      @EditorMgr.closeAllReplayTabs()
    , 3000
    
  noProjFolder: ->
    @setStatusBarMsg 'Archive Disabled', 2, 1
    no
    
  chkProjFolder: (allowCreate) ->
    if not (@rootDir ?= atom.project.getRootDirectory()?.path) then return @noProjFolder()
    @archiveDir = @rootDir + '/.live-archive'
    if not @fs.existsSync @archiveDir
      if not allowCreate then return @noProjFolder()
      choice = atom.confirm
        message: '    -- Live Archive Not Enabled --\n'
        detailedMessage: 'Live Archive is not enabled on this project because there is ' +
                         'no ./live-archive folder in the root. ' +
                         'Click "Create" to create the folder and enable live archiving.'
        buttons: ['Create', 'Cancel']
      if choice is 1 then return @noProjFolder()
      @mkdirp @archiveDir
      process.nextTick => @fs.writeFileSync @archiveDir + '/.gitignore', '**\n'
      
    @setStatusBarMsg 'Archive', 1
    yes
    
  setStatusBarMsg: (args...) ->
    @statusBarView ?= new @StatusBarView @
    @statusBarView.setMsg args... 

  archive: ->
    if not @chkProjFolder() then return
    editorView = atom.workspaceView.getActiveView()
    if not (editor = editorView?.getEditor?()) then return
    buffer = editor.getBuffer() 
    if /(\\|\/)\<\-\s/.test buffer.getUri() then return
    start      = Date.now()
    text       = buffer.getText()
    base       = no
    changed    = @save.text @rootDir, buffer.getUri(), text, base
    if typeof changed is 'string'
      atom.confirm
        message: 'Live Archive Package:\n'
        detailedMessage: 'Error attempting to write to an archive file. \n' + changed
        buttons: ['OK']

    # dbg 'save -', buffer.getUri(), '-', Date.now() - start, 'ms',
            #  (if not changed then '- noChg' else '')
    @setStatusBarMsg 'Archiving', 2, 1, 'Archive'

  openReviewEditor: -> 
    if not (@chkProjFolder yes) then return
    editorView = atom.workspaceView.getActiveView()
    if not (editor = editorView?.getEditor?())
      dbg 'no editor in this tab'
      return
    if (editorMgr = editor.liveArchiveEditorMgr)
      editorMgr.close()
      return
    origPath = @pathUtil.normalize editor.getUri()
    dirName  = @pathUtil.dirname  origPath    # c:\apps\live-archive\lib
    baseName = @pathUtil.basename origPath    # live-archive.coffee
    relPath  = origPath[@rootDir.length+1...] # lib\live-archive.coffee
    dirPath  = @pathUtil.dirname relPath # lib
    archDir  = @pathUtil.normalize @archiveDir + '/' + dirPath
    tabUri   = archDir + '/<- ' + baseName
    archFilePath = archDir + '/' +  baseName + '.la'

    if baseName[0..2] is '<- '
      dbg 'you cannot open a review editor for a review file'
      return
      
    centerLine = Math.ceil((editorView.getFirstVisibleScreenRow() + 
                            editorView.getLastVisibleScreenRow()) / 2)
    cursPos    = editor.getCursorBufferPosition()
    
    try
      fileSize = fs.statSync(archFilePath).size
    catch e
      fileSize = 0
    if not fileSize then @archive()
    
    atom.workspaceView.open(tabUri).then (editor) =>
      if not (editorMgr = editor.liveArchiveEditorMgr)
        new @EditorMgr @, editor, origPath, [centerLine, cursPos]

  deactivate: -> @EditorMgr.destroyAll()
  