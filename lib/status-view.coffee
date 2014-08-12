{View} = require 'atom'
util   = require './utils'
#dbg    = util.debug 'edmgr'
 
module.exports =
class StatusView extends View
  @content: ->
    @div class: 'live-archive-status', \
         style:'height:23px; background-color:gray; color: white; overflow: hidden;
                padding-top:1px; padding-left:10px; font-size: 13px', =>
      @div class: 'msg', style:'clear:both; float:left'
      @div class: 'not-found', \
           style:"float:left; margin-left:10px; color:#f88; display:none", 'Not Found'

  initialize: (@editorMgr) ->
    @moment = require 'moment'
    
  setNotFound: (notFound = yes) ->
    @notFound = notFound
    @setMsg @editorMgr.getState()
    util.callbackWithDelays [250,250,2000, 0], (i) =>
      @notFound = (i & 1) is 0
      @setMsg @editorMgr.getState()
    
  setMsg: (state) ->
    @$msgDiv      ?= @find '.msg'
    @$notFoundDiv ?= @find '.not-found'
    {time, curIndex, lastIndex, loadDelay, auto} = state
    if @notFound then @$notFoundDiv.show() else @$notFoundDiv.hide()
    time = @moment new Date time * 1000
    @$msgDiv.html 'Version ' + (curIndex+1) + ' of ' + (lastIndex+1) + 
                  ',&nbsp;&nbsp;&nbsp;&nbsp;Saved&nbsp;&nbsp;' +
                 time.format('ddd') + '&nbsp;&nbsp;' +
                 time.format('YYYY-MM-DD HH:mm:ss') + ',&nbsp; &nbsp;' +
                 time.fromNow()
                 

  destroy: -> @detach()
