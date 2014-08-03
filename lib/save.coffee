
fs       = require 'fs'
pathUtil = require 'path'
mkdirp   = require 'mkdirp'
dbg      = require('./utils').debug 'save'

# compress = require('compress-buffer').compress

dmpmod   = require 'diff_match_patch'
dmp      = new dmpmod.diff_match_patch()

checkFiles = require './checkFiles'
load       = require './load'

IDX_BASE_MASK = 0x10
IDX_AUTO_MASK = 0x20
DIFF_EQUAL  = 0
DIFF_INSERT = 1
DIFF_BASE   = 2
DIFF_DELETE = 3
DIFF_SHIFT  = 4
DIFF_COMPRESSED_MASK  = 0x40

saveTime = 0
curPath = curText = indexPath = dataPath = null

getUIntVBuf = (num) ->
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

getIndexEntryBuf = (auto, base, fileEndPos) ->
  max = 0x10000
  for idxNumBytesInOfs in [2..6] by 1
    if fileEndPos < max or idxNumBytesInOfs is 6 then break
    max *= 0x100
  indexEntryBuf = new Buffer 1 + idxNumBytesInOfs
  idxHdrByte = (if auto then IDX_AUTO_MASK else 0) | 
               (if base then IDX_BASE_MASK else 0) | idxNumBytesInOfs
  indexEntryBuf.writeUInt8 idxHdrByte,  0, yes
  writeUIntN fileEndPos, idxNumBytesInOfs, indexEntryBuf, 1
  indexEntryBuf

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

getFileLen = (path) ->
  try
    stats = fs.statSync path
  catch e
    fs.closeSync fs.openSync path, 'a'
    return 0
  stats.size

appendDelta = (lineNum, charOfs, diffList, auto) ->
  hasBase = no
  lineNumBuf = getUIntVBuf lineNum
  lineNumLen = lineNumBuf.length
  charOfsBuf = getUIntVBuf charOfs
  charOfsLen = charOfsBuf.length
  deltaLen = 1 + 4 + lineNumLen + charOfsLen
  for diff in diffList
    [diffType, diffStr] = diff
    hasBase or= (diffType is DIFF_BASE)
    diffData = diffStr
    compressed = no
    # if isBase then diffData = compress new Buffer diffStr; compressed = yes
    diff[1] = diffBuf = getDiffBuf diffType, diffData, compressed
    deltaLen += diffBuf.length
  deltaLen += 4

  saveTime      = Math.max saveTime + 3, Math.floor Date.now() / 1000
  dataFileLen   = getFileLen dataPath
  indexEntryBuf = getIndexEntryBuf auto, hasBase, dataFileLen + deltaLen

  deltaBuf = new Buffer deltaLen
  deltaBuf.writeUInt8 (lineNumLen << 2) | charOfsLen, 0
  deltaBuf.writeUInt32BE saveTime, 1, yes
  pos = 5
  lineNumBuf.copy deltaBuf, pos; pos += lineNumLen
  charOfsBuf.copy deltaBuf, pos; pos += charOfsLen
  for diff in diffList
    [diffType, diffBuf] = diff
    diffBuf.copy deltaBuf, pos
    pos += diffBuf.length
  deltaBuf.fill 0xff, pos
  
  fs.appendFileSync  dataPath,      deltaBuf
  fs.appendFileSync indexPath, indexEntryBuf

setPath = (path, projPath, filePath) ->
  if path isnt curPath
    curPath = path
    curText = null
    if path
      indexPath = pathUtil.join path, 'index'
      dataPath  = pathUtil.join path, 'data'
      curText   = load.text(projPath, filePath).text

save = exports

save.text = (projPath, filePath, text, lineNum, charOfs, base, auto) ->
  {path, indexFileSize} = load.getPath projPath, filePath
  if not path or path is curPath and text is curText then return no
  setPath path, projPath, filePath
  diffList = (if indexFileSize is 0 or base then [[DIFF_BASE, text]] else [])
  if curText? and indexFileSize 
    diffList = diffList.concat dmp.diff_main curText, text
  hasChange = no
  for diff in diffList then if diff[0] isnt 0 then hasChange = yes; break
  if hasChange then appendDelta lineNum, charOfs, diffList, auto
  curText = text
  hasChange
