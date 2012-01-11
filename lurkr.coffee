fs = require 'fs'
path = require 'path'
express = require 'express'
irc = require 'irc'
events = require 'events'

class Lurkr extends events.EventEmitter
    constructor: ({@data}) ->
        @app = express.createServer()
        @networks = {}
        @route()
        @on 'chat', (msg) => @log(msg)

    log: (msg) ->
        chandir = path.join @data, msg.channel
        fs.mkdir chandir, 0755, (err) =>
            curfile = path.join chandir, 'current'
            stream = fs.createWriteStream curfile, {flags: 'a'}
            str = JSON.stringify
                message   : msg.message
                sender    : msg.sender
                timestamp : msg.timestamp
            stream.write "#{str}\n"

    route: ->
        @config (err, cfg) =>
            @app.get '/', (req, res) =>
                res.json Object.keys(cfg.channels)
            @app.get '/:chan/current', (req, res) =>
                path = path.join @data, req.params.chan, 'current'
                res.sendfile path
    
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
