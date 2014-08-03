{View} = require 'atom'
dbg    = require('./utils').debug 'sbvw'

module.exports =
class StatusBarView extends View
  @content: ->
    @div class: 'live-archive inline-block', style: 'font-size: 12px; color: black'

  initialize: -> 
    atom.workspaceView.statusBar.appendLeft this

  hilite: (hilite) ->
    switch hilite
      when 1 then @.css color: 'black'
      when 2 then @.css color: 'red'

  setMsg: (msg, hilite, hiliteDelayed) ->
    @.text msg
    @hilite hilite
    if hiliteDelayed
      setTimeout (=> @hilite hiliteDelayed), 500

  destroy: -> @detach()
