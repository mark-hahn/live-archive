
load = require './load'
save = require './save'

module.exports =

  activate: ->
    console.log 'activate'
    atom.workspaceView.command "live-archive:open", => @open()

  open: ->
    debugger
    save.text 'test', 'ABCDEF'
    save.flush()
