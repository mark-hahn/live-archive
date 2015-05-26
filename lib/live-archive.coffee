# lib\live-archive.coffee

{TextEditor, CompositeDisposable} = require 'atom'
fs  = require 'fs'
dbg = require('./utils').debug 'larch'
  
module.exports = 
  activate: ->
    @subs = new CompositeDisposable

    @fs            = require 'fs'
    @pathUtil      = require 'path'
    @mkdirp        = require 'mkdirp'
    {@load, @save} = require 'text-archive-engine'
    @EditorMgr     = require './editor-mgr'
    @StatusBarView = require './status-bar-view'
    
    @subs.add atom.commands.add 'atom-workspace', "core:save",         => @archive()
    @subs.add atom.commands.add 'atom-workspace', "live-archive:open", => @openReviewEditor()

    atom.workspace.onDidChangeActivePaneItem (editor) =>
      dbg 'pane-item-changed 4'
      if not @chkProjFolder() then return
      @EditorMgr.hideAll()
      if not editor instanceof TextEditor
        dbg 'no editor in this tab'
        return
      editor?.liveArchiveEditorMgr?.show()
      
    @setStatusBarMsg 'Archive', 1
    setTimeout =>
      @EditorMgr.closeAllReplayTabs()
    , 3000
    
  noProjFolder: ->
    @setStatusBarMsg 'Archive Disabled', 2, 1
    no
    
  chkProjFolder: (allowCreate) ->
    
    if not (@rootDir ?= atom.project.getDirectories()[0]?.path) then return @noProjFolder()
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
      @mkdirp.sync @archiveDir
      process.nextTick => @fs.writeFileSync @archiveDir + '/.gitignore', '**\n'
      
    @setStatusBarMsg 'Archive', 1
    yes
    
  setStatusBarMsg: (args...) ->
    @statusBarView ?= new @StatusBarView @
    @statusBarView.setMsg args... 

  archive: ->
    if not @chkProjFolder() then return
    if not (editor = atom.workspace.getActiveTextEditor()) then return
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
    if not (editor = atom.workspace.getActiveTextEditor())
      dbg 'no editor in this tab'
      return
    editorEle = atom.views.getView editor
    if (editorMgr = editor.liveArchiveEditorMgr)
      editorMgr.close()
      return
    origPath     = @pathUtil.normalize editor.getPath()
    dirName      = @pathUtil.dirname  origPath    # c:\apps\live-archive\lib
    baseName     = @pathUtil.basename origPath    # live-archive.coffee
    relPath      = origPath[@rootDir.length+1...] # lib\live-archive.coffee
    dirPath      = @pathUtil.dirname relPath      # lib
    archDir      = @pathUtil.join @archiveDir,  dirPath
    tabPath      = @pathUtil.join archDir, '<- ' + baseName
    archFilePath = @pathUtil.join archDir, baseName + '.la'

    if baseName[0..2] is '<- '
      dbg 'you cannot open a review editor for a review file'
      return
      
    centerLine = Math.ceil((editorEle.getFirstVisibleScreenRow() + 
                            editorEle.getLastVisibleScreenRow()) / 2)
    cursPos = editor.getCursorBufferPosition()
    
    try
      fileSize = fs.statSync(archFilePath).size
    catch e
      fileSize = 0
    if not fileSize then @archive()
    
    atom.workspace.open(tabPath).then (editor) =>
      if not (editorMgr = editor.liveArchiveEditorMgr)
        new @EditorMgr @, editor, origPath, [centerLine, cursPos]

  deactivate: -> 
    @subs.dispose()
    @EditorMgr.destroyAll()
  