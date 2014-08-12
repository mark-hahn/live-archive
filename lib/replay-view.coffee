{View} = require 'atom'
dbg    = require('./utils').debug 'repvw'

module.exports =
class ReplayView extends View
  @content: ->
    @div class: 'live-archive-replay', \
                style:'height:52px; font-size: 13px; overflow:hidden;
                       width:1000px; padding: 3px 10px 0 5px; overflow: hidden', =>
      @div style: 'position:relative; top: -2px; width:1000px; height: 15px', =>
        @div style: 'clear: both; float: left; margin-left: 6px',  '-- Tab ---'
        @div style: 'float: left; margin-left: 15px', 
                    '----------- Version Navigation ------------'
        @div style: 'float: left; margin-left: 17px', '--- Differences ---'
        @div style: 'float: left; margin-left: 15px', 
                    '---- Search Across Versions -------'
        @div style: 'float: left; margin-left: 15px', '--- Filter ---'
      
      @div click: 'handle', style: 'clear: both; float: left; width:1000px; height: 15px', =>
        @button style:'margin-left:5px; background-color:#ccc', 'Source'
        @button style:'margin-left:15px; background-color:#ccc', 'Git'
        @button style:'margin-left:5px; background-color:#ccc', '|<'
        @button style:'margin-left:5px; background-color:#ccc', '<<'
        @button style:'margin-left:5px; background-color:#ccc', '<'
        @button style:'margin-left:5px; background-color:#ccc', '>'
        @button style:'margin-left:5px; background-color:#ccc', '>>'
        @button style:'margin-left:5px; background-color:#ccc', '>|'
        
        @button style:'margin-left:15px; background-color:#ccc', 'v'
        @button style:'margin-left:5px; background-color:#ccc', onoff: '1', 'Hilite'
        @button style:'margin-left:5px; background-color:#ccc', '^'

        @button style: 'margin-left:15px; background-color:#ccc', '< '
        @input  style: 'margin-left: 5px; width:80px; background-color:#eee'
        @button style: 'margin-left: 5px; background-color:#ccc', ' >'
        @button style: 'margin-left: 5px; background-color:#ccc', onoff: '1', 'In Diffs'

        @button style:'margin-left:15px; background-color:#ccc', onoff: '1', 'Vis Chgs'

  initialize: (@editorMgr) ->
    @btns = @.find 'button'
    @msg  = @.find '.msg'

  handle: (e) ->
    btn  = e.target.innerText or e.target.nodeName
    $btn = @.find e.target
    if $btn.attr('onoff') is '1'
      @btnStates ?= {}
      btnOn = @btnStates[btn] = not @btnStates[btn]
      $btn.css (if btnOn then backgroundColor: '#aaa' else backgroundColor: '#ccc')
    @editorMgr.loadEditor btn, $btn, btnOn

  @hideCurrent = -> atom.workspaceView.find('.live-archive-replay').hide()

  destroy: -> @detach()
