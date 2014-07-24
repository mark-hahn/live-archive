
load = require './load'
save = require './save'

module.exports =

  activate: ->
    atom.workspaceView.command "live-archive:open", => @open()

    # atom.workspace.eachEditor (editor) ->
    #   buffer = editor.getBuffer()
    #   # buffer.on 'will-be-saved', -> console.log 'will-be-saved'
    #   buffer.on 'saved', ->
    #     root = atom.project.getRootDirectory().path
    #     console.log 'archiving', root, buffer.getUri()
    #     strt = Date.now()
    #     save.text root, buffer.getUri(), buffer.getText()
    #     console.log 'duration', Date.now() - strt

  open: ->
