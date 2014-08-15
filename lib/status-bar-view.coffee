{View} = require 'atom'
dbg    = require('./utils').debug 'sbvw'

module.exports =
class StatusBarView extends View 
  @content: ->
    @div class: 'live-archive inline-block', \
          style: 'font-size: 12px; color: black; cursor: pointer; border-radius: 3px'
 
  initialize: (@liveArchive) ->   
    @hover (=> @css textDecoration: 'underline')
    ,      (=> @css textDecoration: 'none')
    @click => @liveArchive.openReviewEditor()
    do tryIt = =>
      if not (sb = atom.workspaceView.statusBar) 
        setTimeout tryIt, 100
        return
      sb.appendLeft this
 
  hilite: (hilite) -> 
    switch hilite    
      when 1 then @.css backgroundColor: 'transparent'
      when 2 then @.css backgroundColor: '#f66'

  setMsg: (msg, hilite, hiliteDelayed, endMsg) -> 
    @.text msg
    @hilite hilite 
    if hiliteDelayed
      setTimeout =>  
        @.text endMsg
        @hilite hiliteDelayed
      , 500

  destroy: -> @detach()
