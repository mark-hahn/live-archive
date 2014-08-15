{View} = require 'atom'
dbg    = require('./utils').debug 'repvw'

module.exports =
class ReplayView extends View
  @content: ->
    @div class: 'live-archive-replay', \
                style:'height:52px; font-size: 13px; overflow:hidden;
                       width:1000px; padding: 3px 10px 0 5px; overflow: hidden', =>
      @div style: 'position:relative; top: -2px; width:1000px; height: 15px', =>
        @div style: 'clear: both; float: left; margin-left: 7px',  '----- Source ------'
        @div style: 'float: left; margin-left: 19px', 
                    '---------------- Version Navigation ---------------'
        @div style: 'float: left; margin-left: 18px', '------ Differences -------'
        @div style: 'float: left; margin-left: 19px', 
                    '---- Search Across Versions -------'
        @div style: 'float: left; margin-left: 16px', '---- All Tabs ----'
      
      @div click: 'handle', style: 'clear: both; float: left; width:1000px; height: 15px', =>
        @button style:'margin-left:5px; background-color:#ccc', 'Open'
        @button style:'margin-left:5px; background-color:#ccc', 'Revert'
        @button style:'margin-left:15px; background-color:#ccc', 'Git'
        @button style:'margin-left:5px; background-color:#ccc', '|<'
        @button style:'margin-left:5px; background-color:#ccc', '<<'
        @button style:'margin-left:5px; background-color:#ccc', '<'
        @button style:'margin-left:5px; background-color:#ccc', '>'
        @button style:'margin-left:5px; background-color:#ccc', '>>'
        @button style:'margin-left:5px; background-color:#ccc', '>|'
        @button style:'margin-left:5px; background-color:#ccc',  onoff: '1', 'Diff'
        
        @button style:'margin-left:15px; background-color:#ccc', onoff: '1', 'Scrl'
        @button style:'margin-left:5px; background-color:#ccc', 'v'
        @button style:'margin-left:5px; background-color:#ccc',  onoff: '1', 'Hilite'
        @button style:'margin-left:5px; background-color:#ccc', '^'

        @button style: 'margin-left:15px; background-color:#ccc', class: 'srchBtn', '<'
        @input  style: 'margin-left: 5px; width:80px; background-color:#eee', class: 'srchInp'
        @button style: 'margin-left: 5px; background-color:#ccc', class: 'srchBtn', '>'
        @button style: 'margin-left: 5px; background-color:#ccc', onoff: '1', 'In Diffs'

        @button style:'margin-left:15px; background-color:#ccc', 'Sync'
        @button style:'margin-left:5px; background-color:#ccc', 'Close'

  initialize: (@editorMgr) ->
    @btns = @find 'button'
    @msg  = @find '.msg'
    @srch = @find '.srchInp'
    
  handle: (e) ->
    btn  = e.target.innerText or e.target.nodeName
    if btn is 'INPUT' then return
    $btn = @find e.target
    if $btn.hasClass 'srchBtn' 
      btn += 'srch'
      val = @srch.val()
    if $btn.attr('onoff') is '1'
      @btnStates ?= {}
      btnOn = @btnStates[btn] = not @btnStates[btn]
      dbg 'handle css', {btn, btnOn, $btn}
      $btn.css (if btnOn then backgroundColor: '#aaa' else backgroundColor: '#ccc')
    @editorMgr.loadEditor btn, btnOn, null, val
    
  setBtn: (btn, btnOn) ->
    $btn = @find 'button:contains("' + btn + '")'
    if $btn.length > 1 then $btn = @.find $btn.get(if btn is 'Diff' then 0 else 1)
    @btnStates ?= {}
    @btnStates[btn] = btnOn
    dbg 'setBtn css', {btn, btnOn, $btn}
    $btn.css (if btnOn then backgroundColor: '#aaa' else backgroundColor: '#ccc')
    @editorMgr.loadEditor btn, btnOn

  @hideCurrent = -> atom.workspaceView.find('.live-archive-replay').hide()

  destroy: -> @detach()
