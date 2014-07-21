
load = require './load'
save = require './save'

module.exports =

  activate: ->
    atom.workspaceView.command "live-archive:open", => @open()

  open: ->

    fs = require 'fs'
    console.log 'live-archive test'

    try
      fs.unlinkSync 'test/data'
    catch e
    try
      fs.unlinkSync 'test/index'
    catch e

    save.text 'test', 'ABCDEF'
    save.text 'test', 'ABCabcDEFdef'
    save.text 'test', 'ABCabcdef'
    res = load.text 'test'
    console.log res is 'ABCabcdef', res

    console.log 'test finished'
