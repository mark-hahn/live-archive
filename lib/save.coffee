
fs       = require 'fs'
pathUtil = require 'path'
mkdirp   = require 'mkdirp'
# compress = require('compress-buffer').compress

dmpmod   = require 'diff_match_patch'
dmp      = new dmpmod.diff_match_patch()

checkFiles = require './checkFiles'
load       = require './load'

IDX_BASE_MASK       = 0x10
IDX_BASE_SHIFT      = 4
IDX_BYTE_COUNT_MASK = 0x03
DIFF_EQUAL  = 0
DIFF_INSERT = 1
DIFF_BASE   = 2
DIFF_DELETE = 3
DIFF_SHIFT  = 4
DIFF_TYPE_MASK  = 0x30
DIFF_TYPE_SHIFT = 4
DIFF_COMPRESSED_MASK  = 0x40
DIFF_COMPRESSED_SHIFT = 6
DIFF_COUNT_CODE_MASK  = 0x0f

saveTime = 0
curPath = curText = indexPath = dataPath = curProjPath = curFilePath = ''

writeUInt48 = (num, buf, ofs) ->
  ms16 = (num / 0x100000000) & 0xffff
  ls32 = num & 0xffffffff
  buf.writeUInt16BE ms16, ofs,   yes
  buf.writeUInt32BE ls32, ofs+2, yes

writeUIntN = (num, n, buf, ofs) ->
  ofs += n
  for i in [0...n] by 1
    buf.writeUInt8 num & 0xff, --ofs, yes
    num /= 0x100

getIndexEntryBuf = (base, saveTime, fileEndPos) ->
  max = 0x10000
  for idxNumBytesInOfs in [2..6] by 1
    if fileEndPos < max or idxNumBytesInOfs is 6 then break
    max *= 0x10
  indexEntryBuf = new Buffer 1 + 6 + idxNumBytesInOfs
  indexEntryBuf.writeUInt8 (if base then IDX_BASE_MASK else 0) | idxNumBytesInOfs, 0, yes
  writeUInt48 saveTime, indexEntryBuf, 1
  writeUIntN fileEndPos, idxNumBytesInOfs, indexEntryBuf, 1 + 6
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

appendDelta = (diffList) ->
  hasBase = no
  deltaLen = 6
  for diff in diffList
    [diffType, diffStr] = diff
    hasBase or= (diffType is DIFF_BASE)
    diffData = diffStr
    compressed = no
    # if isBase then diffData = compress new Buffer diffStr; compressed = yes
    diff[1] = diffBuf = getDiffBuf diffType, diffData, compressed
    deltaLen += diffBuf.length
  deltaLen += 6

  saveTime      = Math.max saveTime + 3, Date.now()
  dataFileLen   = getFileLen dataPath
  indexEntryBuf = getIndexEntryBuf hasBase, saveTime, dataFileLen + deltaLen

  deltaBuf = new Buffer deltaLen
  writeUInt48 saveTime, deltaBuf, 0
  pos = 6
  for diff in diffList
    [diffType, diffBuf] = diff
    diffBuf.copy deltaBuf, pos
    pos += diffBuf.length
  deltaBuf.fill 0xff, pos

  fs.appendFileSync  dataPath,      deltaBuf
  fs.appendFileSync indexPath, indexEntryBuf

setPath = (path) ->
  if path isnt curPath
    curPath = path
    curText = ''
    if path
      indexPath = pathUtil.join path, 'index'
      dataPath  = pathUtil.join path, 'data'
      curText   = load.text curProjPath, curFilePath

save = exports

save.text = (projPath, filePath, text, base = (curText is '')) ->
  [curProjPath, curFilePath] = [projPath, filePath]
  path = load.getPath projPath, filePath
  if path is curPath and text is curText then return saveTime
  setPath path
  diffList = if curText is '' and base then []           \
             else dmp.diff_main curText, text
  if base then diffList.unshift [DIFF_BASE, text]
  curText = text
  appendDelta diffList
  saveTime
