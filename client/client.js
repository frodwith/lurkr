(function() {
  var channels, expand, join, leave, logRows, msgRow, onHash, scroll, select;

  this.WEB_SOCKET_SWF_LOCATION = '/socket.io/WebSocketMain.swf';

  msgRow = function(_arg) {
    var date, h, m, message, sender, time, timestamp, tr;
    timestamp = _arg.timestamp, sender = _arg.sender, message = _arg.message;
    date = new Date(timestamp);
    h = date.getHours();
    if (h < 10) h = '0' + h;
    m = date.getMinutes();
    if (m < 10) m = '0' + m;
    time = [h, m].join(':');
    tr = $('<tr class="line">');
    $('<td class="timestamp">').text(time).attr('title', date.toString()).appendTo(tr);
    $('<td class="nick">').text("<" + sender + ">").appendTo(tr);
    $('<td class="message">').text(message || ' ').appendTo(tr);
    return tr.get(0);
  };

  logRows = function(log) {
    var line, lines, message, sender, timestamp, _i, _len, _ref, _results;
    lines = log.split(/\n/);
    lines.pop();
    _results = [];
    for (_i = 0, _len = lines.length; _i < _len; _i++) {
      line = lines[_i];
      _ref = line.split(/\t/, 3), timestamp = _ref[0], sender = _ref[1], message = _ref[2];
      timestamp = parseInt(timestamp);
      _results.push({
        timestamp: timestamp,
        sender: sender,
        message: message
      });
    }
    return _results;
  };

  channels = {};

  leave = function(chan) {
    var k, tab, _results;
    tab = channels[chan];
    delete channels[chan];
    tab.button.remove();
    tab.content.remove();
    if (tab.active) {
      _results = [];
      for (k in channels) {
        select(k);
        break;
      }
      return _results;
    }
  };

  join = function(url) {
    var el, more, tab, tbl;
    el = $('<div class=\'tab\'>\n    <div class=\'more\'>More...</div>\n    <table class="log">\n        <caption></caption>\n    </table>\n</div>');
    tab = {};
    more = el.find('.more');
    tbl = el.find('.log');
    tbl.find('caption').text(url);
    return $.getJSON(url, function(channel) {
      var rjoin, room, socket, socketInfo;
      $.get(channel.current, function(log) {
        var r;
        tbl.append((function() {
          var _i, _len, _ref, _results;
          _ref = logRows(log);
          _results = [];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            r = _ref[_i];
            _results.push(msgRow(r));
          }
          return _results;
        })());
        return scroll();
      });
      if (socketInfo = channel.socket) {
        room = socketInfo.room;
        socket = io.connect(socketInfo.server);
        rjoin = function() {
          return socket.emit('join', room);
        };
        rjoin();
        socket.on('reconnect', rjoin);
        socket.on('chat', function(data) {
          var auto;
          if (data.channel !== room) return;
          el = $('#tab-content');
          auto = (el.height() + el.scrollTop()) === el.prop('scrollHeight');
          tbl.append(msgRow(data));
          if (auto) return scroll();
        });
      }
      return $.getJSON(channel.archive, function(urls) {
        var archives, get, k, updateMore;
        archives = (function() {
          var _results;
          _results = [];
          for (k in urls) {
            _results.push(parseInt(k));
          }
          return _results;
        })();
        archives.sort();
        get = function() {
          more.unbind('click');
          return $.get(urls[archives.pop()], function(log) {
            var r;
            tbl.prepend((function() {
              var _i, _len, _ref, _results;
              _ref = logRows(log);
              _results = [];
              for (_i = 0, _len = _ref.length; _i < _len; _i++) {
                r = _ref[_i];
                _results.push(msgRow(r));
              }
              return _results;
            })());
            return updateMore();
          });
        };
        updateMore = function() {
          if (archives.length > 0) {
            return more.click(get);
          } else {
            return more.remove();
          }
        };
        updateMore();
        el.appendTo('#tab-content');
        tab.content = el;
        tab.button = $('<li class="tab-title">').text(channel.channel).prepend($('<span class="close"> x </span>').click(function(e) {
          var k, now;
          now = (function() {
            var _results;
            _results = [];
            for (k in channels) {
              if (k !== url) _results.push(k);
            }
            return _results;
          })();
          location.hash = now.join(',');
          return e.stopPropagation();
        })).click(function() {
          return select(url);
        }).prependTo('#tab-buttons');
        channels[url] = tab;
        select(url);
        return expand();
      });
    });
  };

  select = function(channel) {
    var chan, tab;
    for (chan in channels) {
      tab = channels[chan];
      tab.content.removeClass('active');
      tab.button.removeClass('active');
      tab.active = false;
    }
    tab = channels[channel];
    tab.active = true;
    tab.content.addClass('active');
    tab.button.addClass('active');
    return scroll();
  };

  onHash = function() {
    var chan, set, tab, u, urls, _i, _len, _ref, _results;
    urls = location.hash.replace(/^#/, '');
    set = {};
    _ref = urls.split(/,/);
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      u = _ref[_i];
      if (u) set[u] = true;
    }
    for (chan in channels) {
      tab = channels[chan];
      if (!(chan in set)) leave(chan);
    }
    _results = [];
    for (chan in set) {
      if (!(chan in channels)) {
        _results.push(join(chan));
      } else {
        _results.push(void 0);
      }
    }
    return _results;
  };

  expand = function() {
    var el;
    el = $('#tab-content');
    return el.height($(window).height() - el.position().top);
  };

  scroll = function() {
    var el;
    el = $('#tab-content');
    return el.animate({
      scrollTop: el.prop('scrollHeight')
    }, 'fast');
  };

  $(function() {
    $('#join').click(function() {
      var url;
      url = prompt('Channel url:');
      if (channels[url]) return;
      if (location.hash) {
        return location.hash += ',' + url;
      } else {
        return location.hash = url;
      }
    });
    $(window).on('hashchange', onHash);
    $(window).on('resize', expand);
    return onHash();
  });

}).call(this);
