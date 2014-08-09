
fs       = require 'fs'
pathUtil = require 'path'
mkdirp   = require 'mkdirp'
dbg      = require('./utils').debug 'save'

# {compress} = require 'compress-buffer'

dmpmod   = require 'diff_match_patch'
dmp      = new dmpmod.diff_match_patch()

checkFiles = require './checkFiles'
load       = require './load'

AUTO_MASK = 0x20
BASE_MASK = 0x10

DIFF_EQUAL  = 0
DIFF_INSERT = 1
DIFF_BASE   = 2
DIFF_DELETE = 3
DIFF_SHIFT  = 4
DIFF_COMPRESSED_MASK  = 0x40

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

appendDelta = (lineNum, charOfs, diffList, auto) ->
  hasBase = no
  lineNumBuf = getUIntVBuf lineNum
  lineNumLen = lineNumBuf.length
  charOfsBuf = getUIntVBuf charOfs
  charOfsLen = charOfsBuf.length
  deltaHdrBufLen = 1 + 4 + 1 + lineNumLen + charOfsLen
  
  diffsLen = 0
  for diff in diffList
    [diffType, diffStr] = diff
    hasBase or= (diffType is DIFF_BASE)
    diffData = diffStr
    compressed = no
    # if hasBase then diffData = compress new Buffer diffStr; compressed = yes
    diff[1] = diffBuf = getDiffBuf diffType, diffData, compressed
    diffsLen += diffBuf.length
  
  deltaLen = 1 + 0 + 4 + 1 + lineNumLen + charOfsLen + diffsLen + 4

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
  if auto    then deltaHdrByte |= AUTO_MASK
  if hasBase then deltaHdrByte |= BASE_MASK
  deltaBuf.writeUInt8 deltaHdrByte, 0, yes
  writeUIntN deltaLen, deltaLenLenTrial, deltaBuf, 1
  pos = 1 + deltaLenLenTrial
  saveTime = Math.max saveTime + 3, Math.floor Date.now() / 1000
  deltaBuf.writeUInt32BE saveTime, pos, yes
  pos += 4
  deltaBuf.writeUInt8 ((lineNumLen-1) << 4) | (charOfsLen-1), pos++, yes
  lineNumBuf.copy deltaBuf, pos; pos += lineNumLen
  charOfsBuf.copy deltaBuf, pos; pos += charOfsLen
  for diff in diffList
    [diffType, diffBuf] = diff
    diffBuf.copy deltaBuf, pos
    pos += diffBuf.length
  deltaBuf.fill 0xff, pos
  
  fs.appendFileSync curPath, deltaBuf

save = exports

save.text = (projPath, filePath, text, lineNum, charOfs, base, auto) ->
  {path, dataFileSize} = load.getPath projPath, filePath
  if not path or path is curPath and text is curText then return no
  if path isnt curPath
    curPath = path
    curText = (if path then load.text(projPath, filePath).text)
  diffList = (if dataFileSize is 0 or base then [[DIFF_BASE, text]] else [])
  if curText? and dataFileSize 
    diffList = diffList.concat dmp.diff_main curText, text
  hasChange = no
  for diff in diffList then if diff[0] isnt 0 then hasChange = yes; break
  if hasChange then appendDelta lineNum, charOfs, diffList, auto
  curText = text
  hasChange
