express = require 'express'
zmq     = require 'zmq'
fs      = require 'fs'
async   = require 'async'
path    = require 'path'
io      = require 'socket.io'

xss = (req, res, next) ->
    res.header 'Access-Control-Allow-Origin', '*'
    next()

app = express.createServer(xss)
sio = io.listen(app)
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

class Cacheable
    cache = {}
    get: (cb) ->
        @timestamp (err, stamp) =>
            return cb err if err
            key = @key or @constructor.name
            c = cache[key] or= {}

            # anything <= null == false
            # anything >  null == false
            # Don't reverse this condition.
            if stamp <= c.timestamp
                cb null, c.data
            else
                @fetch (err, data) =>
                    return cb err if err
                    c.timestamp = stamp
                    cb null, c.data = data

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
        if err then cb err else cb null, data

    fetch: (cb) -> @req 'channels', cb

class DataDir extends Cacheable
    timestamp: (cb) ->
        fs.stat config.dataDir, (err, stats) ->
            if err then cb err else
                cb null, stats.mtime.getTime()

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
                cb null, Math.max(info, dir)

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

class ChannelList extends Cacheable
    constructor: ->
        @set = new ChannelSet()

    timestamp: (cb) -> @set.timestamp cb

    fetch: (cb) ->
        @set.get (err, set) ->
            if err then cb err else
                list = (link_to n for n of set)
                cb null, JSON.stringify list

class ChannelInfo extends Cacheable
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

class ChannelArchive extends Cacheable
    constructor: (@name) ->
        @key = "\##{@name}/archive"
        @dir = path.join config.dataDir, @name

    timestamp: (cb) ->
        fs.stat @dir, (err, stats) ->
            if err then cb err else cb null, stats.mtime.getTime()

    fetch: (cb) ->
        fs.readdir @dir, (err, files) =>
            return cb err if err
            result = {}
            for f in files when m = f.match /^(\d+).gz$/
                s = parseInt m[1]
                result[s] = link_to @name, 'archive', s

            cb null, JSON.stringify result

if_chan = (call) ->
    return (req, res, next) ->
        name = req.params.chan
        new ChannelSet().get (err, set) ->
            unless set[name]?
                res.statusCode
                res.contentType 'text'
                res.end "The #{name} channel does not exist"
            else
                call name, req, res, next

app.get '/', (req, res, next) ->
    new ChannelList().get (err, json) ->
        return next err if err
        res.contentType 'json'
        res.end(json)

app.get '/:chan', if_chan (name, req, res, next) ->
    new ChannelInfo(name).get (err, json) ->
        return next err if err
        res.contentType 'json'
        res.send json

app.get '/:chan/archive', if_chan (name, req, res, next) ->
    new ChannelArchive(name).get (err, json) ->
        if err
            if err.code is 'ENOENT'
                res.send []
            else
                next err
        else
            res.contentType 'json'
            res.end json

app.get '/:chan/current', if_chan (name, req, res, next) ->
    curfile = path.join config.dataDir, name, 'current'
    fs.stat curfile, (err, stats) ->
        if err and err.code isnt 'ENOENT'
            next err
        res.contentType 'text'
        if err then res.send '' else res.sendfile curfile

app.get '/:chan/archive/:stamp', if_chan (name, req, res, next) ->
    archive = path.join config.dataDir, name, req.params.stamp + '.gz'
    fs.stat archive, (err, stats) ->
        if err
            if err.code is 'ENOENT'
                res.send 404
            else
                next err
        else
            res.contentType 'text'
            res.header 'Content-Encoding', 'gzip'
            res.sendfile archive

start()
