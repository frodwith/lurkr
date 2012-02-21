(function() {
  var BotInfo, Cacheable, ChannelInfo, ChannelList, ChannelSet, DataDir, app, async, config, express, fs, link_to, readConfig, xss, zmq,
    __slice = Array.prototype.slice,
    __hasProp = Object.prototype.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor; child.__super__ = parent.prototype; return child; };

  express = require('express');

  zmq = require('zmq');

  fs = require('fs');

  async = require('async');

  xss = function(req, res, next) {
    res.header('Access-Control-Allow-Origin', '*');
    return next();
  };

  app = express.createServer(xss);

  readConfig = function() {
    var config;
    config = {
      baseUrl: "http://localhost:8080/",
      dataDir: "/Users/pdriver/code/lurkr/new-data"
    };
    config.baseUrl = config.baseUrl.replace(/\/$/, '');
    return config;
  };

  config = readConfig();

  link_to = function() {
    var parts;
    parts = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
    parts.unshift(config.baseUrl);
    return parts.join('/');
  };

  Cacheable = (function() {
    var cache;

    function Cacheable() {}

    cache = {};

    Cacheable.prototype.get = function(cb) {
      var _this = this;
      return this.timestamp(function(err, stamp) {
        var c, key;
        if (err) return cb(err);
        key = _this.key || _this.constructor.name;
        c = cache[key] || (cache[key] = {});
        if (stamp <= c.timestamp) {
          return cb(null, c.data);
        } else {
          return _this.fetch(function(err, data) {
            if (err) return cb(err);
            c.timestamp = stamp;
            return cb(null, c.data = data);
          });
        }
      });
    };

    return Cacheable;

  })();

  BotInfo = (function(_super) {

    __extends(BotInfo, _super);

    function BotInfo() {
      this.sock = zmq.socket('req');
      this.sock.connect('tcp://127.0.0.1:8666');
    }

    BotInfo.prototype.req = function(cmd, cb) {
      this.sock.once('message', cb);
      return this.sock.send(cmd);
    };

    BotInfo.prototype.timestamp = function(cb) {
      return this.req('timestamp', function(msg) {
        return cb(null, JSON.parse(msg.toString()).timestamp);
      });
    };

    BotInfo.prototype.fetch = function(cb) {
      return this.req('channels', function(msg) {
        return cb(null, JSON.parse(msg.toString()));
      });
    };

    return BotInfo;

  })(Cacheable);

  DataDir = (function(_super) {

    __extends(DataDir, _super);

    function DataDir() {
      DataDir.__super__.constructor.apply(this, arguments);
    }

    DataDir.prototype.timestamp = function(cb) {
      return fs.stat(config.dataDir, function(err, stats) {
        if (err) {
          return cb(err);
        } else {
          return cb(null, stats.mtime.getTime());
        }
      });
    };

    DataDir.prototype.fetch = function(cb) {
      return fs.readdir(config.dataDir, function(err, files) {
        if (err) {
          return cb(err);
        } else {
          return cb(null, files);
        }
      });
    };

    return DataDir;

  })(Cacheable);

  ChannelSet = (function(_super) {

    __extends(ChannelSet, _super);

    function ChannelSet() {
      this.info = new BotInfo();
      this.dir = new DataDir();
    }

    ChannelSet.prototype.timestamp = function(cb) {
      var tasks,
        _this = this;
      tasks = {
        info: function(cb) {
          return _this.info.timestamp(cb);
        },
        dir: function(cb) {
          return _this.dir.timestamp(cb);
        }
      };
      return async.parallel(tasks, function(err, _arg) {
        var dir, info;
        info = _arg.info, dir = _arg.dir;
        if (err) {
          return cb(err);
        } else {
          return cb(null, Math.max(info, dir));
        }
      });
    };

    ChannelSet.prototype.fetch = function(cb) {
      var tasks,
        _this = this;
      tasks = {
        info: function(cb) {
          return _this.info.get(cb);
        },
        dir: function(cb) {
          return _this.dir.get(cb);
        }
      };
      return async.parallel(tasks, function(err, _arg) {
        var dir, info, n, set, _i, _len;
        info = _arg.info, dir = _arg.dir;
        if (err) return cb(err);
        set = {};
        for (n in info) {
          set[n] = true;
        }
        for (_i = 0, _len = dir.length; _i < _len; _i++) {
          n = dir[_i];
          set[n] = true;
        }
        return cb(null, set);
      });
    };

    return ChannelSet;

  })(Cacheable);

  ChannelList = (function(_super) {

    __extends(ChannelList, _super);

    function ChannelList() {
      this.set = new ChannelSet();
    }

    ChannelList.prototype.timestamp = function(cb) {
      return this.set.timestamp(cb);
    };

    ChannelList.prototype.fetch = function(cb) {
      return this.set.get(function(err, set) {
        var list, n;
        if (err) {
          return cb(err);
        } else {
          list = (function() {
            var _results;
            _results = [];
            for (n in set) {
              _results.push(link_to(n));
            }
            return _results;
          })();
          return cb(null, JSON.stringify(list));
        }
      });
    };

    return ChannelList;

  })(Cacheable);

  ChannelInfo = (function(_super) {

    __extends(ChannelInfo, _super);

    function ChannelInfo(name) {
      this.name = name;
      this.key = '#' + name;
      this.info = new BotInfo();
    }

    ChannelInfo.prototype.timestamp = function(cb) {
      return this.info.timestamp(cb);
    };

    ChannelInfo.prototype.fetch = function(cb) {
      var _this = this;
      return this.info.get(function(err, info) {
        var live;
        if (err) return cb(err);
        info = info[_this.name] || {};
        console.log(info);
        live = info[_this.name] != null;
        if (live) info.socket = "a sensible socket.io url for " + _this.name;
        info.archive = link_to(_this.name, 'archive');
        info.current = link_to(_this.name, 'current');
        return cb(null, JSON.stringify(info));
      });
    };

    return ChannelInfo;

  })(Cacheable);

  app.get('/', function(req, res) {
    res.header('Content-Type', 'application/json');
    return new ChannelList().get(function(err, json) {
      if (err) throw err;
      return res.send(json);
    });
  });

  app.get('/:chan', function(req, res) {
    var name;
    res.header('Content-Type', 'application/json');
    name = req.params.chan;
    return new ChannelSet.get(function(err, set) {
      if (err) throw err;
      if (set[name] == null) {
        return res.send(404);
      } else {
        return new ChannelInfo(name).get(function(err, json) {
          if (err) throw err;
          return res.send(json);
        });
      }
    });
  });

  app.listen(8080);

  /*
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
  */

}).call(this);
