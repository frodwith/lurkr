express = require 'express'
zmq     = require 'zmq'
fs      = require 'fs'
async   = require 'async'
path    = require 'path'
io      = require 'socket.io'
crypto  = require 'crypto'

headers = (req, res, next) ->
    res.header 'Date', new Date().toString()
    res.header 'Access-Control-Allow-Origin', '*'
    next()

app = express.createServer headers
sio = io.listen app
sio.set 'log level', 1
sio.sockets.on 'connection', (socket) ->
    socket.on 'join', (room) ->
        socket.join room

config = do ->
    o = JSON.parse(fs.readFileSync 'config.json')
    o.baseUrl = o.baseUrl.replace /\/$/, ''
    o.socketUrl or= o.baseUrl
    return o

start = ->
    live = zmq.socket 'sub'
    live.on 'message', (msg) ->
        obj = JSON.parse msg.toString()
        sio.sockets.in(obj.channel).emit 'chat', obj

    live.setsockopt zmq.ZMQ_SUBSCRIBE, new Buffer ''
    live.connect config.bot.live
    app.listen(config.web.port or 8080)

link_to = (parts...) ->
    parts.unshift config.baseUrl
    parts.join '/'

cacheReply = ({req, res, next, etag, forever, lastModified, send}) ->
    res.header 'Last-Modified', lastModified.toString()

    # For our purposes, either a thing never changes or it always does.
    if forever
        d = new Date()
        d.setFullYear d.getFullYear() + 10
        res.header 'Expires', d.toString()
    else
        res.header 'Cache-Control', 'max-age=0'

    etag = '"' + etag + '"'
    res.header 'ETag', etag

    since = Date.parse req.header 'if-modified-since'
    if not isNaN(since) and lastModified <= new Date(since)
        res.send 304
        return

    if inm = req.header 'If-None-Match'
        for t in inm.split /,\s*/
            if t is etag
                res.send 304
                return

    send()

class Cacheable
    cache = {}

    # This is a shortcut, in case all you care about is the cached data. If
    # you want all the cache info call getCache().
    get: (cb) ->
        @getCache (err, c) ->
            cb err, c and c.data

    checksum: (c) ->
        # No default checksumming, but see StringCache.
        return null

    getCache: (cb) ->
        @timestamp (err, stamp) =>
            return cb err if err
            key = @key or @constructor.name
            c = cache[key] or= {}

            # anything <= null == false
            # anything >  null == false
            # Don't reverse this condition.
            if stamp <= c.timestamp
                cb null, c
            else
                @fetch (err, data) =>
                    return cb err if err
                    c.data = data
                    c.timestamp = stamp
                    c.checksum  = @checksum c
                    cb null, c

# These represent final responses to the user (i.e., the data returned from
# get() is a string). As such, they have a reply method with HTTP cache
# semantics.
class StringCache extends Cacheable
    checksum: (c) ->
        sum = crypto.createHash 'sha1'
        sum.update c.data
        sum.digest 'base64'

    reply: (req, res, next) ->
        @getCache (err, c) =>
            cacheReply
                req: req
                res: res
                next: next
                lastModified: c.timestamp
                etag: c.checksum
                send: ->
                    res.contentType 'json'
                    res.end c.data

class BotInfo extends Cacheable
    constructor: ->
        @sock = zmq.socket 'req'
        @sock.connect config.bot.info or 'tcp://127.0.0.1:8666'

    req: (cmd, cb) ->
        @sock.once 'message', (msg) ->
            try
                data = JSON.parse(msg.toString())
            catch e
                err = e
            cb err, data
        @sock.send cmd

    timestamp: (cb) -> @req 'timestamp', (err, data) ->
        if err then cb err else cb null, new Date(data.timestamp)

    fetch: (cb) -> @req 'channels', cb

class DataDir extends Cacheable
    timestamp: (cb) ->
        fs.stat config.dataDir, (err, stats) ->
            if err then cb err else
                cb null, stats.mtime

    fetch: (cb) ->
        fs.readdir config.dataDir, (err, files) ->
            if err then cb err else
                cb null, files

class ChannelSet extends Cacheable
    constructor: ->
        @info = new BotInfo()
        @dir  = new DataDir()

    timestamp: (cb) ->
        tasks =
            info: (cb) => @info.timestamp cb
            dir:  (cb) => @dir.timestamp cb

        async.parallel tasks, (err, {info, dir}) ->
            if err then cb err else
                cb null, if info > dir then info else dir

    fetch: (cb) ->
        tasks =
            info: (cb) => @info.get cb
            dir:  (cb) => @dir.get cb

        async.parallel tasks, (err, {info, dir}) ->
            return cb err if err
            set    = {}
            set[n] = true for n of info
            set[n] = true for n in dir
            cb null, set

class ChannelList extends StringCache
    constructor: ->
        @set = new ChannelSet()

    timestamp: (cb) -> @set.timestamp cb

    fetch: (cb) ->
        @set.get (err, set) ->
            if err then cb err else
                list = (link_to n for n of set)
                cb null, JSON.stringify list

class ChannelInfo extends StringCache
    constructor: (@name) ->
        @key = '#' + name
        @info = new BotInfo()

    timestamp: (cb) -> @info.timestamp cb

    fetch: (cb) ->
        @info.get (err, info) =>
            return cb err if err
            live = info[@name]?
            chan = info[@name] or {}

            if live
                chan.socket =
                    server: config.socketUrl
                    room:   @name
            else
                chan.channel = 'offline'
                chan.host    = 'offline'
                chan.port    = 'offline'
            chan.archive = link_to @name, 'archive'
            chan.current = link_to @name, 'current'
            cb null, JSON.stringify chan

class ChannelArchive extends StringCache
    constructor: (@name) ->
        @key = "\##{@name}/archive"
        @dir = path.join config.dataDir, @name

    timestamp: (cb) ->
        fs.stat @dir, (err, stats) ->
            if err
                if err.code is 'ENOENT'
                    cb null, new Date()
                else
                    cb err
            else
                cb null, stats.mtime

    fetch: (cb) ->
        fs.readdir @dir, (err, files) =>
            return cb err if err and err.code isnt 'ENOENT'
            result = {}

            unless err # the ENOENT case is just an empty result
                for f in files when m = f.match /^(\d+).gz$/
                    s = parseInt m[1]
                    result[s] = link_to @name, 'archive', s

            cb null, JSON.stringify result

if_chan = (call) ->
    return (req, res, next) ->
        name = req.params.chan
        new ChannelSet().get (err, set) ->
            unless set[name]?
                res.contentType 'text'
                res.send "The #{name} channel does not exist", 404
            else
                call name, req, res, next

app.get '/', (req, res, next) ->
    new ChannelList().reply req, res, next

app.get '/:chan', if_chan (name, req, res, next) ->
    new ChannelInfo(name).reply req, res, next

app.get '/:chan/archive', if_chan (name, req, res, next) ->
    new ChannelArchive(name).reply req, res, next

serveLog = (log, archive, req, res, next) ->
    fs.stat log, (err, stats) ->
        if err
            if err.code is 'ENOENT' then next() else next(err)
            return

        sum = crypto.createHash 'sha1'
        sum.update log
        sum.update stats.mtime.toString()

        cacheReply
            req: req
            res: res
            next: next
            forever: archive
            lastModified: stats.mtime
            etag: sum.digest 'base64'
            send: ->
                res.contentType 'text'
                if archive
                    hdr = req.header('Accept-Encoding') or ''
                    gzip = false
                    for e in hdr.split /,\s*/
                        if e is 'gzip'
                            gzip = true
                            break

                    unless gzip
                        res.send 'Clients must support Content-Encoding: gzip',
                                 406
                        return
                    res.header 'Content-Encoding', 'gzip'
                    res.header 'Vary', 'Accept-Encoding'

                stream = fs.createReadStream log
                stream.pipe res

app.get '/:chan/current', if_chan (name, req, res, next) ->
    p = path.join config.dataDir, name, 'current'
    serveLog p, false, req, res, next

app.get '/:chan/archive/:stamp', if_chan (name, req, res, next) ->
    p = path.join config.dataDir, name, req.params.stamp + '.gz'
    serveLog p, true, req, res, next
 
app.get '*', (req, res) ->
    res.contentType 'text'
    res.send 'Not found', 404

start()
