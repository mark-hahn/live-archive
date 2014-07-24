
fs          = require 'fs'
LiveArchive = require '../lib/live-archive'
load        = require '../lib/load'
save        = require '../lib/save'

# Use the command `window:run-package-specs` (cmd-alt-ctrl-p) to run specs.
#
# To run a specific `it` or `describe` block add an `f` to the front (e.g. `fit`
# or `fdescribe`). Remove the `f` to unfocus the block.

describe "LiveArchive", ->
  describe "when the live-archive:open is triggered", ->
    beforeEach ->
      @paths = [ process.cwd(), process.cwd() + '/lib/save.coffee' ]
      @path  = load.getPath @paths...

      try
        fs.unlinkSync @path + '/data'
      catch e
      try
        fs.unlinkSync @path + '/index'
      catch e

    it "saves and loads small strings", ->
      v1 = 'text'
      v2 = 'T E xt'
      v3 = 'TexT'

      t1 = save.text @paths..., v1
      t2 = save.text @paths..., v2

      expect(load.text @paths...).toBe v2

      t3 = save.text @paths..., v3, yes

      expect(load.text @paths...,   t2).toBe v2
      expect(load.text @paths...,   t1).toBe v1
      expect(load.text @paths...,   t3).toBe v3
      expect(load.text @paths..., t2+1).toBe v2
      expect(load.text @paths..., t2-1).toBe v1
      expect(load.text @paths...,    0).toBe ''
      expect(load.text @paths..., t3+1).toBe v3
      expect(load.text @paths..., t3-1).toBe v2
      expect(load.text @paths...      ).toBe v3
