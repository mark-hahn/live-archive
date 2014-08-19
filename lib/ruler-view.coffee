# {View, EditorView} = require 'atom'
# dbg    = require('./utils').debug 'rulerv'
# 
# sec  = 1000
# min  = 60 * sec
# hr   = 60 * min
# day  = 24 * hr
# week = 7  * day
# mon  = 30 * day
# year = 365 * day
# minScale  =  5 * sec
# fullScale = 50 * yr
# scale =
#   '30Sec':  30  * sec
#   '2Min':    2  * min
#   '10Min':  10  * min
#   '1Hr':     1  * hr
#   '6Hr':     6  * hr
#   '1Day':    1  * day
#   '1Wk':     1  * week
#   '1Mon':    1  * mon
#   '6Mon':    6  * mon
#   '2Yr':     2  * year
#   '10Yr':   10  * year
# 
# module.exports =
# class RulerView extends View
#   @content: ->
#     @div class: 'live-archive-ruler', \
#                 style:'height:45px; font-size: 11px; overflow:hidden; width:100%;
#                        background-color: black', =>
#       @div style: 'position:relative; top: -2px; width:1000px; height: 15px', =>
# 
#   initialize: (@editorMgr) ->
#     
#   resize: ->
#     w = @width()
#     Math.log w
#     
#     
#   handleClick: (e) ->
# 
#   destroy: -> @detach()
