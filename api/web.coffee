express = require 'express'
zmq     = require 'zmq'
fs      = require 'fs'
async   = require 'async'

xss = (req, res, next) ->
    res.header 'Access-Control-Allow-Origin', '*'
    next()

app = express.createServer(xss)

readConfig = ->
    config =
        baseUrl: "http://localhost:8080/"
        dataDir: "/Users/pdriver/code/lurkr/new-data"
    config.baseUrl = config.baseUrl.replace /\/$/, ''
    return config

config = readConfig()

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
        @sock = zmq.socket('req')
        @sock.connect('tcp://127.0.0.1:8666')

    req: (cmd, cb) ->
        @sock.once 'message', cb
        @sock.send cmd

    timestamp: (cb) ->
        @req 'timestamp', (msg) ->
            cb null, JSON.parse(msg.toString()).timestamp

    fetch: (cb) ->
        @req 'channels', (msg) ->
            cb null, JSON.parse(msg.toString())

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
            chan.socket = "a sensible socket.io url for #{@name}" if live
            chan.archive = link_to @name, 'archive'
            chan.current = link_to @name, 'current'
            cb null, JSON.stringify chan

app.get '/', (req, res) ->
    res.header 'Content-Type', 'application/json'
    new ChannelList().get (err, json) ->
        throw err if err
        res.send(json)

app.get '/:chan', (req, res) ->
    res.header 'Content-Type', 'application/json'
    name = req.params.chan
    new ChannelSet().get (err, set) ->
        throw err if err
        unless set[name]?
            res.send 404
        else
            new ChannelInfo(name).get (err, json) ->
                throw err if err
                res.send json

app.listen(8080)

###
            result = {}
            for k, v of @config.channels
                result[k] = @path k
            res.send result

        @app.get '/:chan', (req, res) =>
            name = req.params.chan
            unless chan = @config.channels[name]
                res.send 404
                return
            net  = @config.networks[chan.network]
            res.send
                host: net.host
                port: net.port
                nick: net.nick
                channel: chan.channel
                socket:  @path name
                archive: @path name, 'archive'
                current: @path name, 'current'

        @app.get '/:chan/archive', (req, res) =>
            name = req.params.chan
            dir = path.join @config.data, name
            res.header 'Content-Type', 'text/plain'
            fs.readdir dir, (err, files) =>
                if err and err.code is 'ENOENT'
                    res.send 404
                else if err
                    res.send 500
                    console.warn err
                else
                    for f in files
                        if matches = f.match /^(\d+)\.gz$/
                            res.write @path name, 'archive', "#{matches[1]}\n"
                    res.end()

        @app.get '/:chan/archive/:timestamp', (req, res) =>
            p = req.params
            archive = path.join @config.data, p.chan, p.timestamp + '.gz'
            res.header 'Access-Control-Allow-Origin', '*'
            res.header 'Content-Encoding', 'gzip'
            res.header 'Content-Type', 'text/plain'
            res.sendfile archive

        @app.get '/:chan/current', (req, res) =>
            curfile = path.join @config.data, req.params.chan, 'current'
            res.header 'Content-Type', 'text/plain'
            res.sendfile curfile


fs = require 'fs'
path = require 'path'
express = require 'express'
irc = require 'irc'
events = require 'events'
child = require 'child_process'
io = require 'socket.io'

class Lurkr extends events.EventEmitter
    constructor: (@config) ->
        @app = express.createServer(
            (req, res, next) ->
                res.header 'Access-Control-Allow-Origin', '*'
                next()
        )
        @io = io.listen(@app)
        @io.on 'connection', ->
            console.log('woot')

        @networks = {}
        @route()
        @on 'chat', (msg) =>
            @log(msg)
            @io.of("/#{msg.channel}").emit 'chat', msg
        @base = "http://#{@config.host}:#{@config.port}#{@config.mount or ''}"

    path: ->
        parts = Array.prototype.slice.call(arguments)
        parts.unshift @base
        parts.join '/'

    log: (msg) ->
        chandir = path.join @config.data, msg.channel
        fs.mkdir chandir, 0755, (err) =>
            curfile = path.join chandir, 'current'
            stream = fs.createWriteStream curfile, {flags: 'a'}
            str = [msg.timestamp, msg.sender, msg.message].join("\t")

            stream.on 'close', ->
                fs.stat curfile, (err, stats) ->
                    if stats.size > 8192
                        newfile = path.join chandir, Date.now().toString()
                        fs.rename curfile, newfile, (err) ->
                            console.warn(err) if err
                            child.exec "gzip #{newfile}"

            stream.end "#{str}\n"

    route: ->
        @app.get '/', (req, res) =>
            result = {}
            for k, v of @config.channels
                result[k] = @path k
            res.send result

        @app.get '/:chan', (req, res) =>
            name = req.params.chan
            unless chan = @config.channels[name]
                res.send 404
                return
            net  = @config.networks[chan.network]
            res.send
                host: net.host
                port: net.port
                nick: net.nick
                channel: chan.channel
                socket:  @path name
                archive: @path name, 'archive'
                current: @path name, 'current'

        @app.get '/:chan/archive', (req, res) =>
            name = req.params.chan
            dir = path.join @config.data, name
            res.header 'Content-Type', 'text/plain'
            fs.readdir dir, (err, files) =>
                if err and err.code is 'ENOENT'
                    res.send 404
                else if err
                    res.send 500
                    console.warn err
                else
                    for f in files
                        if matches = f.match /^(\d+)\.gz$/
                            res.write @path name, 'archive', "#{matches[1]}\n"
                    res.end()

        @app.get '/:chan/archive/:timestamp', (req, res) =>
            p = req.params
            archive = path.join @config.data, p.chan, p.timestamp + '.gz'
            res.header 'Access-Control-Allow-Origin', '*'
            res.header 'Content-Encoding', 'gzip'
            res.header 'Content-Type', 'text/plain'
            res.sendfile archive

        @app.get '/:chan/current', (req, res) =>
            curfile = path.join @config.data, req.params.chan, 'current'
            res.header 'Content-Type', 'text/plain'
            res.sendfile curfile
    
    @readConfig: (data, cb) ->
        fs.readFile path.join(data, 'config.json'), (err, contents) ->
            unless err
                try
                    config = JSON.parse(contents)
                    config.data = data
                catch e
                    err = e
            if err
                cb err
            else
                cb null, config

    start: ->
        clients = {}

        for k, o of @config.channels
            @io.of("/#{k}").emit 'power on'
            n = o.network
            clients[n] or=
                net: @config.networks[n]
                channels: {}

            clients[n].channels[o.channel] = k

        for network, o of clients
            {host,nick,port} = o.net
            c = new irc.Client host, nick,
                port     : port
                channels : Object.keys(o.channels)

            c.addListener 'message', (from, to, message) =>
                @emit 'chat',
                    channel   : clients[network].channels[to]
                    sender    : from
                    timestamp : Date.now()
                    message   : message

         @app.listen(@config.port)

config = Lurkr.readConfig './data', (err, cfg) ->
    l = new Lurkr cfg
    l.start()
###
