{Range} = require 'atom'
 
fs            = require 'fs'
load          = require './load'
StatusView    = require './status-view'
ReplayView    = require './replay-view'
dbg           = require('./utils').debug 'edmgr'

module.exports =
class EditorMgr

  @rootDir    = atom.project.getRootDirectory().path
  @editorMgrs = [] 
  
  constructor: (@app, @editor, @origPath) ->
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
    @editor.liveArchiveEditorMgr = @
    @updateFileInfo()
    @curIndex = @lastIndex
    EditorMgr.editorMgrs.push @
    
    @buffer.isModified = -> no
    @buffer.save       = ->
    atom.workspaceView.getActivePane().model.promptToSaveItem = -> yes
  
    @buffer.on 'contents-modified', =>
      @statusView?.setMsg @getState() 
      if @buffer.getText() isnt @curText and not @allowEditing
        choice = atom.confirm
          message: '    -- Are you sure you want to modify history? --\n'
          detailedMessage: 'WARNING: edits will not be saved. ' +
                           'This is not a file. ' +
                           'It is OK to edit a history buffer but often you really ' +
                           'intend to edit the source file. ' +
                           'Press Source to go to the source file, ' +
                           'Edit to continue editing, ' +
                           'or Cancel to undo the edit.'
          buttons: ['Source', 'Edit', 'Cancel']
        switch choice
          when 0 then @goToSrcWin()
          when 1 then @allowEditing = yes
          when 2
            pos = getViewPos()
            @buffer.setText @curText
            @setViewPos pos, @editorView
            
    @curText = @buffer.getText()
    @show()
      
  updateFileInfo: ->
    {path: @archivePath, @dataFileSize} = load.getPath EditorMgr.rootDir, @origPath
    @lastIndex                          = load.lastIndex @archivePath
  
  findGitHead: ->
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
    #dbg 'findGitHead', diffs, idx
    if not found 
      @statusView.setNotFound()
      return @curIndex
    idx

  getViewPos: ->
    if not @editorView then return
    topLine = @editorView.getFirstVisibleScreenRow()
    cursPos = @editor.getCursorBufferPosition()
    [topLine, cursPos]
    
  setViewPos: (pos, view) ->
    if pos and view
      [topLine, cursPos] = pos
      view.scrollToBufferPosition [topLine+2, 0]
      view.getEditor().setCursorBufferPosition cursPos
    
  goToSrcWin: ->
    pos = @getViewPos()
    atom.workspaceView.open @origPath
    setTimeout => 
      @setViewPos pos, atom.workspaceView.getActiveView()
    , 500
    
  revert: ->
    choice = atom.confirm
      message: '    -- Revert source file to this version? --\n'
      detailedMessage: 'This will replace the contents of your working source tab ' +
                       'with the text from this version tab.  If you have made changes to ' +
                       'this version then those changes will be included. ' +
                       'If you change your mind later you can use the undo in the source tab.'
      buttons: ['Cancel', 'Revert']
    switch choice
      when 0 then return
      when 1
        text = @buffer.getText()
        atom.workspaceView.open(@origPath).then (editor) -> editor.setText text
        
  highlightDifferences: (btnOn) ->
    @diffHilitesOn = btnOn
    setMarker = (range, klass) =>
      marker = @buffer.markRange range, liveArchive: yes
      @editor.decorateMarker marker, type: 'highlight', class: klass
    marker.destroy() for marker in @editor.findMarkers liveArchive: yes
    if not btnOn 
      @replayView.setBtn 'Scrl',     no
      @replayView.setBtn 'Diff',     no
      @replayView.setBtn 'In Diffs', no
      return
    {inserts, deletes} = load.getDiffs EditorMgr.rootDir, @origPath, @curIndex, yes
    @inserts = inserts.slice()
    @deletes = deletes.slice()
    insertIdx = deleteIdx = 0
    while (ins = inserts[insertIdx]) or (del = deletes[deleteIdx])
      if ins 
        [insBufBegOfs, insBufEndOfs] = ins
        insBegPos = @buffer.positionForCharacterIndex insBufBegOfs
        insEndPos = @buffer.positionForCharacterIndex insBufEndOfs
        insRange  = Range.fromObject [insBegPos, insEndPos]
        if not del then setMarker insRange, 'la-insert'; insertIdx++; continue
      if del 
        [delBufBegOfs, delBufEndOfs] = del
        delBegPos = @buffer.positionForCharacterIndex delBufBegOfs
        delEndPos = @buffer.positionForCharacterIndex delBufEndOfs
        delRange  = Range.fromObject [delBegPos, delEndPos]
        if not ins then setMarker delRange, 'la-delete'; deleteIdx++; continue
      switch insRange.compare delRange
        when  0 then setMarker insRange, 'la-ins-del'; insertIdx++; deleteIdx++
        when -1
          if insBufEndOfs <= delBufBegOfs # ins totally before del
            setMarker insRange, 'la-insert'; insertIdx++; continue
          if insBegPos is delBegPos # del end before ins end
            setMarker Range.fromObject([insBegPos, delEndPos]), 'la-ins-del'
            inserts[insertIdx][0] = delBufEndOfs
            deleteIdx++
          else    # ins beg before del beg
            setMarker Range.fromObject([insBegPos, delBegPos]), 'la-insert'
            inserts[insertIdx][0] = delBufBegOfs
            insertIdx++
        when +1
          if delBufEndOfs <= insBufBegOfs # del totally before ins
            setMarker delRange, 'la-delete'; deleteIdx++; continue
          if delBegPos is insBegPos # ins end before del end
            setMarker Range.fromObject([delBegPos, insEndPos]), 'la-del-ins'
            deletes[deleteIdx][0] = insBufEndOfs
            insertIdx++
          else    # del beg before ins beg
            setMarker Range.fromObject([delBegPos, insBegPos]), 'la-delete'
            deletes[deleteIdx][0] = insBufBegOfs
            deleteIdx++
            
  gotoHilite: (down) ->
    @replayView.setBtn 'Hilite', yes
    markers = @editor.findMarkers liveArchive: yes
    if markers.length is 0 then return
    cursBufPos = @buffer.characterIndexForPosition @editor.getCursorBufferPosition()
    closestBufPos  = (if down then Infinity else -Infinity)
    charsInBuf =  @buffer.getMaxCharacterIndex()
    for marker in markers
      range  = marker.bufferMarker.range
      bufPos = @buffer.characterIndexForPosition range.start
      if down
        if bufPos <= cursBufPos then bufPos += charsInBuf
        if bufPos >  cursBufPos and bufPos < closestBufPos
          closestBufPos = bufPos
      else
        if bufPos >= cursBufPos then bufPos -= charsInBuf
        if bufPos <  cursBufPos and bufPos > closestBufPos
          closestBufPos = bufPos
    if closestBufPos > charsInBuf then closestBufPos -= charsInBuf
    if closestBufPos < 0          then closestBufPos += charsInBuf
    @editor.setCursorBufferPosition @buffer.positionForCharacterIndex closestBufPos
    atom.workspaceView.focus()
    
  isDiffShowing: ->
    topLineNum = @editorView.getFirstVisibleScreenRow()
    topBufPos  = @buffer.characterIndexForPosition [topLineNum, 0]
    botLineNum = @editorView.getLastVisibleScreenRow()
    botBufPos  = @buffer.characterIndexForPosition [botLineNum, 0]
    for range in @inserts.concat @deletes
      [beg, end] = range
      if not (end < topBufPos or beg > botBufPos) then return yes
    no
    
  diffsBtn: (btnOn) ->
    @navDiffs = btnOn
    if btnOn 
      @replayView.setBtn 'Hilite',    yes
      @replayView.setBtn 'Scrl',      no
      @replayView.setBtn 'In Diffs',  no
    
  scrlBtn: (btnOn) ->
    @navScrl = btnOn
    if btnOn 
      @replayView.setBtn 'Hilite',    yes
      @replayView.setBtn 'Diff',      no
      @replayView.setBtn 'In Diffs',  no
      
  inDiffsBtn: (btnOn) ->
    @SrchInDiffs = btnOn
    if btnOn 
      @replayView.setBtn 'Hilite',  yes
      @replayView.setBtn 'Diff',    no
      @replayView.setBtn 'Scrl',    no
      
  syncBtn: ->
    for editorMgr in EditorMgr.editorMgrs
      editorMgr.time = @time
      
  search: (inc, searchStr) ->
    searchStr = searchStr.toLowerCase()
    if @SrchInDiffs
      res = load.searchDiffs EditorMgr.rootDir, @origPath,  @curIndex, inc, searchStr
      if res
        {idx, textPos: @oneTimeTextPos} = res
        idx
      else 
        @curIndex
    else
      strtIdx = @curIndex + inc
      if not (0 <= strtIdx <= @lastIndex) then return @curIndex
      endIdx = (if inc < 0 then 0 else @lastIndex)
      for idx in [strtIdx..endIdx]
        {text} = load.text EditorMgr.rootDir, @origPath, idx
        if (textPos = text.toLowerCase().indexOf searchStr) > -1
          @oneTimeTextPos = textPos
          return idx
      @curIndex
    
  loadEditor: (btn, btnOn, time, val) ->
    dbg 'loadEditor', {btn, btnOn, val, @curIndex}
    @updateFileInfo()
    if not @dataFileSize then return
    
    if btn
      fwdBackInc = Math.floor Math.sqrt @lastIndex
      rtrn = no
      endIdx = null
      idx = switch btn
        when 'Open'      then @goToSrcWin(); rtrn = yes
        when 'Revert'    then @revert();     rtrn = yes
        when 'Git'       then endIdx = 0; @findGitHead()
        when '|<'        then endIdx = 0; 0
        when '<<'        then endIdx = 0; Math.max 0, @curIndex - fwdBackInc
        when '<'         then endIdx = 0; Math.max 0, @curIndex - 1
        when '>'         then endIdx = @lastIndex; Math.min @lastIndex, @curIndex + 1 
        when '>>'        then endIdx = @lastIndex; Math.min @lastIndex, @curIndex + fwdBackInc
        when 'Diff'      then @diffsBtn btnOn;             rtrn = yes
        when 'Scrl'      then @scrlBtn  btnOn;             rtrn = yes
        when 'v'         then @gotoHilite yes;             rtrn = yes
        when 'Hilite'    then @highlightDifferences btnOn; rtrn = yes
        when '^'         then @gotoHilite no;              rtrn = yes
        when '<srch'     then @search -1, val
        when '>srch'     then @search +1, val
        when 'In Diffs'  then @inDiffsBtn btnOn;           rtrn = yes
        when 'Sync'      then @syncBtn();                  rtrn = yes
        when 'Close'     then @goToSrcWin(); EditorMgr.closeAllReplayTabs(); rtrn = yes
        else                  endIdx = @lastIndex
      if rtrn then return
    
    if not (firstShowing = not @lineNum?)
      oldIndex      = @curIndex
      oldLineNum    = @editorView.getFirstVisibleScreenRow()
      oldLineBufPos = @buffer.characterIndexForPosition([oldLineNum, 0])
      oldCursBufPos = @buffer.characterIndexForPosition(@editor.getCursorBufferPosition())

    {text: @curText, index: @curIndex, time} = load.text EditorMgr.rootDir, @origPath, idx
    @buffer.setText @curText
    
    if not firstShowing and @navScrl
        @gotoHilite no
    else if @oneTimeTextPos
      p1 = @buffer.positionForCharacterIndex @oneTimeTextPos
      p2 = @buffer.positionForCharacterIndex @oneTimeTextPos + val.length
      @editor.addSelectionForBufferRange Range.fromObject [p1, p2]
      @editorView.scrollToCursorPosition()
      @oneTimeTextPos = null
    else
      if firstShowing
        @lineNum = 0
      else
        [lineBufPos] = load.trackPos EditorMgr.rootDir, @origPath, 
                                     oldIndex, @curIndex, [oldLineBufPos]
        @lineNum    = @buffer.positionForCharacterIndex(lineBufPos).row
        cursBufPos  = oldCursBufPos + lineBufPos - oldLineBufPos
        @charOfs    = cursBufPos - lineBufPos
      @editorView.scrollToBufferPosition [@lineNum+2, 0]
      cursPos = @buffer.positionForCharacterIndex cursBufPos
      @editor.setCursorBufferPosition cursPos
      
      if @navDiffs and @curIndex isnt endIdx and not @isDiffShowing() and not time
        @highlightDifferences yes
        # @statusView?.setMsg @getState()
        @loadEditor btn, btnOn
        # setTimeout (-> @loadEditor btn, btnOn), 100
        return
      
    atom.workspaceView.focus()
    @statusView?.setMsg @getState()
    
    if @diffHilitesOn then @highlightDifferences yes
    
  getState: ->
    @updateFileInfo()
    time = load.getTime @curIndex
    {time, @curIndex, @lastIndex, @auto}
    
  show: ->
    if @time then @loadEditor null, null, @time
    @time = null
    itemView = atom.workspaceView.getActiveView()
    paneView = itemView.closest('.pane').view()
    if @statusView
      @replayView.show()
      @statusView.show()
    else
      #dbg 'creating replay views'
      @statusView = new StatusView @
      paneView.append @statusView
      @replayView = new ReplayView @
      paneView.append @replayView
    paneView.find('.minimap').view()?.updateMinimapView()
    @statusView.setMsg @getState()
    @loadEditor()
    
  hide: ->
    if not @statusView then return
    @statusView.hide()
    @replayView.hide()
    if (itemView = atom.workspaceView.getActiveView()) and
        (paneView = itemView.closest('.pane').view())
      paneView.find('.minimap').view()?.updateMinimapView()
      
  destroy: ->
    if @editor then delete @editor.liveArchiveEditorMgr
    for editorMgr, i in EditorMgr.editorMgrs
      if editorMgr is @ then delete EditorMgr.editorMgrs[i]
    @statusView?.destroy
    @replayView?.destroy
    
  @hideAll = -> for editorMgr in EditorMgr.editorMgrs then editorMgr?.hide()

  @closeAllReplayTabs = ->
    if not (tabBarView = atom.workspaceView.find('.tab-bar').view())
      return
    EditorMgr.hideAll()
    for tabView in tabBarView.getTabs() 
      if tabView.title.text()[0..2] is '<- ' 
        tabBarView.closeTab tabView
    EditorMgr.editorMgrs = []
  
  @destroyAll = ->
    for editorMgr in EditorMgr.editorMgrs then editorMgr?.destroy()
    EditorMgr.editorMgrs = []
