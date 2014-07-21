
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

    t1 = save.text 'test', 'ABCDEF'
    t2 = save.text 'test', 'ABCabcDEFdef'

    res = load.text 'test'
    console.log 'last1', 'ABCabcDEFdef', res is 'ABCabcDEFdef', res

    t3 = save.text 'test', 'ABCabcdef'

    res = load.text 'test', t2
    console.log 't2', 'ABCabcDEFdef', res is 'ABCabcDEFdef', res

    res = load.text 'test', t2 + 1
    console.log 't2+1', 'ABCabcDEFdef', res is 'ABCabcDEFdef', res

    res = load.text 'test', t2 - 1
    console.log 't2-1', 'ABCDEF', res is 'ABCDEF', res

    res = load.text 'test', 0
    console.log '0', '', res is '', res

    res = load.text 'test', t3+1
    console.log 't3+1', 'ABCabcdef', res is 'ABCabcdef', res

    res = load.text 'test'
    console.log 'last2', 'ABCabcdef', res is 'ABCabcdef', res

    console.log 'test finished'
