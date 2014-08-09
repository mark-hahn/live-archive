{View} = require 'atom'
dbg    = require('./utils').debug 'repvw'
dbg2   = require('./utils').debug 'repvw', 2

module.exports =
class ReplayView extends View
  @content: ->
    @div class: 'live-archive-replay', \
                style:'height:52px; font-size: 13px; overflow:hidden;
                       width:1000px; padding: 3px 10px 0 5px; overflow: hidden', =>
      @div style: 'position:relative; top: -2px; width:1000px; height: 15px', =>
        @div style: 'clear: both; float: left; margin-left: 10px', '------------ Navigation ------------'
        @div style: 'float: left; margin-left: 18px', '----- Switch -----'
        @div style: 'float: left; margin-left: 15px', '--- Match ---'
        @div style: 'float: left; margin-left: 15px', '---- Filters ----'
        @div style: 'float: left; margin-left: 13px', '-- Scroll --'
        @div style: 'float: left; margin-left: 18px', '--------- Search ---------'
      
      @div click: 'handle', style: 'clear: both; float: left; width:1000px; height: 15px', =>
        @button style:'margin-left:5px; background-color:#ccc', '|<'
        @button style:'margin-left:5px; background-color:#ccc', '<<'
        @button style:'margin-left:5px; background-color:#ccc', '<'
        @button style:'margin-left:5px; background-color:#ccc', '>'
        @button style:'margin-left:5px; background-color:#ccc', '>>'
        @button style:'margin-left:5px; background-color:#ccc', '>|'
        @button style:'margin-left:15px; background-color:#ccc', 'Back'
        @button style:'margin-left:5px; background-color:#ccc', 'Work'
        @button style:'margin-left:15px; background-color:#ccc', 'Git'
        @button style:'margin-left:5px; background-color:#ccc', 'File'
        @button style:'margin-left:15px; background-color:#ccc', 'Visi'
        @button style:'margin-left:5px; background-color:#ccc', 'Save'
        @select name: 'scrl', style: 'margin-left:15px; width:60px; background-color:#aaa', =>
          @option 'Auto'
          @option 'Save'
          @option 'Lock'
          @option 'Top'
        @button click: 'srchb',  style: 'margin-left:15px; background-color:#ccc', '<'
        @input  name:   'srch',  style: 'margin-left:5px; width:80px; background-color:#aaa'
        @button click: 'srchf',  style: 'margin-left:5px; background-color:#ccc', '>'

  initialize: (@editorMgr) ->
    dbg 'ReplayView initialize'
    @btns = @.find 'button'
    @msg  = @.find '.msg'

  handle: (e) ->
    btn  = e.target.innerText or e.target.nodeName
    $btn = @.find e.target
    dbg2 'handle', btn, $btn
    @editorMgr.loadEditor btn, $btn

  @hideCurrent = -> atom.workspaceView.find('.live-archive-replay').hide()

  destroy: -> @detach()
