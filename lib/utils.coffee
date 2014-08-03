
util = exports

enableLevel = 2
  
util.debug = (mod, level = 1, enable = yes) ->
  mod = mod[0..4]
  mod += ':'
  while mod.length < 5 then mod += ' '
  (args...) -> if enable and level >= enableLevel 
                 console.log mod, args...
  