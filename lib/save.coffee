
fs       = require 'fs'
pathUtil = require 'path'
zlib     = require 'zlib'
mkdirp   = require 'mkdirp'
dbg      = require('./utils').debug 'save'
dmpmod   = require 'diff_match_patch'
dmp      = new dmpmod.diff_match_patch()
load     = require './load'

BASE_MASK = 0x10

DIFF_EQUAL  = 0
DIFF_INSERT = 1
DIFF_BASE   = 2
DIFF_DELETE = 3
DIFF_SHIFT  = 4
DIFF_COMPRESSED_MASK = 0x40

saveTime = 0
curPath = curText = dataFileSize = curPath = null

getUIntVBuf = (num) ->
  num
  digits = []
  loop
    digits.unshift num & 0xff
    num = Math.floor num / 0x100
    break if num is 0
  buf = new Buffer digits.length
  for digit, i in digits
    buf.writeUInt8 digit, i, yes
  buf

writeUIntN = (num, n, buf, ofs) ->
  ofs += n
  for i in [0...n] by 1
    buf.writeUInt8 num & 0xff, --ofs, yes
    num /= 0x100

getDiffBuf = (diffType, diffData, compressed) ->
  diffTypeShifted   = (diffType & 3) << DIFF_SHIFT
  compressedShifted = (if compressed then DIFF_COMPRESSED_MASK else 0)
  diffTypeIsEqual   = (diffType is DIFF_EQUAL)
  diffDataIsString  = (typeof diffData is 'string')
  diffDataLen =
    if diffTypeIsEqual then 0
    else if diffDataIsString then Buffer.byteLength diffData
    else diffData.length
  lenInHdr = (if diffTypeIsEqual then diffData.length else diffDataLen)
  if lenInHdr <= 9
    diffBuf = new Buffer 1 + diffDataLen
    diffBuf.writeUInt8 compressedShifted | diffTypeShifted | lenInHdr, 0
    diffDataOfs = 1
  else
    max = 0x100
    for numBytesInDiffDataLen in [1..6]
      if lenInHdr < max or numBytesInDiffDataLen is 6 then break
      max *= 0x100
    diffBuf = new Buffer 1 + numBytesInDiffDataLen + diffDataLen
    diffBuf.writeUInt8 compressedShifted | diffTypeShifted | (numBytesInDiffDataLen + 9), 0
    ofs = numBytesInDiffDataLen
    num = lenInHdr
    for i in [1..numBytesInDiffDataLen] by 1
      diffBuf.writeUInt8 (num & 0xff), ofs--
      num /= 0x100
    diffDataOfs = numBytesInDiffDataLen + 1
  if not diffTypeIsEqual
    if diffDataIsString then diffBuf.write diffData, diffDataOfs
    else                     diffData.copy diffBuf,  diffDataOfs
  diffBuf

appendDelta = (diffList) ->
  deltaHdrBufLen = 1 + 4
  
  diffsLen = 0
  for diff in diffList
    [diffType, diffData] = diff
    compressed = no
    if diffType isnt DIFF_EQUAL
      compressedText = zlib.deflateSync diffData
      # dbg 'compression test', diffData.length, Buffer.byteLength(diffData), compressedText.length
      if compressedText.length < Buffer.byteLength diffData
        diffData = compressedText
        # dbg 'using compressed'
        compressed = yes
    diff[1] = diffBuf = getDiffBuf diffType, diffData, compressed
    diffsLen += diffBuf.length
  
  deltaLen = 1 + 0 + 4 + diffsLen + 4

  for deltaLenLenTrial in [1..6]
    deltaLenLen = 1
    num = Math.floor (deltaLen + deltaLenLenTrial) / 0x100
    while num > 0
        deltaLenLen++
        num = Math.floor num / 0x100
    if deltaLenLen <= deltaLenLenTrial then break
  deltaLenLen = deltaLenLenTrial
    
  deltaLen += deltaLenLenTrial

  deltaBuf = new Buffer deltaLen
  deltaHdrByte = deltaLenLenTrial
  deltaBuf.writeUInt8 deltaHdrByte, 0, yes
  writeUIntN deltaLen, deltaLenLenTrial, deltaBuf, 1
  pos = 1 + deltaLenLenTrial
  saveTime = Math.max saveTime + 3, Math.floor Date.now() / 1000
  deltaBuf.writeUInt32BE saveTime, pos, yes
  pos += 4
  for diff in diffList
    [diffType, diffBuf] = diff
    diffBuf.copy deltaBuf, pos
    pos += diffBuf.length
  deltaBuf.fill 0xff, pos
  
  fs.appendFileSync curPath, deltaBuf

save = exports

save.trackPos = (text1, text2, posIn) ->
  numPos = 0; for i of posIn then numPos++
  textPosIn = textPosOut = diffIdx = done = 0
  posOut = {}
  for diff in dmp.diff_main text1, text2
    [type, str] = diff
    len = str.length
    endTextPosIn = textPosIn + len
    switch type
      when 0  # EQUAL
        for key, pos of posIn
          if pos < endTextPosIn 
            posOut[key] = pos + (textPosOut - textPosIn)
            delete posIn[key]
            if --numPos is 0 then return posOut
        textPosIn  += len
        textPosOut += len
      when -1 # DELETE
        for key, pos of posIn
          if pos < endTextPosIn
            posOut[key] = textPosOut
            delete posIn[key]
            if --numPos is 0 then return posOut
        textPosIn  += len
      else # +1 INSERT
        for key, pos of posIn
          if pos <= textPosIn
            posOut[key] = pos
            delete posIn[key]
            if --numPos is 0 then return posOut
        textPosOut += len
  for key of posIn
    posOut[key] = pos + (textPosOut - textPosIn)
  posOut
  
save.text = (projPath, filePath, text, base) ->
  {path, dataFileSize} = load.getPath projPath, filePath
  if not path or path is curPath and text is curText then return no
  if path isnt curPath
    curPath = path
    curText = (if path then load.text(projPath, filePath).text)
  diffList = (if dataFileSize is 0 or base then [[DIFF_BASE, text]] else [])
  if curText? and dataFileSize 
    diffList = diffList.concat dmp.diff_main curText, text
    dmp.diff_cleanupSemantic diffList
  hasChange = no
  for diff in diffList then if diff[0] isnt 0 then hasChange = yes; break
  if hasChange then appendDelta diffList
  curText = text
  hasChange
