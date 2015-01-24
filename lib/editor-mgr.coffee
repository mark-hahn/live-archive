
# lib\editor-mgr.coffee

{Range} = require 'atom'
  
fs            = require 'fs'
{load, save}  = require 'text-archive-engine'
StatusView    = require './status-view'
# RulerView     = require './ruler-view'
ReplayView    = require './replay-view'
dbg           = require('./utils').debug 'edmgr'
    
module.exports =
class EditorMgr
  
  @editorMgrs = [] 
   
  constructor: (@app, @editor, @origPath, viewPos) ->
    
    if not (@rootDir = atom.project.getDirectories()[0]?.path)
      throw 'no project found for tab' + @origPath
    
    cancel = (msg) =>
      dbg msg + ':', @origPath
      @destroy()
      @invalid = yes
      null
            
    @editorView = atom.views.getView @editor
    @editorEle = atom.views.getView @editor
    @editorEle.classList.add 'live-archive'
    
    
    @buffer = @editor.getBuffer()
    @editor.liveArchiveEditorMgr = @
    @updateFileInfo()
    @curIndex = @lastIndex
    EditorMgr.editorMgrs.push @
    
    @buffer.save = ->
    @buffer.isModified = -> no
    @editor.shouldPromptToSave = -> no

    @curText = @buffer.getText()
    @show viewPos
    @buffer.onDidStopChanging =>
      if @buffer.isModified()
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
              pos = @getViewPos()
              @buffer.setText @curText
              @setViewPos pos, @editor
            
    splitCommand = (e) =>
      dbg 'splitCommand', e
      atom.confirm
        message: 'Notice:\n'
        detailedMessage: 'You may not split a history view.'
        buttons: ['OK']
      e.stopPropagation()
      e.preventDefault()
    
    @subs.push atom.commands.add @editor, 'pane:split-left':  => @toggle()
    @subs.push atom.commands.add @editor, 'pane:split-right': => @toggle()
    @subs.push atom.commands.add @editor, 'pane:split-up':    => @toggle()
    @subs.push atom.commands.add @editor, 'pane:split-down':  => @toggle()

  getViewPos: ->
    if not @editor then return
    centerLine = Math.ceil((@editorEle.getFirstVisibleScreenRow() + 
                            @editorEle.getLastVisibleScreenRow()) / 2)
    cursPos = @editor.getCursorBufferPosition()
    [centerLine, cursPos]
    
  setViewPos: (pos, editor) ->
    if pos? and editor
      [centerLine, cursPos] = pos
      centerLine -= 1
      editor.setCursorBufferPosition cursPos, autoscroll: no
      editor.scrollToBufferPosition [centerLine, 0], center: yes
      
  getBufOfsFromViewPos: (editor = @editor) ->
    [centerLine, cursPos] = @getViewPos()
    buffer     = editor.getBuffer()
    lineBufOfs = buffer.characterIndexForPosition [centerLine, 0]
    cursBufOfs = buffer.characterIndexForPosition cursPos
    [lineBufOfs, cursBufOfs]
    
  setViewPosByBufOfs: (lineBufOfs, cursBufOfs, editor = @editor) ->
    buffer     = editor.getBuffer()
    centerLine = buffer.positionForCharacterIndex(lineBufOfs).row
    cursPos    = buffer.positionForCharacterIndex cursBufOfs
    @setViewPos [centerLine, cursPos], editor

  updateFileInfo: ->
    {path: @archivePath, @dataFileSize} = load.getPath @rootDir, @origPath
    @lastIndex                          = load.lastIndex @archivePath
  
  findGitHead: ->
    if not (repo = atom.project.getRepo()) or
        repo.getPathStatus(@origPath[@rootDir.length+1..]) is 0
      @statusView.setNotFound()
      return @curIndex
    @replayView.setBtn 'Diff',      no

    found = no
    for idx in [@lastIndex..0] by -1
      {text} = load.text @rootDir, @origPath, idx
      if not (diffs = repo.getLineDiffs(@origPath, text))
        idx = @curIndex
        break
      if diffs.length is 0 then found = yes; break
    dbg 'findGitHead', diffs, idx
    if not found 
      @statusView.setNotFound()
      return @curIndex
    idx

  goToSrcWin: ->
    oldBufOfs = @getBufOfsFromViewPos()
    atom.workspace.open(@origPath).then (editor) =>
      srcText = editor.getBuffer().getText()
      [lineBufOfs, cursBufOfs] = oldBufOfs
      {lineBufOfs, cursBufOfs} = save.trackPos @curText, srcText, {lineBufOfs, cursBufOfs}
      @setViewPosByBufOfs lineBufOfs, cursBufOfs, editor
      
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
        atom.workspace.open(@origPath).then (editor) -> editor.setText text
        
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
    {inserts, deletes} = load.getDiffs @rootDir, @origPath, @curIndex, yes
    @inserts   = inserts.slice()
    @deletes   = deletes.slice()
    @addCount  = @inserts.length
    @delCount  = @deletes.length
    insertIdx  = deleteIdx = 0
    loop 
      ins = inserts[insertIdx]
      del = deletes[deleteIdx]
      if not ins and not del then break
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
        when  0 
          setMarker insRange, 'la-insert'
          setMarker insRange, 'la-delete'
          insertIdx++; deleteIdx++
        when -1
          if insBufEndOfs <= delBufBegOfs # ins totally before del
            setMarker insRange, 'la-insert'; insertIdx++; continue
          if insBegPos is delBegPos # del end before ins end
            setMarker Range.fromObject([insBegPos, delEndPos]), 'la-insert'
            setMarker Range.fromObject([insBegPos, delEndPos]), 'la-delete'
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
            setMarker Range.fromObject([delBegPos, insEndPos]), 'la-insert'
            setMarker Range.fromObject([delBegPos, insEndPos]), 'la-delete'
            deletes[deleteIdx][0] = insBufEndOfs
            insertIdx++
          else    # del beg before ins beg
            setMarker Range.fromObject([delBegPos, insBegPos]), 'la-delete'
            deletes[deleteIdx][0] = insBufBegOfs
            deleteIdx++
    @statusView?.setMsg @getState()
          
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
    atom.views.getView(atom.workspace).focus()
    
  isDiffShowing: ->
    topLine    = @editorEle.getFirstVisibleScreenRow()
    topBufPos  = @buffer.characterIndexForPosition [topLine, 0]
    botLineNum = @editorEle.getLastVisibleScreenRow()
    botBufPos  = @buffer.characterIndexForPosition [botLineNum, 0]
    for range in @inserts.concat @deletes
      [beg, end] = range
      if not (end < topBufPos or beg > botBufPos) then return yes
      
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
    # dbg 'search', inc, searchStr
    if @SrchInDiffs
      res = load.searchDiffs @rootDir, @origPath,  @curIndex, inc, searchStr
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
        {text} = load.text @rootDir, @origPath, idx
        if (textPos = text.toLowerCase().indexOf searchStr) > -1
          @oneTimeTextPos = textPos
          return idx
      @curIndex
    
  loadEditor: (btn, btnOn, time, val) ->
    # dbg 'loadEditor', {btn, btnOn, val, @curIndex}
    @updateFileInfo()
    if not @dataFileSize then return
    
    if btn
      fwdBackInc = Math.floor Math.sqrt @lastIndex
      rtrn = no
      endIdx = null
      idx = switch btn
        when 'Source'    then @goToSrcWin(); rtrn = yes
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
        when 'Sync All'  then @syncBtn();                  rtrn = yes
        when 'Close All' then @goToSrcWin(); EditorMgr.closeAllReplayTabs(); rtrn = yes
        else                  endIdx = @lastIndex
      if rtrn then return
    else 
      idx = @prevIndex ? @lastIndex
      
    @time = @lineCount = @addCount = @delCount = null
    
    oldBufOfs = @getBufOfsFromViewPos()
    oldText   = @buffer.getText()
    {text: @curText, index: @curIndex, @time} = load.text @rootDir, @origPath, idx
    @buffer.setText @curText
    
    @lineCount = 1
    lfRegEx = new RegExp '\\n', 'g'
    while lfRegEx.exec @curText then @lineCount++ 
    
    if @navScrl then @gotoHilite no
    else if @oneTimeTextPos
      p1 = @buffer.positionForCharacterIndex @oneTimeTextPos
      p2 = @buffer.positionForCharacterIndex @oneTimeTextPos + val.length
      @editor.addSelectionForBufferRange Range.fromObject [p1, p2]
      @editor.scrollToCursorPosition()
      @oneTimeTextPos = null
    else      
      [lineBufOfs, cursBufOfs] = oldBufOfs
      {lineBufOfs, cursBufOfs} = save.trackPos oldText, @curText, {lineBufOfs, cursBufOfs}
      @setViewPosByBufOfs lineBufOfs, cursBufOfs
      
      if @navDiffs and @curIndex isnt endIdx and not @isDiffShowing() and not time
        @highlightDifferences yes
        @loadEditor btn, btnOn
        return
        
    if @diffHilitesOn then @highlightDifferences yes
    atom.views.getView(atom.workspace).focus()
    @statusView?.setMsg @getState()
    @prevIndex = @curIndex
  
  getState: ->
    @updateFileInfo()
    @time = load.getTime @curIndex
    {@time, @curIndex, @lastIndex, @lineCount, @addCount, @delCount}
    
  show: (viewPos) ->
    if @time then @loadEditor null, null, @time
    @time = null
    pane = atom.views.getView atom.workspace.paneForItem @editor
    if @statusView
      @replayView.show()
      @statusView.show()
    else
      #dbg 'creating replay views'
      @statusView = new StatusView @
      pane.appendChild @statusView[0]
      @replayView = new ReplayView @
      pane.appendChild @replayView[0]
    
    @statusView.setMsg @getState()
    @loadEditor()
    if viewPos then setTimeout (=> @setViewPos viewPos, @editor), 100
    # process.nextTick =>
    #   pane.querySelector('.minimap')?.spacePenView.updateMinimapView()

  hide: ->
    @statusView?.hide()
    @replayView?.hide()
    # process.nextTick =>
    #   pane = atom.views.getView atom.workspace.paneForItem @editor
    #   pane.querySelector('.minimap')?.spacePenView.updateMinimapView()

  destroy: ->
    if @editor then delete @editor.liveArchiveEditorMgr
    for editorMgr, i in EditorMgr.editorMgrs
      if editorMgr is @ then delete EditorMgr.editorMgrs[i]
    @statusView?.destroy()
    @replayView?.destroy()
    # @rulerView?.destroy()

  close: ->
    @editor?.destroy()
    @destroy()

  @hideAll = -> for editorMgr in EditorMgr.editorMgrs then editorMgr?.hide()
  
  @closeAllReplayTabs = ->
    workspaceElement = atom.views.getView atom.workspace
    if not workspaceElement.querySelector '.tab-bar' then return
    EditorMgr.hideAll()
    for editor in atom.workspace.getTextEditors()
      if editor.getTitle().indexOf('<- ') is 0
        editor.destroy()
    
  @destroyAll = ->
    for editorMgr in EditorMgr.editorMgrs then editorMgr?.destroy()
    EditorMgr.editorMgrs = []
