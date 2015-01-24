{View} = require 'atom-space-pen-views'
dbg    = require('./utils').debug 'sbvw'

module.exports =
class StatusBarView extends View 
  @content: ->
    @a class: 'msg inline-block text-highlight', href:'#'
 
  initialize: (@liveArchive) ->   
    @click => @liveArchive.openReviewEditor()
    @msg = @find '.msg'
    do waitForStatusBar = =>
      if not (statusBar = document.querySelector 'status-bar')
        setTimeout waitForStatusBar, 100
        return
      statusBar.addLeftTile item: @

  hilite: (hilite) -> 
    switch hilite    
      when 1 then @.removeClass('text-success').addClass('text-highlight')
      when 2 then @.removeClass('text-highlight').addClass('text-success')

  setMsg: (msg, hilite, hiliteDelayed, endMsg) -> 
    @text msg
    @hilite hilite 
    if hiliteDelayed
      setTimeout =>  
        @text endMsg
        @hilite hiliteDelayed
      , 500

  destroy: -> @detach()
