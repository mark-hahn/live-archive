{View} = require 'atom'
_ = require 'underscore-plus'
_.str = require 'underscore.string'

dbg = require('./utils').debug 'repvw'

module.exports =
class ReplayView extends View
  @content: ->
    @div 
        class: 'live-archive-replay block'
        click: 'handle'
        style:'height:35px; margin-top: 10px; font-size: 14px'
    , =>
      @div class: 'btn-group', style:'margin-left:10px', =>
        @div class:'btn', 'Source'
        @div class:'btn', 'Revert'
          
      @div class: 'btn-group', =>
        @div class:'btn', style:'margin-left:15px', 'Git'
        @div class:'btn', '|<'
        @div class:'btn', '<<'
        @div class:'btn', '<'
        @div class:'btn', '>'
        @div class:'btn', '>>'
        @div class:'btn', '>|'
        @div class:'btn toggle', 'Diff'

      @div class: 'btn-group', style:'margin-left:15px', =>
        @div class:'btn toggle', 'Scrl'
        @div class:'btn', 'v'
        @div class:'btn toggle', 'Hilite'
        @div class:'btn', '^'

      # @div class: 'btn-group', =>
      @div class:'btn srchBtn', style:'margin-left:15px', '<'
      @input 
        placeholder: 'Search Text'
        class: 'native-key-bindings srchInp'
        style: 'position:relative; top:2px; height: 22px; width: 80px; 
                font-size: 14px; font-color: white; background-color: rgba(128,128,128,0.3)'
      @div class:'btn srchBtn', '>'
      @div class:'btn toggle', 'In Diffs'
        
      @div class: 'btn-group', style:'margin-left:15px', =>
        @div class:'btn', 'Sync All'
        @div class:'btn', 'Close All'

  initialize: (@editorMgr) ->
    @srch = @find '.srchInp'
  
  handle: (e) ->
    btn  = e.target.innerText or e.target.nodeName
    $btn = @find e.target
    if $btn.hasClass 'srchInp' then return
    if $btn.hasClass 'srchBtn' 
      btn += 'srch'
      val = _.str.trim @srch.val()
      # dbg 'handle',  {val, srchVal: @srch.val()}
      if not val then return
    if $btn.hasClass 'toggle'
      @btnStates ?= {}
      btnOn = @btnStates[btn] = not @btnStates[btn]
      # dbg 'handle css', {btn, btnOn, $btn}
      if btnOn then $btn.addClass 'selected' else $btn.removeClass 'selected'
    @editorMgr.loadEditor btn, btnOn, null, val
    
  setBtn: (btn, btnOn) ->
    $btn = @find ':contains("' + btn + '"):not(.btn-group)'
    if $btn.length > 1 then $btn = @find $btn.get(if btn is 'Diff' then 0 else 1)
    @btnStates ?= {}
    @btnStates[btn] = btnOn
    # dbg 'setBtn css', {btn, btnOn, $btn}
    if btnOn then $btn.addClass 'selected' else $btn.removeClass 'selected'
    @editorMgr.loadEditor btn, btnOn

  @hideCurrent = -> atom.workspaceView.find('.live-archive-replay').hide()

  destroy: -> @detach()
