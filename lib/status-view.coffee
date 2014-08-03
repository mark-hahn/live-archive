{View} = require 'atom'
util   = require './utils'
dbg    = util.debug 'edmgr'
dbg2   = util.debug 'edmgr', 2

module.exports =
class StatusView extends View
  @content: ->
    @div class: 'live-archive-status', \
         style:'height:25px; background-color:gray; color: white; overflow: hidden;
                padding-top:3px; padding-left:10px; font-size: 13px', =>
      @div class: 'msg', style:'clear:both; float:left'
      @div class: 'modified', \
           style:"float:left; margin-left:10px; color:#f88; display:none", 'Modified'
      @div class: 'not-found', \
           style:"float:left; margin-left:10px; color:#f88; display:none", 'Not Found'

  initialize: (@editorMgr) ->
    dbg 'Status view initialize'
    @moment = require 'moment'
    
  setNotFound: (notFound = yes) ->
    @notFound = notFound
    @setMsg @editorMgr.getState()
    if notFound then setTimeout => 
      @notFound = no
      @setMsg @editorMgr.getState()
      setTimeout => 
        @notFound = yes
        @setMsg @editorMgr.getState()
        setTimeout => 
          @notFound = no
          @setMsg @editorMgr.getState()
        , 2000
      , 250
    , 250

  setMsg: (state) ->
    @$msgDiv      ?= @find '.msg'
    @$modifiedDiv ?= @find '.modified'
    @$notFoundDiv ?= @find '.not-found'
    {modified, time, curIndex, lastIndex, loadDelay, auto} = state
    if modified  then @$modifiedDiv.show() else @$modifiedDiv.hide()
    if @notFound then @$notFoundDiv.show() else @$notFoundDiv.hide()
    time = @moment new Date time * 1000
    @$msgDiv.html 'Version ' + (curIndex+1) + ' of ' + (lastIndex+1) + ' &nbsp;' +
                 (if auto then 'Auto&nbsp;&nbsp;&nbsp;&nbsp;' else 'Saved&nbsp;&nbsp;') +
                 time.format 'YYYY-MM-DD h:mm:ss'

  destroy: -> @detach()
