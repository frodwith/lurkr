fs = require 'fs'
path = require 'path'
express = require 'express'
irc = require 'irc'
events = require 'events'
child = require 'child_process'

class Lurkr extends events.EventEmitter
    constructor: ({@data}) ->
        @app = express.createServer()
        @networks = {}
        @route()
        @on 'chat', (msg) => @log(msg)

    path: ->
        base = @app.set('basepath') || @app.route
        parts = Array.prototype.slice.call(arguments)
        parts.unshift(base.replace /\/$/, '')
        parts.join '/'

    log: (msg) ->
        chandir = path.join @data, msg.channel
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
        @config (err, cfg) =>
            @app.get '/', (req, res) =>
                result = {}
                for k, v of cfg.channels
                    result[k] = @path k
                res.send result

            @app.get '/:chan', (req, res) =>
                chan = req.params.chan
                res.send
                    archive: @path chan, 'archive'
                    current: @path chan, 'current'

            @app.get '/:chan/archive', (req, res) =>
                dir = path.join @data, req.params.chan
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
                                res.write "#{matches[1]}\n"
                        res.end()

            @app.get '/:chan/archive/:timestamp', (req, res) =>
                p = req.params
                archive = path.join @data, p.chan, p.timestamp + '.gz'
                res.header 'Content-Encoding', 'gzip'
                res.header 'Content-Type', 'text/plain'
                res.sendfile archive

            @app.get '/:chan/current', (req, res) =>
                curfile = path.join @data, req.params.chan, 'current'
                res.header 'Content-Type', 'text/plain'
                res.sendfile curfile
    
    # read the config file once (json blob) and pass it to cb
    config: (cb) ->
        return cb(null, @_config) if @_config

        fs.readFile path.join(@data, 'config.json'), (err, data) ->
            unless err
                try
                    @_config = JSON.parse(data)
                catch e
                    err = e
            if err
                cb err
            else
                cb null, @_config

    start: ->
        @config (err, cfg) =>
            clients = {}

            for k, o of cfg.channels
                n = o.network
                clients[n] or=
                    net: cfg.networks[n]
                    channels: []

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

             @app.listen(cfg.port)

l = new Lurkr
    data: './data'

l.start()
